defmodule Sensocto.RoomServer do
  @moduledoc """
  GenServer that manages the state for a single room distributed across the cluster.

  Uses Horde.Registry for cluster-wide unique process registration.
  Handles room configuration, members, sensor connections, and activity tracking.
  """
  use GenServer
  require Logger

  @default_expiry_ms 24 * 60 * 60 * 1000
  @activity_timeout_ms 5000
  @idle_timeout_ms 60_000
  @call_timeout 5_000

  defstruct [
    :id,
    :name,
    :description,
    :owner_id,
    :join_code,
    :created_at,
    :last_activity_at,
    is_public: true,
    configuration: %{},
    members: %{},
    sensor_ids: MapSet.new(),
    sensor_activity: %{},
    expiry_timer: nil
  ]

  # Client API

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end

  @doc """
  Returns a via tuple for locating a room process across the cluster.
  Uses Horde.Registry for distributed process lookup.
  """
  def via_tuple(room_id) do
    {:via, Horde.Registry, {Sensocto.DistributedRoomRegistry, room_id}}
  end

  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state, @call_timeout)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def get_view_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_view_state, @call_timeout)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def add_member(room_id, user_id, role \\ :member) do
    GenServer.call(via_tuple(room_id), {:add_member, user_id, role}, @call_timeout)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def remove_member(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:remove_member, user_id}, @call_timeout)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def add_sensor(room_id, sensor_id) do
    GenServer.call(via_tuple(room_id), {:add_sensor, sensor_id}, @call_timeout)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def remove_sensor(room_id, sensor_id) do
    GenServer.call(via_tuple(room_id), {:remove_sensor, sensor_id}, @call_timeout)
  catch
    :exit, _ -> {:error, :not_found}
  end

  def update_sensor_activity(room_id, sensor_id) do
    GenServer.cast(via_tuple(room_id), {:sensor_activity, sensor_id})
  end

  def is_member?(room_id, user_id) do
    case get_state(room_id) do
      {:ok, state} -> Map.has_key?(state.members, user_id)
      {:error, _} -> false
    end
  end

  def get_member_role(room_id, user_id) do
    case get_state(room_id) do
      {:ok, state} -> Map.get(state.members, user_id)
      {:error, _} -> nil
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :id)
    owner_id = Keyword.fetch!(opts, :owner_id)
    name = Keyword.fetch!(opts, :name)
    description = Keyword.get(opts, :description)
    is_public = Keyword.get(opts, :is_public, true)
    configuration = Keyword.get(opts, :configuration, %{})
    join_code = Keyword.get(opts, :join_code, generate_join_code())
    expiry_ms = Keyword.get(opts, :expiry_ms, @default_expiry_ms)

    # Register join code in distributed registry for cluster-wide lookup
    Horde.Registry.register(Sensocto.DistributedJoinCodeRegistry, join_code, room_id)

    expiry_timer = Process.send_after(self(), :expire, expiry_ms)

    state = %__MODULE__{
      id: room_id,
      name: name,
      description: description,
      owner_id: owner_id,
      join_code: join_code,
      is_public: is_public,
      configuration: configuration,
      created_at: DateTime.utc_now(),
      last_activity_at: DateTime.utc_now(),
      members: %{owner_id => :owner},
      expiry_timer: expiry_timer
    }

    Logger.info("RoomServer started for room #{room_id}")

    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, {:ok, state}, touch_activity(state)}
  end

  @impl true
  def handle_call(:get_view_state, _from, state) do
    view_state = %{
      id: state.id,
      name: state.name,
      description: state.description,
      owner_id: state.owner_id,
      join_code: state.join_code,
      is_public: state.is_public,
      is_persisted: false,
      configuration: state.configuration,
      members: state.members,
      member_count: map_size(state.members),
      sensor_count: MapSet.size(state.sensor_ids),
      sensor_ids: MapSet.to_list(state.sensor_ids),
      sensor_activity: state.sensor_activity,
      created_at: state.created_at,
      last_activity_at: state.last_activity_at
    }

    {:reply, {:ok, view_state}, touch_activity(state)}
  end

  @impl true
  def handle_call({:add_member, user_id, role}, _from, state) do
    if Map.has_key?(state.members, user_id) do
      {:reply, {:error, :already_member}, state}
    else
      new_members = Map.put(state.members, user_id, role)
      new_state = %{state | members: new_members}

      broadcast_room_update(state.id, {:member_joined, user_id, role})

      {:reply, :ok, touch_activity(new_state)}
    end
  end

  @impl true
  def handle_call({:remove_member, user_id}, _from, state) do
    if user_id == state.owner_id do
      {:reply, {:error, :cannot_remove_owner}, state}
    else
      new_members = Map.delete(state.members, user_id)
      new_state = %{state | members: new_members}

      broadcast_room_update(state.id, {:member_left, user_id})

      {:reply, :ok, touch_activity(new_state)}
    end
  end

  @impl true
  def handle_call({:add_sensor, sensor_id}, _from, state) do
    if MapSet.member?(state.sensor_ids, sensor_id) do
      {:reply, {:error, :already_added}, state}
    else
      new_sensor_ids = MapSet.put(state.sensor_ids, sensor_id)
      new_state = %{state | sensor_ids: new_sensor_ids}

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

      broadcast_room_update(state.id, {:sensor_added, sensor_id})

      {:reply, :ok, touch_activity(new_state)}
    end
  end

  @impl true
  def handle_call({:remove_sensor, sensor_id}, _from, state) do
    new_sensor_ids = MapSet.delete(state.sensor_ids, sensor_id)
    new_activity = Map.delete(state.sensor_activity, sensor_id)
    new_state = %{state | sensor_ids: new_sensor_ids, sensor_activity: new_activity}

    Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")

    broadcast_room_update(state.id, {:sensor_removed, sensor_id})

    {:reply, :ok, touch_activity(new_state)}
  end

  @impl true
  def handle_cast({:sensor_activity, sensor_id}, state) do
    if MapSet.member?(state.sensor_ids, sensor_id) do
      new_activity = Map.put(state.sensor_activity, sensor_id, DateTime.utc_now())
      new_state = %{state | sensor_activity: new_activity}
      {:noreply, touch_activity(new_state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:measurement, %{sensor_id: sensor_id}}, state) do
    if MapSet.member?(state.sensor_ids, sensor_id) do
      new_activity = Map.put(state.sensor_activity, sensor_id, DateTime.utc_now())
      new_state = %{state | sensor_activity: new_activity}

      broadcast_room_update(state.id, {:sensor_measurement, sensor_id})

      {:noreply, touch_activity(new_state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info({:measurements_batch, {sensor_id, _measurements}}, state) do
    if MapSet.member?(state.sensor_ids, sensor_id) do
      new_activity = Map.put(state.sensor_activity, sensor_id, DateTime.utc_now())
      new_state = %{state | sensor_activity: new_activity}

      broadcast_room_update(state.id, {:sensor_measurement, sensor_id})

      {:noreply, touch_activity(new_state)}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:expire, state) do
    Logger.info("RoomServer #{state.id} expired, shutting down")
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("RoomServer received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("RoomServer #{state.id} terminating: #{inspect(reason)}")

    if state.expiry_timer do
      Process.cancel_timer(state.expiry_timer)
    end

    broadcast_room_update(state.id, :room_closed)

    :ok
  end

  # Private functions

  defp touch_activity(state) do
    %{state | last_activity_at: DateTime.utc_now()}
  end

  defp broadcast_room_update(room_id, message) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "room:#{room_id}", {:room_update, message})
  end

  defp generate_join_code(length \\ 8) do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    1..length
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> List.to_string()
  end

  @doc """
  Returns the activity status for a sensor in the room.
  :active - data received < 5s ago
  :idle - data received < 60s ago
  :inactive - no recent data
  """
  def sensor_status(state, sensor_id) do
    case Map.get(state.sensor_activity, sensor_id) do
      nil ->
        :inactive

      last_activity ->
        diff_ms = DateTime.diff(DateTime.utc_now(), last_activity, :millisecond)

        cond do
          diff_ms < @activity_timeout_ms -> :active
          diff_ms < @idle_timeout_ms -> :idle
          true -> :inactive
        end
    end
  end
end

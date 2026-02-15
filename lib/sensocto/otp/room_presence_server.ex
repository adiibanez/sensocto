defmodule Sensocto.RoomPresenceServer do
  @moduledoc """
  GenServer for in-memory room presence and sensor association tracking.

  Architecture:
  - GenServer provides fast, real-time state for active sessions
  - State can be seeded from external sources (P2P, mobile, etc.)

  State structure:
  %{
    room_id => %{
      user_id => %{
        sensor_ids: MapSet.t(),
        role: :owner | :admin | :member,
        joined_at: DateTime.t()
      }
    }
  }
  """
  use GenServer
  require Logger

  @name __MODULE__
  @call_timeout 3_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: @name)
  end

  @doc """
  Joins a user to a room with their sensors.
  Updates in-memory state immediately.
  """
  def join_room(room_id, user_id, sensor_ids, opts \\ []) do
    role = Keyword.get(opts, :role, :member)
    GenServer.call(@name, {:join_room, room_id, user_id, sensor_ids, role}, @call_timeout)
  end

  @doc """
  Leaves a room. Removes user's presence and sensors.
  """
  def leave_room(room_id, user_id) do
    GenServer.call(@name, {:leave_room, room_id, user_id}, @call_timeout)
  end

  @doc """
  Updates a user's sensors in a room.
  Called when sensors connect/disconnect.
  """
  def update_sensors(room_id, user_id, sensor_ids) do
    GenServer.call(@name, {:update_sensors, room_id, user_id, sensor_ids}, @call_timeout)
  end

  @doc """
  Gets all sensor IDs in a room from all users.
  Fast in-memory read.
  """
  def get_room_sensors(room_id) do
    GenServer.call(@name, {:get_room_sensors, room_id}, @call_timeout)
  end

  @doc """
  Gets all users present in a room with their sensors.
  """
  def get_room_presences(room_id) do
    GenServer.call(@name, {:get_room_presences, room_id}, @call_timeout)
  end

  @doc """
  Checks if a user is present in a room.
  """
  def in_room?(room_id, user_id) do
    GenServer.call(@name, {:in_room?, room_id, user_id}, @call_timeout)
  end

  @doc """
  Gets all rooms a user is present in.
  """
  def get_user_rooms(user_id) do
    GenServer.call(@name, {:get_user_rooms, user_id}, @call_timeout)
  end

  @doc """
  Hydrates state from backend.
  Called on startup or when recovering state.
  """
  def hydrate_from_backend do
    GenServer.cast(@name, :hydrate_from_backend)
  end

  @doc """
  Seeds state from external source (P2P, mobile, etc).
  Future: Used for P2P state synchronization.
  """
  def seed_state(room_id, presences) do
    GenServer.call(@name, {:seed_state, room_id, presences}, @call_timeout)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Try to hydrate from Neo4j on startup (async to not block)
    Process.send_after(self(), :hydrate_on_startup, 1000)
    {:ok, %{}}
  end

  @impl true
  def handle_call({:join_room, room_id, user_id, sensor_ids, role}, _from, state) do
    sensor_set = MapSet.new(sensor_ids)

    presence = %{
      sensor_ids: sensor_set,
      role: role,
      joined_at: DateTime.utc_now()
    }

    new_state =
      state
      |> Map.update(room_id, %{user_id => presence}, fn room_presences ->
        Map.put(room_presences, user_id, presence)
      end)

    # Broadcast room update
    broadcast_room_update(
      room_id,
      {:user_joined, %{user_id: user_id, sensor_ids: sensor_ids, role: role}}
    )

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:leave_room, room_id, user_id}, _from, state) do
    case get_in(state, [room_id, user_id]) do
      nil ->
        {:reply, {:error, :not_in_room}, state}

      presence ->
        sensor_ids = MapSet.to_list(presence.sensor_ids)

        new_state =
          state
          |> update_in([room_id], fn room_presences ->
            room_presences
            |> Map.delete(user_id)
            |> case do
              empty when map_size(empty) == 0 -> nil
              presences -> presences
            end
          end)
          |> Map.reject(fn {_k, v} -> is_nil(v) end)

        # Broadcast room update
        broadcast_room_update(room_id, {:user_left, %{user_id: user_id, sensor_ids: sensor_ids}})

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:update_sensors, room_id, user_id, sensor_ids}, _from, state) do
    case get_in(state, [room_id, user_id]) do
      nil ->
        {:reply, {:error, :not_in_room}, state}

      presence ->
        sensor_set = MapSet.new(sensor_ids)
        updated_presence = %{presence | sensor_ids: sensor_set}

        new_state = put_in(state, [room_id, user_id], updated_presence)

        # Broadcast room update
        broadcast_room_update(
          room_id,
          {:sensors_updated, %{user_id: user_id, sensor_ids: sensor_ids}}
        )

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call({:get_room_sensors, room_id}, _from, state) do
    sensors =
      case Map.get(state, room_id) do
        nil ->
          []

        presences ->
          presences
          |> Map.values()
          |> Enum.flat_map(fn p -> MapSet.to_list(p.sensor_ids) end)
          |> Enum.uniq()
      end

    {:reply, sensors, state}
  end

  @impl true
  def handle_call({:get_room_presences, room_id}, _from, state) do
    presences =
      case Map.get(state, room_id) do
        nil ->
          []

        room_presences ->
          Enum.map(room_presences, fn {user_id, presence} ->
            %{
              user_id: user_id,
              sensor_ids: MapSet.to_list(presence.sensor_ids),
              role: presence.role,
              joined_at: presence.joined_at
            }
          end)
      end

    {:reply, presences, state}
  end

  @impl true
  def handle_call({:in_room?, room_id, user_id}, _from, state) do
    result = get_in(state, [room_id, user_id]) != nil
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get_user_rooms, user_id}, _from, state) do
    rooms =
      state
      |> Enum.filter(fn {_room_id, presences} -> Map.has_key?(presences, user_id) end)
      |> Enum.map(fn {room_id, presences} ->
        presence = Map.get(presences, user_id)
        %{room_id: room_id, role: presence.role, sensor_ids: MapSet.to_list(presence.sensor_ids)}
      end)

    {:reply, rooms, state}
  end

  @impl true
  def handle_call({:seed_state, room_id, presences}, _from, state) do
    # Seed state from external source (P2P, mobile, etc)
    room_presences =
      Enum.into(presences, %{}, fn p ->
        {p.user_id,
         %{
           sensor_ids: MapSet.new(p.sensor_ids),
           role: p.role,
           joined_at: p.joined_at || DateTime.utc_now()
         }}
      end)

    new_state = Map.put(state, room_id, room_presences)

    Logger.debug("Seeded room #{room_id} with #{length(presences)} presences")

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast(:hydrate_from_backend, state) do
    # No-op: backend hydration removed (was Neo4j)
    {:noreply, state}
  end

  @impl true
  def handle_info(:hydrate_on_startup, state) do
    # No-op: backend hydration removed (was Neo4j)
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("RoomPresenceServer received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp broadcast_room_update(room_id, message) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "room:#{room_id}",
      {:room_update, message}
    )
  end
end

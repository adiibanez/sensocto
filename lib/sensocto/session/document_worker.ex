defmodule Sensocto.Session.DocumentWorker do
  @moduledoc """
  GenServer wrapping per-user session state using a Last-Writer-Wins (LWW) CRDT.

  Each user gets one DocumentWorker that maintains their session state
  (active lens, scroll position, preferences, etc.) and syncs it across
  multiple connected devices via PubSub.

  ## CRDT Strategy

  MVP uses a simple LWW-Register map: each key has a value and a timestamp.
  On conflict, the latest timestamp wins. This can be swapped for Automerge
  or similar later.

  ## Usage

      # Get or start worker for a user
      {:ok, pid} = Sensocto.Session.Supervisor.ensure_worker(user_id)

      # Set session state
      DocumentWorker.put(user_id, "active_lens", :ecg)
      DocumentWorker.put(user_id, "scroll_position", 42)

      # Get session state
      DocumentWorker.get(user_id, "active_lens")
      # => :ecg

      # Merge state from another device
      DocumentWorker.merge(user_id, %{"active_lens" => {:ecg, timestamp}})
  """

  use GenServer
  require Logger

  @pubsub Sensocto.PubSub
  @idle_timeout :timer.minutes(30)

  defstruct user_id: nil,
            state: %{},
            devices: MapSet.new(),
            last_activity: nil

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(user_id) do
    GenServer.start_link(__MODULE__, user_id, name: via(user_id))
  end

  @doc "Put a key-value pair into the session state."
  def put(user_id, key, value) do
    GenServer.cast(via(user_id), {:put, key, value})
  end

  @doc "Get a value from the session state."
  def get(user_id, key, default \\ nil) do
    GenServer.call(via(user_id), {:get, key, default})
  end

  @doc "Get the entire session state map."
  def get_all(user_id) do
    GenServer.call(via(user_id), :get_all)
  end

  @doc "Merge state from another device (LWW resolution)."
  def merge(user_id, remote_state) do
    GenServer.cast(via(user_id), {:merge, remote_state})
  end

  @doc "Register a device connection."
  def register_device(user_id, device_id) do
    GenServer.cast(via(user_id), {:register_device, device_id})
  end

  @doc "Unregister a device connection."
  def unregister_device(user_id, device_id) do
    GenServer.cast(via(user_id), {:unregister_device, device_id})
  end

  @doc "Get connected device count."
  def device_count(user_id) do
    GenServer.call(via(user_id), :device_count)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(user_id) do
    topic = session_topic(user_id)
    Phoenix.PubSub.subscribe(@pubsub, topic)

    Process.send_after(self(), :check_idle, @idle_timeout)

    Logger.debug("Session.DocumentWorker started for user #{user_id}")

    {:ok,
     %__MODULE__{
       user_id: user_id,
       state: %{},
       devices: MapSet.new(),
       last_activity: System.monotonic_time(:millisecond)
     }}
  end

  @impl true
  def handle_cast({:put, key, value}, state) do
    timestamp = System.system_time(:microsecond)
    new_entry = {value, timestamp}
    new_state = Map.put(state.state, key, new_entry)

    # Broadcast to other devices
    broadcast(state.user_id, {:session_update, %{key => new_entry}})

    {:noreply, %{state | state: new_state, last_activity: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_cast({:merge, remote_state}, state) do
    merged =
      Enum.reduce(remote_state, state.state, fn {key, {_value, remote_ts} = remote_entry}, acc ->
        case Map.get(acc, key) do
          nil ->
            Map.put(acc, key, remote_entry)

          {_local_val, local_ts} when remote_ts > local_ts ->
            Map.put(acc, key, remote_entry)

          _ ->
            acc
        end
      end)

    {:noreply, %{state | state: merged, last_activity: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_cast({:register_device, device_id}, state) do
    new_devices = MapSet.put(state.devices, device_id)

    broadcast(state.user_id, {:device_joined, device_id, MapSet.size(new_devices)})

    # Send current state to the new device
    broadcast(state.user_id, {:session_sync, state.state})

    {:noreply,
     %{state | devices: new_devices, last_activity: System.monotonic_time(:millisecond)}}
  end

  @impl true
  def handle_cast({:unregister_device, device_id}, state) do
    new_devices = MapSet.delete(state.devices, device_id)

    broadcast(state.user_id, {:device_left, device_id, MapSet.size(new_devices)})

    {:noreply, %{state | devices: new_devices}}
  end

  @impl true
  def handle_call({:get, key, default}, _from, state) do
    value =
      case Map.get(state.state, key) do
        {val, _ts} -> val
        nil -> default
      end

    {:reply, value, state}
  end

  @impl true
  def handle_call(:get_all, _from, state) do
    # Strip timestamps for external consumption
    clean = Map.new(state.state, fn {key, {value, _ts}} -> {key, value} end)
    {:reply, clean, state}
  end

  @impl true
  def handle_call(:device_count, _from, state) do
    {:reply, MapSet.size(state.devices), state}
  end

  @impl true
  def handle_info({:session_update, remote_state}, state) do
    # Received from another node/process - merge using LWW
    merged =
      Enum.reduce(remote_state, state.state, fn {key, {_value, remote_ts} = remote_entry}, acc ->
        case Map.get(acc, key) do
          nil -> Map.put(acc, key, remote_entry)
          {_local_val, local_ts} when remote_ts > local_ts -> Map.put(acc, key, remote_entry)
          _ -> acc
        end
      end)

    {:noreply, %{state | state: merged}}
  end

  @impl true
  def handle_info({:session_sync, _remote_state}, state) do
    # Ignore sync messages for ourselves (we sent them)
    {:noreply, state}
  end

  @impl true
  def handle_info({:device_joined, _device_id, _count}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({:device_left, _device_id, _count}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info(:check_idle, state) do
    idle_ms = System.monotonic_time(:millisecond) - state.last_activity

    if idle_ms > @idle_timeout and MapSet.size(state.devices) == 0 do
      Logger.debug("Session.DocumentWorker for #{state.user_id} idle, shutting down")
      {:stop, :normal, state}
    else
      Process.send_after(self(), :check_idle, @idle_timeout)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp via(user_id) do
    {:via, Registry, {Sensocto.Session.Registry, user_id}}
  end

  defp session_topic(user_id), do: "session:#{user_id}"

  defp broadcast(user_id, message) do
    Phoenix.PubSub.broadcast(@pubsub, session_topic(user_id), message)
  end
end

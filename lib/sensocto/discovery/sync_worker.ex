defmodule Sensocto.Discovery.SyncWorker do
  @moduledoc """
  Background worker that syncs discovery cache with cluster state.

  Uses PubSub for real-time updates and periodic full sync as safety net.

  ## Design Principles

  1. **Non-blocking**: Never blocks on slow nodes
  2. **Debouncing**: Coalesces rapid updates to reduce load
  3. **Priority**: Deletes processed immediately, updates debounced
  4. **Resilience**: Handles node failures gracefully
  """
  use GenServer
  require Logger

  alias Sensocto.Discovery.DiscoveryCache

  @pubsub Sensocto.PubSub
  @sync_interval_ms 30_000
  @debounce_ms 100

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate full sync of all sensors.
  """
  def force_sync do
    GenServer.cast(__MODULE__, :force_sync)
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Subscribe to discovery events
    Phoenix.PubSub.subscribe(@pubsub, "discovery:sensors")

    # Schedule periodic full sync
    schedule_full_sync()

    # Perform initial sync
    send(self(), :initial_sync)

    Logger.info("[SyncWorker] Started, subscribed to discovery:sensors")

    {:ok, %{pending_updates: [], debounce_timer: nil}}
  end

  # Handle sensor registration broadcasts
  @impl true
  def handle_info({:sensor_registered, sensor_id, view_state, from_node}, state) do
    Logger.debug("[SyncWorker] Sensor registered: #{sensor_id} on #{from_node}")

    # Debounce updates to avoid overwhelming the cache
    state = queue_update({:put, sensor_id, view_state}, state)
    {:noreply, state}
  end

  # Handle sensor unregistration broadcasts - process immediately (high priority)
  @impl true
  def handle_info({:sensor_unregistered, sensor_id, from_node}, state) do
    Logger.debug("[SyncWorker] Sensor unregistered: #{sensor_id} on #{from_node}")

    # Deletes are high priority - process immediately
    DiscoveryCache.delete_sensor(sensor_id)
    {:noreply, state}
  end

  # Flush debounced updates
  @impl true
  def handle_info(:flush_updates, state) do
    # Process all queued updates
    Enum.each(state.pending_updates, fn
      {:put, sensor_id, data} ->
        DiscoveryCache.put_sensor(sensor_id, data)
    end)

    {:noreply, %{state | pending_updates: [], debounce_timer: nil}}
  end

  # Initial sync on startup
  @impl true
  def handle_info(:initial_sync, state) do
    Logger.info("[SyncWorker] Running initial sync")
    sync_sensors()
    {:noreply, state}
  end

  # Periodic full sync
  @impl true
  def handle_info(:full_sync, state) do
    Logger.debug("[SyncWorker] Running periodic full sync")
    sync_sensors()
    schedule_full_sync()
    {:noreply, state}
  end

  @impl true
  def handle_cast(:force_sync, state) do
    Logger.info("[SyncWorker] Force sync requested")
    sync_sensors()
    {:noreply, state}
  end

  # Private helpers

  defp queue_update(update, state) do
    state = %{state | pending_updates: [update | state.pending_updates]}

    # Start debounce timer if not already running
    if state.debounce_timer == nil do
      timer = Process.send_after(self(), :flush_updates, @debounce_ms)
      %{state | debounce_timer: timer}
    else
      state
    end
  end

  defp sync_sensors do
    # Get all sensors from Horde registry (cluster-wide)
    sensor_ids =
      Horde.Registry.select(
        Sensocto.DistributedSensorRegistry,
        [{{:"$1", :_, :_}, [], [:"$1"]}]
      )

    Logger.debug("[SyncWorker] Syncing #{length(sensor_ids)} sensors from registry")

    # Fetch states in parallel with timeout
    sensor_ids
    |> Task.async_stream(
      fn id -> {id, fetch_sensor_state(id)} end,
      max_concurrency: 20,
      timeout: 5_000,
      on_timeout: :kill_task
    )
    |> Enum.each(fn
      {:ok, {id, {:ok, state}}} ->
        DiscoveryCache.put_sensor(id, state)

      {:ok, {id, {:error, reason}}} ->
        Logger.warning("[SyncWorker] Failed to sync sensor #{id}: #{inspect(reason)}")

      {:exit, :timeout} ->
        Logger.warning("[SyncWorker] Timeout syncing sensor")
    end)
  end

  defp fetch_sensor_state(sensor_id) do
    try do
      state = Sensocto.SimpleSensor.get_view_state(sensor_id)

      # Extract discovery-relevant fields
      view_state = %{
        sensor_id: sensor_id,
        sensor_name: Map.get(state, :sensor_name, sensor_id),
        sensor_type: Map.get(state, :sensor_type),
        connector_id: Map.get(state, :connector_id),
        connector_name: Map.get(state, :connector_name),
        attributes: Map.get(state, :attributes, %{}),
        node: node()
      }

      {:ok, view_state}
    catch
      :exit, reason ->
        {:error, reason}
    end
  end

  defp schedule_full_sync do
    Process.send_after(self(), :full_sync, @sync_interval_ms)
  end
end

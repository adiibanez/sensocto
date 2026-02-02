defmodule Sensocto.Discovery.SyncWorker do
  @moduledoc """
  Event-driven worker that syncs discovery cache with cluster state.

  Relies entirely on PubSub events for real-time updates. Only performs
  full sync on startup or when manually triggered (for debugging/recovery).

  ## Design Principles

  1. **Event-driven**: No periodic polling - reacts to sensor lifecycle events
  2. **Non-blocking**: Never blocks on slow nodes
  3. **Debouncing**: Coalesces rapid updates to reduce load
  4. **Priority**: Deletes processed immediately, updates debounced
  5. **Resilience**: Monitors cluster membership for node failures
  """
  use GenServer
  require Logger

  alias Sensocto.Discovery.DiscoveryCache

  @pubsub Sensocto.PubSub
  @debounce_ms 100

  # Client API

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Triggers an immediate full sync of all sensors.
  Use sparingly - only for debugging or recovery scenarios.
  """
  def force_sync do
    GenServer.cast(__MODULE__, :force_sync)
  end

  # GenServer implementation

  @impl true
  def init(_opts) do
    # Subscribe to discovery events (sensor lifecycle)
    Phoenix.PubSub.subscribe(@pubsub, "discovery:sensors")

    # Monitor cluster membership for node up/down events
    :net_kernel.monitor_nodes(true)

    # Perform initial sync only on startup
    send(self(), :initial_sync)

    Logger.info("[SyncWorker] Started (event-driven mode), subscribed to discovery:sensors")

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

  # Handle node up - reconcile sensors from that node
  @impl true
  def handle_info({:nodeup, node}, state) do
    Logger.info(
      "[SyncWorker] Node joined cluster: #{node}, will receive sensor events via PubSub"
    )

    # No action needed - sensors on the new node will broadcast their registration
    {:noreply, state}
  end

  # Handle node down - clean up sensors from that node
  @impl true
  def handle_info({:nodedown, node}, state) do
    Logger.info("[SyncWorker] Node left cluster: #{node}, cleaning up its sensors")
    # Clean up sensors that were on the departed node
    cleanup_sensors_from_node(node)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:force_sync, state) do
    Logger.info("[SyncWorker] Force sync requested (manual recovery)")
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

      {:ok, {id, {:error, {:noproc, _}}}} ->
        # Sensor process no longer exists - clean up stale cache entry
        Logger.debug("[SyncWorker] Sensor #{id} process gone, removing from cache")
        DiscoveryCache.delete_sensor(id)

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

  # Clean up sensors that were registered from a departed node
  defp cleanup_sensors_from_node(departed_node) do
    # Get all cached sensors and remove those from the departed node
    DiscoveryCache.list_sensors()
    |> Enum.filter(fn {_sensor_id, sensor_data} ->
      Map.get(sensor_data, :node) == departed_node
    end)
    |> Enum.each(fn {sensor_id, _} ->
      Logger.debug(
        "[SyncWorker] Removing sensor #{sensor_id} from departed node #{departed_node}"
      )

      DiscoveryCache.delete_sensor(sensor_id)
    end)
  end
end

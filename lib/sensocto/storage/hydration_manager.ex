defmodule Sensocto.Storage.HydrationManager do
  @moduledoc """
  Coordinates multiple storage backends for room hydration and persistence.

  The HydrationManager is the central coordinator for room state persistence:

  1. **Hydration**: Restores room state from backends on startup
  2. **Persistence**: Stores room snapshots to all enabled backends
  3. **Fallback**: Retrieves data from the next available backend on failure

  ## Backends

  Backends are tried in priority order (lower = higher priority):

  - PostgresBackend (priority 1) - Primary persistent storage
  - IrohBackend (priority 2) - P2P distributed storage
  - LocalStorageBackend (priority 3) - Client-side fallback

  ## Hydration Strategies

  - `:priority_fallback` - Try backends in priority order, return first success
  - `:latest` - Query all backends, return highest version
  - `:quorum` - Require majority agreement on checksum (not implemented)

  ## Configuration

      config :sensocto, Sensocto.Storage.HydrationManager,
        backends: [
          {Sensocto.Storage.Backends.PostgresBackend, enabled: true},
          {Sensocto.Storage.Backends.IrohBackend, enabled: true},
          {Sensocto.Storage.Backends.LocalStorageBackend, enabled: false}
        ],
        hydration_strategy: :priority_fallback,
        snapshot_interval_ms: 5_000

  ## Telemetry Events

  - `[:sensocto, :hydration, :start]` - Hydration started
  - `[:sensocto, :hydration, :stop]` - Hydration completed
  - `[:sensocto, :hydration, :backend, :store]` - Snapshot stored to backend
  - `[:sensocto, :hydration, :backend, :get]` - Snapshot retrieved from backend
  - `[:sensocto, :hydration, :backend, :error]` - Backend operation failed
  """

  use GenServer
  require Logger

  alias Sensocto.Storage.Backends.RoomBackend

  @default_backends [
    {Sensocto.Storage.Backends.PostgresBackend, enabled: true},
    {Sensocto.Storage.Backends.IrohBackend, enabled: true},
    {Sensocto.Storage.Backends.LocalStorageBackend, enabled: false}
  ]

  @default_strategy :priority_fallback
  @default_snapshot_interval 5_000

  defstruct [
    :backends,
    :strategy,
    :snapshot_interval,
    pending_snapshots: %{},
    backend_health: %{}
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Hydrates all rooms from backends according to the configured strategy.
  Returns {:ok, count} with the number of rooms hydrated.
  """
  def hydrate_all do
    GenServer.call(__MODULE__, :hydrate_all, 30_000)
  end

  @doc """
  Hydrates a single room from backends.
  Returns {:ok, snapshot} or {:error, reason}.
  """
  def hydrate_room(room_id) do
    GenServer.call(__MODULE__, {:hydrate_room, room_id}, 10_000)
  end

  @doc """
  Stores a room snapshot to all enabled backends.
  """
  def snapshot_room(room_id, room_data) do
    GenServer.cast(__MODULE__, {:snapshot_room, room_id, room_data})
  end

  @doc """
  Stores a room snapshot synchronously to all enabled backends.
  Returns :ok or {:error, reasons}.
  """
  def snapshot_room_sync(room_id, room_data) do
    GenServer.call(__MODULE__, {:snapshot_room_sync, room_id, room_data}, 10_000)
  end

  @doc """
  Deletes a room from all backends.
  """
  def delete_room(room_id) do
    GenServer.cast(__MODULE__, {:delete_room, room_id})
  end

  @doc """
  Returns health status of all backends.
  """
  def backend_health do
    GenServer.call(__MODULE__, :backend_health)
  end

  @doc """
  Returns the current hydration strategy.
  """
  def strategy do
    GenServer.call(__MODULE__, :strategy)
  end

  @doc """
  Flushes all pending snapshots to backends.
  """
  def flush do
    GenServer.call(__MODULE__, :flush, 30_000)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    config = Application.get_env(:sensocto, __MODULE__, [])
    merged_opts = Keyword.merge(config, opts)

    backends_config = Keyword.get(merged_opts, :backends, @default_backends)
    strategy = Keyword.get(merged_opts, :hydration_strategy, @default_strategy)

    snapshot_interval =
      Keyword.get(merged_opts, :snapshot_interval_ms, @default_snapshot_interval)

    # Initialize all backends
    backends = initialize_backends(backends_config)

    state = %__MODULE__{
      backends: backends,
      strategy: strategy,
      snapshot_interval: snapshot_interval,
      backend_health: build_health_map(backends)
    }

    Logger.info(
      "[HydrationManager] Initialized with #{length(backends)} backends, strategy: #{strategy}"
    )

    # Schedule periodic health checks
    schedule_health_check()

    {:ok, state}
  end

  @impl true
  def handle_call(:hydrate_all, _from, state) do
    emit_telemetry(:start, %{strategy: state.strategy})
    start_time = System.monotonic_time()

    {count, new_backends} = do_hydrate_all(state.backends, state.strategy)

    duration = System.monotonic_time() - start_time
    emit_telemetry(:stop, %{count: count, duration: duration})

    Logger.info("[HydrationManager] Hydrated #{count} rooms")
    {:reply, {:ok, count}, %{state | backends: new_backends}}
  end

  @impl true
  def handle_call({:hydrate_room, room_id}, _from, state) do
    {result, new_backends} = do_hydrate_room(room_id, state.backends, state.strategy)
    {:reply, result, %{state | backends: new_backends}}
  end

  @impl true
  def handle_call({:snapshot_room_sync, room_id, room_data}, _from, state) do
    snapshot = RoomBackend.create_snapshot(room_id, room_data)
    {results, new_backends} = store_to_all_backends(snapshot, state.backends)

    errors = Enum.filter(results, fn {_backend, result} -> match?({:error, _}, result) end)

    result =
      if Enum.empty?(errors) do
        :ok
      else
        {:error, Enum.map(errors, fn {backend, {:error, reason}} -> {backend, reason} end)}
      end

    {:reply, result, %{state | backends: new_backends}}
  end

  @impl true
  def handle_call(:backend_health, _from, state) do
    health = build_health_map(state.backends)
    {:reply, health, %{state | backend_health: health}}
  end

  @impl true
  def handle_call(:strategy, _from, state) do
    {:reply, state.strategy, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_backends = flush_all_backends(state.backends)
    {:reply, :ok, %{state | backends: new_backends}}
  end

  @impl true
  def handle_cast({:snapshot_room, room_id, room_data}, state) do
    snapshot = RoomBackend.create_snapshot(room_id, room_data)

    # Store async to all backends
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      store_to_all_backends_async(snapshot, state.backends)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_cast({:delete_room, room_id}, state) do
    # Delete from all backends async
    Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
      delete_from_all_backends(room_id, state.backends)
    end)

    {:noreply, state}
  end

  @impl true
  def handle_info(:health_check, state) do
    health = build_health_map(state.backends)

    # Log any backends that became unavailable
    Enum.each(health, fn {backend_id, ready} ->
      previous = Map.get(state.backend_health, backend_id, true)

      if previous && !ready do
        Logger.warning("[HydrationManager] Backend #{backend_id} became unavailable")
      end

      if !previous && ready do
        Logger.info("[HydrationManager] Backend #{backend_id} became available")
      end
    end)

    schedule_health_check()
    {:noreply, %{state | backend_health: health}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions - Initialization
  # ============================================================================

  defp initialize_backends(backends_config) do
    backends_config
    |> Enum.map(fn {module, opts} ->
      case module.init(opts) do
        {:ok, backend_state} ->
          {module, backend_state}

        {:error, reason} ->
          Logger.error("[HydrationManager] Failed to initialize #{module}: #{inspect(reason)}")
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.sort_by(fn {module, _state} -> module.priority() end)
  end

  defp build_health_map(backends) do
    Map.new(backends, fn {module, backend_state} ->
      {module.backend_id(), module.ready?(backend_state)}
    end)
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 10_000)
  end

  # ============================================================================
  # Private Functions - Hydration
  # ============================================================================

  defp do_hydrate_all(backends, strategy) do
    # Get list of room_ids from the primary backend
    {room_ids, backends} = list_all_room_ids(backends)

    # Hydrate each room
    {snapshots, backends} =
      Enum.reduce(room_ids, {[], backends}, fn room_id, {acc, current_backends} ->
        case do_hydrate_room(room_id, current_backends, strategy) do
          {{:ok, snapshot}, new_backends} ->
            {[snapshot | acc], new_backends}

          {{:error, _reason}, new_backends} ->
            {acc, new_backends}
        end
      end)

    # Notify RoomStore about hydrated rooms
    Enum.each(snapshots, fn snapshot ->
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "hydration:rooms",
        {:room_hydrated, snapshot}
      )
    end)

    {length(snapshots), backends}
  end

  defp list_all_room_ids(backends) do
    # Try each backend in order until one succeeds
    Enum.reduce_while(backends, {[], backends}, fn {module, backend_state},
                                                   {_ids, acc_backends} ->
      if module.ready?(backend_state) do
        case module.list_snapshots(backend_state) do
          {:ok, room_ids, new_state} ->
            updated = update_backend_state(acc_backends, module, new_state)
            {:halt, {room_ids, updated}}

          {:error, _reason, new_state} ->
            updated = update_backend_state(acc_backends, module, new_state)
            {:cont, {[], updated}}
        end
      else
        {:cont, {[], acc_backends}}
      end
    end)
  end

  defp do_hydrate_room(room_id, backends, :priority_fallback) do
    hydrate_priority_fallback(room_id, backends)
  end

  defp do_hydrate_room(room_id, backends, :latest) do
    hydrate_latest(room_id, backends)
  end

  defp do_hydrate_room(room_id, backends, _strategy) do
    # Default to priority_fallback
    hydrate_priority_fallback(room_id, backends)
  end

  defp hydrate_priority_fallback(room_id, backends) do
    Enum.reduce_while(backends, {{:error, :not_found}, backends}, fn {module, backend_state},
                                                                     {_result, acc_backends} ->
      if module.ready?(backend_state) do
        case module.get_snapshot(room_id, backend_state) do
          {:ok, snapshot, new_state} ->
            emit_telemetry(:backend_get, %{backend: module.backend_id(), room_id: room_id})
            updated = update_backend_state(acc_backends, module, new_state)
            {:halt, {{:ok, snapshot}, updated}}

          {:error, :not_found, new_state} ->
            updated = update_backend_state(acc_backends, module, new_state)
            {:cont, {{:error, :not_found}, updated}}

          {:error, reason, new_state} ->
            emit_telemetry(:backend_error, %{
              backend: module.backend_id(),
              room_id: room_id,
              reason: reason
            })

            updated = update_backend_state(acc_backends, module, new_state)
            {:cont, {{:error, reason}, updated}}
        end
      else
        {:cont, {{:error, :not_ready}, acc_backends}}
      end
    end)
  end

  defp hydrate_latest(room_id, backends) do
    # Query all backends and return the highest version
    {results, new_backends} =
      Enum.reduce(backends, {[], backends}, fn {module, backend_state}, {acc, current_backends} ->
        if module.ready?(backend_state) do
          case module.get_snapshot(room_id, backend_state) do
            {:ok, snapshot, new_state} ->
              updated = update_backend_state(current_backends, module, new_state)
              {[snapshot | acc], updated}

            {:error, _reason, new_state} ->
              updated = update_backend_state(current_backends, module, new_state)
              {acc, updated}
          end
        else
          {acc, current_backends}
        end
      end)

    case results do
      [] ->
        {{:error, :not_found}, new_backends}

      snapshots ->
        latest = Enum.max_by(snapshots, & &1.version)
        {{:ok, latest}, new_backends}
    end
  end

  # ============================================================================
  # Private Functions - Storage
  # ============================================================================

  defp store_to_all_backends(snapshot, backends) do
    Enum.reduce(backends, {[], backends}, fn {module, backend_state}, {results, acc_backends} ->
      if module.ready?(backend_state) do
        case module.store_snapshot(snapshot, backend_state) do
          {:ok, new_state} ->
            emit_telemetry(:backend_store, %{
              backend: module.backend_id(),
              room_id: snapshot.room_id
            })

            updated = update_backend_state(acc_backends, module, new_state)
            {[{module.backend_id(), :ok} | results], updated}

          {:error, reason, new_state} ->
            emit_telemetry(:backend_error, %{
              backend: module.backend_id(),
              room_id: snapshot.room_id,
              reason: reason
            })

            updated = update_backend_state(acc_backends, module, new_state)
            {[{module.backend_id(), {:error, reason}} | results], updated}
        end
      else
        {[{module.backend_id(), {:error, :not_ready}} | results], acc_backends}
      end
    end)
  end

  defp store_to_all_backends_async(snapshot, backends) do
    Enum.each(backends, fn {module, backend_state} ->
      if module.ready?(backend_state) do
        case module.store_snapshot(snapshot, backend_state) do
          {:ok, _new_state} ->
            emit_telemetry(:backend_store, %{
              backend: module.backend_id(),
              room_id: snapshot.room_id
            })

          {:error, reason, _new_state} ->
            emit_telemetry(:backend_error, %{
              backend: module.backend_id(),
              room_id: snapshot.room_id,
              reason: reason
            })

            Logger.warning(
              "[HydrationManager] Failed to store to #{module.backend_id()}: #{inspect(reason)}"
            )
        end
      end
    end)
  end

  defp delete_from_all_backends(room_id, backends) do
    Enum.each(backends, fn {module, backend_state} ->
      if module.ready?(backend_state) do
        case module.delete_snapshot(room_id, backend_state) do
          {:ok, _new_state} ->
            Logger.debug("[HydrationManager] Deleted room #{room_id} from #{module.backend_id()}")

          {:error, reason, _new_state} ->
            Logger.warning(
              "[HydrationManager] Failed to delete from #{module.backend_id()}: #{inspect(reason)}"
            )
        end
      end
    end)
  end

  defp flush_all_backends(backends) do
    Enum.map(backends, fn {module, backend_state} ->
      {:ok, new_state} = module.flush(backend_state)
      {module, new_state}
    end)
  end

  # ============================================================================
  # Private Functions - Utilities
  # ============================================================================

  defp update_backend_state(backends, module, new_state) do
    Enum.map(backends, fn
      {^module, _old_state} -> {module, new_state}
      other -> other
    end)
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute([:sensocto, :hydration, event], %{}, metadata)
  end
end

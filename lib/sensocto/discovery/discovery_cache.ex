defmodule Sensocto.Discovery.DiscoveryCache do
  @moduledoc """
  ETS-backed cache for distributed entity discovery.

  Provides fast local reads without cross-node calls for listing operations.
  Each node maintains its own cache that is synchronized via PubSub events.

  ## Design Principles

  1. **Fast reads**: All list operations read directly from ETS (no GenServer bottleneck)
  2. **Serialized writes**: Updates go through GenServer to prevent race conditions
  3. **Staleness tracking**: Each entry tracks when it was last updated
  4. **Graceful degradation**: Stale data preferred over blocking on remote nodes
  """
  use GenServer
  require Logger

  @sensors_table :discovery_sensors
  @staleness_threshold_ms 5_000

  # Client API - Fast ETS reads (no GenServer involved)

  @doc """
  Lists all sensors from the local cache.
  Returns immediately - does not block on remote nodes.
  """
  def list_sensors do
    case :ets.whereis(@sensors_table) do
      :undefined ->
        []

      _tid ->
        :ets.tab2list(@sensors_table)
        |> Enum.map(fn {_id, data, _updated_at} -> data end)
    end
  end

  @doc """
  Gets a sensor from cache with staleness indicator.

  Returns:
  - `{:ok, data, :fresh}` - Data is recent (within staleness threshold)
  - `{:ok, data, :stale}` - Data exists but may be outdated
  - `{:error, :not_found}` - Sensor not in cache
  """
  def get_sensor(sensor_id) do
    case :ets.whereis(@sensors_table) do
      :undefined ->
        {:error, :not_found}

      _tid ->
        case :ets.lookup(@sensors_table, sensor_id) do
          [{^sensor_id, data, updated_at}] ->
            stale? =
              System.monotonic_time(:millisecond) - updated_at > @staleness_threshold_ms

            if stale? do
              {:ok, data, :stale}
            else
              {:ok, data, :fresh}
            end

          [] ->
            {:error, :not_found}
        end
    end
  end

  @doc """
  Returns the number of sensors in the cache.
  """
  def sensor_count do
    case :ets.whereis(@sensors_table) do
      :undefined -> 0
      _tid -> :ets.info(@sensors_table, :size)
    end
  end

  # Client API - Writes go through GenServer

  @doc """
  Adds or updates a sensor in the cache.
  """
  def put_sensor(sensor_id, data) do
    GenServer.cast(__MODULE__, {:put_sensor, sensor_id, data})
  end

  @doc """
  Removes a sensor from the cache.
  """
  def delete_sensor(sensor_id) do
    GenServer.cast(__MODULE__, {:delete_sensor, sensor_id})
  end

  @doc """
  Clears all sensors from the cache.
  """
  def clear_sensors do
    GenServer.cast(__MODULE__, :clear_sensors)
  end

  # GenServer implementation

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Create ETS tables with public read access for fast concurrent reads
    :ets.new(@sensors_table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true
    ])

    Logger.info("[DiscoveryCache] Started with ETS table #{@sensors_table}")

    {:ok, %{}}
  end

  @impl true
  def handle_cast({:put_sensor, sensor_id, data}, state) do
    :ets.insert(@sensors_table, {sensor_id, data, System.monotonic_time(:millisecond)})
    {:noreply, state}
  end

  @impl true
  def handle_cast({:delete_sensor, sensor_id}, state) do
    :ets.delete(@sensors_table, sensor_id)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear_sensors, state) do
    :ets.delete_all_objects(@sensors_table)
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, _state) do
    Logger.info("[DiscoveryCache] Shutting down")
    :ok
  end
end

defmodule Sensocto.SensorsDynamicSupervisor do
  alias Sensocto.SimpleSensor
  use DynamicSupervisor

  # use Horde.DynamicSupervisor
  # alias Horde.DynamicSupervisor

  require Logger

  # https://kobrakai.de/kolumne/child-specs-in-elixir?utm_source=elixir-merge
  def start_link(test) do
    Logger.debug("#{__MODULE__}: start_link, test: #{test}")
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

  @spec init(:no_args) ::
          {:ok,
           %{
             extra_arguments: list(),
             intensity: non_neg_integer(),
             max_children: :infinity | non_neg_integer(),
             period: pos_integer(),
             strategy: :one_for_one
           }}
  def init(:no_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def add_sensor(sensor_id, configuration) do
    child_spec = %{
      id: sensor_id,
      start: {Sensocto.SensorSupervisor, :start_link, [configuration]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }

    case DynamicSupervisor.start_child(__MODULE__, child_spec) do
      # case Sensocto.RegistryUtils.dynamic_start_child(Sensocto.SensorsDynamicSupervisor, __MODULE__, child_spec) do
      {:ok, pid} when is_pid(pid) ->
        Logger.debug("Added sensor #{sensor_id}")

        # Broadcast sensor online event for rooms to auto-join
        Phoenix.PubSub.broadcast(
          Sensocto.PubSub,
          "sensors:global",
          {:sensor_online, sensor_id, configuration}
        )

        {:ok, pid}

      {:error, {:already_started, _pid}} ->
        Logger.debug("Sensor already started #{sensor_id}")
        {:ok, :already_started}

      {:error, reason} ->
        Logger.debug("error adding sensor: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def remove_sensor(sensor_id) do
    case Registry.lookup(Sensocto.SensorPairRegistry, sensor_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        Logger.debug("Stopped sensor #{sensor_id}")

        # Clean up attention tracker records for this sensor
        Sensocto.AttentionTracker.clear_sensor(sensor_id)

        # Clean up attribute store records for this sensor
        Sensocto.AttributeStoreTiered.cleanup(sensor_id)

        # Broadcast sensor offline event
        Phoenix.PubSub.broadcast(
          Sensocto.PubSub,
          "sensors:global",
          {:sensor_offline, sensor_id}
        )

        :ok

      [] ->
        Logger.debug("Error removing sensor: #{sensor_id}")
        :error
    end
  end

  @doc """
  Fetches state from all sensors in parallel using Task.async_stream.

  This is significantly faster than the sequential version when there are many sensors,
  as it fetches sensor states concurrently with a max concurrency of 10.

  ## Options
    - `mode` - :default or :view (default: :default)
    - `values` - number of values to fetch (default: 1)
    - `timeout` - timeout per sensor in ms (default: 5000)
    - `max_concurrency` - max parallel tasks (default: 10)
  """
  def get_all_sensors_state(mode \\ :default, values \\ 1, opts \\ []) do
    # Increased timeout from 5s to 10s for cross-node calls in distributed setup
    timeout = Keyword.get(opts, :timeout, 10_000)
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)

    get_device_names()
    |> Task.async_stream(
      fn sensor_id -> {sensor_id, get_sensor_state(sensor_id, mode, values)} end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(%{}, fn
      {:ok, {_sensor_id, %{} = sensor_state}}, acc ->
        Map.merge(acc, sensor_state)

      {:ok, {sensor_id, :error}}, acc ->
        # Return a minimal placeholder state so sensor remains in list
        # This prevents UI flicker when sensor state fetch times out temporarily
        Logger.debug("Error while retrieving sensor_state #{sensor_id}, using placeholder")
        Map.put(acc, sensor_id, placeholder_sensor_state(sensor_id))

      {:ok, {sensor_id, :ok}}, acc ->
        Logger.debug("get_all_sensors_state Got :ok for #{sensor_id}")
        Map.put(acc, sensor_id, placeholder_sensor_state(sensor_id))

      {:exit, {sensor_id, _reason}}, acc when is_binary(sensor_id) ->
        # Task timed out - return placeholder to keep sensor in list
        Logger.debug("Task timed out for sensor #{sensor_id}, using placeholder")
        Map.put(acc, sensor_id, placeholder_sensor_state(sensor_id))

      {:exit, reason}, acc ->
        Logger.debug("Task exited while fetching sensor state: #{inspect(reason)}")
        acc
    end)
  end

  # Minimal placeholder state for sensors that fail to respond
  # Keeps sensor in the list to avoid UI flicker
  defp placeholder_sensor_state(sensor_id) do
    %{
      sensor_id: sensor_id,
      sensor_name: sensor_id,
      sensor_type: nil,
      connector_id: nil,
      connector_name: "Loading...",
      attributes: %{},
      status: :unavailable
    }
  end

  def get_sensor_state(sensor_id, mode, values) do
    data =
      try do
        case mode do
          :view -> SimpleSensor.get_view_state(sensor_id, values)
          :default -> SimpleSensor.get_state(sensor_id, values)
        end
      catch
        :exit, reason ->
          Logger.debug(
            "Sensor process not available #{sensor_id}, mode: #{mode}, reason: #{inspect(reason)}"
          )

          :error
      end

    case data do
      %{} = sensor_state ->
        %{
          "#{sensor_id}" => sensor_state
        }

      :ok ->
        Logger.debug(
          "get_sensor_state Got :ok for #{sensor_id}, mode: #{mode}, values: #{values}"
        )

      :error ->
        Logger.debug(
          "Failed to retrieve sensor state #{sensor_id}, mode: #{mode}, values: #{values}"
        )

        :error
    end
  end

  @doc """
  Gets all sensor IDs from the distributed sensor registry.

  Uses Horde.Registry for cluster-wide sensor discovery - returns sensors
  from all nodes in the cluster.
  """
  def get_device_names do
    Horde.Registry.select(Sensocto.DistributedSensorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  # Function to extract device names (IDs) from the children list
  def get_device_names2 do
    Logger.debug("children: #{inspect(children())}")

    Enum.map(children(), fn
      {:undefined, pid, :worker, [Sensocto.SensorSupervisor]} ->
        # You can extract device ID here based on how it's registered
        # For example, assuming the device is registered with `{:via, Sensocto.Registry, device_id}`
        case Process.info(pid, :registered_name) do
          {:registered_name, device_id} ->
            device_id

          _ ->
            Logger.debug("nope")
        end

      _ ->
        Logger.debug("test")
    end)
    # Filter out nil values (if the process name is not found)
    |> Enum.filter(& &1)
  end

  # Nice utility method to check which processes are under supervision
  def children do
    DynamicSupervisor.which_children(__MODULE__)
  end

  # Nice utility method to check which processes are under supervision
  def count_children do
    DynamicSupervisor.count_children(__MODULE__)
  end
end

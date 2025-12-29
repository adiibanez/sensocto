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
        :ok

      [] ->
        Logger.debug("Error removing sensor: #{sensor_id}")
        :error
    end
  end

  def get_all_sensors_state(mode \\ :default, values \\ 1) do
    Enum.reduce(get_device_names(), %{}, fn sensor_id, acc ->
      case acc do
        %{} = __sensor_state ->
          if is_map(acc) do
            sensor_state = get_sensor_state(sensor_id, mode, values)

            if is_map(sensor_state) do
              Map.merge(acc, sensor_state)
            else
              acc
            end
          end

        :ok ->
          Logger.debug("get_all_sensors_state Got :ok for #{sensor_id}")

        :error ->
          Logger.debug("Error while retrieving sensor_state #{sensor_id}, ignore")
      end
    end)
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

  # Registry.lookup(Registry.ViaTest, "agent")
  def get_device_names do
    Registry.select(Sensocto.SensorPairRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

    # Sensocto.RegistryUtils.dynamic_select(Sensocto.SensorPairRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
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

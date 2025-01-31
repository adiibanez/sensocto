defmodule Sensocto.SensorsDynamicSupervisor do
  alias Sensocto.SimpleSensor
  use DynamicSupervisor
  require Logger

  # https://kobrakai.de/kolumne/child-specs-in-elixir?utm_source=elixir-merge
  def start_link(test) do
    IO.puts("#{__MODULE__}: start_link, test: #{test}")
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
    # :ok = Phoenix.PubSub.subscribe(Sensocto.PubSub, "sensordata:all")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # def handle_info(message) do
  #   Logger.debug("Received: #{inspect(message)}")
  # end

  # @impl true
  # def handle_infoaaaa(
  #       %Phoenix.Socket.Broadcast{
  #         topic: "sensordata:all",
  #         event: "presence_diff",
  #         payload: payload
  #       },
  #       state
  #     ) do
  #   # sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

  #   Logger.debug("DynamicSupervisor #{inspect(payload)}")

  #   # sensors_online_count = min(2, Enum.count(sensors_online))

  #   # div_class =
  #   #   "grid gap-2 grid-cols-1 md:grid-cols-" <>
  #   #     Integer.to_string(min(2, sensors_online_count)) <>
  #   #     " lg:grid-cols-" <>
  #   #     Integer.to_string(min(4, sensors_online_count))

  #   # div_class =
  #   #   "grid gap-2 grid-cols-4 sd:grid-cols-1 md:grid-cols-2 lg:grid-cols-4"

  #   # socket_to_return =
  #   #   Enum.reduce(payload.leaves, socket, fn {id, metas}, socket ->
  #   #     sensor_dom_id = "sensor_data-" <> sanitize_sensor_id(id)
  #   #     stream
  #   {:ok, state}
  # end

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

  def get_all_sensors_state() do
    Enum.reduce(get_device_names(), %{}, fn sensor_id, acc ->
      case acc do
        %{} = __sensor_state ->
          if is_map(acc) do
            Map.merge(acc, get_sensor_state(sensor_id))
          end

        :ok ->
          Logger.warning("get_all_sensors_state Got :ok for #{sensor_id}")

        :error ->
          Logger.debug("Error while retrieving sensor_state #{sensor_id}, ignore")
      end
    end)
  end

  def get_sensor_state(sensor_id) do
    case SimpleSensor.get_state(sensor_id) do
      %{} = sensor_state ->
        %{"#{sensor_id}" => sensor_state}

      :ok ->
        Logger.warning("get_sensor_state Got :ok for #{sensor_id}")

      :error ->
        Logger.warning("Failed to retrieve sensor state #{sensor_id}")
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
    IO.inspect(children())

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

  # defp via_tuple(worker_name) do
  #  # Sensocto.RegistryUtils.via_dynamic_registry(Sensocto.SensorPairRegistry, sensor_id)
  #  {:via, Registry, {Sensocto.Registry, worker_name}}
  # end
end

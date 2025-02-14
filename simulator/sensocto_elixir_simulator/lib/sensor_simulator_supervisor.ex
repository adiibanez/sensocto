defmodule SensorSimulatorSupervisor do
  use DynamicSupervisor

  # Start the DynamicSupervisor
  def start_link(_) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Function to start a new SensorDataGenServer dynamically
  def start_sensor(config) do
    child_spec = %{
      id: config[:sensor_id],
      start: {Sensocto.SensorSimulatorGenServer, :start_link, [config]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }

    IO.inspect(child_spec)

    # spec = {Sensocto.SensorSimulatorGenServer, config}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  def get_all_sensors_state() do
    Enum.reduce(get_sensor_names(), %{}, fn sensor_id, acc ->
      case acc do
        %{} = __sensor_state ->
          if is_map(acc) do
            sensor_state = get_sensor_state(sensor_id)

            if is_map(sensor_state) do
              Map.merge(acc, sensor_state)
            else
              acc
            end
          end

        :ok ->
          Logger.warning("get_all_sensors_state Got :ok for #{sensor_id}")

        :error ->
          Logger.debug("Error while retrieving sensor_state #{sensor_id}, ignore")
      end
    end)
  end

  def get_sensor_state(sensor_id) do
    case Sensocto.SensorSimulatorGenServer.get_config(sensor_id) do
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
  def get_sensor_names do
    Registry.select(SensorSimulatorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

    # Sensocto.RegistryUtils.dynamic_select(Sensocto.SensorPairRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])
  end

  def set_sensor_config(sensor_id, key, value) do
    case Registry.lookup(SensorSimulatorRegistry, sensor_id) do
      [{pid, _value}] ->
        Process.send_after(pid, {:set_config, key, value}, 0)

      [] ->
        {:error, :not_found}
    end
  end

  # Stop a sensor using its sensor_id
  def stop_sensor(sensor_id) do
    case Registry.lookup(SensorSimulatorRegistry, sensor_id) do
      [{pid, _value}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)

      [] ->
        {:error, :not_found}
    end
  end

  def get_children() do
    DynamicSupervisor.which_children(__MODULE__)
  end

  # Nice utility method to check which processes are under supervision
  def count_children() do
    DynamicSupervisor.count_children(__MODULE__)
  end
end

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
  def start_sensor(sensor_id, config) do

    child_spec = %{
      id: sensor_id,
      start: {Sensocto.SensorSimulatorGenServer, :start_link, [config]},
      shutdown: 5_000,
      restart: :permanent,
      type: :worker
    }

    IO.inspect(child_spec)

    #spec = {Sensocto.SensorSimulatorGenServer, config}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  # Stop a sensor using its sensor_id
  def stop_sensor(sensor_id) do
    case Registry.lookup(SensorRegistry, sensor_id) do
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

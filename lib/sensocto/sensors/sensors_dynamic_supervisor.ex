defmodule Sensocto.SensorsDynamicSupervisor do
  use DynamicSupervisor
  require Logger

  def start_link(test) do
    IO.puts("#{__MODULE__}: start_link, test: #{test}")
    DynamicSupervisor.start_link(__MODULE__, :no_args, name: __MODULE__)
  end

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

  defp via_tuple(sensor_id), do: {:via, Registry, {Sensocto.SensorPairRegistry, sensor_id}}
end

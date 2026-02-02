defmodule Sensocto.AttributeStoreTiered.SensorStub do
  @moduledoc """
  Minimal GenServer that satisfies the supervisor requirement for AttributeStoreTiered.

  This process holds no sensor data - all data operations go directly to ETS.
  It exists solely to:
  1. Return {:ok, pid} for SensorSupervisor compatibility
  2. Register the sensor_id in the SimpleAttributeRegistry
  3. Track sensor registration in the sensors ETS table
  """
  use GenServer
  require Logger

  @sensors_table :attribute_store_sensors

  def start_link(%{sensor_id: sensor_id} = _config) do
    GenServer.start_link(__MODULE__, sensor_id, name: via_tuple(sensor_id))
  end

  @impl true
  def init(sensor_id) do
    # Ensure tables exist (idempotent, in case TableOwner hasn't started yet)
    Sensocto.AttributeStoreTiered.TableOwner.ensure_tables()

    # Register this sensor as active
    :ets.insert(@sensors_table, {sensor_id, System.monotonic_time(:millisecond)})

    Logger.debug("AttributeStoreTiered.SensorStub started for #{sensor_id}")
    {:ok, sensor_id}
  end

  @impl true
  def terminate(_reason, sensor_id) do
    Logger.debug("AttributeStoreTiered.SensorStub terminating for #{sensor_id}")
    :ok
  end

  defp via_tuple(sensor_id) do
    {:via, Registry, {Sensocto.SimpleAttributeRegistry, sensor_id}}
  end
end

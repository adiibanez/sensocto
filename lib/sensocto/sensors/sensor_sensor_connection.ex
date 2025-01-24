defmodule Sensocto.Sensors.SensorSensorConnection do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Sensor
  alias Sensocto.Sensors.Connector
  alias Sensocto.Rooms.Room

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :sensor_id, :uuid, allow_nil?: false
    attribute :connection_id, :uuid, allow_nil?: true
  end

  relationships do
    belongs_to :sensor, Sensocto.Sensors.Sensor
    belongs_to :sensor_connection, Sensocto.Sensors.SensorConnection, allow_nil?: true
  end

  identities do
    identity :unique, keys: [:id]
  end
end

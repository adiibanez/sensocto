defmodule Sensocto.Sensors.SensorType do
  use Ash.Resource,
    domain: Sensocto.Sensors

  # alias Sensocto.Sensors.RoomSensorType
  # alias Sensocto.Sensors.ConnectorSensorType
  # alias Sensocto.Sensors.Sensor

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :name, :atom, allow_nil?: false
    attribute :allowed_attributes, {:array, :atom}, allow_nil?: true
  end

  relationships do
    # many_to_many :room_sensor_types,
    #  Sensocto.Sensors.RoomSensorType,
    #  through: :room_sensor_types

    # many_to_many :connector_sensor_types, Sensocto.Sensors.ConnectorSensorType
    # through: :connector_sensor_types

    # has_many :sensors, Sensocto.Sensors.Sensor#, on_delete: :nilify
  end

  identities do
    identity :unique, keys: [:name]
  end
end

defmodule Sensocto.Sensors.Room do
  use Ash.Resource,
    domain: Sensocto.Sensors

  # alias Sensocto.Accounts.User
  # alias Sensocto.Sensors.SensorType
  # alias Sensocto.Sensors.RoomSensorType
  # alias Sensocto.Sensors.SensorConnection

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: true
    attribute :configuration, :map, allow_nil?: true
  end

  relationships do
    # many_to_many :users, Sensocto.Accounts.User

    # many_to_many :room_sensor_types,
    #  Sensocto.Sensors.SensorType,
    #  through: Sensocto.Sensors.RoomSensorType

    # has_many :sensor_connections, Sensocto.Sensors.SensorConnection#, on_delete: :delete
  end

  identities do
    identity :unique, keys: [:id]
  end
end

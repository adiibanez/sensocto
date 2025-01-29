defmodule Sensocto.Sensors.Connector do
  use Ash.Resource,
    domain: Sensocto.Sensors

  # alias Sensocto.Accounts.User
  # alias Sensocto.Sensors.Sensor
  # alias Sensocto.Sensors.ConnectorSensorType
  # alias Sensocto.Sensors.SensorConnection

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :connector_type, :atom, allow_nil?: false
    attribute :configuration, :map, allow_nil?: true
  end

  relationships do
    # many_to_many :users, Sensocto.Accounts.User,
    # through: Sensocto.Sensors.UserConnector

    # many_to_many :connector_sensor_types,
    #   Sensocto.Sensors.SensorType,
    #   through: Sensocto.Sensors.ConnectorSensorType

    # has_many :sensors, Sensocto.Sensors.Sensor#, on_delete: :delete
    # has_many :sensor_connections, Sensocto.Sensors.SensorConnection#, on_delete: :delete
  end

  identities do
    identity :unique, keys: [:id]
  end
end

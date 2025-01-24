defmodule Sensocto.Sensors.Sensor do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Connector
  alias Sensocto.Sensors.SensorAttribute
  alias Sensocto.Sensors.SensorType
  alias Sensocto.Rooms.Room
  alias Sensocto.Sensors.SensorConnection
  # domain: Sensocto.Sensors

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :sensor_type_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :mac_address, :string do
      allow_nil? true
      public? true
    end

    attribute :configuration, :map do
      allow_nil? true
      public? true
    end

  end

  relationships do
    belongs_to :connector, Sensocto.Sensors.Connector
    belongs_to :sensor_type_rel, Sensocto.Sensors.SensorType
    has_many :attributes, Sensocto.Sensors.SensorAttribute#, on_delete: :delete
    #many_to_many :rooms, Sensocto.Rooms.Room
    many_to_many :sensor_connections, Sensocto.Sensors.SensorConnection, through: Sensocto.Sensors.SensorSensorConnection
  end

  identities do
    identity :unique, keys: [:id, :mac_address]
  end
end

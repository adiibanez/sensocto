defmodule Sensocto.Sensors.SensorConnection do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Connector
  alias Sensocto.Sensors.Room
  alias Sensocto.Sensors.Sensor

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :sensor_id, :uuid, allow_nil?: false
    attribute :connector_id, :uuid, allow_nil?: true
    attribute :room_id, :uuid, allow_nil?: true
    attribute :connected_at, :utc_datetime, allow_nil?: false
    attribute :disconnected_at, :utc_datetime, allow_nil?: true
  end

  relationships do
    belongs_to :sensor, Sensor
    belongs_to :connector, Connector, allow_nil?: true
    belongs_to :room, Room, allow_nil?: true
  end

  identities do
    identity :unique, keys: [:id]
  end
end

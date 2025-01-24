defmodule Sensocto.Sensors.SensorConnection do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Sensor
  alias Sensocto.Sensors.Connector
  alias Sensocto.Rooms.Room

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :sensor_id, :uuid, allow_nil?: false
    attribute :connector_id, :uuid, allow_nil?: true
    attribute :room_id, :uuid, allow_nil?: true
    attribute :connected_at, :utc_datetime, allow_nil?: false
    attribute :disconnected_at, :utc_datetime, allow_nil?: true
  end

  relationships do
    belongs_to :sensor, Sensocto.Sensors.Sensor
    belongs_to :connector, Sensocto.Sensors.Connector, allow_nil?: true
    belongs_to :room, Sensocto.Sensors.Room, allow_nil?: true
  end

  identities do
    identity :unique, keys: [:id]
  end
end

defmodule Sensocto.Sensors.RoomSensorType do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.SensorType
  alias Sensocto.Rooms.Room

  attributes do
    attribute :id, :uuid, primary_key?: true, allow_nil?: false
    attribute :room_id, :uuid, allow_nil?: false
    attribute :sensor_type_id, :uuid, allow_nil?: false
  end

  relationships do
    belongs_to :room, Sensocto.Sensors.Room#, primary_key?: true, allow_nil?: false
    belongs_to :sensor_type, Sensocto.Sensors.SensorType#, primary_key?: true, allow_nil?: false
  end

  identities do
    identity :unique, keys: [:id]
  end
end

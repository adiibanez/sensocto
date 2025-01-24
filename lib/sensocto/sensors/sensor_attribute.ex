defmodule Sensocto.Sensors.SensorAttribute do
  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Sensor

  attributes do
    uuid_primary_key :id
    attribute :sensor_id, :uuid, allow_nil?: false
    attribute :attribute_id, :atom, allow_nil?: false
    attribute :values, :map, default: %{values: []}
  end

  relationships do
    belongs_to :sensor, Sensocto.Sensors.Sensor
  end

  identities do
    identity :unique, keys: [:id]
  end
end

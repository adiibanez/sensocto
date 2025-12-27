defmodule Sensocto.Sensors.SensorAttribute do
  @moduledoc """
  Represents an attribute belonging to a sensor.

  Attributes are the individual data streams from a sensor (e.g., "hr", "battery", "geolocation").
  The attribute_id is stored as a string to prevent atom exhaustion attacks from untrusted input.
  """

  use Ash.Resource,
    domain: Sensocto.Sensors

  alias Sensocto.Sensors.Sensor

  attributes do
    uuid_primary_key :id
    attribute :sensor_id, :uuid, allow_nil?: false

    # Changed from :atom to :string to prevent atom exhaustion DoS
    # Format: alphanumeric with underscores/hyphens, max 64 chars
    attribute :attribute_id, :string, allow_nil?: false

    attribute :values, :map, default: %{values: []}
  end

  validations do
    # Validate attribute_id format matches SafeKeys.validate_attribute_id/1
    validate match(:attribute_id, ~r/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/),
      message: "must start with a letter and contain only alphanumeric characters, underscores, or hyphens (max 64 chars)"
  end

  relationships do
    belongs_to :sensor, Sensor
  end

  identities do
    identity :unique, keys: [:id]
  end
end

defmodule Sensocto.Sensors.SensorAttributeData do
  @moduledoc """
  Stores time-series sensor attribute data.

  Each record represents a single measurement from a sensor attribute at a specific timestamp.
  This is the primary data storage for sensor measurements, backed by PostgreSQL.
  """

  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    otp_app: :sensocto,
    domain: Sensocto.Sensors

  # simple_notifiers: [Ash.Notifier.PubSub]

  postgres do
    table "sensors_attribute_data"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:sensor_id, :attribute_id, :timestamp, :payload]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :sensor_id, :string, allow_nil?: false
    attribute :timestamp, :utc_datetime_usec, allow_nil?: false
    attribute :attribute_id, :string, allow_nil?: false
    attribute :payload, :map, default: %{}, allow_nil?: false
  end

  validations do
    # Validate attribute_id format matches SafeKeys.validate_attribute_id/1
    validate match(:attribute_id, ~r/^[a-zA-Z][a-zA-Z0-9_-]{0,63}$/),
      message: "must start with a letter and contain only alphanumeric characters, underscores, or hyphens (max 64 chars)"

    # Validate sensor_id format
    validate match(:sensor_id, ~r/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/),
      message: "must start with alphanumeric and contain only alphanumeric characters, underscores, or hyphens (max 64 chars)"
  end

  # relationships do
  #   belongs_to :sensor, Sensor
  # end

  identities do
    identity :unique, keys: [:id]
  end
end

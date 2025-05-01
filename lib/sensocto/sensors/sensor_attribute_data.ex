defmodule Sensocto.Sensors.SensorAttributeData do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    otp_app: :sensocto,
    domain: Sensocto.Sensors

  # simple_notifiers: [Ash.Notifier.PubSub]

  alias Sensocto.Sensors.Sensor

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

  # relationships do
  #   belongs_to :sensor, Sensor
  # end

  identities do
    identity :unique, keys: [:id]
  end
end

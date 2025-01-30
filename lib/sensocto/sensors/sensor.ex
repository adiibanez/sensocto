defmodule Sensocto.Sensors.Sensor do
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    otp_app: :sensocto,
    domain: Sensocto.Sensors,
    simple_notifiers: [Ash.Notifier.PubSub]

  alias Sensocto.Sensors.Connector
  alias Sensocto.Sensors.SensorAttribute
  # alias Sensocto.Rooms.Room
  alias Sensocto.Sensors.SensorConnection
  alias Sensocto.Sensors.SensorSensorConnection
  alias Sensocto.Sensors.SensorType
  # domain: Sensocto.Sensors

  postgres do
    table("sensors")
    repo(Sensocto.Repo)
  end

  actions do
    defaults([:read, :destroy, create: :*, update: :*])

    create :simple do
      accept([:name])
      # change set_attribute(:status, :open)
      upsert?(true)
    end

    create :create_from_sensorinfos do
      description("Create sensor based on information provided by connector")

      argument :name, :string do
        description("User readable sensor identification")
        allow_nil?(false)
      end

      # argument :sensor_type, :string do
      #   description "Sensor type"
      #   allow_nil? false
      # end

      # argument :sensor_id, :string do
      #   description "UUID or so"
      #   allow_nil? false
      # end

      upsert?(true)
      upsert_identity(:unique)
      #
      upsert_fields([:id])

      # Uses the information from the token to create or sign in the user
      # change AshAuthentication.Strategy.MagicLink.SignInChange

      # metadata :token, :string do
      #  allow_nil? false
      # end
    end

    update :update_sensor_name do
      description("Create sensor based on information provided by connector")

      argument :name, :string do
        description("User readable sensor identification")
        allow_nil?(false)
      end

      # upsert? true
      # upsert_identity :unique_email
      # upsert_fields [:email]#

      # Uses the information from the token to create or sign in the user
      # change AshAuthentication.Strategy.MagicLink.SignInChange

      # metadata :token, :string do
      #  allow_nil? false
      # end
    end
  end

  attributes do
    uuid_primary_key(:id)

    attribute :name, :string do
      allow_nil?(false)
      public?(true)
    end

    attribute :sensor_type_id, :uuid do
      # attribute :sensor_type, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :mac_address, :string do
      allow_nil?(true)
      public?(true)
    end

    attribute :configuration, :map do
      allow_nil?(true)
      public?(true)
    end
  end

  relationships do
    belongs_to(:connector, Connector)
    belongs_to(:sensor_type_rel, SensorType)
    # , on_delete: :delete
    has_many(:attributes, SensorAttribute)
    # many_to_many :rooms, Sensocto.Rooms.Room
    many_to_many(:sensor_connections, SensorConnection, through: SensorSensorConnection)
  end

  identities do
    identity(:unique, keys: [:id])
  end
end

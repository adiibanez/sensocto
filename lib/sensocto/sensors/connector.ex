defmodule Sensocto.Sensors.Connector do
  @moduledoc """
  Represents a connector device that bridges sensors to the platform.

  A connector is owned by a user and can have multiple sensors attached.
  Connector types include: :web (browser), :native (desktop/mobile app), :iot (IoT device).
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    otp_app: :sensocto,
    domain: Sensocto.Sensors

  alias Sensocto.Accounts.User
  alias Sensocto.Sensors.Sensor

  postgres do
    table "connectors"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :connector_type, :configuration]
      argument :user_id, :uuid, allow_nil?: false

      change manage_relationship(:user_id, :user, type: :append_and_remove)
    end

    create :register_for_user do
      description "Register a new connector for a user"
      accept [:name, :connector_type, :configuration]
      argument :user_id, :uuid, allow_nil?: false

      change manage_relationship(:user_id, :user, type: :append_and_remove)
    end

    update :update do
      accept [:name, :configuration]
    end

    read :list_for_user do
      description "List all connectors for a specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(user_id == ^arg(:user_id))
    end

    read :get_with_sensors do
      description "Get a connector with all its sensors loaded"
      argument :id, :uuid, allow_nil?: false
      get? true

      filter expr(id == ^arg(:id))
      prepare build(load: [:sensors])
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :connector_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:web, :native, :iot, :simulator]
    end

    attribute :configuration, :map do
      allow_nil? true
      public? true
    end

    attribute :last_seen_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :status, :atom do
      allow_nil? false
      default :offline
      public? true
      constraints one_of: [:online, :offline, :idle]
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, User do
      allow_nil? false
    end

    has_many :sensors, Sensor
  end

  identities do
    identity :unique_name_per_user, [:user_id, :name]
  end
end

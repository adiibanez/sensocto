defmodule Sensocto.Sensors.Connector do
  @moduledoc """
  Represents a connector device that bridges sensors to the platform.

  Connectors are persisted in Postgres with user ownership. Runtime-only state
  (pid, node) is tracked in the ConnectorManager GenServer state, not in the
  database.

  Connector types include:
  - `:web` - Browser-based connector
  - `:native` - Desktop/mobile app connector
  - `:iot` - IoT device connector
  - `:simulator` - Test/simulation connector

  ## Usage

      # Register a connector when client connects
      {:ok, connector} = Sensocto.Sensors.Connector.register(%{
        name: "Chrome_mac",
        connector_type: :web,
        user_id: user.id
      })

      # List user's active connectors
      connectors = Sensocto.Sensors.Connector.list_for_user(user.id)

      # Update connector status
      Sensocto.Sensors.Connector.set_online(connector_id)

      # Mark offline on disconnect (soft-unregister)
      Sensocto.Sensors.Connector.set_offline(connector_id)
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Sensocto.Sensors.Sensor

  postgres do
    table "connectors"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    create :register do
      description "Register a new connector when client connects"
      accept [:name, :connector_type, :configuration, :user_id]

      change set_attribute(:status, :online)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
      change set_attribute(:connected_at, &DateTime.utc_now/0)
    end

    update :set_online do
      description "Mark connector as online and update last_seen_at"
      accept []
      require_atomic? false

      change set_attribute(:status, :online)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    update :set_offline do
      description "Mark connector as offline"
      accept []
      require_atomic? false

      change set_attribute(:status, :offline)
    end

    update :set_idle do
      description "Mark connector as idle (connected but inactive)"
      accept []
      require_atomic? false

      change set_attribute(:status, :idle)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    update :heartbeat do
      description "Update last_seen_at timestamp"
      accept []
      require_atomic? false

      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    update :rename do
      description "Rename a connector"
      accept [:name]
      require_atomic? false
    end

    read :list_for_user do
      description "List all connectors for a specific user"
      argument :user_id, :uuid, allow_nil?: false

      filter expr(user_id == ^arg(:user_id))
    end

    read :list_online do
      description "List all online connectors"

      filter expr(status == :online)
    end

    read :get_by_id do
      description "Get a connector by ID"
      argument :id, :uuid, allow_nil?: false
      get? true

      filter expr(id == ^arg(:id))
    end

    read :get_with_sensors do
      description "Get a connector by ID with sensors loaded"
      argument :id, :uuid, allow_nil?: false
      get? true

      filter expr(id == ^arg(:id))
      prepare build(load: [:sensors])
    end

    destroy :forget do
      description "Remove a connector permanently (user action)"
    end
  end

  policies do
    # Allow internal (no actor) calls — ConnectorManager, system processes
    bypass action(:register) do
      authorize_if always()
    end

    bypass action([:set_online, :set_offline, :set_idle, :heartbeat]) do
      authorize_if always()
    end

    bypass action([:read, :list_for_user, :list_online, :get_by_id, :get_with_sensors]) do
      authorize_if always()
    end

    # User-scoped actions: users manage their own connectors
    policy action([:rename, :forget]) do
      authorize_if expr(user_id == ^actor(:id))
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

    attribute :user_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :last_seen_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :connected_at, :utc_datetime_usec do
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
    has_many :sensors, Sensor

    belongs_to :user, Sensocto.Accounts.User do
      allow_nil? true
      attribute_writable? true
      define_attribute? false
      destination_attribute :id
      source_attribute :user_id
    end
  end

  identities do
    identity :unique_id, [:id]
  end
end

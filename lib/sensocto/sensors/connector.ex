defmodule Sensocto.Sensors.Connector do
  @moduledoc """
  Represents a connector device that bridges sensors to the platform.

  Connectors are stored in ETS (in-memory) for fast access and are distributed
  across nodes using :pg process groups for coordination.

  A connector represents an active connection - it is created when a client connects
  and removed when they disconnect. For persistent device information, use the
  Device resource instead.

  Connector types include:
  - `:web` - Browser-based connector
  - `:native` - Desktop/mobile app connector
  - `:iot` - IoT device connector
  - `:simulator` - Test/simulation connector

  ## Usage

      # Register a connector when client connects
      {:ok, connector} = Sensocto.Sensors.Connector.register(%{
        id: socket_id,
        name: "Chrome_mac",
        connector_type: :web,
        user_id: user.id
      })

      # List user's active connectors
      connectors = Sensocto.Sensors.Connector.list_for_user(user.id)

      # Update connector status
      Sensocto.Sensors.Connector.set_online(connector_id)

      # Remove connector on disconnect
      Sensocto.Sensors.Connector.unregister(connector_id)
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: Ash.DataLayer.Ets

  alias Sensocto.Sensors.Sensor

  # ETS configuration for in-memory storage
  ets do
    private? true
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]

    create :register do
      description "Register a new connector when client connects"
      accept [:id, :name, :connector_type, :configuration, :user_id]

      change set_attribute(:status, :online)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
      change set_attribute(:connected_at, &DateTime.utc_now/0)
    end

    update :set_online do
      description "Mark connector as online and update last_seen_at"
      accept []

      change set_attribute(:status, :online)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    update :set_offline do
      description "Mark connector as offline"
      accept []

      change set_attribute(:status, :offline)
    end

    update :set_idle do
      description "Mark connector as idle (connected but inactive)"
      accept []

      change set_attribute(:status, :idle)
      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
    end

    update :heartbeat do
      description "Update last_seen_at timestamp"
      accept []

      change set_attribute(:last_seen_at, &DateTime.utc_now/0)
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

    attribute :node, :atom do
      allow_nil? true
      public? true
      description "The Erlang node this connector is on"
    end

    attribute :pid, :term do
      allow_nil? true
      public? true
      description "The process handling this connector"
    end
  end

  relationships do
    has_many :sensors, Sensor
  end

  identities do
    identity :unique_id, [:id]
  end
end

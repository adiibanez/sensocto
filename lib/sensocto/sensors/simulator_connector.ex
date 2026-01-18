defmodule Sensocto.Sensors.SimulatorConnector do
  @moduledoc """
  Ash resource for persisting simulator connector state.
  Tracks connectors within scenarios for restart recovery.
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "simulator_connectors"
    repo Sensocto.Repo

    references do
      reference :scenario, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:connector_id, :connector_name, :room_id, :sensors_config, :scenario_id]
    end

    create :sync_create do
      accept [:connector_id, :connector_name, :room_id, :sensors_config, :scenario_id]

      argument :id, :uuid, allow_nil?: true

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :id) do
          nil -> changeset
          id -> Ash.Changeset.force_change_attribute(changeset, :id, id)
        end
      end
    end

    read :by_scenario do
      argument :scenario_id, :uuid, allow_nil?: false
      filter expr(scenario_id == ^arg(:scenario_id))
    end

    read :by_connector_id do
      argument :connector_id, :string, allow_nil?: false
      get? true
      filter expr(connector_id == ^arg(:connector_id))
    end

    read :all
  end

  attributes do
    uuid_primary_key :id

    attribute :connector_id, :string do
      allow_nil? false
      description "Logical connector ID from YAML config"
    end

    attribute :connector_name, :string do
      allow_nil? false
      constraints max_length: 100
    end

    attribute :room_id, :uuid do
      allow_nil? true
    end

    attribute :sensors_config, :map do
      default %{}
      description "Original YAML sensor configuration"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :scenario, Sensocto.Sensors.SimulatorScenario do
      allow_nil? false
      attribute_type :uuid
    end

    has_many :track_positions, Sensocto.Sensors.SimulatorTrackPosition do
      destination_attribute :connector_id
    end

    has_many :battery_states, Sensocto.Sensors.SimulatorBatteryState do
      destination_attribute :connector_id
    end
  end

  identities do
    identity :unique_connector_per_scenario, [:scenario_id, :connector_id]
  end
end

defmodule Sensocto.Sensors.SimulatorScenario do
  @moduledoc """
  Ash resource for persisting simulator scenario state.
  Tracks running scenarios so they can survive server restarts.
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "simulator_scenarios"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :start do
      accept [:name, :room_id, :room_name, :config_path]

      change set_attribute(:status, :running)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    create :sync_create do
      accept [:name, :room_id, :room_name, :config_path, :status, :started_at]

      argument :id, :uuid, allow_nil?: true

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :id) do
          nil -> changeset
          id -> Ash.Changeset.force_change_attribute(changeset, :id, id)
        end
      end
    end

    update :stop do
      change set_attribute(:status, :stopped)
      change set_attribute(:stopped_at, &DateTime.utc_now/0)
    end

    update :pause do
      change set_attribute(:status, :paused)
    end

    update :resume do
      change set_attribute(:status, :running)
    end

    read :running do
      filter expr(status == :running)
    end

    read :by_name do
      argument :name, :string, allow_nil?: false
      get? true
      filter expr(name == ^arg(:name) and status == :running)
    end

    read :by_room do
      argument :room_id, :uuid, allow_nil?: false
      filter expr(room_id == ^arg(:room_id) and status == :running)
    end

    read :all
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      constraints min_length: 1, max_length: 100
      description "Scenario name from YAML config"
    end

    attribute :room_id, :uuid do
      allow_nil? true
      description "Associated room ID"
    end

    attribute :room_name, :string do
      allow_nil? true
      constraints max_length: 100
    end

    attribute :config_path, :string do
      allow_nil? false
      description "Path to YAML scenario file"
    end

    attribute :status, :atom do
      constraints one_of: [:running, :stopped, :paused]
      default :stopped
      allow_nil? false
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
    end

    attribute :stopped_at, :utc_datetime_usec do
      allow_nil? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :room, Sensocto.Sensors.Room do
      source_attribute :room_id
      destination_attribute :id
      allow_nil? true
      define_attribute? false
    end

    has_many :connectors, Sensocto.Sensors.SimulatorConnector do
      destination_attribute :scenario_id
    end
  end

  identities do
    identity :unique_name_per_room, [:name, :room_id]
  end
end

defmodule Sensocto.Sensors.SimulatorBatteryState do
  @moduledoc """
  Ash resource for persisting battery simulation state.
  Allows battery levels to persist across server restarts.
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "simulator_battery_states"
    repo Sensocto.Repo

    references do
      reference :connector, on_delete: :delete
    end
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:sensor_id, :level, :charging, :drain_multiplier, :charge_multiplier, :connector_id]
    end

    create :sync_create do
      accept [:sensor_id, :level, :charging, :drain_multiplier, :charge_multiplier, :connector_id]

      argument :id, :uuid, allow_nil?: true

      change fn changeset, _context ->
        case Ash.Changeset.get_argument(changeset, :id) do
          nil -> changeset
          id -> Ash.Changeset.force_change_attribute(changeset, :id, id)
        end
      end
    end

    update :sync_state do
      accept [:level, :charging, :drain_multiplier, :charge_multiplier]
    end

    read :by_connector do
      argument :connector_id, :uuid, allow_nil?: false
      filter expr(connector_id == ^arg(:connector_id))
    end

    read :by_sensor do
      argument :sensor_id, :string, allow_nil?: false
      get? true
      filter expr(sensor_id == ^arg(:sensor_id))
    end

    read :all
  end

  attributes do
    uuid_primary_key :id

    attribute :sensor_id, :string do
      allow_nil? false
    end

    attribute :level, :float do
      constraints min: 0.0, max: 100.0
      default 50.0
      description "Battery level percentage"
    end

    attribute :charging, :boolean do
      default false
    end

    attribute :drain_multiplier, :float do
      default 1.0
      description "Per-sensor drain rate variance"
    end

    attribute :charge_multiplier, :float do
      default 1.0
      description "Per-sensor charge rate variance"
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :connector, Sensocto.Sensors.SimulatorConnector do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_sensor_battery, [:connector_id, :sensor_id]
  end
end

defmodule Sensocto.Repo.Migrations.AddSimulatorPersistence do
  @moduledoc """
  Creates tables for simulator state persistence.
  Allows simulator scenarios to survive server restarts.
  """

  use Ecto.Migration

  def up do
    # Create simulator scenarios table
    create table(:simulator_scenarios, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :room_id, references(:rooms, column: :id, type: :uuid, on_delete: :nilify_all)
      add :room_name, :text
      add :config_path, :text, null: false
      add :status, :text, null: false, default: "stopped"
      add :started_at, :utc_datetime_usec
      add :stopped_at, :utc_datetime_usec

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:simulator_scenarios, [:status])
    create index(:simulator_scenarios, [:room_id])

    create unique_index(:simulator_scenarios, [:name, :room_id],
             name: "simulator_scenarios_unique_name_per_room_index"
           )

    # Create simulator connectors table
    create table(:simulator_connectors, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :connector_id, :text, null: false
      add :connector_name, :text, null: false
      add :room_id, :uuid
      add :sensors_config, :map, default: %{}

      add :scenario_id,
          references(:simulator_scenarios, column: :id, type: :uuid, on_delete: :delete_all),
          null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:simulator_connectors, [:scenario_id, :connector_id],
             name: "simulator_connectors_unique_connector_per_scenario_index"
           )

    create index(:simulator_connectors, [:scenario_id])

    # Create simulator track positions table
    create table(:simulator_track_positions, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :sensor_id, :text, null: false
      add :track_name, :text
      add :track_mode, :text
      add :current_time_s, :float, default: 0.0
      add :playback_speed, :float, default: 1.0
      add :loop, :boolean, default: true
      add :last_position, :map, default: %{}

      add :connector_id,
          references(:simulator_connectors, column: :id, type: :uuid, on_delete: :delete_all),
          null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:simulator_track_positions, [:connector_id, :sensor_id],
             name: "simulator_track_positions_unique_sensor_track_index"
           )

    create index(:simulator_track_positions, [:connector_id])

    # Create simulator battery states table
    create table(:simulator_battery_states, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :sensor_id, :text, null: false
      add :level, :float, default: 50.0
      add :charging, :boolean, default: false
      add :drain_multiplier, :float, default: 1.0
      add :charge_multiplier, :float, default: 1.0

      add :connector_id,
          references(:simulator_connectors, column: :id, type: :uuid, on_delete: :delete_all),
          null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:simulator_battery_states, [:connector_id, :sensor_id],
             name: "simulator_battery_states_unique_sensor_battery_index"
           )

    create index(:simulator_battery_states, [:connector_id])
  end

  def down do
    drop_if_exists table(:simulator_battery_states)
    drop_if_exists table(:simulator_track_positions)
    drop_if_exists table(:simulator_connectors)
    drop_if_exists table(:simulator_scenarios)
  end
end

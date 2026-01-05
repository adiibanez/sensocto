defmodule Sensocto.Repo.Migrations.AddScaleIndexes do
  @moduledoc """
  Adds indexes to support scaling to 100s-1000s of sensors.

  These indexes optimize:
  - Time-series queries on sensor_attribute_data
  - Sensor lookups by various fields
  """
  use Ecto.Migration

  def change do
    # Primary index for time-series queries
    # Covers: SELECT * FROM sensors_attribute_data WHERE sensor_id = ? AND attribute_id = ? ORDER BY timestamp DESC
    create_if_not_exists index(:sensors_attribute_data, [:sensor_id, :attribute_id, :timestamp],
                           name: "sensors_attribute_data_sensor_attr_time_idx")

    # Index for querying all attributes of a sensor
    create_if_not_exists index(:sensors_attribute_data, [:sensor_id, :timestamp],
                           name: "sensors_attribute_data_sensor_time_idx")

    # Index for time-range queries across all sensors
    create_if_not_exists index(:sensors_attribute_data, [:timestamp],
                           name: "sensors_attribute_data_timestamp_idx")
  end
end

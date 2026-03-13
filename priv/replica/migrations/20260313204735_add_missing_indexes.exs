defmodule Sensocto.Repo.Migrations.AddMissingIndexes do
  use Ecto.Migration

  def change do
    # Compound indexes for time-series queries on sensor attribute data
    create_if_not_exists index(:sensors_attribute_data, [:sensor_id, :timestamp])

    create_if_not_exists index(:sensors_attribute_data, [
                           :sensor_id,
                           :attribute_id,
                           :timestamp
                         ])

    # Indexes for guided_sessions queries (used in lobby mount)
    create_if_not_exists index(:guided_sessions, [:guide_user_id])
    create_if_not_exists index(:guided_sessions, [:status])
    create_if_not_exists index(:guided_sessions, [:follower_user_id])
  end
end

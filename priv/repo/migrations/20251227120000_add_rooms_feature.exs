defmodule Sensocto.Repo.Migrations.AddRoomsFeature do
  @moduledoc """
  Adds rooms and room_memberships tables for the rooms feature.
  """
  use Ecto.Migration

  def up do
    # Create rooms table
    create table(:rooms, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false
      add :description, :text
      add :configuration, :map, default: %{}
      add :is_public, :boolean, null: false, default: true
      add :is_persisted, :boolean, null: false, default: true
      add :join_code, :text
      add :owner_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:rooms, [:join_code], name: "rooms_unique_join_code_index")
    create index(:rooms, [:owner_id])
    create index(:rooms, [:is_public])

    # Create room_memberships table
    create table(:room_memberships, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :role, :text, null: false, default: "member"
      add :joined_at, :utc_datetime_usec, null: false, default: fragment("(now() AT TIME ZONE 'utc')")
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
    end

    create unique_index(:room_memberships, [:room_id, :user_id], name: "room_memberships_unique_membership_index")
    create index(:room_memberships, [:user_id])

    # Add room_id to sensor_connections if the table exists
    # Check if sensor_connections table exists first
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'sensor_connections') THEN
        IF NOT EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'sensor_connections' AND column_name = 'room_id') THEN
          ALTER TABLE sensor_connections ADD COLUMN room_id UUID REFERENCES rooms(id) ON DELETE SET NULL;
          CREATE INDEX IF NOT EXISTS sensor_connections_room_id_index ON sensor_connections(room_id);
        END IF;
      END IF;
    END $$;
    """
  end

  def down do
    # Remove room_id from sensor_connections if it exists
    execute """
    DO $$
    BEGIN
      IF EXISTS (SELECT FROM information_schema.columns WHERE table_name = 'sensor_connections' AND column_name = 'room_id') THEN
        DROP INDEX IF EXISTS sensor_connections_room_id_index;
        ALTER TABLE sensor_connections DROP COLUMN room_id;
      END IF;
    END $$;
    """

    drop_if_exists unique_index(:room_memberships, [:room_id, :user_id], name: "room_memberships_unique_membership_index")
    drop_if_exists index(:room_memberships, [:user_id])
    drop_if_exists table(:room_memberships)

    drop_if_exists unique_index(:rooms, [:join_code], name: "rooms_unique_join_code_index")
    drop_if_exists index(:rooms, [:owner_id])
    drop_if_exists index(:rooms, [:is_public])
    drop_if_exists table(:rooms)
  end
end

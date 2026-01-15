defmodule Sensocto.Repo.Migrations.CreateObject3dPlaylists do
  @moduledoc """
  Creates object3d_playlists and object3d_playlist_items tables for synchronized 3D object viewing.
  """
  use Ecto.Migration

  def up do
    # Create object3d_playlists table
    create table(:object3d_playlists, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false, default: "3D Objects"
      add :room_id, references(:rooms, type: :uuid, on_delete: :delete_all), null: true
      add :is_lobby, :boolean, null: false, default: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    # Only one lobby playlist allowed
    create unique_index(:object3d_playlists, [:is_lobby],
      where: "is_lobby = true",
      name: "object3d_playlists_unique_lobby_index"
    )

    # One playlist per room
    create unique_index(:object3d_playlists, [:room_id],
      where: "room_id IS NOT NULL",
      name: "object3d_playlists_unique_room_index"
    )

    create index(:object3d_playlists, [:room_id])

    # Create object3d_playlist_items table
    create table(:object3d_playlist_items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :playlist_id, references(:object3d_playlists, type: :uuid, on_delete: :delete_all),
        null: false

      add :splat_url, :text, null: false
      add :name, :text
      add :description, :text
      add :thumbnail_url, :text
      add :source_url, :text
      # Default camera position as "x,y,z"
      add :camera_preset_position, :text
      # Default camera target as "x,y,z"
      add :camera_preset_target, :text
      add :added_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all), null: true
      add :position, :integer, null: false, default: 0
      add :viewed_at, :utc_datetime_usec, null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:object3d_playlist_items, [:playlist_id])
    create index(:object3d_playlist_items, [:playlist_id, :position])
    create index(:object3d_playlist_items, [:added_by_user_id])
  end

  def down do
    drop_if_exists index(:object3d_playlist_items, [:added_by_user_id])
    drop_if_exists index(:object3d_playlist_items, [:playlist_id, :position])
    drop_if_exists index(:object3d_playlist_items, [:playlist_id])
    drop_if_exists table(:object3d_playlist_items)

    drop_if_exists index(:object3d_playlists, [:room_id])
    drop_if_exists unique_index(:object3d_playlists, [:room_id], name: "object3d_playlists_unique_room_index")
    drop_if_exists unique_index(:object3d_playlists, [:is_lobby], name: "object3d_playlists_unique_lobby_index")
    drop_if_exists table(:object3d_playlists)
  end
end

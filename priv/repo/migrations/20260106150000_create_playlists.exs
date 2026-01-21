defmodule Sensocto.Repo.Migrations.CreatePlaylists do
  @moduledoc """
  Creates playlists and playlist_items tables for synchronized YouTube playback.
  """
  use Ecto.Migration

  def up do
    # Create playlists table
    create table(:playlists, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :name, :text, null: false, default: "Playlist"
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
    create unique_index(:playlists, [:is_lobby],
             where: "is_lobby = true",
             name: "playlists_unique_lobby_index"
           )

    # One playlist per room
    create unique_index(:playlists, [:room_id],
             where: "room_id IS NOT NULL",
             name: "playlists_unique_room_index"
           )

    create index(:playlists, [:room_id])

    # Create playlist_items table
    create table(:playlist_items, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :playlist_id, references(:playlists, type: :uuid, on_delete: :delete_all), null: false
      add :youtube_url, :text, null: false
      add :youtube_video_id, :text, null: false
      add :title, :text
      add :duration_seconds, :integer
      add :thumbnail_url, :text
      add :added_by_user_id, references(:users, type: :uuid, on_delete: :nilify_all), null: true
      add :position, :integer, null: false, default: 0
      add :played_at, :utc_datetime_usec, null: true

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:playlist_items, [:playlist_id])
    create index(:playlist_items, [:playlist_id, :position])
    create index(:playlist_items, [:added_by_user_id])
  end

  def down do
    drop_if_exists index(:playlist_items, [:added_by_user_id])
    drop_if_exists index(:playlist_items, [:playlist_id, :position])
    drop_if_exists index(:playlist_items, [:playlist_id])
    drop_if_exists table(:playlist_items)

    drop_if_exists index(:playlists, [:room_id])
    drop_if_exists unique_index(:playlists, [:room_id], name: "playlists_unique_room_index")
    drop_if_exists unique_index(:playlists, [:is_lobby], name: "playlists_unique_lobby_index")
    drop_if_exists table(:playlists)
  end
end

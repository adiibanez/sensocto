defmodule Sensocto.Repo.Migrations.RemovePlaylistsRoomFk do
  @moduledoc """
  Removes the foreign key constraint from playlists.room_id since rooms
  are now stored in-memory (via RoomStore with Iroh sync) rather than PostgreSQL.

  The room_id column is kept to associate playlists with rooms, but without
  the FK constraint that would require the room to exist in the database.
  """
  use Ecto.Migration

  def up do
    # Drop the existing foreign key constraint
    drop constraint(:playlists, "playlists_room_id_fkey")

    # Keep the index for performance
    # The unique index already exists from the original migration
  end

  def down do
    # Re-add the foreign key constraint
    # Note: This will fail if there are playlists with room_ids that don't exist in rooms table
    alter table(:playlists) do
      modify :room_id, references(:rooms, type: :uuid, on_delete: :delete_all),
        from: {:uuid, null: true}
    end
  end
end

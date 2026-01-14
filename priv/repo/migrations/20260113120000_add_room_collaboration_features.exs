defmodule Sensocto.Repo.Migrations.AddRoomCollaborationFeatures do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :media_playback_enabled, :boolean, default: true, null: false
      add :object_3d_enabled, :boolean, default: false, null: false
    end
  end
end

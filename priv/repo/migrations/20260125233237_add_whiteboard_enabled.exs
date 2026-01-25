defmodule Sensocto.Repo.Migrations.AddWhiteboardEnabled do
  @moduledoc """
  Add whiteboard_enabled flag to rooms table.
  """

  use Ecto.Migration

  def up do
    alter table(:rooms) do
      add :whiteboard_enabled, :boolean, null: false, default: false
    end
  end

  def down do
    alter table(:rooms) do
      remove :whiteboard_enabled
    end
  end
end

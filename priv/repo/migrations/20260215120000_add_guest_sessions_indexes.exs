defmodule Sensocto.Repo.Migrations.AddGuestSessionsIndexes do
  use Ecto.Migration

  def change do
    create_if_not_exists index(:guest_sessions, [:token])
    create_if_not_exists index(:guest_sessions, [:last_active_at])
  end
end

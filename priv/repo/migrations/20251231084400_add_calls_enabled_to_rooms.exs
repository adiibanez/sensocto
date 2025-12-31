defmodule Sensocto.Repo.Migrations.AddCallsEnabledToRooms do
  use Ecto.Migration

  def change do
    alter table(:rooms) do
      add :calls_enabled, :boolean, default: true, null: false
    end
  end
end

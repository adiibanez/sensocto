defmodule Sensocto.Repo.Migrations.AddUserProfileFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :display_name, :text
      add :avatar_url, :text
      add :bio, :text
      add :status_emoji, :string, size: 10
      add :timezone, :string, default: "Europe/Berlin"
      add :is_public, :boolean, default: true, null: false
    end

    create index(:users, [:display_name])
  end
end

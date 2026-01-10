defmodule Sensocto.Repo.Replica.Migrations.AddUserPreferences do
  use Ecto.Migration

  def change do
    create table(:user_preferences, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      # UI State preferences stored as flexible JSON
      add :ui_state, :map, default: %{}

      # Last visited path for navigation resumption
      add :last_visited_path, :string

      # Timestamps
      timestamps()
    end

    create unique_index(:user_preferences, [:user_id])
  end
end

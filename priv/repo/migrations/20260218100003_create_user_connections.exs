defmodule Sensocto.Repo.Migrations.CreateUserConnections do
  use Ecto.Migration

  def change do
    create table(:user_connections, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :from_user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :to_user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :connection_type, :text, null: false, default: "follows"
      add :strength, :integer, null: false, default: 5

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:user_connections, [:from_user_id, :to_user_id, :connection_type],
             name: "user_connections_unique_connection_index"
           )

    create index(:user_connections, [:from_user_id])
    create index(:user_connections, [:to_user_id])
  end
end

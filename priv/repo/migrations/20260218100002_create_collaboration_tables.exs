defmodule Sensocto.Repo.Migrations.CreateCollaborationTables do
  use Ecto.Migration

  def change do
    create table(:polls, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :title, :text, null: false
      add :description, :text
      add :poll_type, :text, null: false, default: "single_choice"
      add :status, :text, null: false, default: "draft"
      add :visibility, :text, null: false, default: "public"
      add :results_visible, :text, null: false, default: "always"
      add :closes_at, :utc_datetime_usec
      add :room_id, references(:rooms, type: :uuid, on_delete: :nilify_all)
      add :creator_id, references(:users, type: :uuid, on_delete: :delete_all), null: false

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :updated_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:polls, [:creator_id])
    create index(:polls, [:room_id])
    create index(:polls, [:status])

    create table(:poll_options, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :poll_id, references(:polls, type: :uuid, on_delete: :delete_all), null: false
      add :label, :text, null: false
      add :position, :integer, null: false, default: 0

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create index(:poll_options, [:poll_id])

    create table(:votes, primary_key: false) do
      add :id, :uuid, null: false, default: fragment("gen_random_uuid()"), primary_key: true
      add :poll_id, references(:polls, type: :uuid, on_delete: :delete_all), null: false
      add :option_id, references(:poll_options, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, type: :uuid, on_delete: :delete_all), null: false
      add :weight, :integer, null: false, default: 1

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end

    create unique_index(:votes, [:poll_id, :user_id, :option_id],
             name: "votes_unique_poll_user_option_index"
           )

    create index(:votes, [:poll_id])
    create index(:votes, [:user_id])
  end
end

defmodule Sensocto.Repo.Migrations.CreateGuestSessions do
  @moduledoc """
  Creates the guest_sessions table for persisting guest user sessions.
  """

  use Ecto.Migration

  def up do
    create table(:guest_sessions, primary_key: false) do
      add :id, :text, null: false, primary_key: true
      add :display_name, :text, null: false
      add :token, :text, null: false

      add :last_active_at, :utc_datetime,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")

      add :inserted_at, :utc_datetime_usec,
        null: false,
        default: fragment("(now() AT TIME ZONE 'utc')")
    end
  end

  def down do
    drop table(:guest_sessions)
  end
end

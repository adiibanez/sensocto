defmodule Sensocto.Accounts.GuestSession do
  @moduledoc """
  Persistent storage for guest user sessions.

  Guest sessions are stored in the database to survive server restarts.
  Each guest has a unique ID and token for authentication, plus a display name
  and activity tracking for cleanup of stale sessions.
  """
  use Ash.Resource,
    data_layer: AshPostgres.DataLayer,
    otp_app: :sensocto,
    domain: Sensocto.Accounts

  postgres do
    table "guest_sessions"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:id, :display_name, :token]
    end

    update :touch do
      accept []
      change set_attribute(:last_active_at, &DateTime.utc_now/0)
    end

    read :by_id do
      get? true
      argument :id, :string, allow_nil?: false
      filter expr(id == ^arg(:id))
    end

    read :expired do
      argument :before, :utc_datetime, allow_nil?: false
      filter expr(last_active_at < ^arg(:before))
    end

    destroy :cleanup_expired do
      argument :before, :utc_datetime, allow_nil?: false
      change filter(expr(last_active_at < ^arg(:before)))
    end
  end

  attributes do
    attribute :id, :string do
      primary_key? true
      allow_nil? false
      public? true
    end

    attribute :display_name, :string do
      allow_nil? false
      public? true
    end

    attribute :token, :string do
      allow_nil? false
      sensitive? true
    end

    attribute :last_active_at, :utc_datetime do
      allow_nil? false
      default &DateTime.utc_now/0
    end

    create_timestamp :inserted_at
  end
end

defmodule Sensocto.Guidance.GuidedSession do
  use Ash.Resource,
    domain: Sensocto.Guidance,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "guided_sessions"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:follower_user_id, :room_id, :drift_back_seconds]

      argument :guide_user_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:guide_user_id, arg(:guide_user_id))
      change set_attribute(:status, :pending)

      change fn changeset, _context ->
        Ash.Changeset.force_change_attribute(changeset, :invite_code, generate_invite_code())
      end
    end

    update :assign_follower do
      accept [:follower_user_id]
    end

    update :accept do
      accept []
      change set_attribute(:status, :active)
      change set_attribute(:started_at, &DateTime.utc_now/0)
    end

    update :decline do
      accept []
      change set_attribute(:status, :declined)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
    end

    update :end_session do
      accept []
      change set_attribute(:status, :ended)
      change set_attribute(:ended_at, &DateTime.utc_now/0)
    end

    read :by_invite_code do
      argument :invite_code, :string, allow_nil?: false
      get? true
      filter expr(invite_code == ^arg(:invite_code) and status in [:pending, :active])
    end

    read :active_for_user do
      argument :user_id, :uuid, allow_nil?: false

      filter expr(
               status == :active and
                 (guide_user_id == ^arg(:user_id) or follower_user_id == ^arg(:user_id))
             )
    end

    read :pending_for_others do
      argument :user_id, :uuid, allow_nil?: false

      filter expr(
               status == :pending and
                 guide_user_id != ^arg(:user_id) and
                 is_nil(follower_user_id)
             )
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:pending, :active, :ended, :declined]
      default :pending
    end

    attribute :guide_user_id, :uuid do
      allow_nil? false
    end

    attribute :follower_user_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :room_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :invite_code, :string do
      allow_nil? false
    end

    attribute :drift_back_seconds, :integer do
      allow_nil? false
      public? true
      default 15
      constraints min: 5, max: 120
    end

    attribute :started_at, :utc_datetime_usec do
      allow_nil? true
    end

    attribute :ended_at, :utc_datetime_usec do
      allow_nil? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_invite_code, [:invite_code]
  end

  @doc """
  Generates a 6-character invite code from an unambiguous alphabet.
  """
  def generate_invite_code(length \\ 6) do
    alphabet = ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

    1..length
    |> Enum.map(fn _ -> Enum.random(alphabet) end)
    |> List.to_string()
  end
end

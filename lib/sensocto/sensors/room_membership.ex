defmodule Sensocto.Sensors.RoomMembership do
  @moduledoc """
  Join table for room memberships.
  Tracks which users are members of which rooms and their roles.
  """
  use Ash.Resource,
    domain: Sensocto.Sensors,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "room_memberships"
    repo Sensocto.Repo
  end

  attributes do
    uuid_primary_key :id

    attribute :role, :atom do
      constraints one_of: [:owner, :admin, :member]
      default :member
      allow_nil? false
    end

    attribute :joined_at, :utc_datetime_usec do
      default &DateTime.utc_now/0
      allow_nil? false
    end
  end

  relationships do
    belongs_to :room, Sensocto.Sensors.Room do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :user, Sensocto.Accounts.User do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_membership, [:room_id, :user_id]
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:role]
      argument :room_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      change manage_relationship(:room_id, :room, type: :append)
      change manage_relationship(:user_id, :user, type: :append)
    end

    create :join do
      accept []
      argument :room_id, :uuid, allow_nil?: false
      argument :user_id, :uuid, allow_nil?: false

      change set_attribute(:role, :member)
      change manage_relationship(:room_id, :room, type: :append)
      change manage_relationship(:user_id, :user, type: :append)
    end

    update :promote_to_admin do
      change set_attribute(:role, :admin)
    end

    update :demote_to_member do
      change set_attribute(:role, :member)
    end
  end
end

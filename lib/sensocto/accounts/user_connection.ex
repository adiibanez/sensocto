defmodule Sensocto.Accounts.UserConnection do
  use Ash.Resource,
    domain: Sensocto.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_connections"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:connection_type, :strength]

      argument :from_user_id, :uuid, allow_nil?: false
      argument :to_user_id, :uuid, allow_nil?: false

      change set_attribute(:from_user_id, arg(:from_user_id))
      change set_attribute(:to_user_id, arg(:to_user_id))
    end

    read :for_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(from_user_id == ^arg(:user_id) or to_user_id == ^arg(:user_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :from_user_id, :uuid do
      allow_nil? false
    end

    attribute :to_user_id, :uuid do
      allow_nil? false
    end

    attribute :connection_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:follows, :collaborates, :mentors]
      default :follows
    end

    attribute :strength, :integer do
      allow_nil? false
      public? true
      constraints min: 1, max: 10
      default 5
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_connection, [:from_user_id, :to_user_id, :connection_type]
  end
end

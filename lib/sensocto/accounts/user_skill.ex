defmodule Sensocto.Accounts.UserSkill do
  use Ash.Resource,
    domain: Sensocto.Accounts,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "user_skills"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :add_skill do
      accept [:skill_name, :level]

      argument :user_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:user_id, arg(:user_id))
    end

    update :update_level do
      accept [:level]
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :skill_name, :string do
      allow_nil? false
      public? true
      constraints max_length: 100
    end

    attribute :level, :atom do
      allow_nil? false
      constraints one_of: [:beginner, :intermediate, :expert]
      default :beginner
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    belongs_to :user, Sensocto.Accounts.User do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_user_skill, [:user_id, :skill_name]
  end
end

defmodule Sensocto.Collaboration.Poll do
  use Ash.Resource,
    domain: Sensocto.Collaboration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "polls"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [
        :title,
        :description,
        :poll_type,
        :visibility,
        :results_visible,
        :closes_at,
        :room_id
      ]

      argument :creator_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:creator_id, arg(:creator_id))
      change set_attribute(:status, :open)
    end

    update :close do
      accept []
      change set_attribute(:status, :closed)
    end

    read :for_room do
      argument :room_id, :uuid, allow_nil?: false
      filter expr(room_id == ^arg(:room_id) and status == :open)
    end

    read :public_open do
      filter expr(visibility == :public and status == :open)
    end

    read :by_creator do
      argument :creator_id, :uuid, allow_nil?: false
      filter expr(creator_id == ^arg(:creator_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :title, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :description, :string do
      allow_nil? true
      public? true
    end

    attribute :poll_type, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:single_choice, :multiple_choice]
      default :single_choice
    end

    attribute :status, :atom do
      allow_nil? false
      constraints one_of: [:draft, :open, :closed, :archived]
      default :draft
    end

    attribute :visibility, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:public, :room, :private]
      default :public
    end

    attribute :results_visible, :atom do
      allow_nil? false
      public? true
      constraints one_of: [:always, :after_close, :creator_only]
      default :always
    end

    attribute :closes_at, :utc_datetime_usec do
      allow_nil? true
      public? true
    end

    attribute :room_id, :uuid do
      allow_nil? true
      public? true
    end

    attribute :creator_id, :uuid do
      allow_nil? false
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  relationships do
    has_many :options, Sensocto.Collaboration.PollOption do
      sort position: :asc
    end

    has_many :votes, Sensocto.Collaboration.Vote
  end

  aggregates do
    count :vote_count, :votes
  end
end

defmodule Sensocto.Collaboration.PollOption do
  use Ash.Resource,
    domain: Sensocto.Collaboration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "poll_options"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:label, :position]

      argument :poll_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:poll_id, arg(:poll_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :label, :string do
      allow_nil? false
      public? true
      constraints max_length: 200
    end

    attribute :position, :integer do
      allow_nil? false
      public? true
      default 0
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :poll, Sensocto.Collaboration.Poll do
      allow_nil? false
      attribute_type :uuid
    end

    has_many :votes, Sensocto.Collaboration.Vote do
      destination_attribute :option_id
    end
  end

  aggregates do
    count :vote_count, :votes
  end
end

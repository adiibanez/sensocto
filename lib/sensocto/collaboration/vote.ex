defmodule Sensocto.Collaboration.Vote do
  use Ash.Resource,
    domain: Sensocto.Collaboration,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "votes"
    repo Sensocto.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :cast do
      accept [:weight]

      argument :poll_id, :uuid do
        allow_nil? false
      end

      argument :option_id, :uuid do
        allow_nil? false
      end

      argument :user_id, :uuid do
        allow_nil? false
      end

      change set_attribute(:poll_id, arg(:poll_id))
      change set_attribute(:option_id, arg(:option_id))
      change set_attribute(:user_id, arg(:user_id))

      validate fn changeset, _context ->
        user_id = Ash.Changeset.get_argument(changeset, :user_id)

        if is_binary(user_id) and String.starts_with?(user_id, "guest_") do
          {:error, field: :user_id, message: "guests cannot vote"}
        else
          :ok
        end
      end

      change after_action(fn _changeset, vote, _context ->
               Phoenix.PubSub.broadcast(
                 Sensocto.PubSub,
                 "poll:#{vote.poll_id}",
                 {:vote_cast, vote.poll_id}
               )

               {:ok, vote}
             end)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
    end

    attribute :weight, :integer do
      allow_nil? false
      default 1
      constraints min: 1, max: 100
    end

    create_timestamp :inserted_at
  end

  relationships do
    belongs_to :poll, Sensocto.Collaboration.Poll do
      allow_nil? false
      attribute_type :uuid
    end

    belongs_to :option, Sensocto.Collaboration.PollOption do
      allow_nil? false
      attribute_type :uuid
    end
  end

  identities do
    identity :unique_vote, [:poll_id, :user_id, :option_id]
  end
end

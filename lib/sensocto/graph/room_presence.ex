defmodule Sensocto.Graph.RoomPresence do
  @moduledoc """
  Neo4j graph representation of a user's presence in a room.

  This is an edge/relationship resource that connects:
  - UserNode (user)
  - RoomNode (room)
  - sensor_ids (list of sensor IDs the user brings to the room)

  When a user joins a room, all their available sensors are associated with the room.
  When they leave, those sensors are removed from the room context.
  """
  use Ash.Resource,
    domain: Sensocto.Graph,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :RoomPresence
  end

  actions do
    default_accept :*
    defaults [:create, :read, :update, :destroy]

    read :by_user_and_room do
      argument :user_id, :uuid, allow_nil?: false
      argument :room_id, :uuid, allow_nil?: false
      get? true
      filter expr(user_id == ^arg(:user_id) and room_id == ^arg(:room_id))
    end

    read :by_room do
      argument :room_id, :uuid, allow_nil?: false
      filter expr(room_id == ^arg(:room_id))
    end

    read :by_user do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :user_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :room_id, :uuid do
      allow_nil? false
      public? true
    end

    attribute :sensor_ids, {:array, :string} do
      default []
      allow_nil? false
      public? true
      description "List of sensor IDs the user brings to the room"
    end

    attribute :role, :atom do
      constraints one_of: [:owner, :admin, :member]
      default :member
      allow_nil? false
      public? true
    end

    attribute :joined_at, :utc_datetime do
      default &DateTime.utc_now/0
      allow_nil? false
      public? true
    end

    create_timestamp :inserted_at
    update_timestamp :updated_at
  end

  identities do
    identity :unique_user_room, [:user_id, :room_id]
  end
end

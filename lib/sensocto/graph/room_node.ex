defmodule Sensocto.Graph.RoomNode do
  @moduledoc """
  Neo4j graph representation of a room.

  Stores room identity and relationships:
  - MEMBER_OF edges from UserNode (users in the room)
  - SENSOR_IN edges from sensors connected to the room
  """
  use Ash.Resource,
    domain: Sensocto.Graph,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :Room
  end

  actions do
    default_accept :*
    defaults [:create, :read, :update, :destroy]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      get? true
      filter expr(id == ^arg(:id))
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      allow_nil? false
      public? true
    end

    attribute :join_code, :string do
      allow_nil? true
      public? true
    end

    attribute :is_public, :boolean do
      default true
      public? true
    end

    create_timestamp :inserted_at
  end
end

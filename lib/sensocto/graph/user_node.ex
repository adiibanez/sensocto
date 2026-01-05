defmodule Sensocto.Graph.UserNode do
  @moduledoc """
  Neo4j graph representation of a user.

  Stores user identity for graph relationships:
  - MEMBER_OF edges to RoomNode
  - OWNS edges to RoomNode (for room ownership)
  """
  use Ash.Resource,
    domain: Sensocto.Graph,
    data_layer: AshNeo4j.DataLayer

  neo4j do
    label :User
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

    attribute :email, :string do
      allow_nil? false
      public? true
    end

    attribute :display_name, :string do
      allow_nil? true
      public? true
    end

    create_timestamp :inserted_at
  end
end

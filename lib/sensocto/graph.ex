defmodule Sensocto.Graph do
  @moduledoc """
  Ash Domain for Sensocto graph modeling using Neo4j.

  This domain handles graph-based relationships between:
  - Users and their room memberships
  - Rooms and their connected sensors
  - User presence tracking with associated sensors

  The graph data complements the PostgreSQL data stored in Sensocto.Sensors,
  providing efficient relationship queries and path finding.
  """
  use Ash.Domain

  resources do
    resource Sensocto.Graph.RoomNode
    resource Sensocto.Graph.UserNode
    resource Sensocto.Graph.RoomPresence
  end
end

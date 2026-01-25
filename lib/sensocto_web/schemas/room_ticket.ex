defmodule SensoctoWeb.Schemas.RoomTicket do
  @moduledoc """
  OpenAPI schemas for room ticket (P2P connection bootstrap) endpoints.
  """

  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule Ticket do
    @moduledoc "Room ticket schema for P2P connections"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RoomTicket",
      description: "A ticket containing P2P connection information for joining a room via Iroh",
      type: :object,
      properties: %{
        room_id: %Schema{type: :string, format: :uuid, description: "Room identifier"},
        room_name: %Schema{type: :string, description: "Room name"},
        docs_namespace: %Schema{
          type: :string,
          description: "Hex-encoded Iroh docs namespace"
        },
        gossip_topic: %Schema{
          type: :string,
          description: "Hex-encoded Iroh gossip topic"
        },
        bootstrap_peers: %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "List of bootstrap peer addresses"
        },
        relay_url: %Schema{
          type: :string,
          format: :uri,
          description: "URL of the relay server",
          nullable: true
        },
        created_at: %Schema{
          type: :integer,
          description: "Unix timestamp when ticket was created"
        },
        expires_at: %Schema{
          type: :integer,
          description: "Unix timestamp when ticket expires"
        }
      },
      required: [:room_id, :room_name, :docs_namespace, :gossip_topic, :created_at, :expires_at],
      example: %{
        room_id: "550e8400-e29b-41d4-a716-446655440000",
        room_name: "Lab Room 1",
        docs_namespace: "a1b2c3d4e5f6...",
        gossip_topic: "f6e5d4c3b2a1...",
        bootstrap_peers: ["peer1.example.com:4433"],
        relay_url: "https://relay.example.com",
        created_at: 1_737_802_800,
        expires_at: 1_737_889_200
      }
    })
  end

  defmodule TicketResponse do
    @moduledoc "Response schema for ticket generation"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "TicketResponse",
      description: "Response containing generated room ticket",
      type: :object,
      properties: %{
        ok: %Schema{type: :boolean, description: "Whether the operation was successful"},
        ticket: Ticket,
        encoded: %Schema{
          type: :string,
          description: "Base64-encoded ticket for easy sharing"
        },
        deep_link: %Schema{
          type: :string,
          format: :uri,
          description: "Deep link URL (sensocto://room?ticket=...)"
        },
        web_url: %Schema{
          type: :string,
          format: :uri,
          description: "Web URL for joining the room"
        }
      },
      required: [:ok, :ticket, :encoded],
      example: %{
        ok: true,
        ticket: %{
          room_id: "550e8400-e29b-41d4-a716-446655440000",
          room_name: "Lab Room 1",
          docs_namespace: "a1b2c3d4e5f6...",
          gossip_topic: "f6e5d4c3b2a1...",
          bootstrap_peers: [],
          created_at: 1_737_802_800,
          expires_at: 1_737_889_200
        },
        encoded: "eyJyb29tX2lkIjoiNTUwZTg0MDAuLi4=",
        deep_link: "sensocto://room?ticket=eyJyb29tX2lkIjoiNTUwZTg0MDAuLi4=",
        web_url: "https://app.sensocto.com/rooms/join?ticket=eyJyb29tX2lkIjoiNTUwZTg0MDAuLi4="
      }
    })
  end

  defmodule VerifyTicketRequest do
    @moduledoc "Request schema for ticket verification"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VerifyTicketRequest",
      description: "Request body for verifying a room ticket",
      type: :object,
      properties: %{
        ticket: %Schema{type: :string, description: "Base64-encoded ticket to verify"}
      },
      required: [:ticket],
      example: %{
        ticket: "eyJyb29tX2lkIjoiNTUwZTg0MDAuLi4="
      }
    })
  end

  defmodule VerifyTicketResponse do
    @moduledoc "Response schema for ticket verification"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VerifyTicketResponse",
      description: "Response from ticket verification",
      type: :object,
      properties: %{
        ok: %Schema{type: :boolean, description: "Whether the operation was successful"},
        valid: %Schema{type: :boolean, description: "Whether the ticket is valid"},
        expired: %Schema{type: :boolean, description: "Whether the ticket has expired"},
        ticket: Ticket
      },
      required: [:ok, :valid],
      example: %{
        ok: true,
        valid: true,
        expired: false,
        ticket: %{
          room_id: "550e8400-e29b-41d4-a716-446655440000",
          room_name: "Lab Room 1",
          docs_namespace: "a1b2c3d4e5f6...",
          gossip_topic: "f6e5d4c3b2a1...",
          bootstrap_peers: [],
          created_at: 1_737_802_800,
          expires_at: 1_737_889_200
        }
      }
    })
  end
end

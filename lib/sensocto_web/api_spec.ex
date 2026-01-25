defmodule SensoctoWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Sensocto REST API.

  This module defines the OpenAPI 3.0 specification for all REST endpoints
  in the Sensocto platform.

  ## Usage

  The specification is available at:
  - JSON: GET /api/openapi
  - Swagger UI: GET /swaggerui

  ## Generating Static Files

  To generate static OpenAPI specification files:

      mix openapi.spec.json --spec SensoctoWeb.ApiSpec
      mix openapi.spec.yaml --spec SensoctoWeb.ApiSpec
  """

  alias OpenApiSpex.{
    Components,
    Info,
    MediaType,
    OpenApi,
    Operation,
    Parameter,
    PathItem,
    RequestBody,
    Response,
    Schema,
    SecurityScheme,
    Server
  }

  alias SensoctoWeb.Endpoint
  alias SensoctoWeb.Schemas.{Auth, Common, Health, Room, RoomTicket}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "Sensocto API",
        version: "1.0.0",
        description: """
        REST API for the Sensocto IoT Sensor Platform.

        ## Authentication

        Most endpoints require a Bearer token in the Authorization header:

            Authorization: Bearer <jwt_token>

        Tokens are obtained through the authentication flow (sign-in via web UI
        or magic link, then extract the JWT from the session).

        ## Real-time Data

        For real-time sensor data streaming, use the WebSocket channels at
        `wss://your-host/socket/websocket`. This REST API is for management
        operations and P2P bootstrap.

        ## Endpoints Overview

        - **Authentication** - Token verification and user info
        - **Rooms** - List and view rooms
        - **Room Tickets** - P2P connection bootstrap via Iroh
        - **Health** - Service health checks
        """,
        contact: %OpenApiSpex.Contact{
          name: "Sensocto Team"
        },
        license: %OpenApiSpex.License{
          name: "Proprietary"
        }
      },
      servers: [
        Server.from_endpoint(Endpoint)
      ],
      paths: paths(),
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "JWT Bearer token authentication"
          }
        },
        schemas: %{
          "Error" => Common.Error.schema(),
          "User" => Auth.User.schema(),
          "VerifyResponse" => Auth.VerifyResponse.schema(),
          "DebugVerifyRequest" => Auth.DebugVerifyRequest.schema(),
          "Room" => Room.Room.schema(),
          "Sensor" => Room.Sensor.schema(),
          "SensorAttribute" => Room.SensorAttribute.schema(),
          "RoomListResponse" => Room.RoomListResponse.schema(),
          "RoomResponse" => Room.RoomResponse.schema(),
          "RoomTicket" => RoomTicket.Ticket.schema(),
          "TicketResponse" => RoomTicket.TicketResponse.schema(),
          "VerifyTicketRequest" => RoomTicket.VerifyTicketRequest.schema(),
          "VerifyTicketResponse" => RoomTicket.VerifyTicketResponse.schema(),
          "LivenessResponse" => Health.LivenessResponse.schema(),
          "ReadinessResponse" => Health.ReadinessResponse.schema()
        }
      },
      tags: [
        %OpenApiSpex.Tag{name: "Authentication", description: "Token verification and user info"},
        %OpenApiSpex.Tag{name: "Rooms", description: "Room listing and details"},
        %OpenApiSpex.Tag{name: "Room Tickets", description: "P2P connection bootstrap via Iroh"},
        %OpenApiSpex.Tag{name: "Health", description: "Service health checks"}
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp paths do
    %{
      # Authentication endpoints
      "/api/auth/verify" => %PathItem{
        get: auth_verify_operation(),
        post: auth_verify_operation()
      },
      "/api/me" => %PathItem{
        get: me_operation()
      },
      "/api/auth/debug" => %PathItem{
        post: debug_verify_operation()
      },
      # Room endpoints
      "/api/rooms" => %PathItem{
        get: rooms_index_operation()
      },
      "/api/rooms/public" => %PathItem{
        get: rooms_public_operation()
      },
      "/api/rooms/{id}" => %PathItem{
        get: room_show_operation()
      },
      # Room ticket endpoints
      "/api/rooms/{id}/ticket" => %PathItem{
        get: room_ticket_operation()
      },
      "/api/rooms/by-code/{code}/ticket" => %PathItem{
        get: room_ticket_by_code_operation()
      },
      "/api/rooms/verify-ticket" => %PathItem{
        post: verify_ticket_operation()
      },
      # Health endpoints
      "/health/live" => %PathItem{
        get: health_liveness_operation()
      },
      "/health/ready" => %PathItem{
        get: health_readiness_operation()
      }
    }
  end

  # Authentication operations
  defp auth_verify_operation do
    %Operation{
      tags: ["Authentication"],
      summary: "Verify authentication token",
      description: """
      Verifies a JWT token and returns the authenticated user's information.
      The token should be sent as a Bearer token in the Authorization header.
      This endpoint is used by mobile apps after scanning a QR code or
      receiving a deep link with an authentication token.
      """,
      operationId: "verifyToken",
      security: [%{"bearerAuth" => []}],
      responses: %{
        200 => json_response("Successful verification", Auth.VerifyResponse),
        401 => json_response("Invalid or missing token", Common.Error)
      }
    }
  end

  defp me_operation do
    %Operation{
      tags: ["Authentication"],
      summary: "Get current user info",
      description: """
      Returns the current authenticated user's information.
      Same as verify but semantically for getting user info after auth.
      """,
      operationId: "getCurrentUser",
      security: [%{"bearerAuth" => []}],
      responses: %{
        200 => json_response("User information", Auth.VerifyResponse),
        401 => json_response("Invalid or missing token", Common.Error)
      }
    }
  end

  defp debug_verify_operation do
    %Operation{
      tags: ["Authentication"],
      summary: "Debug token verification",
      description: """
      Debug endpoint to manually verify a token without the load_from_bearer plug.
      For testing purposes only.
      """,
      operationId: "debugVerifyToken",
      requestBody: %RequestBody{
        description: "Token to verify",
        required: true,
        content: %{
          "application/json" => %MediaType{
            schema: Auth.DebugVerifyRequest
          }
        }
      },
      responses: %{
        200 => json_response("Successful verification", Auth.VerifyResponse),
        400 => json_response("Missing token", Common.Error),
        401 => json_response("Invalid token", Common.Error)
      }
    }
  end

  # Room operations
  defp rooms_index_operation do
    %Operation{
      tags: ["Rooms"],
      summary: "List user's rooms",
      description: "Lists all rooms the authenticated user is a member of.",
      operationId: "listUserRooms",
      security: [%{"bearerAuth" => []}],
      responses: %{
        200 => json_response("List of rooms", Room.RoomListResponse),
        401 => json_response("Invalid or missing token", Common.Error)
      }
    }
  end

  defp rooms_public_operation do
    %Operation{
      tags: ["Rooms"],
      summary: "List public rooms",
      description: "Lists all public rooms available on the platform.",
      operationId: "listPublicRooms",
      security: [%{"bearerAuth" => []}],
      responses: %{
        200 => json_response("List of public rooms", Room.RoomListResponse),
        401 => json_response("Invalid or missing token", Common.Error)
      }
    }
  end

  defp room_show_operation do
    %Operation{
      tags: ["Rooms"],
      summary: "Get room details",
      description: """
      Gets details for a specific room.
      Requires authentication and room membership (or room must be public).
      """,
      operationId: "getRoom",
      security: [%{"bearerAuth" => []}],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          description: "Room UUID",
          required: true,
          schema: %Schema{type: :string, format: :uuid}
        }
      ],
      responses: %{
        200 => json_response("Room details", Room.RoomResponse),
        401 => json_response("Invalid or missing token", Common.Error),
        403 => json_response("Not a member of this room", Common.Error),
        404 => json_response("Room not found", Common.Error)
      }
    }
  end

  # Room ticket operations
  defp room_ticket_operation do
    %Operation{
      tags: ["Room Tickets"],
      summary: "Generate room ticket by ID",
      description: """
      Generates a room ticket for P2P connection bootstrap via Iroh.
      Requires authentication and room membership.
      """,
      operationId: "getRoomTicket",
      security: [%{"bearerAuth" => []}],
      parameters: [
        %Parameter{
          name: :id,
          in: :path,
          description: "Room UUID",
          required: true,
          schema: %Schema{type: :string, format: :uuid}
        },
        %Parameter{
          name: :include_secret,
          in: :query,
          description: "Include write secret (owner/admin only)",
          required: false,
          schema: %Schema{type: :boolean, default: false}
        },
        %Parameter{
          name: :expires_in,
          in: :query,
          description: "Seconds until expiry (default: 86400 = 24 hours, max: 604800 = 1 week)",
          required: false,
          schema: %Schema{type: :integer, default: 86400}
        }
      ],
      responses: %{
        200 => json_response("Room ticket", RoomTicket.TicketResponse),
        401 => json_response("Invalid or missing token", Common.Error),
        403 => json_response("Not a member of this room", Common.Error),
        404 => json_response("Room not found", Common.Error),
        500 => json_response("Failed to generate ticket", Common.Error)
      }
    }
  end

  defp room_ticket_by_code_operation do
    %Operation{
      tags: ["Room Tickets"],
      summary: "Generate room ticket by join code",
      description: """
      Generates a room ticket using a join code.
      Does not require authentication - anyone with the code can get a ticket.
      The ticket will have limited permissions (no write secret).
      """,
      operationId: "getRoomTicketByCode",
      parameters: [
        %Parameter{
          name: :code,
          in: :path,
          description: "Room join code",
          required: true,
          schema: %Schema{type: :string}
        }
      ],
      responses: %{
        200 => json_response("Room ticket", RoomTicket.TicketResponse),
        404 => json_response("Room not found", Common.Error),
        500 => json_response("Failed to generate ticket", Common.Error)
      }
    }
  end

  defp verify_ticket_operation do
    %Operation{
      tags: ["Room Tickets"],
      summary: "Verify and decode a ticket",
      description: "Verifies a room ticket and returns its decoded contents.",
      operationId: "verifyRoomTicket",
      requestBody: %RequestBody{
        description: "Ticket to verify",
        required: true,
        content: %{
          "application/json" => %MediaType{
            schema: RoomTicket.VerifyTicketRequest
          }
        }
      },
      responses: %{
        200 => json_response("Ticket verification result", RoomTicket.VerifyTicketResponse),
        400 => json_response("Invalid ticket format", Common.Error)
      }
    }
  end

  # Health operations
  defp health_liveness_operation do
    %Operation{
      tags: ["Health"],
      summary: "Liveness check",
      description: """
      Shallow health check for load balancers.
      Returns 200 if the BEAM is responsive.
      """,
      operationId: "healthLiveness",
      responses: %{
        200 => json_response("Service is alive", Health.LivenessResponse)
      }
    }
  end

  defp health_readiness_operation do
    %Operation{
      tags: ["Health"],
      summary: "Readiness check",
      description: """
      Deep health check for orchestrators.
      Checks database, PubSub, and critical processes.
      Returns 200 if all checks pass, 503 if any fail.
      """,
      operationId: "healthReadiness",
      responses: %{
        200 => json_response("Service is ready", Health.ReadinessResponse),
        503 => json_response("Service is degraded", Health.ReadinessResponse)
      }
    }
  end

  # Helper for JSON responses
  defp json_response(description, schema) do
    %Response{
      description: description,
      content: %{
        "application/json" => %MediaType{
          schema: schema
        }
      }
    }
  end
end

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
    PathItem,
    Response,
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
          "ReadinessResponse" => Health.ReadinessResponse.schema(),
          "Connector" => SensoctoWeb.Schemas.ConnectorSchemas.ConnectorSchema.schema(),
          "ConnectorListResponse" =>
            SensoctoWeb.Schemas.ConnectorSchemas.ConnectorListResponse.schema(),
          "ConnectorResponse" => SensoctoWeb.Schemas.ConnectorSchemas.ConnectorResponse.schema(),
          "ConnectorUpdateRequest" =>
            SensoctoWeb.Schemas.ConnectorSchemas.ConnectorUpdateRequest.schema()
        }
      },
      tags: [
        %OpenApiSpex.Tag{name: "Authentication", description: "Token verification and user info"},
        %OpenApiSpex.Tag{name: "Rooms", description: "Room listing and details"},
        %OpenApiSpex.Tag{name: "Room Tickets", description: "P2P connection bootstrap via Iroh"},
        %OpenApiSpex.Tag{name: "Connectors", description: "Connector management"},
        %OpenApiSpex.Tag{name: "Health", description: "Service health checks"}
      ]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end

  defp paths do
    auto_paths = OpenApiSpex.Paths.from_router(SensoctoWeb.Router)

    manual_paths = %{
      "/health/live" => %PathItem{get: health_liveness_operation()},
      "/health/ready" => %PathItem{get: health_readiness_operation()}
    }

    Map.merge(auto_paths, manual_paths)
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

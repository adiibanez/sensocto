defmodule SensoctoWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the Sensocto REST API.

  This module defines the OpenAPI 3.0 specification for all REST endpoints
  in the Sensocto platform. The specification is auto-generated from
  controller operation specs.

  ## Usage

  The specification is available at:
  - JSON: GET /api/openapi
  - Swagger UI: GET /api/swaggerui

  ## Generating Static Files

  To generate static OpenAPI specification files:

      mix openapi.spec.json --spec SensoctoWeb.ApiSpec
      mix openapi.spec.yaml --spec SensoctoWeb.ApiSpec
  """

  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Components, SecurityScheme}
  alias SensoctoWeb.{Endpoint, Router}
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
      paths: Paths.from_router(Router),
      components: %Components{
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "JWT",
            description: "JWT Bearer token authentication"
          }
        }
      }
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end

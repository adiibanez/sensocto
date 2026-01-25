defmodule SensoctoWeb.Schemas.Auth do
  @moduledoc """
  OpenAPI schemas for authentication endpoints.
  """

  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule User do
    @moduledoc "User information schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "User",
      description: "User account information",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Unique user identifier"},
        email: %Schema{type: :string, format: :email, description: "User email address"},
        display_name: %Schema{type: :string, description: "User display name"}
      },
      required: [:id, :email],
      example: %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        email: "user@example.com",
        display_name: "John Doe"
      }
    })
  end

  defmodule VerifyResponse do
    @moduledoc "Response schema for token verification"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "VerifyResponse",
      description: "Response from token verification endpoint",
      type: :object,
      properties: %{
        ok: %Schema{type: :boolean, description: "Whether the operation was successful"},
        user: User
      },
      required: [:ok, :user],
      example: %{
        ok: true,
        user: %{
          id: "550e8400-e29b-41d4-a716-446655440000",
          email: "user@example.com",
          display_name: "John Doe"
        }
      }
    })
  end

  defmodule DebugVerifyRequest do
    @moduledoc "Request schema for debug token verification"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DebugVerifyRequest",
      description: "Request body for debug token verification",
      type: :object,
      properties: %{
        token: %Schema{type: :string, description: "JWT token to verify"}
      },
      required: [:token],
      example: %{
        token: "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..."
      }
    })
  end
end

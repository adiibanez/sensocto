defmodule SensoctoWeb.Schemas.Common do
  @moduledoc """
  Common OpenAPI schemas used across multiple endpoints.
  """

  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule Error do
    @moduledoc "Standard error response schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      description: "Standard error response",
      type: :object,
      properties: %{
        ok: %Schema{type: :boolean, description: "Always false for errors"},
        error: %Schema{type: :string, description: "Error message"}
      },
      required: [:error],
      example: %{
        ok: false,
        error: "Unauthorized"
      }
    })
  end

  defmodule Timestamp do
    @moduledoc "ISO8601 timestamp schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Timestamp",
      description: "ISO8601 formatted timestamp",
      type: :string,
      format: :"date-time",
      example: "2026-01-25T12:00:00Z"
    })
  end

  defmodule UUID do
    @moduledoc "UUID schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "UUID",
      description: "Universally unique identifier",
      type: :string,
      format: :uuid,
      example: "550e8400-e29b-41d4-a716-446655440000"
    })
  end
end

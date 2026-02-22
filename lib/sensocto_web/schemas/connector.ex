defmodule SensoctoWeb.Schemas.ConnectorSchemas do
  @moduledoc "OpenAPI schemas for connector endpoints."

  alias OpenApiSpex.Schema

  defmodule ConnectorSchema do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Connector",
      description: "A connector device that bridges sensors to the platform",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        name: %Schema{type: :string},
        connector_type: %Schema{type: :string, enum: ["web", "native", "iot", "simulator"]},
        status: %Schema{type: :string, enum: ["online", "offline", "idle"]},
        configuration: %Schema{type: :object},
        last_seen_at: %Schema{type: :string, format: :"date-time", nullable: true},
        connected_at: %Schema{type: :string, format: :"date-time", nullable: true},
        inserted_at: %Schema{type: :string, format: :"date-time"},
        updated_at: %Schema{type: :string, format: :"date-time"},
        sensors: %Schema{type: :array, items: SensoctoWeb.Schemas.Room.Sensor}
      },
      required: [:id, :name, :connector_type, :status]
    })
  end

  defmodule ConnectorListResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ConnectorListResponse",
      type: :object,
      properties: %{
        connectors: %Schema{type: :array, items: ConnectorSchema}
      },
      required: [:connectors]
    })
  end

  defmodule ConnectorResponse do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ConnectorResponse",
      type: :object,
      properties: %{
        connector: ConnectorSchema
      },
      required: [:connector]
    })
  end

  defmodule ConnectorUpdateRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ConnectorUpdateRequest",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "New name for the connector"}
      },
      required: [:name]
    })
  end
end

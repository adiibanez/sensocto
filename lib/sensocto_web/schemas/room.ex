defmodule SensoctoWeb.Schemas.Room do
  @moduledoc """
  OpenAPI schemas for room-related endpoints.
  """

  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule SensorAttribute do
    @moduledoc "Sensor attribute schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SensorAttribute",
      description: "A sensor attribute with its current value",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Attribute unique identifier"},
        attribute_type: %Schema{
          type: :string,
          description: "Type of attribute (e.g., heartrate, temperature, accelerometer)"
        },
        attribute_name: %Schema{type: :string, description: "Human-readable attribute name"},
        last_value: %Schema{
          oneOf: [
            %Schema{type: :number},
            %Schema{type: :string},
            %Schema{type: :object},
            %Schema{type: :array}
          ],
          description: "Last recorded value",
          nullable: true
        },
        last_updated: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the value was last updated",
          nullable: true
        }
      },
      example: %{
        id: "550e8400-e29b-41d4-a716-446655440001",
        attribute_type: "heartrate",
        attribute_name: "Heart Rate",
        last_value: 72,
        last_updated: "2026-01-25T12:00:00Z"
      }
    })
  end

  defmodule Sensor do
    @moduledoc "Sensor information schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Sensor",
      description: "A sensor connected to a room",
      type: :object,
      properties: %{
        sensor_id: %Schema{type: :string, description: "Unique sensor identifier"},
        sensor_name: %Schema{type: :string, description: "Human-readable sensor name"},
        sensor_type: %Schema{
          type: :string,
          description: "Type of sensor (e.g., generic, wearable)"
        },
        connector_id: %Schema{type: :string, description: "ID of the connector/user"},
        connector_name: %Schema{type: :string, description: "Name of the connector/user"},
        activity_status: %Schema{
          type: :string,
          enum: ["active", "inactive", "unknown"],
          description: "Current activity status"
        },
        attributes: %Schema{
          type: :array,
          items: SensorAttribute,
          description: "List of sensor attributes"
        }
      },
      example: %{
        sensor_id: "sensor-001",
        sensor_name: "Heart Monitor",
        sensor_type: "wearable",
        connector_id: "550e8400-e29b-41d4-a716-446655440000",
        connector_name: "John Doe",
        activity_status: "active",
        attributes: []
      }
    })
  end

  defmodule Room do
    @moduledoc "Room information schema"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Room",
      description: "A collaboration room for sensor data sharing",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid, description: "Unique room identifier"},
        name: %Schema{type: :string, description: "Room name"},
        description: %Schema{type: :string, description: "Room description", nullable: true},
        owner_id: %Schema{type: :string, format: :uuid, description: "ID of the room owner"},
        join_code: %Schema{
          type: :string,
          description: "Code for joining the room",
          nullable: true
        },
        is_public: %Schema{type: :boolean, description: "Whether the room is publicly accessible"},
        is_persisted: %Schema{type: :boolean, description: "Whether room data is persisted"},
        calls_enabled: %Schema{
          type: :boolean,
          description: "Whether video/voice calls are enabled"
        },
        media_playback_enabled: %Schema{
          type: :boolean,
          description: "Whether media playback is enabled"
        },
        object_3d_enabled: %Schema{type: :boolean, description: "Whether 3D objects are enabled"},
        created_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the room was created",
          nullable: true
        },
        updated_at: %Schema{
          type: :string,
          format: :"date-time",
          description: "When the room was last updated",
          nullable: true
        },
        sensors: %Schema{type: :array, items: Sensor, description: "Sensors in the room"},
        member_count: %Schema{type: :integer, description: "Number of members in the room"}
      },
      required: [:id, :name, :owner_id],
      example: %{
        id: "550e8400-e29b-41d4-a716-446655440000",
        name: "Lab Room 1",
        description: "Main research lab",
        owner_id: "550e8400-e29b-41d4-a716-446655440001",
        join_code: "ABC123",
        is_public: false,
        is_persisted: true,
        calls_enabled: true,
        media_playback_enabled: false,
        object_3d_enabled: false,
        created_at: "2026-01-01T00:00:00Z",
        updated_at: "2026-01-25T12:00:00Z",
        sensors: [],
        member_count: 5
      }
    })
  end

  defmodule RoomListResponse do
    @moduledoc "Response schema for room list endpoints"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RoomListResponse",
      description: "List of rooms",
      type: :object,
      properties: %{
        rooms: %Schema{type: :array, items: Room, description: "List of rooms"}
      },
      required: [:rooms],
      example: %{
        rooms: [
          %{
            id: "550e8400-e29b-41d4-a716-446655440000",
            name: "Lab Room 1",
            description: "Main research lab",
            owner_id: "550e8400-e29b-41d4-a716-446655440001",
            is_public: false,
            member_count: 5,
            sensors: []
          }
        ]
      }
    })
  end

  defmodule RoomResponse do
    @moduledoc "Response schema for single room endpoint"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RoomResponse",
      description: "Single room details",
      type: :object,
      properties: %{
        room: Room
      },
      required: [:room]
    })
  end
end

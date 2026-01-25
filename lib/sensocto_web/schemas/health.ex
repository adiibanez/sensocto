defmodule SensoctoWeb.Schemas.Health do
  @moduledoc """
  OpenAPI schemas for health check endpoints.
  """

  alias OpenApiSpex.Schema
  require OpenApiSpex

  defmodule LivenessResponse do
    @moduledoc "Response schema for liveness check"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "LivenessResponse",
      description: "Simple liveness check response",
      type: :object,
      properties: %{
        status: %Schema{type: :string, enum: ["ok"], description: "Status indicator"},
        timestamp: %Schema{
          type: :string,
          format: :"date-time",
          description: "Current server time"
        }
      },
      required: [:status, :timestamp],
      example: %{
        status: "ok",
        timestamp: "2026-01-25T12:00:00Z"
      }
    })
  end

  defmodule DatabaseCheck do
    @moduledoc "Database health check result"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DatabaseCheck",
      description: "Database health check result",
      type: :object,
      properties: %{
        healthy: %Schema{type: :boolean, description: "Whether database is healthy"},
        latency_ms: %Schema{type: :integer, description: "Query latency in milliseconds"},
        error: %Schema{type: :string, description: "Error message if unhealthy", nullable: true}
      },
      required: [:healthy]
    })
  end

  defmodule PubSubCheck do
    @moduledoc "PubSub health check result"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "PubSubCheck",
      description: "PubSub health check result",
      type: :object,
      properties: %{
        healthy: %Schema{type: :boolean, description: "Whether PubSub is healthy"},
        error: %Schema{type: :string, description: "Error message if unhealthy", nullable: true}
      },
      required: [:healthy]
    })
  end

  defmodule SupervisorsCheck do
    @moduledoc "Supervisors health check result"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SupervisorsCheck",
      description: "Critical supervisors health check result",
      type: :object,
      properties: %{
        healthy: %Schema{type: :boolean, description: "Whether all supervisors are alive"},
        details: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string, enum: ["alive", "dead"]},
          description: "Status of each supervisor"
        }
      },
      required: [:healthy]
    })
  end

  defmodule SystemLoadCheck do
    @moduledoc "System load health check result"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "SystemLoadCheck",
      description: "System load health check result",
      type: :object,
      properties: %{
        healthy: %Schema{type: :boolean, description: "Whether system load is acceptable"},
        level: %Schema{
          type: :string,
          enum: ["low", "medium", "high", "critical", "unknown"],
          description: "Current load level"
        },
        scheduler_utilization: %Schema{
          type: :number,
          description: "Scheduler utilization percentage"
        },
        memory_pressure: %Schema{type: :number, description: "Memory pressure percentage"},
        pubsub_pressure: %Schema{type: :number, description: "PubSub pressure percentage"},
        message_queue_pressure: %Schema{
          type: :number,
          description: "Message queue pressure percentage"
        },
        error: %Schema{type: :string, description: "Error message if unavailable", nullable: true}
      },
      required: [:healthy]
    })
  end

  defmodule HealthChecks do
    @moduledoc "All health checks combined"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "HealthChecks",
      description: "Combined health check results",
      type: :object,
      properties: %{
        database: DatabaseCheck,
        pubsub: PubSubCheck,
        supervisors: SupervisorsCheck,
        system_load: SystemLoadCheck
      },
      required: [:database, :pubsub, :supervisors, :system_load]
    })
  end

  defmodule ReadinessResponse do
    @moduledoc "Response schema for readiness check"
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ReadinessResponse",
      description: "Deep readiness check response with component status",
      type: :object,
      properties: %{
        status: %Schema{
          type: :string,
          enum: ["healthy", "degraded"],
          description: "Overall health status"
        },
        checks: HealthChecks,
        timestamp: %Schema{type: :string, format: :"date-time", description: "Check timestamp"}
      },
      required: [:status, :checks, :timestamp],
      example: %{
        status: "healthy",
        checks: %{
          database: %{healthy: true, latency_ms: 5},
          pubsub: %{healthy: true},
          supervisors: %{healthy: true, details: %{}},
          system_load: %{healthy: true, level: "low"}
        },
        timestamp: "2026-01-25T12:00:00Z"
      }
    })
  end
end

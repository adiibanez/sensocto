defmodule SensoctoWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),
      summary(
        "sensocto.live.mount.duration",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary(
        "sensocto.live.handle_info.measurement.duration",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary(
        "sensocto.live.handle_event.request_seed_data.duration",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),

      # counter("metrics.emit.value"),

      # summary("sensocto.sensors.messages.measurement.count",
      #   # tags: [:status],
      #   reporter_options: [report_as: :counter],
      #   tags: [:sensor_id]
      # ),

      summary(
        "sensocto.sensors.messages.mps.value",
        description: "The number of messages per second",
        tags: [:sensor_id]
      ),
      distribution(
        "sensocto.sensors.messages.mps.value",
        description: "The number of messages per second",
        tags: [:sensor_id]
      ),

      # summary("sensocto.live.mount",
      #   unit: {:native, :millisecond},
      #   description:
      #     "The time during liveview mount"
      # ),

      # summary("sensocto.live.handle_info.measurement",
      #   unit: {:native, :millisecond},
      #   description:
      #     "The time during liveview mount"
      # ),

      # Database Metrics
      summary("sensocto.repo.query.total_time",
        unit: {:native, :millisecond},
        description: "The sum of the other measurements"
      ),
      summary("sensocto.repo.query.decode_time",
        unit: {:native, :millisecond},
        description: "The time spent decoding the data received from the database"
      ),
      summary("sensocto.repo.query.query_time",
        unit: {:native, :millisecond},
        description: "The time spent executing the query"
      ),
      summary("sensocto.repo.query.queue_time",
        unit: {:native, :millisecond},
        description: "The time spent waiting for a database connection"
      ),
      summary("sensocto.repo.query.idle_time",
        unit: {:native, :millisecond},
        description:
          "The time the connection spent waiting before being checked out for the query"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {SensoctoWeb, :count_users, []}
    ]
  end
end

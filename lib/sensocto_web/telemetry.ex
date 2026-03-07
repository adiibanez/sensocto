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

      # ── Iroh Room Store metrics ─────────────────────────────────────
      # Duration of each NIF call (tagged by status: ok | error | circuit_open)
      summary("iroh.room_store.store_room.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh NIF latency for storing a room document"
      ),
      summary("iroh.room_store.get_room.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh NIF latency for reading a room document"
      ),
      summary("iroh.room_store.delete_room.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh NIF latency for tombstoning a room document"
      ),
      summary("iroh.room_store.store_membership.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh NIF latency for storing a membership entry"
      ),
      summary("iroh.room_store.get_membership.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh NIF latency for reading a membership entry"
      ),
      summary("iroh.room_store.delete_membership.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh NIF latency for tombstoning a membership entry"
      ),
      counter("iroh.room_store.store_room.exception",
        description: "Iroh store_room NIF exceptions (NIF crash or timeout)"
      ),
      counter("iroh.room_store.get_room.exception",
        description: "Iroh get_room NIF exceptions"
      ),

      # ── Iroh CRDT (Automerge) metrics ──────────────────────────────
      summary("iroh.crdt.get_state.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status],
        description: "Iroh automerge_to_json NIF latency"
      ),
      summary("iroh.crdt.set_media_field.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status, :field],
        description: "Iroh automerge_map_put latency for media fields"
      ),
      summary("iroh.crdt.set_object3d_field.stop.duration",
        unit: {:native, :millisecond},
        tags: [:status, :field],
        description: "Iroh automerge_map_put latency for 3D object fields"
      ),
      counter("iroh.crdt.get_state.exception",
        description: "Iroh CRDT get_state NIF exceptions"
      ),

      # ── Biomimetic System Metrics ────────────────────────────────────────────

      # SystemLoadMonitor — composite system pulse (0.0–1.0 pressures)
      last_value("sensocto.bio.system.scheduler.value",
        description: "BEAM scheduler utilization (0.0–1.0)"
      ),
      last_value("sensocto.bio.system.pubsub_pressure.value",
        description: "PubSub dispatch queue pressure (0.0–1.0)"
      ),
      last_value("sensocto.bio.system.memory_pressure.value",
        description: "System memory pressure (0.0–1.0)"
      ),
      last_value("sensocto.bio.system.queue_pressure.value",
        description: "Process mailbox queue pressure (0.0–1.0)"
      ),
      last_value("sensocto.bio.system.load_multiplier.value",
        description: "Current load batch-window multiplier (1.0=normal, 5.0=critical)"
      ),

      # HomeostaticTuner — load state distribution (% time in each state)
      last_value("sensocto.bio.homeostasis.distribution.value",
        tags: [:level],
        description: "% of samples in each load state (homeostatic plasticity)"
      ),
      last_value("sensocto.bio.homeostasis.offset.value",
        tags: [:level],
        description: "Adaptive threshold offsets tuned by HomeostaticTuner"
      ),

      # NoveltyDetector — Locus Coeruleus-inspired anomaly detection
      last_value("sensocto.bio.novelty.recent_events.value",
        description: "Novelty/anomaly events in the last 60 seconds"
      ),
      last_value("sensocto.bio.novelty.total_tracked.value",
        description: "Total novelty events tracked (ring-buffer, max 100)"
      ),

      # CircadianScheduler — SCN-inspired circadian phase
      last_value("sensocto.bio.circadian.adjustment.value",
        description: "Circadian phase adjustment factor (0.85=off-peak, 1.2=peak)"
      ),
      last_value("sensocto.bio.circadian.ultradian.value",
        description: "Ultradian BRAC modulation factor (~90-min oscillation)"
      ),

      # PredictiveLoadBalancer — Cerebellum-inspired pre-adjustment
      last_value("sensocto.bio.predictive.pre_boosts.value",
        description: "Sensors with active pre-boost prediction (attention spike incoming)"
      ),
      last_value("sensocto.bio.predictive.post_peaks.value",
        description: "Sensors in post-peak cooldown"
      ),

      # ResourceArbiter — retina lateral-inhibition allocation
      last_value("sensocto.bio.resource.sensors.value",
        description: "Sensors with active competitive resource allocations"
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  @doc """
  Emits telemetry events for the biomimetic system state.
  Called by the telemetry poller every 10 seconds.
  """
  def emit_bio_metrics do
    # SystemLoadMonitor — composite system pulse
    try do
      m = Sensocto.SystemLoadMonitor.get_metrics()

      :telemetry.execute([:sensocto, :bio, :system, :scheduler], %{value: m.scheduler_utilization})

      :telemetry.execute([:sensocto, :bio, :system, :pubsub_pressure], %{value: m.pubsub_pressure})

      :telemetry.execute([:sensocto, :bio, :system, :memory_pressure], %{
        value: m.memory_pressure
      })

      :telemetry.execute([:sensocto, :bio, :system, :queue_pressure], %{
        value: m.message_queue_pressure
      })

      :telemetry.execute([:sensocto, :bio, :system, :load_multiplier], %{
        value: m.load_multiplier
      })
    rescue
      _ -> :ok
    end

    # HomeostaticTuner — load state distribution + threshold offsets
    try do
      state = Sensocto.Bio.HomeostaticTuner.get_state()

      for level <- [:normal, :elevated, :high, :critical] do
        pct = Map.get(state.actual_distribution, level, 0.0) * 100

        :telemetry.execute(
          [:sensocto, :bio, :homeostasis, :distribution],
          %{value: pct},
          %{level: level}
        )
      end

      for level <- [:elevated, :high, :critical] do
        offset = Map.get(state.threshold_offsets, level, 0.0)

        :telemetry.execute(
          [:sensocto, :bio, :homeostasis, :offset],
          %{value: offset},
          %{level: level}
        )
      end
    rescue
      _ -> :ok
    end

    # NoveltyDetector — Locus Coeruleus-inspired anomaly detection
    try do
      events = Sensocto.Bio.NoveltyDetector.get_recent_events(100)
      now = System.system_time(:millisecond)
      recent_count = Enum.count(events, fn e -> now - e.timestamp < 60_000 end)

      :telemetry.execute([:sensocto, :bio, :novelty, :recent_events], %{value: recent_count})
      :telemetry.execute([:sensocto, :bio, :novelty, :total_tracked], %{value: length(events)})
    rescue
      _ -> :ok
    end

    # CircadianScheduler — SCN-inspired phase tracking
    try do
      adjustment = Sensocto.Bio.CircadianScheduler.get_phase_adjustment()
      ultradian = Sensocto.Bio.CircadianScheduler.ultradian_modulation()

      :telemetry.execute([:sensocto, :bio, :circadian, :adjustment], %{value: adjustment})
      :telemetry.execute([:sensocto, :bio, :circadian, :ultradian], %{value: ultradian})
    rescue
      _ -> :ok
    end

    # PredictiveLoadBalancer — Cerebellum-inspired pre-adjustment
    try do
      predictions = Sensocto.Bio.PredictiveLoadBalancer.get_predictions()
      pre_boosts = Enum.count(predictions, fn {_, v} -> match?({:pre_boost, _}, v) end)
      post_peaks = Enum.count(predictions, fn {_, v} -> match?({:post_peak, _}, v) end)

      :telemetry.execute([:sensocto, :bio, :predictive, :pre_boosts], %{value: pre_boosts})
      :telemetry.execute([:sensocto, :bio, :predictive, :post_peaks], %{value: post_peaks})
    rescue
      _ -> :ok
    end

    # ResourceArbiter — retina lateral-inhibition resource allocation
    try do
      allocations = Sensocto.Bio.ResourceArbiter.get_allocations()

      :telemetry.execute([:sensocto, :bio, :resource, :sensors], %{
        value: map_size(allocations)
      })
    rescue
      _ -> :ok
    end
  end

  defp periodic_measurements do
    [
      {__MODULE__, :emit_bio_metrics, []}
    ]
  end
end

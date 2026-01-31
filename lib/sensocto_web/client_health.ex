defmodule SensoctoWeb.ClientHealth do
  @moduledoc """
  Tracks client health metrics and manages adaptive quality levels for LiveViews.

  ## Philosophy

  Default to maximum throughput (raw/realtime data). Throttling is a last
  resort when server load or client performance becomes a problem. The system
  should keep trying to send as much realtime data as possible.

  ## Quality Levels

  - `:high` - Maximum throughput, raw data (~60fps)
  - `:medium` - Still realtime, slight batching (~20fps)
  - `:low` - First level of throttling (only on real pressure)
  - `:minimal` - Emergency mode (significant throttling)

  ## Client Metrics Tracked

  - FPS (frames per second)
  - CPU pressure (nominal, fair, serious, critical)
  - Memory usage
  - Battery level and charging status
  - Network type and quality
  - Dropped frames
  - Render lag

  ## Usage in LiveView

  ```elixir
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:client_health, ClientHealth.init())
      # ...
    {:ok, socket}
  end

  def handle_event("client_health", report, socket) do
    {new_health, changed?, quality, reason} =
      ClientHealth.process_health_report(socket.assigns.client_health, report)

    socket = assign(socket, :client_health, new_health)

    socket =
      if changed? do
        # Adapt lens subscription
        socket
        |> unsubscribe_current_lens()
        |> subscribe_to_lens(quality)
        |> push_event("quality_changed", %{level: quality, reason: reason})
      else
        socket
      end

    {:noreply, socket}
  end
  ```
  """

  require Logger

  @type quality_level :: :high | :medium | :low | :minimal

  @type health_state :: %{
          current_quality: quality_level(),
          health_history: [integer()],
          last_quality_change: integer(),
          degradation_reason: String.t() | nil,
          metrics: map()
        }

  # Quality thresholds with hysteresis (different enter/exit to prevent flapping)
  # Conservative thresholds: only downgrade when there's significant pressure
  # Throttling is a last resort - stay at high quality as long as possible
  @quality_thresholds %{
    high: %{enter: 60, exit: 40},
    medium: %{enter: 35, exit: 20},
    low: %{enter: 15, exit: 5}
    # Below low exit = minimal
  }

  # Minimum time between quality changes (prevent flapping)
  @quality_change_cooldown_ms 5_000

  # Number of health reports to average
  @history_window 5

  # ============================================================================
  # Public API
  # ============================================================================

  @doc """
  Initialize health tracking state for a socket.
  """
  @spec init() :: health_state()
  def init do
    %{
      current_quality: :high,
      health_history: [],
      last_quality_change: System.monotonic_time(:millisecond),
      degradation_reason: nil,
      metrics: %{}
    }
  end

  @doc """
  Process a health report from the client.

  Returns `{new_state, quality_changed?, new_quality, reason}`
  """
  @spec process_health_report(health_state(), map()) ::
          {health_state(), boolean(), quality_level(), String.t() | nil}
  def process_health_report(state, report) do
    health_score = Map.get(report, "healthScore", 100)

    # Keep rolling window of health scores
    history = Enum.take([health_score | state.health_history], @history_window)
    avg_health = if Enum.empty?(history), do: 100, else: Enum.sum(history) / length(history)

    # Determine new quality level with hysteresis
    {new_quality, reason} = determine_quality(avg_health, state.current_quality, report)

    # Check cooldown
    now = System.monotonic_time(:millisecond)
    cooldown_elapsed = now - state.last_quality_change >= @quality_change_cooldown_ms

    quality_changed = new_quality != state.current_quality && cooldown_elapsed

    new_state = %{
      state
      | health_history: history,
        current_quality: if(quality_changed, do: new_quality, else: state.current_quality),
        last_quality_change: if(quality_changed, do: now, else: state.last_quality_change),
        degradation_reason:
          if(quality_changed && new_quality != :high, do: reason, else: state.degradation_reason),
        metrics: extract_metrics(report)
    }

    if quality_changed do
      Logger.info(
        "Client quality changed: #{state.current_quality} -> #{new_quality}, reason: #{reason}"
      )
    end

    {new_state, quality_changed, new_quality, reason}
  end

  @doc """
  Returns the appropriate lens configuration for a quality level.

  Philosophy: Default to maximum throughput (raw/realtime data).
  Throttling is a last resort when server load becomes a problem.
  """
  @spec lens_config_for_quality(quality_level()) :: map()
  def lens_config_for_quality(quality) do
    case quality do
      :high ->
        # Maximum throughput - send everything as fast as possible
        %{
          default_lens: "lens:raw",
          focused_lens: "lens:raw",
          batch_window_ms: 16,
          max_sensors_realtime: :unlimited
        }

      :medium ->
        # Still realtime, slightly batched to reduce message count
        %{
          default_lens: "lens:raw",
          focused_lens: "lens:raw",
          batch_window_ms: 50,
          max_sensors_realtime: :unlimited
        }

      :low ->
        # First level of actual throttling - only when there's real pressure
        %{
          default_lens: "lens:throttled:20",
          focused_lens: "lens:raw",
          batch_window_ms: 100,
          max_sensors_realtime: 20
        }

      :minimal ->
        # Emergency mode - significant throttling
        %{
          default_lens: "lens:throttled:10",
          focused_lens: "lens:throttled:20",
          batch_window_ms: 200,
          max_sensors_realtime: 5
        }
    end
  end

  @doc """
  Get the current quality level.
  """
  @spec current_quality(health_state()) :: quality_level()
  def current_quality(state), do: state.current_quality

  @doc """
  Get the average health score.
  """
  @spec average_health(health_state()) :: float()
  def average_health(state) do
    if Enum.empty?(state.health_history) do
      100.0
    else
      Enum.sum(state.health_history) / length(state.health_history)
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp determine_quality(avg_health, current_quality, report) do
    reason = identify_degradation_reason(report)
    network_type = Map.get(report, "networkEffectiveType")

    # Force immediate downgrade for slow networks (bypass normal scoring)
    # This prevents mailbox accumulation on 3G/2G connections
    forced_quality = force_quality_for_network(network_type)

    new_quality =
      cond do
        # Network-forced quality takes precedence (immediate downgrade)
        forced_quality != nil ->
          forced_quality

        # Upgrading (need to exceed enter threshold)
        current_quality == :minimal && avg_health >= @quality_thresholds.low.enter ->
          :low

        current_quality == :low && avg_health >= @quality_thresholds.medium.enter ->
          :medium

        current_quality == :medium && avg_health >= @quality_thresholds.high.enter ->
          :high

        # Downgrading (need to drop below exit threshold)
        current_quality == :high && avg_health < @quality_thresholds.high.exit ->
          :medium

        current_quality == :medium && avg_health < @quality_thresholds.medium.exit ->
          :low

        current_quality == :low && avg_health < @quality_thresholds.low.exit ->
          :minimal

        # No change
        true ->
          current_quality
      end

    {new_quality, reason}
  end

  # Force quality level based on network type to prevent backpressure
  # Returns nil if no force is needed (let normal scoring decide)
  defp force_quality_for_network("slow-2g"), do: :minimal
  defp force_quality_for_network("2g"), do: :minimal
  defp force_quality_for_network("3g"), do: :low
  defp force_quality_for_network(_), do: nil

  defp identify_degradation_reason(report) do
    cond do
      Map.get(report, "cpuPressure") in ["serious", "critical"] ->
        "High CPU load"

      (fps = Map.get(report, "fps")) && fps < 30 ->
        "Low frame rate (#{fps} fps)"

      (mem = Map.get(report, "memoryPressure")) && mem > 0.85 ->
        "High memory usage"

      (battery = Map.get(report, "batteryLevel")) && battery < 15 &&
          !Map.get(report, "batteryCharging", true) ->
        "Low battery"

      Map.get(report, "networkEffectiveType") in ["slow-2g", "2g", "3g"] ->
        "Slow network connection (#{Map.get(report, "networkEffectiveType")})"

      Map.get(report, "thermalState") == "throttled" ->
        "Device thermal throttling"

      (dropped = Map.get(report, "droppedFrames")) && dropped > 5 ->
        "Frame drops detected"

      true ->
        "General performance degradation"
    end
  end

  defp extract_metrics(report) do
    %{
      fps: Map.get(report, "fps"),
      cpu_pressure: Map.get(report, "cpuPressure"),
      memory_pressure: Map.get(report, "memoryPressure"),
      battery_level: Map.get(report, "batteryLevel"),
      battery_charging: Map.get(report, "batteryCharging"),
      network_type: Map.get(report, "networkEffectiveType"),
      dropped_frames: Map.get(report, "droppedFrames"),
      health_score: Map.get(report, "healthScore"),
      timestamp: System.system_time(:millisecond)
    }
  end
end

defmodule SensoctoWeb.Admin.SystemStatusLive do
  @moduledoc """
  System status dashboard for visualizing biomimetic system health.

  Displays real-time metrics from:
  - SystemLoadMonitor (CPU, memory, PubSub pressure)
  - CircadianScheduler (time-based patterns)
  - NoveltyDetector (anomaly detection)
  - PredictiveLoadBalancer (learned predictions)
  - ResourceArbiter (sensor resource allocation)
  - HomeostaticTuner (threshold adaptation)
  - AttentionTracker (user attention levels)
  """

  use SensoctoWeb, :live_view

  alias Sensocto.SystemLoadMonitor

  alias Sensocto.Bio.{
    CircadianScheduler,
    NoveltyDetector,
    PredictiveLoadBalancer,
    ResourceArbiter,
    HomeostaticTuner
  }

  alias Sensocto.AttentionTracker

  require Logger

  @refresh_interval 2000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:load")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "bio:novelty:global")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "bio:circadian")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "bio:homeostasis")

      send(self(), :refresh_metrics)
    end

    {:ok, assign_initial_state(socket)}
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    Process.send_after(self(), :refresh_metrics, @refresh_interval)
    {:noreply, refresh_all_metrics(socket)}
  end

  # Handle system load changes
  @impl true
  def handle_info({:system_load_changed, metrics}, socket) do
    {:noreply, assign(socket, :system_metrics, Map.merge(socket.assigns.system_metrics, metrics))}
  end

  @impl true
  def handle_info({:memory_protection_changed, %{active: active}}, socket) do
    system_metrics = Map.put(socket.assigns.system_metrics, :memory_protection_active, active)
    {:noreply, assign(socket, :system_metrics, system_metrics)}
  end

  # Handle novelty events
  @impl true
  def handle_info({:novelty_detected, sensor_id, attribute_id, z_score}, socket) do
    event = %{
      sensor_id: sensor_id,
      attribute_id: attribute_id,
      z_score: z_score,
      timestamp: DateTime.utc_now()
    }

    events = [event | Enum.take(socket.assigns.novelty_events, 9)]
    {:noreply, assign(socket, :novelty_events, events)}
  end

  # Handle circadian phase changes
  @impl true
  def handle_info({:phase_change, %{phase: phase, adjustment: adjustment}}, socket) do
    socket =
      socket
      |> assign(:circadian_phase, phase)
      |> assign(:circadian_adjustment, adjustment)

    {:noreply, socket}
  end

  # Handle homeostatic adaptations
  @impl true
  def handle_info({:adaptation, %{actual: distribution, offsets: offsets}}, socket) do
    socket =
      socket
      |> assign(:homeostatic_distribution, distribution)
      |> assign(:homeostatic_offsets, offsets)

    {:noreply, socket}
  end

  # Catch-all for other messages
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("force_refresh", _params, socket) do
    {:noreply, refresh_all_metrics(socket)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp assign_initial_state(socket) do
    socket
    |> assign(:page_title, "System Status")
    |> assign(:system_metrics, default_system_metrics())
    |> assign(:circadian_phase, :unknown)
    |> assign(:circadian_adjustment, 1.0)
    |> assign(:circadian_profile, %{})
    |> assign(:novelty_events, [])
    |> assign(:novelty_threshold, 3.0)
    |> assign(:predictions, %{})
    |> assign(:allocations, %{})
    |> assign(:homeostatic_distribution, default_distribution())
    |> assign(:homeostatic_offsets, %{elevated: 0.0, high: 0.0, critical: 0.0})
    |> assign(:homeostatic_target, HomeostaticTuner.get_target_distribution())
    |> assign(:attention_summary, default_attention_summary())
  end

  defp refresh_all_metrics(socket) do
    socket
    |> assign(:system_metrics, fetch_system_metrics())
    |> assign(:circadian_phase, fetch_circadian_phase())
    |> assign(:circadian_adjustment, fetch_circadian_adjustment())
    |> assign(:circadian_profile, fetch_circadian_profile())
    |> assign(:novelty_events, fetch_novelty_events())
    |> assign(:predictions, fetch_predictions())
    |> assign(:allocations, fetch_allocations())
    |> assign_homeostatic_state()
    |> assign(:attention_summary, build_attention_summary())
  end

  defp fetch_system_metrics do
    try do
      SystemLoadMonitor.get_metrics()
    catch
      :exit, _ -> default_system_metrics()
    end
  end

  defp default_system_metrics do
    %{
      load_level: :normal,
      load_multiplier: 1.0,
      scheduler_utilization: 0.0,
      memory_pressure: 0.0,
      pubsub_pressure: 0.0,
      message_queue_pressure: 0.0,
      memory_protection_active: false
    }
  end

  defp fetch_circadian_phase do
    try do
      CircadianScheduler.get_phase()
    catch
      :exit, _ -> :unknown
    end
  end

  defp fetch_circadian_adjustment do
    try do
      CircadianScheduler.get_phase_adjustment()
    catch
      :exit, _ -> 1.0
    end
  end

  defp fetch_circadian_profile do
    try do
      CircadianScheduler.get_profile()
    catch
      :exit, _ -> %{}
    end
  end

  defp fetch_novelty_events do
    try do
      NoveltyDetector.get_recent_events(10)
    catch
      :exit, _ -> []
    end
  end

  defp fetch_predictions do
    try do
      PredictiveLoadBalancer.get_predictions()
    catch
      :exit, _ -> %{}
    end
  end

  defp fetch_allocations do
    try do
      ResourceArbiter.get_allocations()
    catch
      :exit, _ -> %{}
    end
  end

  defp assign_homeostatic_state(socket) do
    try do
      state = HomeostaticTuner.get_state()

      # Calculate distribution from samples if actual_distribution is empty
      distribution =
        case Map.get(state, :actual_distribution, %{}) do
          dist when dist == %{} or dist == nil ->
            calculate_distribution_from_samples(Map.get(state, :load_samples, []))

          dist ->
            dist
        end

      socket
      |> assign(:homeostatic_distribution, distribution)
      |> assign(
        :homeostatic_offsets,
        Map.get(state, :threshold_offsets, %{elevated: 0.0, high: 0.0, critical: 0.0})
      )
    catch
      :exit, _ -> socket
    end
  end

  defp calculate_distribution_from_samples([]), do: default_distribution()

  defp calculate_distribution_from_samples(samples) do
    total = length(samples)

    Enum.reduce(samples, %{normal: 0, elevated: 0, high: 0, critical: 0}, fn level, acc ->
      Map.update(acc, level, 1, &(&1 + 1))
    end)
    |> Enum.map(fn {level, count} -> {level, count / total} end)
    |> Map.new()
  end

  defp default_distribution do
    %{normal: 0.0, elevated: 0.0, high: 0.0, critical: 0.0}
  end

  defp build_attention_summary do
    try do
      state = AttentionTracker.get_state()

      # Get attention counts from ETS cache (more accurate than state.attention_state)
      attention_counts =
        try do
          :ets.tab2list(:sensor_attention_cache)
          |> Enum.reduce(%{high: 0, medium: 0, low: 0, none: 0}, fn {_sensor_id, level}, acc ->
            Map.update(acc, level, 1, &(&1 + 1))
          end)
        rescue
          ArgumentError -> %{high: 0, medium: 0, low: 0, none: 0}
        end

      total_sensors =
        try do
          :ets.info(:sensor_attention_cache, :size) || 0
        rescue
          _ -> 0
        end

      # Get pinned sensors
      pinned_sensors =
        state.pinned_sensors
        |> Enum.flat_map(fn {sensor_id, users} ->
          if MapSet.size(users) > 0, do: [sensor_id], else: []
        end)

      # Count battery states
      battery_counts =
        state.battery_states
        |> Enum.reduce(%{normal: 0, low: 0, critical: 0}, fn {_user_id, {state_atom, _meta}},
                                                             acc ->
          Map.update(acc, state_atom, 1, &(&1 + 1))
        end)

      %{
        attention_counts: attention_counts,
        pinned_sensors: pinned_sensors,
        battery_counts: battery_counts,
        total_sensors: total_sensors
      }
    catch
      :exit, _ -> default_attention_summary()
    end
  end

  defp default_attention_summary do
    %{
      attention_counts: %{high: 0, medium: 0, low: 0, none: 0},
      pinned_sensors: [],
      battery_counts: %{normal: 0, low: 0, critical: 0},
      total_sensors: 0
    }
  end

  # ============================================================================
  # Component Functions
  # ============================================================================

  @doc """
  Renders a badge showing the current system load level.
  """
  attr :level, :atom, required: true

  def load_level_badge(assigns) do
    {bg, text, label} =
      case assigns.level do
        :normal -> {"bg-green-600/20", "text-green-400", "Normal"}
        :elevated -> {"bg-yellow-600/20", "text-yellow-400", "Elevated"}
        :high -> {"bg-orange-600/20", "text-orange-400", "High"}
        :critical -> {"bg-red-600/20", "text-red-400", "Critical"}
        _ -> {"bg-gray-600/20", "text-gray-400", "Unknown"}
      end

    assigns = assign(assigns, bg: bg, text: text, label: label)

    ~H"""
    <span class={"px-3 py-1 rounded-full text-sm font-medium #{@bg} #{@text}"}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a metric gauge with percentage value.
  """
  attr :label, :string, required: true
  attr :value, :float, required: true
  attr :icon, :string, required: true
  attr :warning, :boolean, default: false

  def metric_gauge(assigns) do
    percentage = assigns.value * 100

    color =
      cond do
        assigns.warning -> "bg-red-500"
        percentage >= 85 -> "bg-red-500"
        percentage >= 70 -> "bg-orange-500"
        percentage >= 50 -> "bg-yellow-500"
        true -> "bg-green-500"
      end

    assigns = assign(assigns, percentage: percentage, color: color)

    ~H"""
    <div class="flex flex-col">
      <div class="flex items-center gap-1 mb-1">
        <Heroicons.icon name={@icon} type="outline" class="h-4 w-4 text-gray-400" />
        <span class="text-xs text-gray-400">{@label}</span>
      </div>
      <div class="h-2 bg-gray-700 rounded-full overflow-hidden">
        <div class={"h-full rounded-full transition-all #{@color}"} style={"width: #{@percentage}%"} />
      </div>
      <span class="text-sm font-mono text-gray-300 mt-1">{Float.round(@percentage, 1)}%</span>
    </div>
    """
  end

  @doc """
  Renders a badge showing the circadian phase.
  """
  attr :phase, :atom, required: true

  def phase_badge(assigns) do
    {bg, text} =
      case assigns.phase do
        :off_peak -> {"bg-green-600/20", "text-green-400"}
        :approaching_off_peak -> {"bg-green-600/10", "text-green-300"}
        :normal -> {"bg-gray-600/20", "text-gray-400"}
        :approaching_peak -> {"bg-orange-600/20", "text-orange-400"}
        :peak -> {"bg-red-600/20", "text-red-400"}
        _ -> {"bg-gray-600/20", "text-gray-400"}
      end

    label =
      assigns.phase
      |> to_string()
      |> String.replace("_", " ")
      |> String.split()
      |> Enum.map(&String.capitalize/1)
      |> Enum.join(" ")

    assigns = assign(assigns, bg: bg, text: text, label: label)

    ~H"""
    <span class={"px-2 py-1 rounded-full text-xs #{@bg} #{@text}"}>
      {@label}
    </span>
    """
  end

  @doc """
  Renders a badge showing prediction status.
  """
  attr :prediction, :map, required: true

  def prediction_badge(assigns) do
    {bg, text, label} =
      case assigns.prediction do
        %{state: :pre_boost} ->
          {"bg-cyan-600/20", "text-cyan-400", "Pre-boost"}

        %{state: :post_peak} ->
          {"bg-purple-600/20", "text-purple-400", "Post-peak"}

        %{factor: factor} when factor < 1.0 ->
          {"bg-green-600/20", "text-green-400", "Boosted"}

        %{factor: factor} when factor > 1.0 ->
          {"bg-orange-600/20", "text-orange-400", "Throttled"}

        _ ->
          {"bg-gray-600/20", "text-gray-400", "Normal"}
      end

    factor = Map.get(assigns.prediction, :factor, 1.0)
    assigns = assign(assigns, bg: bg, text: text, label: label, factor: factor)

    ~H"""
    <div class="flex items-center gap-2">
      <span class={"px-2 py-0.5 rounded text-xs #{@bg} #{@text}"}>{@label}</span>
      <span class="text-xs font-mono text-gray-400">{Float.round(@factor * 1.0, 2)}x</span>
    </div>
    """
  end

  @doc """
  Renders an attention level badge.
  """
  attr :level, :atom, required: true

  def attention_badge(assigns) do
    {bg, text, icon} =
      case assigns.level do
        :high -> {"bg-green-600/20", "text-green-400", "eye"}
        :medium -> {"bg-yellow-600/20", "text-yellow-400", "eye"}
        :low -> {"bg-orange-600/20", "text-orange-400", "eye-slash"}
        _ -> {"bg-gray-600/20", "text-gray-400", "eye-slash"}
      end

    assigns = assign(assigns, bg: bg, text: text, icon: icon)

    ~H"""
    <span class={"flex items-center gap-1 px-2 py-0.5 rounded text-xs #{@bg} #{@text}"}>
      <Heroicons.icon name={@icon} type="outline" class="h-3 w-3" />
      {@level}
    </span>
    """
  end

  # ============================================================================
  # Helper Functions for Colors
  # ============================================================================

  defp profile_bar_color(score) when score >= 0.7, do: "bg-red-500"
  defp profile_bar_color(score) when score >= 0.5, do: "bg-orange-500"
  defp profile_bar_color(score) when score >= 0.3, do: "bg-yellow-500"
  defp profile_bar_color(_score), do: "bg-green-500"

  defp level_color(:normal), do: "text-green-400"
  defp level_color(:elevated), do: "text-yellow-400"
  defp level_color(:high), do: "text-orange-400"
  defp level_color(:critical), do: "text-red-400"
  defp level_color(_), do: "text-gray-400"

  defp level_bar_color(:normal), do: "bg-green-500"
  defp level_bar_color(:elevated), do: "bg-yellow-500"
  defp level_bar_color(:high), do: "bg-orange-500"
  defp level_bar_color(:critical), do: "bg-red-500"
  defp level_bar_color(_), do: "bg-gray-500"
end

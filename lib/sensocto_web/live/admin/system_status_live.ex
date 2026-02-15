defmodule SensoctoWeb.Admin.SystemStatusLive do
  @moduledoc """
  System status dashboard for monitoring system health.

  Displays real-time metrics from:
  - SystemLoadMonitor (CPU, memory, PubSub pressure)
  - PriorityLens (backpressure and quality distribution)
  - AttentionTracker (user attention levels and battery states)
  """

  use SensoctoWeb, :live_view

  alias Sensocto.SystemLoadMonitor
  alias Sensocto.Lenses.PriorityLens
  alias Sensocto.AttentionTracker
  alias Sensocto.AttributeStoreTiered

  require Logger

  # Adaptive refresh: faster when healthy, slower under load
  @refresh_interval_normal 2000
  @refresh_interval_elevated 4000
  @refresh_interval_high 8000
  # Debounce attention updates to avoid excessive ETS scans (100ms window)
  @attention_debounce_ms 100

  @cluster_refresh_interval 10_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "system:load")
      # Subscribe to attention changes for real-time updates
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:lobby")

      send(self(), :refresh_metrics)
      send(self(), :refresh_cluster_metrics)
    end

    {:ok, assign_initial_state(socket) |> assign(:attention_update_timer, nil)}
  end

  @impl true
  def handle_info(:refresh_metrics, socket) do
    # Adaptive refresh: slower when under load to reduce monitoring overhead
    interval = adaptive_refresh_interval(socket.assigns.system_metrics.load_level)
    Process.send_after(self(), :refresh_metrics, interval)
    {:noreply, refresh_all_metrics(socket)}
  end

  @impl true
  def handle_info(:refresh_cluster_metrics, socket) do
    Process.send_after(self(), :refresh_cluster_metrics, @cluster_refresh_interval)
    {:noreply, fetch_cluster_metrics(socket)}
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

  @impl true
  def handle_info(:attention_tracker_restarted, socket), do: {:noreply, socket}

  # Handle attention changes - debounce to avoid excessive ETS scans
  @impl true
  def handle_info({:attention_changed, %{sensor_id: _sensor_id, level: _level}}, socket) do
    # Cancel any pending timer
    if socket.assigns.attention_update_timer do
      Process.cancel_timer(socket.assigns.attention_update_timer)
    end

    # Schedule debounced update
    timer = Process.send_after(self(), :update_attention_counts, @attention_debounce_ms)
    {:noreply, assign(socket, :attention_update_timer, timer)}
  end

  # Perform the actual attention counts update (debounced)
  @impl true
  def handle_info(:update_attention_counts, socket) do
    # Update attention counts from ETS directly (fast, no GenServer blocking)
    # This is the high-priority path for real-time attention updates
    attention_counts =
      try do
        :ets.tab2list(:sensor_attention_cache)
        |> Enum.reduce(%{high: 0, medium: 0, low: 0, none: 0}, fn {_sensor_id, level}, acc ->
          Map.update(acc, level, 1, &(&1 + 1))
        end)
      rescue
        ArgumentError -> socket.assigns.attention_summary.attention_counts
      end

    total_sensors =
      try do
        :ets.info(:sensor_attention_cache, :size) || 0
      rescue
        _ -> socket.assigns.attention_summary.total_sensors
      end

    # Update only the ETS-derived values (fast path)
    # Pinned sensors and battery states are updated on the slower refresh cycle
    updated_summary =
      socket.assigns.attention_summary
      |> Map.put(:attention_counts, attention_counts)
      |> Map.put(:total_sensors, total_sensors)

    socket = assign(socket, attention_summary: updated_summary, attention_update_timer: nil)

    socket =
      if MapSet.member?(socket.assigns.graph_tiles, :attention) do
        update_graph_data(socket, :attention)
      else
        socket
      end

    {:noreply, socket}
  end

  # Catch-all for other messages
  @impl true
  def handle_info(_msg, socket), do: {:noreply, socket}

  @impl true
  def handle_event("force_refresh", _params, socket) do
    {:noreply, refresh_all_metrics(socket)}
  end

  @impl true
  def handle_event("toggle_graph", %{"tile" => tile}, socket) do
    tile_atom = String.to_existing_atom(tile)
    graph_tiles = socket.assigns.graph_tiles

    {new_tiles, socket} =
      if MapSet.member?(graph_tiles, tile_atom) do
        {MapSet.delete(graph_tiles, tile_atom), socket}
      else
        socket = update_graph_data(socket, tile_atom)
        {MapSet.put(graph_tiles, tile_atom), socket}
      end

    {:noreply, assign(socket, :graph_tiles, new_tiles)}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp assign_initial_state(socket) do
    socket
    |> assign(:page_title, "System Status")
    |> assign(:system_metrics, default_system_metrics())
    |> assign(:backpressure_stats, default_backpressure_stats())
    |> assign(:attention_summary, default_attention_summary())
    |> assign(:cluster_metrics, %{})
    |> assign(:current_node, node())
    |> assign(:connected_nodes, Node.list())
    |> assign(:graph_tiles, MapSet.new())
    |> assign(:graph_data, %{})
  end

  defp refresh_all_metrics(socket) do
    socket
    |> assign(:system_metrics, fetch_system_metrics())
    |> assign(:backpressure_stats, fetch_backpressure_stats())
    |> assign(:attention_summary, build_attention_summary())
    |> refresh_active_graphs()
  end

  defp refresh_active_graphs(socket) do
    Enum.reduce(socket.assigns.graph_tiles, socket, fn tile, acc ->
      update_graph_data(acc, tile)
    end)
  end

  defp update_graph_data(socket, :system_load) do
    m = socket.assigns.system_metrics

    data = %{
      cpu: m.scheduler_utilization,
      memory: m.memory_pressure,
      pubsub: m.pubsub_pressure,
      queues: m.message_queue_pressure,
      load_level: Atom.to_string(m.load_level)
    }

    assign(socket, :graph_data, Map.put(socket.assigns.graph_data, :system_load, data))
  end

  defp update_graph_data(socket, :backpressure) do
    socket_data =
      try do
        :ets.tab2list(:priority_lens_sockets)
        |> Enum.map(fn {socket_id, state} ->
          %{
            id: to_string(socket_id),
            quality: Atom.to_string(state.quality),
            sensor_count: MapSet.size(state.sensor_ids)
          }
        end)
      rescue
        ArgumentError -> []
      end

    assign(
      socket,
      :graph_data,
      Map.put(socket.assigns.graph_data, :backpressure, %{sockets: socket_data})
    )
  end

  defp update_graph_data(socket, :attention) do
    sensors =
      try do
        :ets.tab2list(:sensor_attention_cache)
        |> Enum.take(200)
        |> Enum.map(fn {sensor_id, level} ->
          %{id: to_string(sensor_id), level: Atom.to_string(level)}
        end)
      rescue
        ArgumentError -> []
      end

    assign(
      socket,
      :graph_data,
      Map.put(socket.assigns.graph_data, :attention, %{sensors: sensors})
    )
  end

  defp update_graph_data(socket, :battery) do
    sensors =
      try do
        :ets.tab2list(:sensor_attention_cache)
        |> Enum.take(200)
        |> Enum.map(fn {sensor_id, _level} ->
          battery_level = get_sensor_battery_level(sensor_id)

          status =
            cond do
              is_nil(battery_level) -> "normal"
              battery_level < 15 -> "critical"
              battery_level < 30 -> "low"
              true -> "normal"
            end

          %{id: to_string(sensor_id), status: status}
        end)
      rescue
        ArgumentError -> []
      end

    assign(socket, :graph_data, Map.put(socket.assigns.graph_data, :battery, %{sensors: sensors}))
  end

  defp update_graph_data(socket, _unknown), do: socket

  defp fetch_system_metrics do
    try do
      SystemLoadMonitor.get_metrics()
    catch
      :exit, _ -> default_system_metrics()
    end
  end

  defp fetch_backpressure_stats do
    # Direct ETS read from PriorityLens - no GenServer call
    PriorityLens.get_stats()
  end

  defp default_backpressure_stats do
    %{
      socket_count: 0,
      quality_distribution: %{high: 0, medium: 0, low: 0, minimal: 0, paused: 0},
      total_sensor_subscriptions: 0,
      paused_count: 0,
      degraded_count: 0,
      healthy: true
    }
  end

  defp fetch_cluster_metrics(socket) do
    # Get local node metrics with region
    local_metrics = fetch_system_metrics()
    local_region = System.get_env("FLY_REGION")
    local_metrics_with_region = Map.put(local_metrics, :fly_region, local_region)

    # Get metrics from connected nodes via RPC (including their FLY_REGION)
    remote_metrics =
      Node.list()
      |> Enum.map(fn remote_node ->
        case :rpc.call(remote_node, Sensocto.SystemLoadMonitor, :get_metrics, [], 2000) do
          {:badrpc, _reason} ->
            {remote_node, :unavailable}

          metrics ->
            # Also fetch the remote node's FLY_REGION
            remote_region =
              case :rpc.call(remote_node, System, :get_env, ["FLY_REGION"], 1000) do
                {:badrpc, _} -> nil
                region -> region
              end

            {remote_node, Map.put(metrics, :fly_region, remote_region)}
        end
      end)
      |> Map.new()

    all_metrics = Map.put(remote_metrics, node(), local_metrics_with_region)

    assign(socket,
      cluster_metrics: all_metrics,
      connected_nodes: Node.list()
    )
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

      # Count battery states from actual sensor battery attributes
      sensor_ids =
        try do
          :ets.tab2list(:sensor_attention_cache)
          |> Enum.map(fn {sensor_id, _} -> sensor_id end)
        rescue
          _ -> []
        end

      battery_counts =
        sensor_ids
        |> Enum.reduce(%{normal: 0, low: 0, critical: 0}, fn sensor_id, acc ->
          battery_level = get_sensor_battery_level(sensor_id)

          cond do
            is_nil(battery_level) -> acc
            battery_level < 15 -> Map.update!(acc, :critical, &(&1 + 1))
            battery_level < 30 -> Map.update!(acc, :low, &(&1 + 1))
            true -> Map.update!(acc, :normal, &(&1 + 1))
          end
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

  # Get the latest battery level for a sensor from AttributeStoreTiered
  defp get_sensor_battery_level(sensor_id) do
    try do
      case AttributeStoreTiered.get_attributes(sensor_id, 1) do
        %{"battery" => [%{payload: %{level: level}} | _]} when is_number(level) ->
          level

        _ ->
          nil
      end
    rescue
      _ -> nil
    catch
      :exit, _ -> nil
    end
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

  # Adaptive refresh intervals based on system load
  # Slower refresh under load to reduce monitoring overhead
  defp adaptive_refresh_interval(:normal), do: @refresh_interval_normal
  defp adaptive_refresh_interval(:elevated), do: @refresh_interval_elevated
  defp adaptive_refresh_interval(_high_or_critical), do: @refresh_interval_high

  # Fly.io regions mapped to country flags
  @region_flags %{
    # North America
    "iad" => "🇺🇸",
    "ewr" => "🇺🇸",
    "ord" => "🇺🇸",
    "lax" => "🇺🇸",
    "sjc" => "🇺🇸",
    "sea" => "🇺🇸",
    "dfw" => "🇺🇸",
    "den" => "🇺🇸",
    "atl" => "🇺🇸",
    "bos" => "🇺🇸",
    "mia" => "🇺🇸",
    "phx" => "🇺🇸",
    "yul" => "🇨🇦",
    "yyz" => "🇨🇦",
    "gdl" => "🇲🇽",
    "qro" => "🇲🇽",
    # South America
    "gru" => "🇧🇷",
    "gig" => "🇧🇷",
    "eze" => "🇦🇷",
    "scl" => "🇨🇱",
    "bog" => "🇨🇴",
    # Europe
    "ams" => "🇳🇱",
    "cdg" => "🇫🇷",
    "fra" => "🇩🇪",
    "lhr" => "🇬🇧",
    "mad" => "🇪🇸",
    "waw" => "🇵🇱",
    "arn" => "🇸🇪",
    "otp" => "🇷🇴",
    # Asia Pacific
    "nrt" => "🇯🇵",
    "hnd" => "🇯🇵",
    "sin" => "🇸🇬",
    "hkg" => "🇭🇰",
    "syd" => "🇦🇺",
    "mel" => "🇦🇺",
    "bom" => "🇮🇳",
    "del" => "🇮🇳",
    "icn" => "🇰🇷",
    # Africa & Middle East
    "jnb" => "🇿🇦",
    "dxb" => "🇦🇪"
  }

  @doc """
  Returns a safe display info for a node: flag emoji and short unique ID.
  Does not expose the full node name for security reasons.

  The optional `metrics` parameter can include a `:fly_region` key which will be
  used preferentially over extracting the region from the node name.
  """
  def node_display_info(node_name, metrics \\ nil) do
    node_str = to_string(node_name)

    # Try to get region from:
    # 1. The fly_region from metrics (fetched via RPC for remote nodes)
    # 2. For current node, FLY_REGION env var
    # 3. Extract from node name as fallback
    region =
      cond do
        is_map(metrics) and is_binary(metrics[:fly_region]) ->
          metrics[:fly_region]

        node_name == node() ->
          System.get_env("FLY_REGION") || extract_region(node_str)

        true ->
          extract_region(node_str)
      end

    flag = Map.get(@region_flags, region, "🖥️")

    # Generate a short, unique identifier from node name hash
    # This is deterministic but doesn't reveal the actual node name
    short_id =
      :crypto.hash(:sha256, node_str)
      |> Base.encode16(case: :lower)
      |> String.slice(0, 6)

    # If we found a region, include it in the display
    label =
      if region do
        "#{String.upcase(region)}-#{short_id}"
      else
        short_id
      end

    %{flag: flag, label: label, region: region}
  end

  defp extract_region(node_str) do
    # Lowercase for matching
    node_lower = String.downcase(node_str)

    # Try multiple patterns to extract region code
    cond do
      # Pattern 1: region in app name like "sensocto-iad@..." or "myapp-fra@..."
      match = Regex.run(~r/([a-z]+)-([a-z]{3})@/, node_lower) ->
        case match do
          [_, _app, region] -> if known_region?(region), do: region, else: nil
          _ -> nil
        end

      # Pattern 2: region in internal domain like "...fly-sensocto-iad.internal"
      match = Regex.run(~r/-([a-z]{3})\.internal/, node_lower) ->
        case match do
          [_, region] -> if known_region?(region), do: region, else: nil
          _ -> nil
        end

      # Pattern 3: region as subdomain like "@iad.fly-..." or ".iad.internal"
      match = Regex.run(~r/[@\.]([a-z]{3})\./, node_lower) ->
        case match do
          [_, region] -> if known_region?(region), do: region, else: nil
          _ -> nil
        end

      # Pattern 4: last 3-letter segment before @ that matches a known region
      # This catches patterns like "sensocto-iad@fdaa:0:..."
      true ->
        # Extract everything before @ and split by common delimiters
        before_at = node_lower |> String.split("@") |> List.first() || ""

        before_at
        |> String.split(~r/[-_.]/)
        |> Enum.find(&known_region?/1)
    end
  end

  defp known_region?(region), do: Map.has_key?(@region_flags, region)
end

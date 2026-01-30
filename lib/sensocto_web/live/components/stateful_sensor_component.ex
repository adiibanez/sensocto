defmodule SensoctoWeb.Live.Components.StatefulSensorComponent do
  @moduledoc """
  LiveComponent version of StatefulSensorLive for efficient virtual scrolling.

  Unlike the LiveView version, this component runs in the parent's process,
  eliminating the overhead of separate Erlang processes and PubSub subscriptions
  per sensor. The parent (LobbyLive) handles PubSub and routes data to components
  via send_update/3.

  ## Key differences from StatefulSensorLive:

  1. No PubSub subscriptions - parent handles all subscriptions
  2. No Process.send_after - parent manages flush timing
  3. Data arrives via update/2 with :measurement or :measurements_batch keys
  4. Events that need parent action use callbacks or send to parent

  ## Usage:

      <.live_component
        module={StatefulSensorComponent}
        id={"sensor_\#{sensor_id}"}
        sensor_id={sensor_id}
        sensor={sensor_state}
        view_mode={@global_view_mode}
        user_id={@current_user && @current_user.id}
        is_favorite={sensor_id in @favorite_sensors}
      />
  """

  use SensoctoWeb, :live_component

  alias Sensocto.SimpleSensor
  alias Sensocto.AttentionTracker
  alias SensoctoWeb.Live.Components.AttributeComponent

  # Import render_sensor_header/1 from BaseComponents
  import SensoctoWeb.Live.BaseComponents, only: [render_sensor_header: 1]

  require Logger

  # ============================================================================
  # Function Components (moved from StatefulSensorLive)
  # ============================================================================

  @doc """
  Renders a connection status badge showing sensor state.
  States: :disconnected, :connecting, :connected, :streaming, :error
  """
  attr :status, :atom, required: true
  attr :last_data_at, :any, default: nil
  attr :batch_window, :integer, default: nil
  attr :latency_ms, :integer, default: nil
  attr :error_count, :integer, default: 0

  def connection_status_badge(assigns) do
    now = System.monotonic_time(:millisecond)

    staleness_ms =
      case assigns.last_data_at do
        nil -> nil
        ts -> now - ts
      end

    {icon_name, color_class, label, pulse} =
      case assigns.status do
        :streaming ->
          cond do
            staleness_ms && staleness_ms > 5000 ->
              {"exclamation-triangle", "text-yellow-400", "Stale", false}

            staleness_ms && staleness_ms > 2000 ->
              {"signal", "text-yellow-400", "Slow", false}

            true ->
              {"signal", "text-green-400", "Streaming", true}
          end

        :connected ->
          {"check-circle", "text-green-400", "Connected", false}

        :connecting ->
          {"arrow-path", "text-yellow-400", "Connecting", true}

        :disconnected ->
          {"x-circle", "text-gray-500", "Disconnected", false}

        :error ->
          {"exclamation-circle", "text-red-400", "Error", false}

        _ ->
          {"question-mark-circle", "text-gray-500", "Unknown", false}
      end

    staleness_text =
      case staleness_ms do
        nil -> nil
        ms when ms < 1000 -> "#{ms}ms ago"
        ms when ms < 60_000 -> "#{div(ms, 1000)}s ago"
        ms -> "#{div(ms, 60_000)}m ago"
      end

    assigns =
      assigns
      |> assign(:icon_name, icon_name)
      |> assign(:color_class, color_class)
      |> assign(:label, label)
      |> assign(:pulse, pulse)
      |> assign(:staleness_text, staleness_text)

    latency_color =
      case assigns[:latency_ms] do
        nil -> "text-gray-500"
        ms when ms < 100 -> "text-green-400"
        ms when ms < 300 -> "text-yellow-400"
        ms when ms < 500 -> "text-orange-400"
        _ -> "text-red-400"
      end

    assigns = assign(assigns, :latency_color, latency_color)

    ~H"""
    <div
      class={"flex items-center gap-1 text-xs #{@color_class}"}
      title={"Status: #{@label}" <>
        (if @staleness_text, do: " • Last data: #{@staleness_text}", else: "") <>
        (if @latency_ms, do: " • Latency: #{@latency_ms}ms", else: "") <>
        (if @error_count > 0, do: " • #{@error_count} errors", else: "")}
    >
      <span class={["flex items-center", if(@pulse, do: "animate-pulse", else: "")]}>
        <Heroicons.icon name={@icon_name} type="solid" class="h-3 w-3" />
      </span>
      <span
        :if={@latency_ms}
        class={[@latency_color, "font-mono text-[10px] cursor-pointer"]}
        title="Server roundtrip latency"
      >
        {@latency_ms}ms
      </span>
      <span
        :if={@error_count > 0}
        class="text-red-400 font-mono text-[10px] flex items-center gap-0.5"
      >
        <Heroicons.icon name="exclamation-triangle" type="solid" class="h-2.5 w-2.5" />
        {@error_count}
      </span>
      <span :if={@status == :connecting}>
        <Heroicons.icon name="arrow-path" type="outline" class="h-3 w-3 animate-spin" />
      </span>
    </div>
    """
  end

  @doc """
  Renders an attention level badge with appropriate color and icon.
  """
  attr :level, :atom, required: true

  def attention_badge(assigns) do
    {color_class, icon_name, label} =
      case assigns.level do
        :high -> {"text-green-400", "eye", "High"}
        :medium -> {"text-yellow-400", "eye", "Medium"}
        :low -> {"text-orange-400", "eye-slash", "Low"}
        :none -> {"text-gray-500", "eye-slash", "None"}
        _ -> {"text-gray-500", "eye-slash", "Unknown"}
      end

    assigns =
      assigns
      |> assign(:color_class, color_class)
      |> assign(:icon_name, icon_name)
      |> assign(:label, label)

    ~H"""
    <span
      class={"flex items-center gap-1 text-xs #{@color_class}"}
      title={"Attention: #{@label} - affects data update frequency"}
    >
      <Heroicons.icon name={@icon_name} type="outline" class="h-3 w-3" />
      <span class="hidden sm:inline">{@label}</span>
    </span>
    """
  end

  # ============================================================================
  # Lifecycle Callbacks
  # ============================================================================

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:highlighted, false)
     |> assign(:view_mode, :summary)
     |> assign(:show_map_modal, false)
     |> assign(:show_detail_modal, false)
     |> assign(:pending_measurements, [])
     |> assign(:pressed_buttons, %{})
     |> assign(:connection_status, :connected)
     |> assign(:last_data_at, nil)
     |> assign(:batch_window, 100)
     |> assign(:error_count, 0)
     |> assign(:latency_ms, nil)
     |> assign(:battery_state, :normal)
     |> assign(:is_pinned, false)
     |> assign(:attention_level, :none)
     |> assign(:attributes_loaded, true)}
  end

  @impl true
  def update(assigns, socket) do
    socket = handle_special_updates(assigns, socket)

    # Handle normal assign updates
    socket =
      socket
      |> assign(:sensor_id, assigns[:sensor_id] || socket.assigns[:sensor_id])
      |> assign_sensor_state(assigns)
      |> assign_if_present(assigns, :view_mode)
      |> assign_if_present(assigns, :user_id)
      |> assign_if_present(assigns, :is_favorite)
      |> assign_if_present(assigns, :attention_level)
      |> assign_if_present(assigns, :is_pinned)
      |> assign(:id, assigns[:id])

    {:ok, socket}
  end

  # Handle special update messages (measurements, flush, etc.)
  defp handle_special_updates(assigns, socket) do
    socket
    |> maybe_handle_measurement(assigns)
    |> maybe_handle_measurements_batch(assigns)
    |> maybe_handle_flush(assigns)
    |> maybe_handle_new_state(assigns)
  end

  defp maybe_handle_measurement(%{assigns: socket_assigns} = socket, %{measurement: measurement}) do
    sensor_id = socket_assigns.sensor_id
    attribute_id = measurement.attribute_id

    # Handle button press/release
    socket =
      if measurement[:event] in ["press", "release"] and attribute_id == "button" do
        button_id = measurement.payload
        current_pressed = Map.get(socket_assigns.pressed_buttons, attribute_id, MapSet.new())

        new_pressed =
          case measurement[:event] do
            "press" -> MapSet.put(current_pressed, button_id)
            "release" -> MapSet.delete(current_pressed, button_id)
          end

        pressed_buttons = Map.put(socket_assigns.pressed_buttons, attribute_id, new_pressed)

        send_update(
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{attribute_id}",
          lastvalue: measurement,
          pressed_buttons: new_pressed
        )

        assign(socket, :pressed_buttons, pressed_buttons)
      else
        # Normal measurement - update AttributeComponent
        send_update(
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{attribute_id}",
          lastvalue: measurement
        )

        socket
      end

    # Buffer for throttled push
    pending = [measurement | socket_assigns.pending_measurements]
    now = System.monotonic_time(:millisecond)

    socket
    |> assign(:pending_measurements, pending)
    |> assign(:last_data_at, now)
    |> assign(:connection_status, :streaming)
  end

  defp maybe_handle_measurement(socket, _assigns), do: socket

  defp maybe_handle_measurements_batch(%{assigns: socket_assigns} = socket, %{
         measurements_batch: measurements_list
       })
       when is_list(measurements_list) do
    sensor_id = socket_assigns.sensor_id

    # Get latest measurement per attribute for LiveComponent updates
    latest_measurements =
      measurements_list
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {_attribute_id, measurements} ->
        Enum.max_by(measurements, & &1.timestamp)
      end)

    # Update LiveComponents immediately
    Enum.each(latest_measurements, fn measurement ->
      send_update(
        AttributeComponent,
        id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
        lastvalue: measurement
      )
    end)

    # Buffer all measurements
    pending = measurements_list ++ socket_assigns.pending_measurements
    now = System.monotonic_time(:millisecond)

    socket
    |> assign(:pending_measurements, pending)
    |> assign(:last_data_at, now)
    |> assign(:connection_status, :streaming)
  end

  defp maybe_handle_measurements_batch(socket, _assigns), do: socket

  defp maybe_handle_flush(%{assigns: socket_assigns} = socket, %{flush: true}) do
    case socket_assigns.pending_measurements do
      [] ->
        socket

      measurements ->
        sensor_id = socket_assigns.sensor_id
        sorted_measurements = Enum.sort_by(measurements, & &1.timestamp)

        socket
        |> push_event("measurements_batch", %{
          sensor_id: sensor_id,
          attributes: sorted_measurements
        })
        |> assign(:pending_measurements, [])
    end
  end

  defp maybe_handle_flush(socket, _assigns), do: socket

  defp maybe_handle_new_state(socket, %{new_state: true}) do
    sensor_id = socket.assigns.sensor_id

    try do
      new_sensor_state = SimpleSensor.get_view_state(sensor_id)
      assign(socket, :sensor, new_sensor_state)
    catch
      :exit, _ ->
        Logger.warning("Sensor #{sensor_id} process not found during state update in component")

        socket
    end
  end

  defp maybe_handle_new_state(socket, _assigns), do: socket

  defp assign_sensor_state(socket, %{sensor: sensor}) when is_map(sensor) do
    socket
    |> assign(:sensor, sensor)
    |> assign(:sensor_name, sensor[:sensor_name] || sensor[:sensor_id])
    |> assign(:sensor_type, sensor[:sensor_type] || "unknown")
  end

  defp assign_sensor_state(socket, %{sensor_id: sensor_id}) do
    if socket.assigns[:sensor] do
      socket
    else
      # Fetch sensor state if not provided
      sensor = fetch_sensor_state(sensor_id)

      socket
      |> assign(:sensor, sensor)
      |> assign(:sensor_name, sensor[:sensor_name] || sensor[:sensor_id])
      |> assign(:sensor_type, sensor[:sensor_type] || "unknown")
    end
  end

  defp assign_sensor_state(socket, _assigns), do: socket

  defp assign_if_present(socket, assigns, key) do
    if Map.has_key?(assigns, key) do
      assign(socket, key, Map.get(assigns, key))
    else
      socket
    end
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("toggle_highlight", _params, socket) do
    {:noreply, assign(socket, :highlighted, not socket.assigns.highlighted)}
  end

  @impl true
  def handle_event("toggle_view_mode", _params, socket) do
    new_mode = if socket.assigns.view_mode == :normal, do: :summary, else: :normal
    {:noreply, assign(socket, :view_mode, new_mode)}
  end

  @impl true
  def handle_event("toggle_favorite", _params, socket) do
    user_id = socket.assigns[:user_id]
    sensor_id = socket.assigns.sensor_id

    if user_id do
      # Broadcast to parent (LobbyLive) to handle persistence
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "lobby:favorites",
        {:toggle_favorite, user_id, sensor_id}
      )

      # Optimistically toggle local state
      {:noreply, assign(socket, :is_favorite, !socket.assigns.is_favorite)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("show_map_modal", _params, socket) do
    {:noreply, assign(socket, :show_map_modal, true)}
  end

  @impl true
  def handle_event("close_map_modal", _params, socket) do
    {:noreply, assign(socket, :show_map_modal, false)}
  end

  @impl true
  def handle_event("show_detail_modal", _params, socket) do
    {:noreply, assign(socket, :show_detail_modal, true)}
  end

  @impl true
  def handle_event("close_detail_modal", _params, socket) do
    {:noreply, assign(socket, :show_detail_modal, false)}
  end

  # Latency ping/pong
  @impl true
  def handle_event("latency_ping", %{"ping_id" => ping_id}, socket) do
    next_interval_ms = calculate_adaptive_ping_interval(socket)

    {:noreply,
     push_event(socket, "latency_pong", %{ping_id: ping_id, next_interval_ms: next_interval_ms})}
  end

  @impl true
  def handle_event("latency_report", %{"latency_ms" => latency_ms}, socket) do
    {:noreply, assign(socket, :latency_ms, latency_ms)}
  end

  # Clear attribute data
  @impl true
  def handle_event(
        "clear-attribute",
        %{"sensor_id" => sensor_id, "attribute_id" => attribute_id},
        socket
      ) do
    {:noreply,
     push_event(socket, "clear-attribute", %{
       sensor_id: sensor_id,
       attribute_id: attribute_id,
       data: []
     })}
  end

  # Request seed data
  @impl true
  def handle_event(
        "request-seed-data",
        %{
          "sensor_id" => sensor_id,
          "attribute_id" => attribute_id,
          "from" => from,
          "to" => to,
          "limit" => limit
        },
        socket
      ) do
    start = System.monotonic_time()

    attribute_data =
      try do
        SimpleSensor.get_attribute(sensor_id, attribute_id, from, to, limit)
      catch
        :exit, _ ->
          Logger.warning("Sensor #{sensor_id} process not found during request-seed-data")
          []
      end

    new_socket =
      push_event(socket, "seeddata", %{
        sensor_id: sensor_id,
        attribute_id: attribute_id,
        data: attribute_data
      })

    :telemetry.execute(
      [:sensocto, :live, :handle_event, :request_seed_data],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:noreply, new_socket}
  end

  @impl true
  def handle_event("request-seed-data", params, socket) do
    Logger.warning("Received incomplete request-seed-data event: #{inspect(params)}")
    {:noreply, socket}
  end

  # ============================================================================
  # Attention Tracking Events
  # ============================================================================

  @impl true
  def handle_event("view_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)

    Logger.debug(
      "[StatefulSensorComponent] view_enter: sensor=#{sensor_id}, attr=#{attr_id}, user=#{user_id}"
    )

    AttentionTracker.register_view(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("view_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("focus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.register_focus(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("focus", _params, socket) do
    Logger.debug("Ignoring malformed focus event")
    {:noreply, socket}
  end

  @impl true
  def handle_event("unfocus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_focus(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("unfocus", _params, socket) do
    Logger.debug("Ignoring malformed unfocus event")
    {:noreply, socket}
  end

  @impl true
  def handle_event("hover_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)

    Logger.debug(
      "[StatefulSensorComponent] hover_enter: sensor=#{sensor_id}, attr=#{attr_id}, user=#{user_id}"
    )

    AttentionTracker.register_hover(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("hover_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_hover(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("pin_sensor", %{"sensor_id" => sensor_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.pin_sensor(sensor_id, user_id)

    socket =
      socket
      |> update_attention_level(sensor_id)
      |> push_event("pin_state_changed", %{sensor_id: sensor_id, pinned: true})

    {:noreply, socket}
  end

  @impl true
  def handle_event("unpin_sensor", %{"sensor_id" => sensor_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unpin_sensor(sensor_id, user_id)

    socket =
      socket
      |> update_attention_level(sensor_id)
      |> push_event("pin_state_changed", %{sensor_id: sensor_id, pinned: false})

    {:noreply, socket}
  end

  @impl true
  def handle_event("page_hidden", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.unregister_view(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("page_visible", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    user_id = get_user_id(socket)
    AttentionTracker.register_view(sensor_id, attr_id, user_id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event(
        "battery_state_changed",
        %{"state" => state_str, "level" => level, "charging" => charging} = params,
        socket
      ) do
    user_id = get_user_id(socket)

    battery_state =
      case state_str do
        "critical" -> :critical
        "low" -> :low
        _ -> :normal
      end

    source =
      case Map.get(params, "source") do
        "native_ios" -> :native_ios
        "native_android" -> :native_android
        "external_api" -> :external_api
        _ -> :web_api
      end

    AttentionTracker.report_battery_state(user_id, battery_state,
      source: source,
      level: level,
      charging: charging
    )

    {:noreply, assign(socket, :battery_state, battery_state)}
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp get_user_id(socket) do
    socket.assigns[:user_id] || socket.id || "anonymous"
  end

  # Update attention_level assign by reading from AttentionTracker ETS cache
  defp update_attention_level(socket, sensor_id) do
    level = AttentionTracker.get_sensor_attention_level(sensor_id)
    assign(socket, :attention_level, level)
  end

  defp fetch_sensor_state(sensor_id) do
    case SimpleSensor.get_view_state(sensor_id) do
      state when is_map(state) -> state
      _ -> fallback_sensor_state(sensor_id)
    end
  catch
    :exit, _ ->
      fallback_sensor_state(sensor_id)
  end

  defp fallback_sensor_state(sensor_id) do
    %{sensor_id: sensor_id, sensor_name: sensor_id, sensor_type: "unknown", attributes: %{}}
  end

  @base_ping_interval_ms 3000
  @min_ping_interval_ms 2000
  @max_ping_interval_ms 30000

  defp calculate_adaptive_ping_interval(socket) do
    attention_level = socket.assigns[:attention_level] || :none

    load_multiplier =
      try do
        Sensocto.SystemLoadMonitor.get_load_multiplier()
      catch
        :exit, _ -> 1.0
      end

    attention_multiplier =
      case attention_level do
        :high -> 0.5
        :medium -> 1.0
        :low -> 3.0
        :none -> 5.0
        _ -> 2.0
      end

    sensor_count =
      try do
        :ets.info(:sensor_attention_cache, :size) || 50
      rescue
        _ -> 50
      end

    count_factor =
      if attention_level in [:low, :none] and sensor_count > 50 do
        min(3.0, sensor_count / 50)
      else
        1.0
      end

    interval =
      trunc(@base_ping_interval_ms * attention_multiplier * load_multiplier * count_factor)

    max(@min_ping_interval_ms, min(@max_ping_interval_ms, interval))
  end
end

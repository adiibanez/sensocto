defmodule SensoctoWeb.LobbyLive.SensorDetailLive do
  @moduledoc """
  Full-page detail view for a single sensor, accessed from the lobby.

  This view provides:
  - Full-screen visualizations (ECG, Map, IMU, Skeleton)
  - Tab-based navigation between visualization types
  - Real-time data streaming at full fidelity
  - Back navigation to lobby preserving scroll position

  Routes:
  - /lobby/sensors/:sensor_id - Show sensor detail
  - /lobby/sensors/:sensor_id/:lens - Show specific visualization lens
  """

  use SensoctoWeb, :live_view

  alias Sensocto.SimpleSensor
  alias Sensocto.AttentionTracker
  alias SensoctoWeb.Live.Components.AttributeComponent

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  require Logger

  # Throttle push_events to prevent WebSocket message queue buildup
  @push_throttle_interval 100

  # Available visualization tabs
  @tabs [:overview, :ecg, :map, :imu, :skeleton, :raw]

  @impl true
  def mount(%{"sensor_id" => sensor_id} = params, _session, socket) do
    # Subscribe to PubSub topics for this sensor
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}")
      Process.send_after(self(), :flush_throttled_measurements, @push_throttle_interval)
    end

    # Fetch sensor state
    sensor_state = fetch_sensor_state(sensor_id)

    # Get initial attention level
    initial_attention = AttentionTracker.get_sensor_attention_level(sensor_id)

    # Determine active tab from lens param or default to :overview
    active_tab =
      case params["lens"] do
        nil -> :overview
        lens -> String.to_existing_atom(lens)
      end
      |> then(fn tab -> if tab in @tabs, do: tab, else: :overview end)

    # Extract available lenses from sensor attributes
    available_tabs = compute_available_tabs(sensor_state.attributes)

    {:ok,
     socket
     |> assign(:sensor, sensor_state)
     |> assign(:sensor_id, sensor_id)
     |> assign(:sensor_name, sensor_state.sensor_name)
     |> assign(:sensor_type, sensor_state.sensor_type)
     |> assign(:attention_level, initial_attention)
     |> assign(:active_tab, active_tab)
     |> assign(:available_tabs, available_tabs)
     |> assign(:pending_measurements, [])
     |> assign(:pressed_buttons, %{})
     |> assign(:connection_status, :connected)
     |> assign(:last_data_at, nil)
     |> assign(:latency_ms, nil)
     |> assign(:error_count, 0)
     |> assign(:view_mode, :normal)
     |> assign(:battery_state, :normal)}
  end

  @impl true
  def handle_params(%{"lens" => lens}, _uri, socket) do
    tab =
      try do
        String.to_existing_atom(lens)
      rescue
        _ -> :overview
      end

    tab = if tab in @tabs, do: tab, else: :overview
    {:noreply, assign(socket, :active_tab, tab)}
  end

  def handle_params(_params, _uri, socket) do
    {:noreply, socket}
  end

  # ============================================================================
  # Render
  # ============================================================================

  @impl true
  def render(assigns) do
    ~H"""
    <div class="min-h-screen bg-gray-900 text-white">
      <%!-- Header with back navigation --%>
      <header class="bg-gray-800 border-b border-gray-700 px-4 py-3">
        <div class="flex items-center justify-between max-w-7xl mx-auto">
          <div class="flex items-center gap-4">
            <.link
              navigate={~p"/lobby"}
              class="flex items-center gap-2 text-gray-400 hover:text-white transition-colors"
            >
              <Heroicons.icon name="arrow-left" type="outline" class="h-5 w-5" />
              <span class="hidden sm:inline">Back to Lobby</span>
            </.link>
            <div class="h-6 w-px bg-gray-700" />
            <div>
              <h1 class="text-lg font-semibold">{@sensor_name}</h1>
              <p class="text-sm text-gray-400">{@sensor_type}</p>
            </div>
          </div>
          <div class="flex items-center gap-4">
            <.attention_badge level={@attention_level} />
            <.connection_status_badge
              status={@connection_status}
              last_data_at={@last_data_at}
              latency_ms={@latency_ms}
              error_count={@error_count}
            />
          </div>
        </div>
      </header>

      <%!-- Tab navigation --%>
      <nav class="bg-gray-800/50 border-b border-gray-700">
        <div class="max-w-7xl mx-auto px-4">
          <div class="flex gap-1 overflow-x-auto">
            <.tab_button
              :for={tab <- @available_tabs}
              tab={tab}
              active={@active_tab == tab}
              sensor_id={@sensor_id}
            />
          </div>
        </div>
      </nav>

      <%!-- Main content area --%>
      <main class="max-w-7xl mx-auto p-4">
        <div
          id={"sensor_content_#{@sensor_id}"}
          class="w-full"
          phx-hook="AttentionTracker"
          data-sensor_id={@sensor_id}
        >
          <%= case @active_tab do %>
            <% :overview -> %>
              <.overview_tab
                sensor={@sensor}
                sensor_id={@sensor_id}
                view_mode={@view_mode}
                pressed_buttons={@pressed_buttons}
              />
            <% :ecg -> %>
              <.ecg_tab sensor={@sensor} sensor_id={@sensor_id} />
            <% :map -> %>
              <.map_tab sensor={@sensor} sensor_id={@sensor_id} socket={@socket} />
            <% :imu -> %>
              <.imu_tab sensor={@sensor} sensor_id={@sensor_id} socket={@socket} />
            <% :skeleton -> %>
              <.skeleton_tab sensor={@sensor} sensor_id={@sensor_id} socket={@socket} />
            <% :raw -> %>
              <.raw_tab sensor={@sensor} sensor_id={@sensor_id} />
            <% _ -> %>
              <.overview_tab
                sensor={@sensor}
                sensor_id={@sensor_id}
                view_mode={@view_mode}
                pressed_buttons={@pressed_buttons}
              />
          <% end %>
        </div>
      </main>

      <%!-- Footer status bar --%>
      <footer class="fixed bottom-0 left-0 right-0 bg-gray-800 border-t border-gray-700 px-4 py-2">
        <div class="max-w-7xl mx-auto flex items-center justify-between text-sm">
          <div class="flex items-center gap-4 text-gray-400">
            <span>Sensor ID: <code class="font-mono text-gray-300">{@sensor_id}</code></span>
            <span>Attributes: {map_size(@sensor.attributes)}</span>
          </div>
          <div class="flex items-center gap-4 text-gray-400">
            <span :if={@latency_ms}>
              Latency: <span class="text-green-400">{@latency_ms}ms</span>
            </span>
          </div>
        </div>
      </footer>
    </div>
    """
  end

  # ============================================================================
  # Function Components
  # ============================================================================

  attr :tab, :atom, required: true
  attr :active, :boolean, required: true
  attr :sensor_id, :string, required: true

  defp tab_button(assigns) do
    tab_info = %{
      overview: %{label: "Overview", icon: "squares-2x2"},
      ecg: %{label: "ECG", icon: "heart"},
      map: %{label: "Map", icon: "map"},
      imu: %{label: "IMU", icon: "cube"},
      skeleton: %{label: "Skeleton", icon: "user"},
      raw: %{label: "Raw Data", icon: "code-bracket"}
    }

    info = Map.get(tab_info, assigns.tab, %{label: "Unknown", icon: "question-mark-circle"})
    assigns = assign(assigns, :info, info)

    ~H"""
    <.link
      patch={
        if @tab == :overview,
          do: ~p"/lobby/sensors/#{@sensor_id}",
          else: ~p"/lobby/sensors/#{@sensor_id}/#{@tab}"
      }
      class={[
        "flex items-center gap-2 px-4 py-3 text-sm font-medium border-b-2 transition-colors whitespace-nowrap",
        if(@active,
          do: "border-green-500 text-green-400",
          else: "border-transparent text-gray-400 hover:text-white hover:border-gray-500"
        )
      ]}
    >
      <Heroicons.icon name={@info.icon} type="outline" class="h-4 w-4" />
      {@info.label}
    </.link>
    """
  end

  attr :sensor, :map, required: true
  attr :sensor_id, :string, required: true
  attr :view_mode, :atom, required: true
  attr :pressed_buttons, :map, required: true

  defp overview_tab(assigns) do
    ~H"""
    <div class="grid gap-4 md:grid-cols-2 lg:grid-cols-3">
      <div
        :for={{attribute_id, attribute} <- @sensor.attributes}
        class="bg-gray-800 rounded-lg p-4 border border-gray-700"
      >
        <.live_component
          id={"attribute_#{@sensor_id}_#{attribute_id}"}
          module={AttributeComponent}
          attribute={attribute}
          sensor_id={@sensor_id}
          attribute_type={attribute.attribute_type}
          view_mode={@view_mode}
          pressed_buttons={Map.get(@pressed_buttons, attribute_id, MapSet.new())}
        />
      </div>
      <div :if={@sensor.attributes == %{}} class="col-span-full text-center py-12">
        <Heroicons.icon name="chart-bar" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
        <p class="mt-2 text-sm text-gray-400">No attributes available</p>
      </div>
    </div>
    """
  end

  attr :sensor, :map, required: true
  attr :sensor_id, :string, required: true

  defp ecg_tab(assigns) do
    ecg_attribute = Map.get(assigns.sensor.attributes, "ecg")
    assigns = assign(assigns, :ecg_attribute, ecg_attribute)

    ~H"""
    <div class="h-[500px]">
      <%= if @ecg_attribute do %>
        <div
          id={"ecg-accumulator-#{@sensor_id}"}
          phx-hook="SensorDataAccumulator"
          data-sensor_id={@sensor_id}
          data-attribute_id="ecg"
          class="h-full"
        >
          <.svelte
            name="SingleECG"
            props={
              %{
                sensor_id: @sensor_id,
                attribute_id: "ecg",
                color: "#00ff00",
                title: "ECG Waveform",
                showHeader: true,
                minHeight: "480px"
              }
            }
          />
        </div>
      <% else %>
        <div class="bg-gray-800 rounded-lg p-4 border border-gray-700 text-center py-12">
          <Heroicons.icon name="heart" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
          <p class="mt-2 text-sm text-gray-400">No ECG data available for this sensor</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :sensor, :map, required: true
  attr :sensor_id, :string, required: true
  attr :socket, :any, required: true

  defp map_tab(assigns) do
    geo_attribute = Map.get(assigns.sensor.attributes, "geolocation")
    assigns = assign(assigns, :geo_attribute, geo_attribute)

    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <%= if @geo_attribute && @geo_attribute[:lastvalue] && @geo_attribute.lastvalue[:payload] do %>
        <h2 class="text-lg font-semibold mb-4">Location</h2>
        <div class="h-96 rounded-lg overflow-hidden">
          <.svelte
            name="Map"
            props={
              %{
                identifier: "detail_map_#{@sensor_id}",
                position: %{
                  lat: @geo_attribute.lastvalue.payload[:latitude],
                  lng: @geo_attribute.lastvalue.payload[:longitude],
                  accuracy: @geo_attribute.lastvalue.payload[:accuracy]
                }
              }
            }
            socket={@socket}
            class="w-full h-full"
          />
        </div>
        <div class="mt-4 text-sm text-gray-400 grid grid-cols-3 gap-4">
          <div>
            <span class="block text-gray-500">Latitude</span>
            <span class="text-white font-mono">{@geo_attribute.lastvalue.payload[:latitude]}</span>
          </div>
          <div>
            <span class="block text-gray-500">Longitude</span>
            <span class="text-white font-mono">{@geo_attribute.lastvalue.payload[:longitude]}</span>
          </div>
          <div>
            <span class="block text-gray-500">Accuracy</span>
            <span class="text-white font-mono">{@geo_attribute.lastvalue.payload[:accuracy]}m</span>
          </div>
        </div>
      <% else %>
        <div class="text-center py-12">
          <Heroicons.icon name="map" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
          <p class="mt-2 text-sm text-gray-400">No location data available for this sensor</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :sensor, :map, required: true
  attr :sensor_id, :string, required: true
  attr :socket, :any, required: true

  defp imu_tab(assigns) do
    imu_attribute = Map.get(assigns.sensor.attributes, "imu")
    assigns = assign(assigns, :imu_attribute, imu_attribute)

    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <%= if @imu_attribute do %>
        <h2 class="text-lg font-semibold mb-4">IMU Visualization</h2>
        <div class="h-96">
          <.svelte
            name="ImuVisualization"
            props={
              %{
                identifier: "detail_imu_#{@sensor_id}",
                sensorId: @sensor_id,
                attributeId: "imu"
              }
            }
            socket={@socket}
            class="w-full h-full"
          />
        </div>
      <% else %>
        <div class="text-center py-12">
          <Heroicons.icon name="cube" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
          <p class="mt-2 text-sm text-gray-400">No IMU data available for this sensor</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :sensor, :map, required: true
  attr :sensor_id, :string, required: true
  attr :socket, :any, required: true

  defp skeleton_tab(assigns) do
    skeleton_attribute = Map.get(assigns.sensor.attributes, "skeleton")
    assigns = assign(assigns, :skeleton_attribute, skeleton_attribute)

    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <%= if @skeleton_attribute do %>
        <h2 class="text-lg font-semibold mb-4">Skeleton / Pose</h2>
        <div class="h-96">
          <.svelte
            name="SkeletonVisualization"
            props={
              %{
                sensor_id: @sensor_id,
                attribute_id: "skeleton",
                size: "normal"
              }
            }
            socket={@socket}
            class="w-full h-full"
          />
        </div>
      <% else %>
        <div class="text-center py-12">
          <Heroicons.icon name="user" type="outline" class="mx-auto h-12 w-12 text-gray-500" />
          <p class="mt-2 text-sm text-gray-400">No skeleton/pose data available for this sensor</p>
        </div>
      <% end %>
    </div>
    """
  end

  attr :sensor, :map, required: true
  attr :sensor_id, :string, required: true

  defp raw_tab(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-4 border border-gray-700">
      <h2 class="text-lg font-semibold mb-4">Raw Data</h2>
      <div class="space-y-4">
        <div
          :for={{attribute_id, attribute} <- @sensor.attributes}
          class="border-b border-gray-700 pb-4 last:border-0"
        >
          <h3 class="font-medium text-green-400 mb-2">{attribute_id}</h3>
          <div class="text-sm text-gray-400 space-y-1">
            <div>Type: <span class="text-white">{attribute[:attribute_type] || "unknown"}</span></div>
            <div>
              Sampling Rate: <span class="text-white">{attribute[:sampling_rate] || "N/A"} Hz</span>
            </div>
            <div :if={attribute[:lastvalue]}>
              <span class="block text-gray-500">Latest Value:</span>
              <pre class="text-xs text-white bg-gray-900 p-2 rounded mt-1 overflow-x-auto">{Jason.encode!(attribute.lastvalue, pretty: true)}</pre>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  # Attention badge component
  attr :level, :atom, required: true

  defp attention_badge(assigns) do
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
      <Heroicons.icon name={@icon_name} type="outline" class="h-4 w-4" />
      <span>{@label}</span>
    </span>
    """
  end

  # Connection status badge component
  attr :status, :atom, required: true
  attr :last_data_at, :any, default: nil
  attr :latency_ms, :integer, default: nil
  attr :error_count, :integer, default: 0

  defp connection_status_badge(assigns) do
    {icon_name, color_class, label} =
      case assigns.status do
        :streaming -> {"signal", "text-green-400", "Streaming"}
        :connected -> {"check-circle", "text-green-400", "Connected"}
        :connecting -> {"arrow-path", "text-yellow-400", "Connecting"}
        :disconnected -> {"x-circle", "text-gray-500", "Disconnected"}
        :error -> {"exclamation-circle", "text-red-400", "Error"}
        _ -> {"question-mark-circle", "text-gray-500", "Unknown"}
      end

    assigns =
      assigns
      |> assign(:icon_name, icon_name)
      |> assign(:color_class, color_class)
      |> assign(:label, label)

    ~H"""
    <span class={"flex items-center gap-1 text-xs #{@color_class}"}>
      <Heroicons.icon name={@icon_name} type="solid" class="h-4 w-4" />
      <span>{@label}</span>
    </span>
    """
  end

  # ============================================================================
  # PubSub Handlers
  # ============================================================================

  @impl true
  def handle_info({:measurement, measurement}, socket) do
    sensor_id = socket.assigns.sensor_id
    attribute_id = measurement.attribute_id
    event = Map.get(measurement, :event)

    # Handle button press/release events to track pressed state
    socket =
      if event in ["press", "release"] and attribute_id == "button" do
        button_id = measurement.payload
        current_pressed = Map.get(socket.assigns.pressed_buttons, attribute_id, MapSet.new())

        new_pressed =
          case event do
            "press" -> MapSet.put(current_pressed, button_id)
            "release" -> MapSet.delete(current_pressed, button_id)
          end

        updated_pressed_buttons =
          Map.put(socket.assigns.pressed_buttons, attribute_id, new_pressed)

        # Update the LiveComponent with pressed_buttons
        send_update(
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{attribute_id}",
          lastvalue: measurement,
          pressed_buttons: new_pressed
        )

        assign(socket, :pressed_buttons, updated_pressed_buttons)
      else
        # Update the LiveComponent without pressed_buttons
        send_update(
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{attribute_id}",
          lastvalue: measurement
        )

        socket
      end

    # Buffer measurement for throttled push
    pending = [measurement | socket.assigns.pending_measurements]
    now = System.monotonic_time(:millisecond)

    {:noreply,
     socket
     |> assign(:pending_measurements, pending)
     |> assign(:last_data_at, now)
     |> assign(:connection_status, :streaming)}
  end

  @impl true
  def handle_info({:measurements_batch, {_sensor_id, measurements_list}}, socket)
      when is_list(measurements_list) do
    sensor_id = socket.assigns.sensor_id

    # Process button events to update pressed_buttons state
    socket =
      measurements_list
      |> Enum.filter(fn m ->
        Map.get(m, :event) in ["press", "release"] and m.attribute_id == "button"
      end)
      |> Enum.sort_by(& &1.timestamp)
      |> Enum.reduce(socket, fn measurement, acc_socket ->
        button_id = measurement.payload
        event = Map.get(measurement, :event)
        current_pressed = Map.get(acc_socket.assigns.pressed_buttons, "button", MapSet.new())

        new_pressed =
          case event do
            "press" -> MapSet.put(current_pressed, button_id)
            "release" -> MapSet.delete(current_pressed, button_id)
          end

        updated_pressed_buttons =
          Map.put(acc_socket.assigns.pressed_buttons, "button", new_pressed)

        assign(acc_socket, :pressed_buttons, updated_pressed_buttons)
      end)

    # Update LiveComponents with latest per attribute
    latest_measurements =
      measurements_list
      |> Enum.group_by(& &1.attribute_id)
      |> Enum.map(fn {_attr_id, measurements} ->
        Enum.max_by(measurements, & &1.timestamp)
      end)

    Enum.each(latest_measurements, fn measurement ->
      if measurement.attribute_id == "button" do
        pressed = Map.get(socket.assigns.pressed_buttons, "button", MapSet.new())

        send_update(
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
          lastvalue: measurement,
          pressed_buttons: pressed
        )
      else
        send_update(
          AttributeComponent,
          id: "attribute_#{sensor_id}_#{measurement.attribute_id}",
          lastvalue: measurement
        )
      end
    end)

    pending = measurements_list ++ socket.assigns.pending_measurements
    now = System.monotonic_time(:millisecond)

    {:noreply,
     socket
     |> assign(:pending_measurements, pending)
     |> assign(:last_data_at, now)
     |> assign(:connection_status, :streaming)}
  end

  @impl true
  def handle_info({:new_state, _sensor_id}, socket) do
    try do
      new_sensor_state = SimpleSensor.get_view_state(socket.assigns.sensor_id)
      {:noreply, assign(socket, :sensor, new_sensor_state)}
    catch
      :exit, _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:attention_changed, %{sensor_id: sensor_id, level: new_level}}, socket)
      when sensor_id == socket.assigns.sensor_id do
    {:noreply, assign(socket, :attention_level, new_level)}
  end

  def handle_info({:attention_changed, _}, socket), do: {:noreply, socket}

  # Handle events delegated from child components (e.g., AttributeComponent)
  @impl true
  def handle_info({:component_event, event_name, params}, socket) do
    # Re-dispatch the event as if it came directly to the LiveView
    handle_event(event_name, params, socket)
  end

  @impl true
  def handle_info(:flush_throttled_measurements, socket) do
    Process.send_after(self(), :flush_throttled_measurements, @push_throttle_interval)

    case socket.assigns.pending_measurements do
      [] ->
        {:noreply, socket}

      measurements ->
        sensor_id = socket.assigns.sensor_id
        sorted_measurements = Enum.sort_by(measurements, & &1.timestamp)

        socket =
          socket
          |> push_event("measurements_batch", %{
            sensor_id: sensor_id,
            attributes: sorted_measurements
          })
          |> assign(:pending_measurements, [])

        {:noreply, socket}
    end
  end

  # ============================================================================
  # Event Handlers
  # ============================================================================

  @impl true
  def handle_event("latency_ping", %{"ping_id" => ping_id}, socket) do
    {:noreply, push_event(socket, "latency_pong", %{ping_id: ping_id, next_interval_ms: 3000})}
  end

  @impl true
  def handle_event("latency_report", %{"latency_ms" => latency_ms}, socket) do
    {:noreply, assign(socket, :latency_ms, latency_ms)}
  end

  @impl true
  def handle_event("view_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.register_view(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("view_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.unregister_view(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("hover_enter", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.register_hover(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("hover_leave", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.unregister_hover(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("focus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.register_focus(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("unfocus", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.unregister_focus(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  # Page visibility events (triggered when tab/window is hidden/shown)
  @impl true
  def handle_event("page_hidden", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.unregister_view(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  @impl true
  def handle_event("page_visible", %{"sensor_id" => sensor_id, "attribute_id" => attr_id}, socket) do
    AttentionTracker.register_view(sensor_id, attr_id, socket.id)
    {:noreply, update_attention_level(socket, sensor_id)}
  end

  # Catch-all for page visibility events without params
  @impl true
  def handle_event("page_hidden", _params, socket), do: {:noreply, socket}
  @impl true
  def handle_event("page_visible", _params, socket), do: {:noreply, socket}

  # Sensor pinning for guaranteed high-frequency updates
  @impl true
  def handle_event("pin_sensor", %{"sensor_id" => sensor_id}, socket) do
    AttentionTracker.pin_sensor(sensor_id, socket.id)
    {:noreply, push_event(socket, "pin_state_changed", %{sensor_id: sensor_id, pinned: true})}
  end

  @impl true
  def handle_event("unpin_sensor", %{"sensor_id" => sensor_id}, socket) do
    AttentionTracker.unpin_sensor(sensor_id, socket.id)
    {:noreply, push_event(socket, "pin_state_changed", %{sensor_id: sensor_id, pinned: false})}
  end

  # Battery state tracking for energy-aware throttling
  @impl true
  def handle_event(
        "battery_state_changed",
        %{"state" => state_str, "level" => level, "charging" => charging} = params,
        socket
      ) do
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

    Logger.debug(
      "Battery state changed for #{socket.id}: #{battery_state} (level: #{level}%, charging: #{charging}, source: #{source})"
    )

    AttentionTracker.report_battery_state(socket.id, battery_state,
      source: source,
      level: level,
      charging: charging
    )

    {:noreply, assign(socket, :battery_state, battery_state)}
  end

  # Catch-all for malformed events
  @impl true
  def handle_event("focus", _params, socket), do: {:noreply, socket}
  @impl true
  def handle_event("unfocus", _params, socket), do: {:noreply, socket}

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
    attribute_data =
      try do
        SimpleSensor.get_attribute(sensor_id, attribute_id, from, to, limit)
      catch
        :exit, _ -> []
      end

    {:noreply,
     push_event(socket, "seeddata", %{
       sensor_id: sensor_id,
       attribute_id: attribute_id,
       data: attribute_data
     })}
  end

  @impl true
  def handle_event("request-seed-data", _params, socket), do: {:noreply, socket}

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

  # ============================================================================
  # Helper Functions
  # ============================================================================

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

  defp update_attention_level(socket, sensor_id) do
    level = AttentionTracker.get_sensor_attention_level(sensor_id)
    assign(socket, :attention_level, level)
  end

  defp compute_available_tabs(attributes) do
    base_tabs = [:overview]

    specialized_tabs =
      Enum.reduce(attributes, [], fn {_attr_id, attr}, acc ->
        case attr[:attribute_type] do
          "ecg" -> [:ecg | acc]
          "geolocation" -> [:map | acc]
          "imu" -> [:imu | acc]
          "skeleton" -> [:skeleton | acc]
          _ -> acc
        end
      end)
      |> Enum.uniq()

    base_tabs ++ specialized_tabs ++ [:raw]
  end
end

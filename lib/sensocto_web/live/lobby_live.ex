defmodule SensoctoWeb.LobbyLive do
  @moduledoc """
  Full-page view of all sensors in the lobby.
  Shows all sensors from the SensorsDynamicSupervisor with real-time updates.
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  use Sensocto.Chat.AIChatHandler
  alias SensoctoWeb.StatefulSensorLive
  # Used in template when @use_sensor_components is true
  alias SensoctoWeb.Live.Components.StatefulSensorComponent, warn: false
  alias SensoctoWeb.Live.Components.MediaPlayerComponent
  alias SensoctoWeb.Live.Components.Object3DPlayerComponent
  alias SensoctoWeb.Live.Components.WhiteboardComponent
  alias SensoctoWeb.Sensocto.Presence
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Calls
  alias Sensocto.Accounts.UserPreferences

  # Require authentication for this LiveView
  on_mount {SensoctoWeb.LiveUserAuth, :ensure_authenticated}

  # Feature flag: use LiveComponent instead of live_render for sensor tiles
  # This reduces process overhead during virtual scrolling
  @use_sensor_components true

  # Component flush interval - how often to flush measurement buffers to JS
  @component_flush_interval_ms 100

  @grid_cols_sm_default 2
  @grid_cols_lg_default 3
  @grid_cols_xl_default 4
  @grid_cols_2xl_default 5

  # Virtual scroll configuration
  @default_row_height 140
  # Preload more sensors initially for smoother experience
  @default_visible_count 72

  # Threshold for switching to summary mode (<=3 sensors = normal, >3 = summary)
  # Kept for future use when dynamic view mode switching is implemented
  @summary_mode_threshold 3
  _ = @summary_mode_threshold

  # Performance monitoring: batch flush interval in ms
  # Measurements are buffered and flushed at this interval to reduce push_event calls
  @measurement_flush_interval_ms 50

  # Performance telemetry: log interval in ms
  @perf_log_interval_ms 5_000

  # Phase sync buffer sizes (Kuramoto order parameter)
  @breathing_phase_buffer_size 50
  @hrv_phase_buffer_size 20

  # Suppress unused warnings - these are used in handle_info callbacks
  _ = @measurement_flush_interval_ms
  _ = @perf_log_interval_ms
  _ = @use_sensor_components
  _ = @component_flush_interval_ms
  _ = @breathing_phase_buffer_size
  _ = @hrv_phase_buffer_size

  @impl true
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:lobby")
    # Subscribe to lobby call events
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "call:lobby")
    # Subscribe to 3D object player events
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:lobby")
    # Subscribe to whiteboard events
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "whiteboard:lobby")
    # Subscribe to global attention changes to re-filter sensor list in realtime
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:lobby")
    # Subscribe to favorite toggle events from child sensor LiveViews
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "lobby:favorites")
    # Subscribe to chat messages for the lobby
    Sensocto.Chat.ChatStore.subscribe("lobby")

    # Subscribe to user-specific attention level updates for webcam backpressure
    user = socket.assigns[:current_user]

    if user do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "call:lobby:user:#{user.id}")
    end

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)
    # Extract stable list of sensor IDs - only changes when sensors are added/removed
    sensor_ids = sensors |> Map.keys() |> Enum.sort()

    # NOTE: Direct sensor subscriptions removed - now using PriorityLens for data delivery
    # Signal subscriptions kept for attribute change notifications
    Enum.each(sensor_ids, fn sensor_id ->
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
    end)

    # Calculate max attributes across all sensors for view mode decision
    max_attributes = calculate_max_attributes(sensors)

    # Determine view mode: normal for <=3 sensors with few attributes, summary otherwise
    default_view_mode = determine_view_mode(sensors_count, max_attributes)

    # Extract composite visualization data
    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors} =
      extract_composite_data(sensors)

    # Compute available lenses based on actual sensor attributes
    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors,
        respiration_sensors,
        hrv_sensors
      )

    # Group sensors by connector (user)
    sensors_by_user = group_sensors_by_user(sensors)

    # Get available rooms for join UI
    user = socket.assigns[:current_user]
    public_rooms = if user, do: Sensocto.Rooms.list_public_rooms(), else: []

    # Load user's favorite sensors
    favorite_sensors =
      if user do
        UserPreferences.get_ui_state(user.id, "favorite_sensors", [])
      else
        []
      end

    # Check if there's an active call in the lobby
    call_active = Calls.call_exists?(:lobby)

    new_socket =
      socket
      |> assign(
        # Store socket.id for multi-tab sync identification
        socket_id: socket.id,
        page_title: "Lobby",
        # Chat context for layout-level chat components
        chat_room_id: "lobby",
        current_path: "/lobby",
        # Store full sensors map for LiveComponent rendering
        sensors: sensors,
        sensors_online_count: sensors_count,
        sensors_online: %{},
        sensors_offline: %{},
        sensor_ids: sensor_ids,
        all_sensor_ids: sensor_ids,
        global_view_mode: default_view_mode,
        grid_cols_sm: min(@grid_cols_sm_default, max(1, sensors_count)),
        grid_cols_lg: min(@grid_cols_lg_default, max(1, sensors_count)),
        grid_cols_xl: min(@grid_cols_xl_default, max(1, sensors_count)),
        grid_cols_2xl: min(@grid_cols_2xl_default, max(1, sensors_count)),
        heartrate_sensors: heartrate_sensors,
        imu_sensors: imu_sensors,
        location_sensors: location_sensors,
        ecg_sensors: ecg_sensors,
        battery_sensors: battery_sensors,
        skeleton_sensors: skeleton_sensors,
        respiration_sensors: respiration_sensors,
        hrv_sensors: hrv_sensors,
        available_lenses: available_lenses,
        sensors_by_user: sensors_by_user,
        favorite_sensors: favorite_sensors,
        public_rooms: public_rooms,
        show_join_modal: false,
        join_code: "",
        # Call-related assigns
        lobby_mode: :media,
        call_active: call_active,
        in_call: false,
        call_participants: %{},
        call_speaking: false,
        audio_enabled: true,
        video_enabled: true,
        call_expanded: false,
        # Bump animation assigns for mode buttons
        media_bump: false,
        object3d_bump: false,
        whiteboard_bump: false,
        # Lobby mode presence counts
        media_viewers: 0,
        object3d_viewers: 0,
        whiteboard_viewers: 0,
        # Control request modal state
        control_request_modal: nil,
        media_control_request_modal: nil,
        # Timer refs for auto-transfer on timeout
        media_control_request_timer: nil,
        # Controller user IDs for request modals
        media_controller_user_id: nil,
        # Sync mode: :synced (default) or :solo (watch independently)
        sync_mode: :synced,
        # Users grouped by sync mode for visual indicator
        synced_users: [],
        solo_users: [],
        # Performance monitoring: measurement buffer for batching push_events
        measurement_buffer: %{},
        measurement_flush_timer: nil,
        # Performance stats for telemetry
        perf_stats: %{
          handle_info_count: 0,
          handle_info_total_us: 0,
          handle_info_max_us: 0,
          push_event_count: 0,
          last_report_time: System.monotonic_time(:millisecond)
        },
        # Minimum attention filter (0=none, 1=low, 2=medium, 3=high)
        min_attention: 0,
        # Timer for debouncing attention filter updates
        attention_filter_timer: nil,
        # Client health monitoring for adaptive streaming
        client_health: SensoctoWeb.ClientHealth.init(),
        # PriorityLens integration for adaptive data delivery
        priority_lens_registered: false,
        priority_lens_topic: nil,
        # Data mode: :realtime (batch) or :digest (low quality summary)
        data_mode: :realtime,
        # Current quality level for UI display
        current_quality: :high,
        # Manual quality override (nil = automatic, or :high/:medium/:low/:minimal)
        quality_override: nil,
        # Track consecutive healthy checks for upgrade hysteresis
        consecutive_healthy_checks: 0,
        # Virtual scroll state
        visible_range: {0, min(@default_visible_count, sensors_count)},
        row_height: @default_row_height,
        cols: 4,
        # Show loading indicator during initial sensor population
        virtual_scroll_loading: true,
        # Phase sync (Kuramoto) server-side state for persistence
        sync_phase_buffers: %{},
        sync_smoothed: %{}
      )

    # Track and subscribe to room mode presence (lobby is treated as room_id "lobby")
    # Generate a unique presence key for this connection (allows multiple tabs per user)
    presence_key = "#{user && user.id}:#{System.unique_integer([:positive])}"

    new_socket =
      if connected?(new_socket) and user do
        # Subscribe to room mode presence updates
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "room:lobby:mode_presence")

        # Track this connection's presence with their current room mode
        # Using a unique key per connection to count each tab separately
        user_name = Map.get(user, :email) || Map.get(user, :display_name) || "Anonymous"

        Presence.track(self(), "room:lobby:mode_presence", presence_key, %{
          room_mode: :media,
          user_id: user.id,
          user_name: user_name,
          sync_mode: :synced
        })

        # Get initial presence counts
        {media_count, object3d_count, whiteboard_count} = count_room_mode_presence("lobby")
        {synced_users, solo_users} = get_sync_mode_users("lobby")

        # Schedule refreshes to catch late-registered attributes
        # Attributes are auto-registered on first data receipt, which may happen after mount
        Process.send_after(self(), :refresh_available_lenses, 1000)
        Process.send_after(self(), :refresh_available_lenses, 3000)

        # Start performance logging timer
        Process.send_after(self(), :log_perf_stats, @perf_log_interval_ms)

        # Start component flush timer (for LiveComponent measurement buffers)
        Process.send_after(self(), :flush_component_measurements, @component_flush_interval_ms)

        # Register with PriorityLens for adaptive data streaming
        # This enables client health-based quality adaptation
        {priority_lens_registered, priority_lens_topic} =
          case Sensocto.Lenses.PriorityLens.register_socket(
                 new_socket.id,
                 sensor_ids,
                 quality: :high
               ) do
            {:ok, topic} ->
              Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)
              {true, topic}

            {:error, reason} ->
              Logger.warning("Failed to register with PriorityLens: #{inspect(reason)}")
              {false, nil}
          end

        new_socket
        |> assign(:presence_key, presence_key)
        |> assign(:media_viewers, media_count)
        |> assign(:object3d_viewers, object3d_count)
        |> assign(:whiteboard_viewers, whiteboard_count)
        |> assign(:synced_users, synced_users)
        |> assign(:solo_users, solo_users)
        |> assign(:priority_lens_registered, priority_lens_registered)
        |> assign(:priority_lens_topic, priority_lens_topic)
      else
        assign(new_socket, :presence_key, presence_key)
      end

    :telemetry.execute(
      [:sensocto, :live, :lobby, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    {:ok, new_socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    # Update PriorityLens focused sensor based on current view
    # ECG needs full data fidelity for waveform visualization
    socket = update_lens_focus_for_action(socket, socket.assigns.live_action)

    # Push historical data so composite charts are pre-populated on navigation
    socket = seed_composite_historical_data(socket, socket.assigns.live_action)

    {:noreply, socket}
  end

  # Set focused sensor for PriorityLens based on current live_action
  # Focused sensors get priority even at lower quality levels
  # Also registers attention for composite lens sensors so data flows via data:global
  defp update_lens_focus_for_action(socket, live_action) do
    if socket.assigns[:priority_lens_registered] do
      case live_action do
        :ecg ->
          # ECG needs all data points - focus on first ECG sensor for priority
          case socket.assigns.ecg_sensors do
            [%{sensor_id: first} | _] ->
              Sensocto.Lenses.PriorityLens.set_focused_sensor(socket.id, first)

            _ ->
              :ok
          end

        _ ->
          # Clear focus for other views
          Sensocto.Lenses.PriorityLens.set_focused_sensor(socket.id, nil)
      end
    end

    # Register attention for sensors in composite views so data flows to data:global
    # Without this, freshly started sensors with attention_level :none won't broadcast
    ensure_attention_for_composite_sensors(socket, live_action)

    socket
  end

  # Composite lens views need sensors to broadcast to data:global.
  # Registers a lightweight "view" for all relevant sensors.
  defp ensure_attention_for_composite_sensors(socket, action)
       when action in [:heartrate, :ecg, :imu, :location, :battery, :skeleton, :respiration, :hrv] do
    viewer_id = socket.id

    sensor_ids =
      case action do
        :heartrate -> Enum.map(socket.assigns.heartrate_sensors, & &1.sensor_id)
        :ecg -> Enum.map(socket.assigns.ecg_sensors, & &1.sensor_id)
        :imu -> Enum.map(socket.assigns.imu_sensors, & &1.sensor_id)
        :location -> Enum.map(socket.assigns.location_sensors, & &1.sensor_id)
        :battery -> Enum.map(socket.assigns.battery_sensors, & &1.sensor_id)
        :skeleton -> Enum.map(socket.assigns.skeleton_sensors, & &1.sensor_id)
        :respiration -> Enum.map(socket.assigns.respiration_sensors, & &1.sensor_id)
        :hrv -> Enum.map(socket.assigns.hrv_sensors, & &1.sensor_id)
      end

    attr_key = "composite_#{action}"

    Enum.each(sensor_ids, fn sensor_id ->
      Sensocto.AttentionTracker.register_view(sensor_id, attr_key, viewer_id)
    end)
  end

  defp ensure_attention_for_composite_sensors(_socket, _action), do: :ok

  # Push historical data from AttributeStoreTiered when entering a composite lens view
  # so the chart is pre-populated instead of starting from zero
  defp seed_composite_historical_data(socket, action)
       when action in [:heartrate, :ecg, :respiration, :battery, :hrv] do
    {sensor_ids, attr_ids} =
      case action do
        :heartrate ->
          {Enum.map(socket.assigns.heartrate_sensors, & &1.sensor_id), ["heartrate", "hr"]}

        :ecg ->
          {Enum.map(socket.assigns.ecg_sensors, & &1.sensor_id), ["ecg"]}

        :respiration ->
          {Enum.map(socket.assigns.respiration_sensors, & &1.sensor_id), ["respiration"]}

        :battery ->
          {Enum.map(socket.assigns.battery_sensors, & &1.sensor_id), ["battery"]}

        :hrv ->
          {Enum.map(socket.assigns.hrv_sensors, & &1.sensor_id), ["hrv"]}
      end

    socket =
      Enum.reduce(sensor_ids, socket, fn sensor_id, acc ->
        Enum.reduce(attr_ids, acc, fn attr_id, inner_acc ->
          case Sensocto.AttributeStoreTiered.get_attribute(sensor_id, attr_id, 0, :infinity, 500) do
            {:ok, data} when data != [] ->
              push_event(inner_acc, "composite_seed_data", %{
                sensor_id: sensor_id,
                attribute_id: attr_id,
                data: Enum.map(data, &%{payload: &1.payload, timestamp: &1.timestamp})
              })

            _ ->
              inner_acc
          end
        end)
      end)

    # Also seed sync history for breathing/HRV composite views
    sync_attr_id =
      case action do
        :respiration -> "breathing_sync"
        :hrv -> "hrv_sync"
        _ -> nil
      end

    if sync_attr_id do
      case Sensocto.AttributeStoreTiered.get_attribute(
             "__composite_sync",
             sync_attr_id,
             0,
             :infinity,
             500
           ) do
        {:ok, data} when data != [] ->
          push_event(socket, "composite_seed_data", %{
            sensor_id: "__composite_sync",
            attribute_id: sync_attr_id,
            data: Enum.map(data, &%{payload: &1.payload, timestamp: &1.timestamp})
          })

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp seed_composite_historical_data(socket, _action), do: socket

  defp calculate_max_attributes(sensors) do
    sensors
    |> Enum.map(fn {_id, sensor} -> map_size(sensor.attributes || %{}) end)
    |> Enum.max(fn -> 0 end)
  end

  # Filter sensor IDs by minimum attention level
  # Returns only sensors that meet or exceed the minimum attention threshold
  defp filter_sensors_by_attention(sensor_ids, min_attention) when min_attention == 0 do
    # No filter - return all sensors
    sensor_ids
  end

  defp filter_sensors_by_attention(sensor_ids, min_attention) do
    Enum.filter(sensor_ids, fn sensor_id ->
      level = Sensocto.AttentionTracker.get_sensor_attention_level(sensor_id)
      attention_level_to_int(level) >= min_attention
    end)
  end

  # Convert attention level atom to integer for comparison
  defp attention_level_to_int(:none), do: 0
  defp attention_level_to_int(:low), do: 1
  defp attention_level_to_int(:medium), do: 2
  defp attention_level_to_int(:high), do: 3
  defp attention_level_to_int(_), do: 0

  # Partition sensors for virtual scroll rendering
  # Returns {rows_before, visible_ids, rows_after, sensors_remaining} for CSS spacer heights
  defp partition_sensors_for_virtual_scroll(sensor_ids, {start_idx, end_idx}, cols) do
    total = length(sensor_ids)
    cols = max(1, cols)

    # Clamp indices
    start_idx = max(0, min(start_idx, total))
    end_idx = max(start_idx, min(end_idx, total))

    visible_ids = Enum.slice(sensor_ids, start_idx, end_idx - start_idx)

    # Calculate spacer heights (in rows) - use ceiling to account for partial rows
    rows_before = div(start_idx, cols)
    sensors_remaining = max(0, total - end_idx)
    # Use ceiling for rows_after to ensure spacer covers partial rows
    rows_after = if sensors_remaining > 0, do: div(sensors_remaining + cols - 1, cols), else: 0

    {rows_before, visible_ids, rows_after, sensors_remaining}
  end

  defp count_room_mode_presence(room_id) do
    presences = Presence.list("room:#{room_id}:mode_presence")

    Enum.reduce(presences, {0, 0, 0}, fn {_user_id, %{metas: metas}},
                                         {media, object3d, whiteboard} ->
      # Get the most recent presence meta (last one)
      case List.last(metas) do
        %{room_mode: :media} -> {media + 1, object3d, whiteboard}
        %{room_mode: :object3d} -> {media, object3d + 1, whiteboard}
        %{room_mode: :whiteboard} -> {media, object3d, whiteboard + 1}
        _ -> {media, object3d, whiteboard}
      end
    end)
  end

  defp get_sync_mode_users(room_id) do
    presences = Presence.list("room:#{room_id}:mode_presence")

    Enum.reduce(presences, {[], []}, fn {_key, %{metas: metas}}, {synced, solo} ->
      case List.last(metas) do
        %{sync_mode: :solo, user_id: uid, user_name: uname} ->
          {synced, [%{user_id: uid, user_name: uname} | solo]}

        %{user_id: uid, user_name: uname} ->
          # Default to synced if sync_mode not set
          {[%{user_id: uid, user_name: uname} | synced], solo}

        %{user_id: uid} ->
          {[%{user_id: uid, user_name: "Anonymous"} | synced], solo}

        _ ->
          {synced, solo}
      end
    end)
  end

  defp determine_view_mode(_sensors_count, _max_attributes) do
    # Always start in summary mode - users can expand individual tiles as needed
    :summary
  end

  defp extract_composite_data(sensors) do
    heartrate_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type in ["heartrate", "hr"]
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        hr_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type in ["heartrate", "hr"]
          end)

        bpm =
          case hr_attr do
            {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
            nil -> 0
          end

        %{sensor_id: sensor_id, bpm: bpm}
      end)

    imu_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "imu"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        imu_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type == "imu"
          end)

        orientation =
          case imu_attr do
            {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || %{}
            nil -> %{}
          end

        %{sensor_id: sensor_id, orientation: orientation}
      end)

    location_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "geolocation"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        geo_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type == "geolocation"
          end)

        position =
          case geo_attr do
            {_attr_id, attr} ->
              payload = (attr.lastvalue && attr.lastvalue.payload) || %{}

              %{
                lat: payload["latitude"] || payload[:latitude] || 0,
                lng: payload["longitude"] || payload[:longitude] || 0
              }

            nil ->
              %{lat: 0, lng: 0}
          end

        %{sensor_id: sensor_id, lat: position.lat, lng: position.lng, username: sensor.username}
      end)

    ecg_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "ecg"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        ecg_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type == "ecg"
          end)

        value =
          case ecg_attr do
            {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
            nil -> 0
          end

        %{sensor_id: sensor_id, value: value}
      end)

    battery_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "battery"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        battery_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type == "battery"
          end)

        level =
          case battery_attr do
            {_attr_id, attr} ->
              payload = attr.lastvalue && attr.lastvalue.payload

              cond do
                is_map(payload) -> payload["level"] || payload[:level] || 0
                is_number(payload) -> payload
                true -> 0
              end

            nil ->
              0
          end

        %{sensor_id: sensor_id, level: level, sensor_name: sensor.sensor_name}
      end)

    skeleton_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "skeleton"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        # Also check if this sensor has heartrate data
        hr_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type in ["heartrate", "hr"]
          end)

        bpm =
          case hr_attr do
            {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
            nil -> 0
          end

        %{sensor_id: sensor_id, username: sensor.username, bpm: bpm}
      end)

    respiration_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "respiration"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        resp_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type == "respiration"
          end)

        value =
          case resp_attr do
            {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
            nil -> 0
          end

        %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, value: value}
      end)

    hrv_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type == "hrv"
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        hrv_attr =
          Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
            attr.attribute_type == "hrv"
          end)

        value =
          case hrv_attr do
            {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
            nil -> 0
          end

        %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, value: value}
      end)

    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors}
  end

  # Compute which lens types are available based on actual sensor attributes
  defp compute_available_lenses(
         heartrate_sensors,
         imu_sensors,
         location_sensors,
         ecg_sensors,
         battery_sensors,
         skeleton_sensors,
         respiration_sensors,
         hrv_sensors
       ) do
    lenses = []
    lenses = if length(heartrate_sensors) > 0, do: [:heartrate | lenses], else: lenses
    lenses = if length(imu_sensors) > 0, do: [:imu | lenses], else: lenses
    lenses = if length(location_sensors) > 0, do: [:location | lenses], else: lenses
    lenses = if length(ecg_sensors) > 0, do: [:ecg | lenses], else: lenses
    lenses = if length(battery_sensors) > 0, do: [:battery | lenses], else: lenses
    lenses = if length(skeleton_sensors) > 0, do: [:skeleton | lenses], else: lenses
    lenses = if length(respiration_sensors) > 0, do: [:respiration | lenses], else: lenses
    lenses = if length(hrv_sensors) > 0, do: [:hrv | lenses], else: lenses
    Enum.reverse(lenses)
  end

  defp group_sensors_by_user(sensors) do
    sensors
    |> Enum.group_by(fn {_id, sensor} -> {sensor.connector_id, sensor.connector_name} end)
    |> Enum.map(fn {{connector_id, connector_name}, sensor_list} ->
      # Collect all attribute types and latest values across sensors
      all_attributes =
        sensor_list
        |> Enum.flat_map(fn {_id, sensor} ->
          (sensor.attributes || %{})
          |> Map.values()
          |> Enum.map(fn attr ->
            %{
              type: attr.attribute_type,
              name: Map.get(attr, :attribute_name, attr.attribute_id),
              value: attr.lastvalue && attr.lastvalue.payload,
              timestamp: attr.lastvalue && attr.lastvalue.timestamp
            }
          end)
        end)

      # Group by attribute type for summary
      attributes_summary =
        all_attributes
        |> Enum.group_by(& &1.type)
        |> Enum.map(fn {type, attrs} ->
          # Get latest value for this type
          latest = Enum.max_by(attrs, fn a -> a.timestamp || 0 end, fn -> %{value: nil} end)
          %{type: type, count: length(attrs), latest_value: latest.value}
        end)
        |> Enum.sort_by(& &1.type)

      %{
        connector_id: connector_id,
        connector_name: connector_name || "Unknown",
        sensor_count: length(sensor_list),
        sensors:
          Enum.map(sensor_list, fn {id, s} ->
            %{sensor_id: id, sensor_name: s.sensor_name}
          end),
        attributes_summary: attributes_summary,
        total_attributes: length(all_attributes)
      }
    end)
    |> Enum.sort_by(& &1.connector_name)
  end

  # Helper functions for user video card integration
  defp user_in_call?(call_participants, connector_id) do
    Enum.any?(call_participants, fn {_user_id, participant} ->
      participant[:connector_id] == connector_id ||
        participant[:metadata][:connector_id] == connector_id
    end)
  end

  defp get_user_video_tier(call_participants, connector_id) do
    Enum.find_value(call_participants, :viewer, fn {_user_id, participant} ->
      if participant[:connector_id] == connector_id ||
           participant[:metadata][:connector_id] == connector_id do
        participant[:tier] || :viewer
      end
    end)
  end

  defp user_speaking?(call_participants, connector_id) do
    Enum.any?(call_participants, fn {_user_id, participant} ->
      (participant[:connector_id] == connector_id ||
         participant[:metadata][:connector_id] == connector_id) &&
        participant[:speaking] == true
    end)
  end

  # Handle room mode presence diffs (for viewer counts) - MUST come before general presence_diff handler
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "room:lobby:mode_presence",
          event: "presence_diff"
        },
        socket
      ) do
    {media_count, object3d_count, whiteboard_count} = count_room_mode_presence("lobby")
    {synced_users, solo_users} = get_sync_mode_users("lobby")

    {:noreply,
     socket
     |> assign(:media_viewers, media_count)
     |> assign(:object3d_viewers, object3d_count)
     |> assign(:whiteboard_viewers, whiteboard_count)
     |> assign(:synced_users, synced_users)
     |> assign(:solo_users, solo_users)}
  end

  # Handle sensor presence diffs
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          event: "presence_diff",
          payload: payload
        },
        socket
      ) do
    # Only process if there are actual joins or leaves
    if Enum.empty?(payload.joins) and Enum.empty?(payload.leaves) do
      {:noreply, socket}
    else
      Logger.debug(
        "Lobby presence Joins: #{Enum.count(payload.joins)}, Leaves: #{Enum.count(payload.leaves)}"
      )

      sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
      sensors_count = Enum.count(sensors)

      # Only update sensor_ids if the set of sensors has changed
      # This prevents child LiveViews from being re-mounted when only sensor data changes
      new_sensor_ids = sensors |> Map.keys() |> Enum.sort()
      current_sensor_ids = socket.assigns.sensor_ids

      # Only update if sensor list actually changed
      if new_sensor_ids != current_sensor_ids do
        # Subscribe to signal topics for any new sensors (data comes via PriorityLens)
        new_sensors = new_sensor_ids -- current_sensor_ids

        Enum.each(new_sensors, fn sensor_id ->
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
        end)

        sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

        # Update composite visualization data
        {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
         skeleton_sensors, respiration_sensors, hrv_sensors} =
          extract_composite_data(sensors)

        # Recompute available lenses when sensors change
        available_lenses =
          compute_available_lenses(
            heartrate_sensors,
            imu_sensors,
            location_sensors,
            ecg_sensors,
            battery_sensors,
            skeleton_sensors,
            respiration_sensors,
            hrv_sensors
          )

        # Filter sensor IDs based on current min_attention setting
        min_attention = socket.assigns[:min_attention] || 0
        filtered_sensor_ids = filter_sensors_by_attention(new_sensor_ids, min_attention)

        updated_socket =
          socket
          |> assign(:sensors, sensors)
          |> assign(:sensors_online_count, sensors_count)
          |> assign(:sensors_online, sensors_online)
          |> assign(:all_sensor_ids, new_sensor_ids)
          |> assign(:sensor_ids, filtered_sensor_ids)
          |> assign(:heartrate_sensors, heartrate_sensors)
          |> assign(:imu_sensors, imu_sensors)
          |> assign(:location_sensors, location_sensors)
          |> assign(:ecg_sensors, ecg_sensors)
          |> assign(:battery_sensors, battery_sensors)
          |> assign(:skeleton_sensors, skeleton_sensors)
          |> assign(:respiration_sensors, respiration_sensors)
          |> assign(:hrv_sensors, hrv_sensors)
          |> assign(:available_lenses, available_lenses)
          |> assign(:sensors_by_user, group_sensors_by_user(sensors))

        # Update PriorityLens with new sensor list for adaptive streaming
        if updated_socket.assigns[:priority_lens_registered] do
          Sensocto.Lenses.PriorityLens.set_sensors(updated_socket.id, new_sensor_ids)
        end

        # Only update sensors_offline if there are actual leaves
        updated_socket =
          if map_size(payload.leaves) > 0 do
            assign(updated_socket, :sensors_offline, payload.leaves)
          else
            updated_socket
          end

        {:noreply, updated_socket}
      else
        # Sensor list unchanged - only update count if it actually changed
        # Avoid updating sensors_online/sensors_offline maps to prevent template re-evaluation
        if sensors_count != socket.assigns.sensors_online_count do
          {:noreply, assign(socket, :sensors_online_count, sensors_count)}
        else
          {:noreply, socket}
        end
      end
    end
  end

  @impl true
  def handle_info({:signal, msg}, socket) do
    IO.inspect(msg, label: "Lobby handled signal")
    {:noreply, put_flash(socket, :info, "Signal received!")}
  end

  @impl true
  def handle_info({:trigger_parent_flash, message}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  # ==========================================================================
  # PriorityLens Message Handlers (adaptive streaming)
  # ==========================================================================

  # Mailbox backpressure thresholds
  # Start throttling early to prevent runaway queue growth
  @mailbox_backpressure_threshold 50
  # Critical threshold - pause data delivery entirely
  @mailbox_critical_threshold 150
  # Recovery threshold - resume from paused when queue drops below this
  @mailbox_recovery_threshold 20
  # Delay before checking if we can recover from paused state
  @recovery_check_delay_ms 3_000
  # Delay between progressive quality upgrade attempts (when mailbox is healthy)
  # Increased from 5s to 15s to prevent rapid oscillation
  @upgrade_check_delay_ms 15_000
  # Threshold for considering mailbox healthy enough to upgrade
  @mailbox_healthy_threshold 10
  # Number of consecutive healthy checks required before upgrading
  # This adds hysteresis to prevent upgrade-downgrade oscillation
  @consecutive_healthy_checks_required 2

  # Handle PriorityLens batch data (high/medium quality)
  # batch_data structure: %{sensor_id => %{attribute_id => measurement}}
  @impl true
  def handle_info({:lens_batch, batch_data}, socket) do
    # Debug: trace lens_batch handling
    if Map.has_key?(batch_data, "46991438cf49") do
      Logger.debug(
        "LobbyLive: lens_batch received with web connector data, live_action=#{socket.assigns.live_action}"
      )
    end

    # Check mailbox depth - apply backpressure if overwhelmed
    {:message_queue_len, queue_len} = Process.info(self(), :message_queue_len)

    cond do
      # CRITICAL: Queue is severely backed up - pause entirely
      queue_len > @mailbox_critical_threshold ->
        Logger.warning(
          "LobbyLive #{socket.id}: CRITICAL backpressure (#{queue_len} msgs), pausing data"
        )

        socket =
          if socket.assigns[:priority_lens_registered] do
            # Jump straight to paused - stop all data delivery
            Sensocto.Lenses.PriorityLens.set_quality(socket.id, :paused)

            # Schedule a recovery check
            Process.send_after(self(), :check_backpressure_recovery, @recovery_check_delay_ms)

            socket
            |> assign(:current_quality, :paused)
            |> push_event("quality_changed", %{
              level: :paused,
              reason: "Critical backpressure: mailbox queue depth #{queue_len}"
            })
          else
            socket
          end

        {:noreply, socket}

      # WARNING: Queue is growing - aggressive downgrade
      queue_len > @mailbox_backpressure_threshold ->
        Logger.warning(
          "LobbyLive #{socket.id}: mailbox backpressure (#{queue_len} msgs), dropping batch"
        )

        # Auto-downgrade quality aggressively if we have a registered lens
        socket =
          if socket.assigns[:priority_lens_registered] do
            current = socket.assigns[:current_quality] || :high
            # Skip intermediate levels when queue is high
            new_quality =
              cond do
                queue_len > 100 -> :minimal
                queue_len > 75 -> :low
                true -> downgrade_quality(current)
              end

            if new_quality != current do
              Sensocto.Lenses.PriorityLens.set_quality(socket.id, new_quality)

              # Schedule upgrade check to eventually recover to :high
              Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)

              socket
              |> assign(:current_quality, new_quality)
              |> push_event("quality_changed", %{
                level: new_quality,
                reason: "Backpressure: mailbox queue depth #{queue_len}"
              })
            else
              socket
            end
          else
            socket
          end

        {:noreply, socket}

      # Normal processing
      true ->
        socket = assign(socket, :data_mode, :realtime)

        case socket.assigns.live_action do
          :sensors ->
            socket = process_lens_batch_for_sensors(socket, batch_data)
            {:noreply, socket}

          action
          when action in [
                 :heartrate,
                 :imu,
                 :location,
                 :ecg,
                 :battery,
                 :skeleton,
                 :respiration,
                 :hrv
               ] ->
            socket = process_lens_batch_for_composite(socket, batch_data, action)
            socket = maybe_compute_and_store_sync(socket, batch_data, action)
            {:noreply, socket}

          :graph ->
            socket = process_lens_batch_for_graph(socket, batch_data)
            {:noreply, socket}

          _ ->
            {:noreply, socket}
        end
    end
  end

  # Handle PriorityLens digest data (low/minimal quality)
  # digests structure: %{sensor_id => %{attribute_id => %{count, avg, min, max, latest}}}
  @impl true
  def handle_info({:lens_digest, digests}, socket) do
    socket = assign(socket, :data_mode, :digest)

    case socket.assigns.live_action do
      :sensors ->
        # For sensors grid, push digest data for summary display
        socket =
          Enum.reduce(digests, socket, fn {sensor_id, attrs}, acc ->
            push_event(acc, "sensor_digest", %{sensor_id: sensor_id, attributes: attrs})
          end)

        {:noreply, socket}

      action when action in [:heartrate, :battery, :respiration, :hrv] ->
        # These can work with digest mode - show latest values
        socket = process_lens_digest_for_composite(socket, digests, action)
        {:noreply, socket}

      _action ->
        # ECG, IMU, skeleton need real-time data - digest mode just shows placeholder
        {:noreply, socket}
    end
  end

  # Recovery check for paused quality mode
  # When mailbox has drained, recover to minimal quality to resume data flow
  @impl true
  def handle_info(:check_backpressure_recovery, socket) do
    {:message_queue_len, queue_len} = Process.info(self(), :message_queue_len)
    current_quality = socket.assigns[:current_quality]

    socket =
      if current_quality == :paused and queue_len < @mailbox_recovery_threshold do
        Logger.info(
          "LobbyLive #{socket.id}: Recovering from paused (queue: #{queue_len}), resuming at minimal"
        )

        Sensocto.Lenses.PriorityLens.set_quality(socket.id, :minimal)

        # Schedule progressive upgrade check to eventually get back to :high
        Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)

        socket
        |> assign(:current_quality, :minimal)
        |> push_event("quality_changed", %{
          level: :minimal,
          reason: "Recovered from backpressure (queue: #{queue_len})"
        })
      else
        # Still under pressure or not paused, schedule another check if paused
        if current_quality == :paused do
          Process.send_after(self(), :check_backpressure_recovery, @recovery_check_delay_ms)
        end

        socket
      end

    {:noreply, socket}
  end

  # Progressive quality upgrade check
  # When mailbox is healthy, gradually restore quality back to :high
  #
  # HYBRID QUALITY CONTROL:
  # - Mailbox depth is AUTHORITATIVE (controls capacity)
  # - ClientHealth is ADVISORY (can cap maximum quality but not force higher)
  # - Requires consecutive healthy checks before upgrading (hysteresis)
  #
  # The effective quality is: min(mailbox_allows, client_health_allows)
  @impl true
  def handle_info(:check_quality_upgrade, socket) do
    {:message_queue_len, queue_len} = Process.info(self(), :message_queue_len)
    current_quality = socket.assigns[:current_quality] || :high
    quality_override = socket.assigns[:quality_override]
    consecutive_healthy = socket.assigns[:consecutive_healthy_checks] || 0

    # Get client health recommended quality (advisory ceiling)
    client_health = socket.assigns[:client_health]
    client_recommended = if client_health, do: client_health.current_quality, else: :high

    socket =
      cond do
        # Don't upgrade if user has set a manual override
        quality_override != nil ->
          socket

        # Already at high quality - nothing to do, reset counter
        current_quality == :high ->
          assign(socket, :consecutive_healthy_checks, 0)

        # Mailbox is healthy - track consecutive healthy checks
        queue_len < @mailbox_healthy_threshold ->
          new_consecutive = consecutive_healthy + 1

          # Only upgrade after consecutive healthy checks (hysteresis)
          if new_consecutive >= @consecutive_healthy_checks_required do
            mailbox_target = upgrade_quality(current_quality)

            # Hybrid: Don't upgrade past what client health recommends
            new_quality =
              Sensocto.Lenses.PriorityLens.min_quality(mailbox_target, client_recommended)

            if new_quality != current_quality do
              Logger.info(
                "LobbyLive #{socket.id}: Upgrading quality #{current_quality} -> #{new_quality} (queue: #{queue_len}, consecutive_healthy: #{new_consecutive}, client_ceiling: #{client_recommended})"
              )

              if socket.assigns[:priority_lens_registered] do
                Sensocto.Lenses.PriorityLens.set_quality(socket.id, new_quality)
              end

              # Schedule another upgrade check if not yet at target
              if new_quality != :high and new_quality != client_recommended do
                Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)
              end

              socket
              |> assign(:current_quality, new_quality)
              |> assign(:consecutive_healthy_checks, 0)
              |> push_event("quality_changed", %{
                level: new_quality,
                reason:
                  "Progressive recovery (queue: #{queue_len}, stable for #{new_consecutive} checks)"
              })
            else
              # Can't upgrade due to client health ceiling, but keep checking
              Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)
              assign(socket, :consecutive_healthy_checks, new_consecutive)
            end
          else
            # Not enough consecutive healthy checks yet, keep counting
            Logger.debug(
              "LobbyLive #{socket.id}: Mailbox healthy (#{queue_len}), consecutive: #{new_consecutive}/#{@consecutive_healthy_checks_required}"
            )

            Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)
            assign(socket, :consecutive_healthy_checks, new_consecutive)
          end

        # Mailbox still has some pressure - reset counter, check again later
        true ->
          Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)
          assign(socket, :consecutive_healthy_checks, 0)
      end

    {:noreply, socket}
  end

  # ==========================================================================
  # Legacy Direct Measurement Handlers (DEPRECATED)
  # These are kept for backwards compatibility but LobbyLive no longer
  # subscribes to "data:#{sensor_id}" topics. Data now comes via PriorityLens.
  # These handlers will only fire if messages come from other sources.
  # ==========================================================================

  # Legacy: Handle single measurement (now handled by lens_batch)
  @impl true
  def handle_info({:measurement, %{:sensor_id => _sensor_id}}, socket) do
    # Data now comes via PriorityLens - this handler is deprecated
    {:noreply, socket}
  end

  # Legacy: Handle batch measurements (now handled by lens_batch)
  # ECG data now properly flows through PriorityLens with high-frequency support
  @impl true
  def handle_info({:measurements_batch, {_sensor_id, _measurements_list}}, socket) do
    # Data now comes via PriorityLens - this handler is deprecated
    {:noreply, socket}
  end

  # Flush measurement buffer - sends batched measurements to clients
  @impl true
  def handle_info(:flush_measurement_buffer, socket) do
    buffer = socket.assigns.measurement_buffer

    if map_size(buffer) > 0 do
      # Push one batched event per sensor (combines all buffered measurements)
      socket =
        Enum.reduce(buffer, socket, fn {sensor_id, measurements}, acc ->
          push_event(acc, "measurements_batch", %{
            sensor_id: sensor_id,
            attributes: measurements
          })
        end)

      # Update perf stats
      perf_stats = socket.assigns.perf_stats
      push_count = map_size(buffer)

      new_perf_stats = %{
        perf_stats
        | push_event_count: perf_stats.push_event_count + push_count
      }

      {:noreply,
       socket
       |> assign(:measurement_buffer, %{})
       |> assign(:measurement_flush_timer, nil)
       |> assign(:perf_stats, new_perf_stats)}
    else
      {:noreply, assign(socket, :measurement_flush_timer, nil)}
    end
  end

  # Performance logging - reports server-side stats every 5 seconds
  @impl true
  def handle_info(:log_perf_stats, socket) do
    perf_stats = socket.assigns.perf_stats
    now = System.monotonic_time(:millisecond)
    elapsed_ms = now - perf_stats.last_report_time

    if perf_stats.handle_info_count > 0 and elapsed_ms > 0 do
      avg_us = div(perf_stats.handle_info_total_us, perf_stats.handle_info_count)
      rate = Float.round(perf_stats.handle_info_count * 1000 / elapsed_ms, 1)

      Logger.info(
        "[LobbyPerf] #{elapsed_ms}ms: #{perf_stats.handle_info_count} handle_info (#{rate}/s), " <>
          "avg: #{avg_us}µs, max: #{perf_stats.handle_info_max_us}µs, " <>
          "push_events: #{perf_stats.push_event_count}"
      )
    end

    # Reset stats and schedule next report
    Process.send_after(self(), :log_perf_stats, @perf_log_interval_ms)

    {:noreply,
     assign(socket, :perf_stats, %{
       handle_info_count: 0,
       handle_info_total_us: 0,
       handle_info_max_us: 0,
       push_event_count: 0,
       last_report_time: now
     })}
  end

  # Media player events - forward to component via send_update AND push events to JS hook
  @impl true
  def handle_info({:media_state_changed, state}, socket) do
    Logger.debug(
      "LobbyLive received media_state_changed: #{inspect(state.state)} pos=#{state.position_seconds}"
    )

    # In solo mode, ignore position syncs but still update component state for info display
    if socket.assigns.sync_mode == :solo do
      # Only update component state, don't push sync events to JS
      send_update(MediaPlayerComponent,
        id: "lobby-media-player",
        player_state: state.state,
        position_seconds: state.position_seconds,
        current_item: state.current_item
      )

      {:noreply, socket}
    else
      send_update(MediaPlayerComponent,
        id: "lobby-media-player",
        player_state: state.state,
        position_seconds: state.position_seconds,
        current_item: state.current_item
      )

      # Push sync event directly to JS hook from parent LiveView
      socket =
        push_event(socket, "media_sync", %{
          state: state.state,
          position_seconds: state.position_seconds
        })

      # Trigger bump animation only on active user interaction (not heartbeat syncs)
      is_active = Map.get(state, :is_active, false)

      socket =
        if is_active and not socket.assigns.media_bump do
          Process.send_after(self(), :clear_media_bump, 300)
          assign(socket, :media_bump, true)
        else
          socket
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:media_video_changed, %{item: item}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      current_item: item
    )

    # Push video change event directly to JS hook from parent LiveView
    socket =
      push_event(socket, "media_load_video", %{
        video_id: item.youtube_video_id,
        start_seconds: 0
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_playlist_updated, %{items: items}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      playlist_items: items
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:media_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name} = params},
        socket
      ) do
    # pending_request_user_id comes from server (nil when control changes)
    pending_request_user_id = Map.get(params, :pending_request_user_id)

    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      controller_user_id: user_id,
      controller_user_name: user_name,
      pending_request_user_id: pending_request_user_id
    )

    # Store controller_user_id so we can check if current user is the controller for request modal
    # Also close the modal if control changed (request was fulfilled or timed out)
    {:noreply,
     socket
     |> assign(:media_controller_user_id, user_id)
     |> assign(:media_control_request_modal, nil)}
  end

  # 3D Object player events - forward to component
  @impl true
  def handle_info(
        {:object3d_item_changed, %{item: item, camera_position: pos, camera_target: target}},
        socket
      ) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
      current_item: item,
      camera_position: pos,
      camera_target: target
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:object3d_camera_synced, %{camera_position: position, camera_target: target} = event},
        socket
      ) do
    # In solo mode, ignore camera syncs entirely
    if socket.assigns.sync_mode == :solo do
      {:noreply, socket}
    else
      # Filter by socket_id instead of user_id to support multi-tab sync
      # This allows same user in different tabs to receive camera syncs
      controller_socket_id = Map.get(event, :controller_socket_id)

      # Don't forward camera sync to the controller tab itself - it's the source
      is_controller_tab = controller_socket_id && socket.id == controller_socket_id

      unless is_controller_tab do
        send_update(Object3DPlayerComponent,
          id: "lobby-object3d-player",
          synced_camera_position: position,
          synced_camera_target: target
        )
      end

      # Trigger bump animation only on active camera movement (not heartbeat syncs)
      is_active = Map.get(event, :is_active, false)

      socket =
        if is_active and not socket.assigns.object3d_bump do
          Process.send_after(self(), :clear_object3d_bump, 300)
          assign(socket, :object3d_bump, true)
        else
          socket
        end

      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:object3d_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name}},
        socket
      ) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
      controller_user_id: user_id,
      controller_user_name: user_name,
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    # Store controller_user_id so we can check if current user is the controller
    {:noreply, assign(socket, :object3d_controller_user_id, user_id)}
  end

  @impl true
  def handle_info({:object3d_playlist_updated, %{items: items}}, socket) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
      playlist_items: items
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:control_requested, %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:object3d_controller_user_id]

    # Only show modal to the controller
    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      {:noreply,
       socket
       |> assign(:control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      {:noreply, socket}
    end
  end

  # Handle object3d control request with 30s timeout (server-managed)
  # Shows modal with Keep/Release buttons and audio notification
  @impl true
  def handle_info(
        {:object3d_control_requested,
         %{
           requester_id: requester_id,
           requester_name: requester_name,
           controller_user_id: _controller_id,
           timeout_seconds: _timeout
         }},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:object3d_controller_user_id]

    # Only show modal to the controller
    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      # Update component with pending request info
      send_update(Object3DPlayerComponent,
        id: "lobby-object3d-player",
        pending_request_user_id: requester_id,
        pending_request_user_name: requester_name
      )

      # Show modal with Keep/Release buttons (uses existing control_request_modal)
      {:noreply,
       socket
       |> assign(:control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      # Not the controller - just update component (e.g., requester sees "pending")
      send_update(Object3DPlayerComponent,
        id: "lobby-object3d-player",
        pending_request_user_id: requester_id,
        pending_request_user_name: requester_name
      )

      {:noreply, socket}
    end
  end

  # Handle object3d control request denied (keep control was clicked)
  @impl true
  def handle_info(
        {:object3d_control_request_denied, %{requester_id: _requester_id}},
        socket
      ) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    # Also dismiss the modal if it's open
    {:noreply, assign(socket, :control_request_modal, nil)}
  end

  # Handle media player control requests (server manages the 30s timeout)
  @impl true
  def handle_info(
        {:media_control_requested,
         %{requester_id: requester_id, requester_name: requester_name} = _params},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:media_controller_user_id]

    # Update all clients with pending request info (for requester countdown display)
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      pending_request_user_id: requester_id
    )

    # Only show modal to the controller
    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      {:noreply,
       socket
       |> assign(:media_control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      {:noreply, socket}
    end
  end

  # Handle media control request cancellation
  @impl true
  def handle_info({:media_control_request_cancelled, _params}, socket) do
    # Clear pending request in component
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      pending_request_user_id: nil
    )

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  # Handle media control request denied (keep control was clicked)
  @impl true
  def handle_info({:media_control_request_denied, _params}, socket) do
    # Clear pending request in component
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      pending_request_user_id: nil
    )

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  # Legacy handler - no longer used since server manages timeout
  # Keep for backwards compatibility but it should never fire
  # Handle call events from CallServer via PubSub

  # Handle call events from CallServer via PubSub
  @impl true
  def handle_info({:call_event, event}, socket) do
    socket =
      case event do
        {:participant_joined, participant} ->
          new_participants =
            Map.put(socket.assigns.call_participants, participant.user_id, participant)

          assign(socket, :call_participants, new_participants)

        {:participant_left, user_id} ->
          new_participants = Map.delete(socket.assigns.call_participants, user_id)
          assign(socket, :call_participants, new_participants)

        :call_ended ->
          socket
          |> assign(:call_active, false)
          |> assign(:in_call, false)
          |> assign(:call_participants, %{})

        _ ->
          socket
      end

    {:noreply, socket}
  end

  # Handle push_event requests from call components
  @impl true
  def handle_info({:push_event, event, payload}, socket) do
    {:noreply, push_event(socket, event, payload)}
  end

  # Handle attention level changes for webcam backpressure
  @impl true
  def handle_info({:attention_level_changed, level}, socket) do
    # Push to JS hook to adjust webcam quality
    socket = push_event(socket, "set_attention_level", %{level: Atom.to_string(level)})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:global_attention_level, level}, socket) do
    # Global system load affects all call participants
    socket = push_event(socket, "set_attention_level", %{level: Atom.to_string(level)})
    {:noreply, socket}
  end

  # Handle sensor attention changes to re-filter sensor list in realtime
  # Debounced to avoid excessive re-renders from rapid attention changes
  @impl true
  def handle_info({:attention_changed, %{sensor_id: _sensor_id, level: _level}}, socket) do
    min_attention = socket.assigns[:min_attention] || 0

    # Only schedule re-filter if min_attention > 0 (otherwise all sensors are shown)
    if min_attention > 0 do
      # Cancel any pending attention filter timer
      if socket.assigns[:attention_filter_timer] do
        Process.cancel_timer(socket.assigns[:attention_filter_timer])
      end

      # Debounce: schedule re-filter in 500ms
      timer = Process.send_after(self(), :refilter_by_attention, 500)
      {:noreply, assign(socket, :attention_filter_timer, timer)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:refilter_by_attention, socket) do
    all_sensor_ids = socket.assigns[:all_sensor_ids] || socket.assigns.sensor_ids
    min_attention = socket.assigns[:min_attention] || 0
    filtered_sensor_ids = filter_sensors_by_attention(all_sensor_ids, min_attention)

    {:noreply,
     socket
     |> assign(:sensor_ids, filtered_sensor_ids)
     |> assign(:attention_filter_timer, nil)}
  end

  # Refresh available lenses after mount to catch late-registered attributes
  @impl true
  # Handle favorite toggle broadcasts from child sensor LiveViews
  def handle_info({:toggle_favorite, user_id, sensor_id}, socket) do
    user = socket.assigns.current_user

    # Only handle if it's for the current user
    if user && user.id == user_id do
      current_favorites = socket.assigns.favorite_sensors

      new_favorites =
        if sensor_id in current_favorites do
          List.delete(current_favorites, sensor_id)
        else
          [sensor_id | current_favorites]
        end

      UserPreferences.set_ui_state(user.id, "favorite_sensors", new_favorites)

      {:noreply, assign(socket, :favorite_sensors, new_favorites)}
    else
      {:noreply, socket}
    end
  end

  def handle_info(:refresh_available_lenses, socket) do
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)

    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors} =
      extract_composite_data(sensors)

    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors,
        respiration_sensors,
        hrv_sensors
      )

    # Re-filter sensors based on current min_attention setting
    # This ensures sensors are removed when their attention drops below threshold
    all_sensor_ids = socket.assigns[:all_sensor_ids] || socket.assigns.sensor_ids
    min_attention = socket.assigns[:min_attention] || 0
    filtered_sensor_ids = filter_sensors_by_attention(all_sensor_ids, min_attention)

    {:noreply,
     socket
     |> assign(:sensors, sensors)
     |> assign(:heartrate_sensors, heartrate_sensors)
     |> assign(:imu_sensors, imu_sensors)
     |> assign(:location_sensors, location_sensors)
     |> assign(:ecg_sensors, ecg_sensors)
     |> assign(:battery_sensors, battery_sensors)
     |> assign(:skeleton_sensors, skeleton_sensors)
     |> assign(:respiration_sensors, respiration_sensors)
     |> assign(:hrv_sensors, hrv_sensors)
     |> assign(:available_lenses, available_lenses)
     |> assign(:sensors_by_user, group_sensors_by_user(sensors))
     |> assign(:sensor_ids, filtered_sensor_ids)}
  end

  # Clear bump animations after timeout
  @impl true
  def handle_info(:clear_media_bump, socket) do
    {:noreply, assign(socket, :media_bump, false)}
  end

  @impl true
  def handle_info(:clear_object3d_bump, socket) do
    {:noreply, assign(socket, :object3d_bump, false)}
  end

  @impl true
  def handle_info(:clear_whiteboard_bump, socket) do
    {:noreply, assign(socket, :whiteboard_bump, false)}
  end

  # Whiteboard PubSub handlers

  # Real-time stroke progress for live drawing preview
  @impl true
  def handle_info({:whiteboard_stroke_progress, %{stroke: stroke, user_id: user_id}}, socket) do
    # Don't echo back to the user who is drawing
    if socket.assigns.current_user &&
         to_string(socket.assigns.current_user.id) != to_string(user_id) do
      send_update(WhiteboardComponent,
        id: "lobby-whiteboard",
        stroke_progress: %{stroke: stroke, user_id: user_id}
      )
    end

    {:noreply, socket}
  end

  # Batched strokes for scalability
  @impl true
  def handle_info({:whiteboard_strokes_batch, %{strokes: strokes}}, socket) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      new_strokes: strokes
    )

    socket =
      if not socket.assigns.whiteboard_bump do
        Process.send_after(self(), :clear_whiteboard_bump, 300)
        assign(socket, :whiteboard_bump, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:whiteboard_stroke_added, %{stroke: stroke}}, socket) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      new_stroke: stroke
    )

    socket =
      if not socket.assigns.whiteboard_bump do
        Process.send_after(self(), :clear_whiteboard_bump, 300)
        assign(socket, :whiteboard_bump, true)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:whiteboard_cleared, _params}, socket) do
    send_update(WhiteboardComponent, id: "lobby-whiteboard", strokes: [])
    {:noreply, socket}
  end

  @impl true
  def handle_info({:whiteboard_undo, %{removed_stroke: removed_stroke}}, socket) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      undo_stroke: removed_stroke
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:whiteboard_background_changed, %{color: color}}, socket) do
    send_update(WhiteboardComponent, id: "lobby-whiteboard", background_color: color)
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:whiteboard_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name}},
        socket
      ) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      controller_user_id: user_id,
      controller_user_name: user_name,
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:whiteboard_control_requested,
         %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      pending_request_user_id: requester_id,
      pending_request_user_name: requester_name
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:whiteboard_control_request_denied, _params}, socket) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:whiteboard_control_request_cancelled, _params}, socket) do
    send_update(WhiteboardComponent,
      id: "lobby-whiteboard",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:noreply, socket}
  end

  # Handle attention changes from UserVideoCardComponent
  @impl true
  def handle_info({:user_attention_change, connector_id, level}, socket) do
    # Forward attention change to CallHook for quality tier adjustment
    Logger.debug("User attention change: #{connector_id} -> #{level}")

    socket =
      push_event(socket, "set_participant_attention", %{
        connector_id: connector_id,
        level: Atom.to_string(level)
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:user_focus, connector_id}, socket) do
    # User clicked on a card to focus - boost quality to highest tier
    Logger.debug("User focus requested: #{connector_id}")

    socket =
      push_event(socket, "set_participant_attention", %{
        connector_id: connector_id,
        level: "high"
      })

    {:noreply, socket}
  end

  # Handle sensor state changes (e.g., new attributes registered)
  # This refreshes available lenses when attributes are auto-registered
  @impl true
  def handle_info({:new_state, _sensor_id}, socket) do
    # Re-fetch all sensors and recompute available lenses
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)

    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors} =
      extract_composite_data(sensors)

    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors,
        respiration_sensors,
        hrv_sensors
      )

    {:noreply,
     socket
     |> assign(:sensors, sensors)
     |> assign(:heartrate_sensors, heartrate_sensors)
     |> assign(:imu_sensors, imu_sensors)
     |> assign(:location_sensors, location_sensors)
     |> assign(:ecg_sensors, ecg_sensors)
     |> assign(:battery_sensors, battery_sensors)
     |> assign(:skeleton_sensors, skeleton_sensors)
     |> assign(:respiration_sensors, respiration_sensors)
     |> assign(:hrv_sensors, hrv_sensors)
     |> assign(:available_lenses, available_lenses)
     |> assign(:sensors_by_user, group_sensors_by_user(sensors))}
  end

  # Flush measurement buffers in all visible sensor components
  @impl true
  def handle_info(:flush_component_measurements, socket) do
    # Schedule next flush
    Process.send_after(self(), :flush_component_measurements, @component_flush_interval_ms)

    # Get visible sensor range
    {start_idx, end_idx} = socket.assigns.visible_range
    visible_sensor_ids = socket.assigns.sensor_ids |> Enum.slice(start_idx, end_idx - start_idx)

    # Send flush to each visible component
    Enum.each(visible_sensor_ids, fn sensor_id ->
      send_update(StatefulSensorComponent, id: "sensor_#{sensor_id}", flush: true)
    end)

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_all_view_mode", _params, socket) do
    new_mode = if socket.assigns.global_view_mode == :summary, do: :normal, else: :summary

    # Broadcast to all sensor LiveViews to update their view mode
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "ui:view_mode",
      {:global_view_mode_changed, new_mode}
    )

    {:noreply, assign(socket, :global_view_mode, new_mode)}
  end

  # Room join/leave events
  @impl true
  def handle_event("open_join_modal", _params, socket) do
    {:noreply, assign(socket, :show_join_modal, true)}
  end

  @impl true
  def handle_event("close_join_modal", _params, socket) do
    {:noreply, assign(socket, show_join_modal: false, join_code: "")}
  end

  @impl true
  def handle_event("update_join_code", %{"join_code" => code}, socket) do
    {:noreply, assign(socket, :join_code, String.upcase(code))}
  end

  @impl true
  def handle_event("join_room_by_code", %{"join_code" => code}, socket) do
    user = socket.assigns.current_user

    case Sensocto.Rooms.join_by_code(String.trim(code), user) do
      {:ok, room} ->
        # Join with sensors via Neo4j graph
        Sensocto.Rooms.join_room_with_sensors(room, user)

        socket =
          socket
          |> put_flash(:info, "Joined room: #{room.name}")
          |> push_navigate(to: ~p"/rooms/#{room.id}")

        {:noreply, socket}

      {:error, :not_found} ->
        {:noreply, put_flash(socket, :error, "Room not found with that code")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to join room")}
    end
  end

  @impl true
  def handle_event("join_room", %{"room_id" => room_id}, socket) do
    user = socket.assigns.current_user

    case Sensocto.Rooms.get_room(room_id) do
      {:ok, room} ->
        case Sensocto.Rooms.join_room_with_sensors(room, user) do
          {:ok, _room} ->
            socket =
              socket
              |> put_flash(:info, "Joined room: #{room.name}")
              |> push_navigate(to: ~p"/rooms/#{room_id}")

            {:noreply, socket}

          {:error, _reason} ->
            {:noreply, put_flash(socket, :error, "Failed to join room")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Room not found")}
    end
  end

  # Media player hook events
  @impl true
  def handle_event("report_duration", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("request_media_sync", _params, socket) do
    # JS hook requests current state when player becomes ready
    # This ensures new tabs get properly synchronized
    # NOTE: Only push media_sync for position/state - do NOT push media_load_video
    # as that would reload the video and reset playback position
    case MediaPlayerServer.get_state(:lobby) do
      {:ok, state} ->
        socket =
          push_event(socket, "media_sync", %{
            state: state.state,
            position_seconds: state.position_seconds
          })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  # Lobby mode switching
  @impl true
  def handle_event("switch_lobby_mode", %{"mode" => mode}, socket) do
    new_mode = String.to_existing_atom(mode)
    old_mode = socket.assigns.lobby_mode
    user = socket.assigns.current_user

    # Release control when leaving a controlled mode (playback continues without controller)
    if user && old_mode != new_mode do
      release_control_for_mode(old_mode, user.id)
    end

    # Update presence to reflect new mode
    presence_key = socket.assigns[:presence_key]

    if user && presence_key do
      Presence.update(self(), "room:lobby:mode_presence", presence_key, %{
        room_mode: new_mode,
        user_id: user.id,
        user_name: Map.get(user, :email) || Map.get(user, :display_name) || "Anonymous",
        sync_mode: socket.assigns.sync_mode
      })
    end

    socket =
      socket
      |> assign(:lobby_mode, new_mode)
      |> push_event("save_lobby_mode", %{mode: mode})

    {:noreply, socket}
  end

  # Quick join call from persistent call controls bar (one-click join)
  @impl true
  def handle_event("quick_join_call", %{"mode" => mode}, socket) do
    # Join the call but DON'T switch tabs - user stays on current view (3D object, media, etc.)
    # The call controls bar provides full access to call features regardless of active tab
    socket = push_event(socket, "join_call", %{mode: mode})
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_call_audio", _, socket) do
    {:noreply, push_event(socket, "toggle_audio", %{})}
  end

  @impl true
  def handle_event("toggle_call_video", _, socket) do
    {:noreply, push_event(socket, "toggle_video", %{})}
  end

  @impl true
  def handle_event("toggle_call_expanded", _, socket) do
    {:noreply, assign(socket, :call_expanded, !socket.assigns.call_expanded)}
  end

  @impl true
  def handle_event("toggle_sync_mode", _, socket) do
    new_mode = if socket.assigns.sync_mode == :synced, do: :solo, else: :synced
    user = socket.assigns.current_user
    presence_key = socket.assigns[:presence_key]

    # Update presence to reflect sync mode change
    if user && presence_key do
      Presence.update(self(), "room:lobby:mode_presence", presence_key, %{
        room_mode: socket.assigns.lobby_mode,
        user_id: user.id,
        user_name: Map.get(user, :email) || Map.get(user, :display_name) || "Anonymous",
        sync_mode: new_mode
      })
    end

    {:noreply, assign(socket, :sync_mode, new_mode)}
  end

  @impl true
  def handle_event("toggle_favorite", %{"sensor-id" => sensor_id}, socket) do
    user = socket.assigns.current_user

    if user do
      current_favorites = socket.assigns.favorite_sensors

      new_favorites =
        if sensor_id in current_favorites do
          List.delete(current_favorites, sensor_id)
        else
          [sensor_id | current_favorites]
        end

      UserPreferences.set_ui_state(user.id, "favorite_sensors", new_favorites)

      {:noreply, assign(socket, :favorite_sensors, new_favorites)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("leave_call", _, socket) do
    {:noreply, push_event(socket, "leave_call", %{})}
  end

  # Handle audio/video toggled events from CallHook
  @impl true
  def handle_event("audio_toggled", %{"enabled" => enabled}, socket) do
    {:noreply, assign(socket, :audio_enabled, enabled)}
  end

  @impl true
  def handle_event("video_toggled", %{"enabled" => enabled}, socket) do
    {:noreply, assign(socket, :video_enabled, enabled)}
  end

  # Restore lobby mode from localStorage (via JS hook)
  @impl true
  def handle_event("restore_lobby_mode", %{"mode" => mode}, socket) do
    new_mode = String.to_existing_atom(mode)

    # Update presence to reflect restored mode
    user = socket.assigns.current_user
    presence_key = socket.assigns[:presence_key]

    if user && presence_key do
      Presence.update(self(), "room:lobby:mode_presence", presence_key, %{
        room_mode: new_mode,
        user_id: user.id,
        user_name: Map.get(user, :email) || Map.get(user, :display_name) || "Anonymous",
        sync_mode: socket.assigns.sync_mode
      })
    end

    {:noreply, assign(socket, :lobby_mode, new_mode)}
  end

  # Control request modal handlers
  @impl true
  def handle_event("dismiss_control_request", _, socket) do
    # "Keep Control" - cancel the pending request timer on the server
    current_user = socket.assigns.current_user

    if current_user do
      alias Sensocto.Object3D.Object3DPlayerServer
      Object3DPlayerServer.keep_control(:lobby, current_user.id)
    end

    {:noreply, assign(socket, :control_request_modal, nil)}
  end

  @impl true
  def handle_event("release_control_from_modal", _, socket) do
    current_user = socket.assigns.current_user
    modal_data = socket.assigns.control_request_modal

    if current_user && modal_data do
      alias Sensocto.Object3D.Object3DPlayerServer

      # First release control from current user
      Object3DPlayerServer.release_control(:lobby, current_user.id)

      # Then give control to the requester
      Object3DPlayerServer.take_control(
        :lobby,
        modal_data.requester_id,
        modal_data.requester_name
      )
    end

    {:noreply, assign(socket, :control_request_modal, nil)}
  end

  # Media control request modal handlers
  @impl true
  def handle_event("dismiss_media_control_request", _, socket) do
    current_user = socket.assigns[:current_user]

    # Use server's keep_control to cancel the request and notify others
    if current_user do
      alias Sensocto.Media.MediaPlayerServer
      MediaPlayerServer.keep_control(:lobby, current_user.id)
    end

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  @impl true
  def handle_event("release_media_control_from_modal", _, socket) do
    current_user = socket.assigns.current_user
    modal_data = socket.assigns.media_control_request_modal

    if current_user && modal_data do
      alias Sensocto.Media.MediaPlayerServer

      # First release control from current user
      MediaPlayerServer.release_control(:lobby, current_user.id)

      # Then give control to the requester
      MediaPlayerServer.take_control(
        :lobby,
        modal_data.requester_id,
        modal_data.requester_name
      )
    end

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  # Minimum attention filter slider
  @impl true
  def handle_event("set_min_attention", %{"min_attention" => value}, socket) do
    min_attention = String.to_integer(value)
    all_sensor_ids = socket.assigns[:all_sensor_ids] || socket.assigns.sensor_ids
    filtered_ids = filter_sensors_by_attention(all_sensor_ids, min_attention)

    {:noreply,
     socket
     |> assign(:min_attention, min_attention)
     |> assign(:sensor_ids, filtered_ids)
     |> push_event("save_min_attention", %{min_attention: min_attention})}
  end

  # Restore min_attention from localStorage (via JS hook)
  @impl true
  def handle_event("restore_min_attention", %{"min_attention" => min_attention}, socket) do
    all_sensor_ids = socket.assigns[:all_sensor_ids] || socket.assigns.sensor_ids
    filtered_ids = filter_sensors_by_attention(all_sensor_ids, min_attention)

    {:noreply,
     socket
     |> assign(:min_attention, min_attention)
     |> assign(:sensor_ids, filtered_ids)}
  end

  # Virtual scroll: handle visible range changes from JS hook
  @impl true
  def handle_event(
        "visible_range_changed",
        %{"start_index" => start_idx, "end_index" => end_idx, "cols" => cols},
        socket
      ) do
    {:noreply,
     socket
     |> assign(:visible_range, {start_idx, end_idx})
     |> assign(:cols, max(1, cols))
     |> assign(:virtual_scroll_loading, false)
     |> push_event("virtual_scroll_loaded", %{})}
  end

  # Lens view selector (dropdown)
  @impl true
  def handle_event("select_view", %{"view" => view}, socket) do
    path =
      case view do
        "sensors" -> ~p"/lobby"
        "users" -> ~p"/lobby/users"
        "favorites" -> ~p"/lobby/favorites"
        "heartrate" -> ~p"/lobby/heartrate"
        "imu" -> ~p"/lobby/imu"
        "location" -> ~p"/lobby/location"
        "ecg" -> ~p"/lobby/ecg"
        "battery" -> ~p"/lobby/battery"
        "skeleton" -> ~p"/lobby/skeleton"
        "breathing" -> ~p"/lobby/breathing"
        "hrv" -> ~p"/lobby/hrv"
        _ -> ~p"/lobby"
      end

    {:noreply, push_patch(socket, to: path)}
  end

  # Call-related events from JS hooks
  @impl true
  def handle_event("call_joined", %{"endpoint_id" => _endpoint_id}, socket) do
    {:noreply, assign(socket, :in_call, true)}
  end

  @impl true
  def handle_event("call_left", _params, socket) do
    {:noreply, assign(socket, :in_call, false)}
  end

  @impl true
  def handle_event("call_error", params, socket) do
    message = Map.get(params, "message", "Unknown error")
    can_retry = Map.get(params, "canRetry", false)

    socket =
      socket
      |> assign(:in_call, false)
      |> assign(:call_state, "error")

    if can_retry do
      {:noreply, put_flash(socket, :error, "#{message} Click Video/Voice to try again.")}
    else
      {:noreply, put_flash(socket, :error, "Call error: #{message}")}
    end
  end

  @impl true
  def handle_event("call_state_changed", %{"state" => state}, socket) do
    {:noreply, assign(socket, :call_state, state)}
  end

  @impl true
  def handle_event("call_reconnecting", params, socket) do
    attempt = Map.get(params, "attempt", 1)
    max = Map.get(params, "max", 3)

    socket =
      socket
      |> assign(:call_state, "reconnecting")
      |> put_flash(:info, "Reconnecting to call (#{attempt}/#{max})...")

    {:noreply, socket}
  end

  @impl true
  def handle_event("call_reconnected", _params, socket) do
    socket =
      socket
      |> assign(:call_state, "connected")
      |> clear_flash()
      |> put_flash(:info, "Reconnected to call")

    {:noreply, socket}
  end

  @impl true
  def handle_event("call_joining_retry", params, socket) do
    attempt = Map.get(params, "attempt", 1)
    max = Map.get(params, "max", 3)
    {:noreply, put_flash(socket, :info, "Retrying connection (#{attempt}/#{max})...")}
  end

  @impl true
  def handle_event("channel_reconnecting", _params, socket) do
    {:noreply, put_flash(socket, :warning, "Connection interrupted, attempting to reconnect...")}
  end

  @impl true
  def handle_event("socket_error", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("connection_unhealthy", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("connection_state_changed", %{"state" => state}, socket) do
    {:noreply, assign(socket, :connection_state, state)}
  end

  @impl true
  def handle_event("participant_joined", params, socket) do
    user_id = params["user_id"] || params["peer_id"]

    if user_id && user_id != to_string(socket.assigns.current_user.id) do
      participant = %{
        user_id: user_id,
        endpoint_id: params["endpoint_id"],
        user_info: params["user_info"] || params["metadata"] || %{},
        audio_enabled: true,
        video_enabled: true
      }

      new_participants = Map.put(socket.assigns.call_participants, user_id, participant)
      {:noreply, assign(socket, :call_participants, new_participants)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("participant_left", params, socket) do
    user_id = params["user_id"] || params["peer_id"]

    if user_id do
      new_participants = Map.delete(socket.assigns.call_participants, user_id)
      {:noreply, assign(socket, :call_participants, new_participants)}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("track_ready", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("track_removed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("connection_state_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("quality_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("participant_audio_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("participant_video_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("speaking_changed", %{"speaking" => speaking}, socket) do
    {:noreply, assign(socket, :call_speaking, speaking)}
  end

  @impl true
  def handle_event("participant_speaking", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("my_tier_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("producer_mode_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("consumer_mode_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("tier_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("webrtc_stats", _params, socket), do: {:noreply, socket}

  # Client health monitoring - adapts data stream quality based on client performance
  #
  # HYBRID QUALITY CONTROL:
  # - ClientHealth is ADVISORY: it sets a "ceiling" for quality
  # - ClientHealth CAN trigger immediate DOWNGRADE (client struggling = fast response)
  # - ClientHealth should NOT trigger UPGRADE (let mailbox-based recovery handle that)
  # - Mailbox-based recovery respects client health ceiling via :check_quality_upgrade
  @impl true
  def handle_event("client_health", report, socket) do
    # Skip automatic quality adjustment if manual override is set
    if socket.assigns[:quality_override] do
      {:noreply, socket}
    else
      client_health = socket.assigns[:client_health] || SensoctoWeb.ClientHealth.init()

      {new_health, quality_changed, new_quality, reason} =
        SensoctoWeb.ClientHealth.process_health_report(client_health, report)

      # Always update client_health state (advisory for upgrade path)
      socket = assign(socket, :client_health, new_health)

      current_quality = socket.assigns[:current_quality] || :high

      # Only apply DOWNGRADES immediately. Upgrades happen via :check_quality_upgrade
      # which respects client health ceiling
      is_downgrade = quality_changed && quality_worse?(new_quality, current_quality)

      socket =
        if is_downgrade do
          Logger.info(
            "ClientHealth downgrade for socket #{socket.id}: #{current_quality} -> #{new_quality}, reason: #{reason}"
          )

          # Immediate downgrade - client is struggling
          if socket.assigns[:priority_lens_registered] do
            Sensocto.Lenses.PriorityLens.set_quality(socket.id, new_quality)
          end

          # Schedule upgrade check to eventually recover
          Process.send_after(self(), :check_quality_upgrade, @upgrade_check_delay_ms)

          socket
          |> assign(:current_quality, new_quality)
          |> push_event("quality_changed", %{level: new_quality, reason: reason})
        else
          socket
        end

      {:noreply, socket}
    end
  end

  # Manual quality override - for testing/demo purposes
  @impl true
  def handle_event("set_quality_override", %{"quality" => "auto"}, socket) do
    # Clear override, return to automatic mode
    socket =
      socket
      |> assign(:quality_override, nil)
      |> push_event("quality_changed", %{level: :auto, reason: "Switched to automatic mode"})

    {:noreply, socket}
  end

  @impl true
  def handle_event("set_quality_override", %{"quality" => quality_str}, socket) do
    quality = String.to_existing_atom(quality_str)

    # Update PriorityLens with the override quality
    if socket.assigns[:priority_lens_registered] do
      Sensocto.Lenses.PriorityLens.set_quality(socket.id, quality)
    end

    socket =
      socket
      |> assign(:quality_override, quality)
      |> assign(:current_quality, quality)
      |> push_event("quality_changed", %{level: quality, reason: "Manual override"})

    {:noreply, socket}
  end

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Lobby Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    # Unregister composite attention views
    cleanup_composite_attention(socket)

    # Unregister from PriorityLens to clean up per-socket state
    if socket.assigns[:priority_lens_registered] do
      Sensocto.Lenses.PriorityLens.unregister_socket(socket.id)
    end

    :ok
  end

  defp cleanup_composite_attention(socket) do
    action = socket.assigns[:live_action]
    viewer_id = socket.id

    sensor_ids =
      case action do
        :heartrate -> Enum.map(socket.assigns[:heartrate_sensors] || [], & &1.sensor_id)
        :ecg -> Enum.map(socket.assigns[:ecg_sensors] || [], & &1.sensor_id)
        :imu -> Enum.map(socket.assigns[:imu_sensors] || [], & &1.sensor_id)
        :location -> Enum.map(socket.assigns[:location_sensors] || [], & &1.sensor_id)
        :battery -> Enum.map(socket.assigns[:battery_sensors] || [], & &1.sensor_id)
        :skeleton -> Enum.map(socket.assigns[:skeleton_sensors] || [], & &1.sensor_id)
        :respiration -> Enum.map(socket.assigns[:respiration_sensors] || [], & &1.sensor_id)
        :hrv -> Enum.map(socket.assigns[:hrv_sensors] || [], & &1.sensor_id)
        _ -> []
      end

    if sensor_ids != [] do
      attr_key = "composite_#{action}"

      Enum.each(sensor_ids, fn sensor_id ->
        Sensocto.AttentionTracker.unregister_view(sensor_id, attr_key, viewer_id)
      end)
    end
  end

  # ==========================================================================
  # PriorityLens Helper Functions
  # ==========================================================================

  # Downgrade quality one level for backpressure handling
  defp downgrade_quality(:high), do: :medium
  defp downgrade_quality(:medium), do: :low
  defp downgrade_quality(:low), do: :minimal
  defp downgrade_quality(:minimal), do: :minimal
  defp downgrade_quality(:paused), do: :paused

  # Upgrade quality one level during recovery (inverse of downgrade)
  defp upgrade_quality(:paused), do: :minimal
  defp upgrade_quality(:minimal), do: :low
  defp upgrade_quality(:low), do: :medium
  defp upgrade_quality(:medium), do: :high
  defp upgrade_quality(:high), do: :high

  # Quality ordering for comparison (lower index = better quality)
  @quality_order [:high, :medium, :low, :minimal, :paused]

  # Returns true if q1 is worse (lower throughput) than q2
  defp quality_worse?(q1, q2) do
    idx1 = Enum.find_index(@quality_order, &(&1 == q1)) || 0
    idx2 = Enum.find_index(@quality_order, &(&1 == q2)) || 0
    idx1 > idx2
  end

  # Maximum send_update calls per batch cycle to prevent overwhelming the system
  @max_updates_per_batch 20

  # Transform lens_batch to push_events for graph view
  # Pushes sensor activity events to trigger node pulsation in the graph
  defp process_lens_batch_for_graph(socket, batch_data) do
    # Rate limit: only push updates for a subset of sensors per batch
    sensors_to_update =
      batch_data
      |> Map.keys()
      |> Enum.take(@max_updates_per_batch)

    Enum.reduce(sensors_to_update, socket, fn sensor_id, acc ->
      attributes = Map.get(batch_data, sensor_id, %{})

      # Push a graph_activity event for the sensor with its updated attributes
      push_event(acc, "graph_activity", %{
        sensor_id: sensor_id,
        attribute_ids: Map.keys(attributes),
        timestamp: System.system_time(:millisecond)
      })
    end)
  end

  # Transform lens_batch to push_events for sensors view
  # With LiveComponents, we send updates directly to the component instead of push_event
  # Rate-limited to @max_updates_per_batch to prevent overwhelming slow clients
  defp process_lens_batch_for_sensors(socket, batch_data) do
    # Get visible sensor range to only update visible components
    {start_idx, end_idx} = socket.assigns.visible_range

    # Guard against invalid range (start > end can happen during rapid scrolling)
    count = max(0, end_idx - start_idx)
    visible_sensor_ids = socket.assigns.sensor_ids |> Enum.slice(start_idx, count)

    # Only process sensors that appear in this batch AND are visible
    # This reduces unnecessary work when batch_data is sparse
    sensors_with_data = Map.keys(batch_data) |> MapSet.new()

    # Debug: Check if web connector sensor has button data in this batch
    web_connector_id = "46991438cf49"

    if Map.has_key?(batch_data, web_connector_id) do
      sensor_attrs = Map.get(batch_data, web_connector_id, %{})
      attr_keys = Map.keys(sensor_attrs)
      Logger.debug("LobbyLive: Web connector attrs in batch: #{inspect(attr_keys)}")

      button_data = Map.get(sensor_attrs, "button")

      if button_data do
        Logger.debug("LobbyLive: Web connector button data: #{inspect(button_data)}")
        is_visible = web_connector_id in visible_sensor_ids

        Logger.debug(
          "LobbyLive: visible_range=#{inspect({start_idx, end_idx})}, sensor in visible=#{is_visible}"
        )
      end
    end

    # Filter to visible sensors with data, then rate-limit
    sensors_to_update =
      visible_sensor_ids
      |> Enum.filter(&MapSet.member?(sensors_with_data, &1))
      |> Enum.take(@max_updates_per_batch)

    # Also find non-visible sensors that have button data - buttons need instant feedback
    # even when the sensor card isn't visible (summary bar shows button state)
    non_visible_sensors_with_buttons =
      batch_data
      |> Enum.filter(fn {sensor_id, attrs} ->
        not MapSet.member?(MapSet.new(visible_sensor_ids), sensor_id) and
          Map.has_key?(attrs, "button")
      end)
      |> Enum.map(fn {sensor_id, _} -> sensor_id end)

    # Combine visible sensors + non-visible sensors with button data
    all_sensors_to_update = sensors_to_update ++ non_visible_sensors_with_buttons

    Enum.each(all_sensors_to_update, fn sensor_id ->
      attributes = Map.get(batch_data, sensor_id, %{})

      measurements =
        Enum.flat_map(attributes, fn {attr_id, m} ->
          # Handle both single measurements and lists (for high-frequency data like ECG)
          case m do
            list when is_list(list) ->
              Enum.map(list, fn item ->
                %{attribute_id: attr_id, payload: item.payload, timestamp: item.timestamp}
                |> maybe_add_event(item)
              end)

            single ->
              [
                %{attribute_id: attr_id, payload: single.payload, timestamp: single.timestamp}
                |> maybe_add_event(single)
              ]
          end
        end)

      send_update(StatefulSensorComponent,
        id: "sensor_#{sensor_id}",
        measurements_batch: measurements
      )
    end)

    socket
  end

  # Add event field to measurement if present (for button press/release)
  # Handles both atom and string keys for robustness
  defp maybe_add_event(measurement, source) do
    event = Map.get(source, :event) || Map.get(source, "event")

    case event do
      nil -> measurement
      e -> Map.put(measurement, :event, e)
    end
  end

  # Transform lens_batch to push_events for composite views
  defp process_lens_batch_for_composite(socket, batch_data, action) do
    # Map action to attribute type
    attr_type =
      case action do
        :heartrate -> ["heartrate", "hr"]
        :ecg -> ["ecg"]
        :imu -> ["imu"]
        :location -> ["geolocation"]
        :battery -> ["battery"]
        :skeleton -> ["skeleton"]
        :respiration -> ["respiration"]
        :hrv -> ["hrv"]
      end

    Enum.reduce(batch_data, socket, fn {sensor_id, attributes}, acc ->
      # Filter to relevant attributes for this composite view
      relevant =
        Enum.filter(attributes, fn {attr_id, _m} ->
          attr_id in attr_type or String.contains?(attr_id, attr_type)
        end)

      Enum.reduce(relevant, acc, fn {attr_id, m}, sock ->
        # Handle both single measurements and lists (for high-frequency data like ECG)
        case m do
          list when is_list(list) ->
            # Push each measurement in the list
            Enum.reduce(list, sock, fn item, inner_sock ->
              push_event(inner_sock, "composite_measurement", %{
                sensor_id: sensor_id,
                attribute_id: attr_id,
                payload: item.payload,
                timestamp: item.timestamp
              })
            end)

          single ->
            push_event(sock, "composite_measurement", %{
              sensor_id: sensor_id,
              attribute_id: attr_id,
              payload: single.payload,
              timestamp: single.timestamp
            })
        end
      end)
    end)
  end

  # Transform lens_digest to push_events for composite views
  defp process_lens_digest_for_composite(socket, digests, action) do
    attr_type =
      case action do
        :heartrate -> ["heartrate", "hr"]
        :battery -> ["battery"]
        :respiration -> ["respiration"]
        :hrv -> ["hrv"]
        _ -> []
      end

    Enum.reduce(digests, socket, fn {sensor_id, attributes}, acc ->
      relevant =
        Enum.filter(attributes, fn {attr_id, _stats} ->
          attr_id in attr_type or String.contains?(attr_id, attr_type)
        end)

      Enum.reduce(relevant, acc, fn {attr_id, stats}, sock ->
        # For digest mode, push the latest value as if it were a measurement
        push_event(sock, "composite_measurement", %{
          sensor_id: sensor_id,
          attribute_id: attr_id,
          payload: stats.latest,
          timestamp: System.system_time(:millisecond)
        })
      end)
    end)
  end

  # Compute Kuramoto phase sync from batch data and store in AttributeStoreTiered
  defp maybe_compute_and_store_sync(socket, batch_data, action)
       when action in [:respiration, :hrv] do
    {attr_filter, sync_attr_id, buffer_size, min_buffer_len} =
      case action do
        :respiration -> {["respiration"], "breathing_sync", @breathing_phase_buffer_size, 15}
        :hrv -> {["hrv"], "hrv_sync", @hrv_phase_buffer_size, 8}
      end

    phase_buffers = socket.assigns.sync_phase_buffers

    # Update phase buffers with new values from batch
    phase_buffers =
      Enum.reduce(batch_data, phase_buffers, fn {sensor_id, attributes}, buffers ->
        relevant =
          Enum.filter(attributes, fn {attr_id, _} -> attr_id in attr_filter end)

        Enum.reduce(relevant, buffers, fn {_attr_id, m}, bufs ->
          values =
            case m do
              list when is_list(list) ->
                Enum.map(list, &extract_sync_value(&1.payload))

              single ->
                [extract_sync_value(single.payload)]
            end

          buffer = Map.get(bufs, sensor_id, [])
          buffer = buffer ++ values

          buffer =
            if length(buffer) > buffer_size,
              do: Enum.take(buffer, -buffer_size),
              else: buffer

          Map.put(bufs, sensor_id, buffer)
        end)
      end)

    # Compute Kuramoto phase sync
    phases =
      phase_buffers
      |> Map.values()
      |> Enum.map(fn buffer ->
        if length(buffer) >= min_buffer_len, do: estimate_phase(buffer), else: nil
      end)
      |> Enum.reject(&is_nil/1)

    sync_smoothed_map = socket.assigns.sync_smoothed

    if length(phases) >= 2 do
      n = length(phases)

      sum_cos =
        Enum.reduce(phases, 0.0, fn theta, acc -> acc + :math.cos(theta) end)

      sum_sin =
        Enum.reduce(phases, 0.0, fn theta, acc -> acc + :math.sin(theta) end)

      r = :math.sqrt(:math.pow(sum_cos / n, 2) + :math.pow(sum_sin / n, 2))

      prev = Map.get(sync_smoothed_map, action, 0.0)
      smoothed = if prev == 0.0, do: r, else: 0.85 * prev + 0.15 * r
      sync_value = round(smoothed * 100)
      sync_smoothed_map = Map.put(sync_smoothed_map, action, smoothed)

      timestamp = System.system_time(:millisecond)

      Sensocto.AttributeStoreTiered.put_attribute(
        "__composite_sync",
        sync_attr_id,
        timestamp,
        sync_value
      )

      socket
      |> assign(:sync_phase_buffers, phase_buffers)
      |> assign(:sync_smoothed, sync_smoothed_map)
    else
      socket
      |> assign(:sync_phase_buffers, phase_buffers)
      |> assign(:sync_smoothed, sync_smoothed_map)
    end
  end

  defp maybe_compute_and_store_sync(socket, _batch_data, _action), do: socket

  defp extract_sync_value(payload) when is_number(payload), do: payload * 1.0

  defp extract_sync_value(payload) when is_map(payload) do
    val = payload["value"] || payload["v"] || payload[:value]
    if is_number(val), do: val * 1.0, else: 0.0
  end

  defp extract_sync_value(_), do: 0.0

  # Estimate instantaneous phase from a rolling buffer of sensor values.
  # Uses normalized value + derivative direction to map to [0, 2*pi].
  defp estimate_phase(buffer) do
    n = length(buffer)
    {min_val, max_val} = Enum.min_max(buffer)
    range = max_val - min_val

    if range < 2 do
      nil
    else
      current = List.last(buffer)
      norm = max(0.0, min(1.0, (current - min_val) / range))

      lookback = min(5, n - 1)
      derivative = current - Enum.at(buffer, n - 1 - lookback)

      base_angle = :math.acos(1 - 2 * norm)
      if derivative >= 0, do: base_angle, else: 2 * :math.pi() - base_angle
    end
  end

  # Release control for a specific mode when user navigates away
  # Playback continues without a controller - anyone can then take control
  defp release_control_for_mode(:media, user_id) do
    alias Sensocto.Media.MediaPlayerServer
    MediaPlayerServer.release_control(:lobby, user_id)
  rescue
    _ -> :ok
  end

  defp release_control_for_mode(:object3d, user_id) do
    alias Sensocto.Object3D.Object3DPlayerServer
    Object3DPlayerServer.release_control(:lobby, user_id)
  rescue
    _ -> :ok
  end

  defp release_control_for_mode(:whiteboard, user_id) do
    alias Sensocto.Whiteboard.WhiteboardServer
    WhiteboardServer.release_control(:lobby, user_id)
  rescue
    _ -> :ok
  end

  defp release_control_for_mode(_mode, _user_id), do: :ok
end

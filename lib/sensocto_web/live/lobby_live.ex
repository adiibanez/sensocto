defmodule SensoctoWeb.LobbyLive do
  @moduledoc """
  Full-page view of all sensors in the lobby.
  Shows all sensors from the SensorsDynamicSupervisor with real-time updates.
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  use Sensocto.Chat.AIChatHandler
  import SensoctoWeb.LiveHelpers.SensorData
  import SensoctoWeb.LobbyLive.Components
  import SensoctoWeb.LobbyLive.LensComponents
  import SensoctoWeb.LobbyLive.FloatingDockComponents
  alias SensoctoWeb.StatefulSensorLive
  # Used in template when @use_sensor_components is true
  alias SensoctoWeb.Live.Components.StatefulSensorComponent, warn: false
  # Used in hook modules, kept for potential future use in this module
  alias SensoctoWeb.Live.Components.MediaPlayerComponent, warn: false
  alias SensoctoWeb.Live.Components.Object3DPlayerComponent, warn: false
  alias SensoctoWeb.Live.Components.WhiteboardComponent, warn: false
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
  @default_row_height 90
  # Preload more sensors initially for smoother experience
  @default_visible_count 72

  # Performance monitoring: batch flush interval in ms
  # Measurements are buffered and flushed at this interval to reduce push_event calls
  @measurement_flush_interval_ms 50

  # Performance telemetry: log interval in ms
  @perf_log_interval_ms 5_000

  # Suppress unused warnings - these are used in handle_info callbacks
  _ = @measurement_flush_interval_ms
  _ = @perf_log_interval_ms
  _ = @use_sensor_components
  _ = @component_flush_interval_ms

  @impl true
  def mount(_params, _session, socket) do
    start = System.monotonic_time()

    # Subscribe only when connected (avoid double subscription on disconnected + connected mount)
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "presence:all")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:lobby")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "lobby:favorites")
    end

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)
    # Extract stable list of sensor IDs - only changes when sensors are added/removed
    sensor_ids = sort_sensors(Map.keys(sensors), sensors, :activity)

    # Calculate max attributes across all sensors for view mode decision
    max_attributes = calculate_max_attributes(sensors)

    # Determine view mode: normal for <=3 sensors with few attributes, summary otherwise
    default_view_mode = determine_view_mode(sensors_count, max_attributes)

    # Extract composite visualization data (needs full sensors with lastvalue)
    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors, gaze_sensors} =
      extract_composite_data(sensors)

    # Strip values lists from sensors before storing on socket (only lastvalue is read)
    sensors = strip_sensor_values(sensors)

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
        hrv_sensors,
        gaze_sensors
      )

    # Group sensors by connector (user)
    sensors_by_user = group_sensors_by_user(sensors)

    # Defer DB queries to connected mount — avoid running them twice (disconnected + connected)
    user = socket.assigns[:current_user]

    {public_rooms, favorite_sensors} =
      if connected?(socket) and user do
        {Sensocto.Rooms.list_public_rooms(),
         UserPreferences.get_ui_state(user.id, "favorite_sensors", [])}
      else
        {[], []}
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
        sensor_ids: sensor_ids,
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
        gaze_sensors: gaze_sensors,
        available_lenses: available_lenses,
        sensors_by_user: sensors_by_user,
        favorite_sensors: favorite_sensors,
        public_rooms: public_rooms,
        show_join_modal: false,
        join_code: "",
        # Call-related assigns
        lobby_layout: :stacked,
        floating_expanded_sensors: [],
        floating_dock_collapsed: false,
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
        avatar_bump: false,
        avatar_fullscreen: false,
        avatar_world: :bioluminescent,
        avatar_wind: 50,
        avatar_controller_user_id: nil,
        avatar_controller_user_name: nil,
        avatar_pending_request_user_id: nil,
        avatar_pending_request_user_name: nil,
        # Lobby mode presence counts
        media_viewers: 0,
        object3d_viewers: 0,
        whiteboard_viewers: 0,
        avatar_viewers: 0,
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
        # Performance stats for telemetry
        perf_stats: %{
          handle_info_count: 0,
          handle_info_total_us: 0,
          handle_info_max_us: 0,
          push_event_count: 0,
          last_report_time: System.monotonic_time(:millisecond)
        },
        # Sort mode for sensor grid (:activity, :name, :type, :battery)
        sort_by: :name,
        # Timer for debouncing activity re-sort on attention changes
        sort_timer: nil,
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
        # Guided session state (nil when no active session)
        guided_session: nil,
        guiding_session: nil,
        available_guided_session: nil,
        show_guide_modal: false,
        guide_invite_code: nil,
        guide_share_url: nil,
        guided_following: true,
        guided_presence: %{guide_connected: false, follower_connected: false},
        guided_annotations: [],
        guided_suggestion: nil,
        guided_focused_sensor_id: nil,
        guide_panel_expanded: true
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
        {media_count, object3d_count, whiteboard_count, avatar_count} =
          count_room_mode_presence("lobby")

        {synced_users, solo_users} = get_sync_mode_users("lobby")

        # Schedule single refresh to catch late-registered attributes (2s after mount)
        Process.send_after(self(), :refresh_available_lenses, 2000)

        # Start performance logging timer
        Process.send_after(self(), :log_perf_stats, @perf_log_interval_ms)

        # Register with PriorityLens for adaptive data streaming
        # Does NOT subscribe to the PubSub topic here — ViewerDataChannel handles composite/graph
        # delivery. LobbyLive only subscribes in sensors grid view (see update_lens_subscription/2).
        {priority_lens_registered, priority_lens_topic} =
          case Sensocto.Lenses.PriorityLens.register_socket(
                 new_socket.id,
                 sensor_ids,
                 quality: :high
               ) do
            {:ok, topic} ->
              {true, topic}

            {:error, reason} ->
              Logger.warning("Failed to register with PriorityLens: #{inspect(reason)}")
              {false, nil}
          end

        # Schedule the viewer token push after the first render so the
        # CompositeMeasurementHandler hook's handleEvent is registered when it arrives.
        if priority_lens_registered do
          send(self(), :push_viewer_token)
        end

        viewer_channel_socket = new_socket

        viewer_channel_socket
        |> assign(:presence_key, presence_key)
        |> assign(:media_viewers, media_count)
        |> assign(:object3d_viewers, object3d_count)
        |> assign(:whiteboard_viewers, whiteboard_count)
        |> assign(:avatar_viewers, avatar_count)
        |> assign(:synced_users, synced_users)
        |> assign(:solo_users, solo_users)
        |> assign(:priority_lens_registered, priority_lens_registered)
        |> assign(:priority_lens_topic, priority_lens_topic)
        |> assign(:lens_locally_subscribed, false)
      else
        assign(new_socket, :presence_key, presence_key)
      end

    :telemetry.execute(
      [:sensocto, :live, :lobby, :mount],
      %{duration: System.monotonic_time() - start},
      %{}
    )

    # Defer non-essential subscriptions to after first render
    send(self(), :deferred_subscriptions)

    # Attach hooks to delegate handler groups to separate modules
    new_socket =
      new_socket
      |> attach_hook(
        :media,
        :handle_info,
        &SensoctoWeb.LobbyLive.Hooks.MediaHook.on_handle_info/2
      )
      |> attach_hook(
        :object3d,
        :handle_info,
        &SensoctoWeb.LobbyLive.Hooks.Object3DHook.on_handle_info/2
      )
      |> attach_hook(
        :whiteboard,
        :handle_info,
        &SensoctoWeb.LobbyLive.Hooks.WhiteboardHook.on_handle_info/2
      )
      |> attach_hook(:call, :handle_info, &SensoctoWeb.LobbyLive.Hooks.CallHook.on_handle_info/2)
      |> attach_hook(
        :guided,
        :handle_info,
        &SensoctoWeb.LobbyLive.Hooks.GuidedSessionHook.on_handle_info/2
      )
      |> attach_hook(
        :avatar,
        :handle_info,
        &SensoctoWeb.LobbyLive.Hooks.AvatarHook.on_handle_info/2
      )

    {:ok, new_socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    action = socket.assigns.live_action

    # Dynamic page title per lens view
    socket = assign(socket, :page_title, lens_page_title(action))

    # Update PriorityLens focused sensor based on current view
    # ECG needs full data fidelity for waveform visualization
    socket = update_lens_focus_for_action(socket, action)

    # Manage PubSub subscription: only subscribe in sensors grid view.
    # Composite/graph views use ViewerDataChannel — data never touches the LV mailbox.
    socket = update_lens_subscription(socket, action)

    # Async historical data loading — view renders immediately, data fills in
    socket = start_seed_data_async(socket, action)

    # Re-push the viewer channel token for every composite/graph navigation.
    # The CompositeMeasurementHandler hook is conditionally rendered (:if={@live_action == :x}),
    # so it is destroyed and re-mounted on each view change. The freshly-mounted hook
    # needs the token to join ViewerDataChannel. Push events are delivered after the DOM
    # patch so the hook's handleEvent is registered before the event fires.
    socket = push_viewer_token_for_composite(socket, action)

    {:noreply, socket}
  end

  # All views including sensors: push token so SensorGridHook / CompositeMeasurementHandler
  # can join ViewerDataChannel after each handle_params (hook elements are destroyed/remounted).
  # Composite/graph views: re-push the signed token so the freshly-mounted
  # CompositeMeasurementHandler hook can join ViewerDataChannel.
  defp push_viewer_token_for_composite(socket, _action) do
    if socket.assigns[:priority_lens_registered] do
      viewer_token = Phoenix.Token.sign(SensoctoWeb.Endpoint, "viewer_data", socket.id)
      push_event(socket, "viewer_channel_token", %{token: viewer_token})
    else
      socket
    end
  end

  # Avatar tab: push viewer token so CompositeMeasurementHandler can join ViewerDataChannel.
  defp push_viewer_token_for_avatar(socket) do
    if socket.assigns[:priority_lens_registered] do
      viewer_token = Phoenix.Token.sign(SensoctoWeb.Endpoint, "viewer_data", socket.id)
      push_event(socket, "viewer_channel_token", %{token: viewer_token})
    else
      socket
    end
  end

  # Avatar tab: register attention views for IMU + heartrate + respiration sensors
  # so they broadcast to data:attention:* and flow through PriorityLens → ViewerDataChannel.
  defp ensure_attention_for_avatar(socket) do
    viewer_id = socket.id

    sensor_ids =
      Enum.uniq(
        Enum.map(socket.assigns[:imu_sensors] || [], & &1.sensor_id) ++
          Enum.map(socket.assigns[:heartrate_sensors] || [], & &1.sensor_id) ++
          Enum.map(socket.assigns[:respiration_sensors] || [], & &1.sensor_id)
      )

    Enum.each(sensor_ids, fn sensor_id ->
      Sensocto.AttentionTracker.register_view(sensor_id, "composite_avatar", viewer_id)
    end)

    socket
  end

  # Avatar tab: unregister attention views when leaving avatar mode.
  defp cleanup_avatar_attention(socket) do
    viewer_id = socket.id

    sensor_ids =
      Enum.uniq(
        Enum.map(socket.assigns[:imu_sensors] || [], & &1.sensor_id) ++
          Enum.map(socket.assigns[:heartrate_sensors] || [], & &1.sensor_id) ++
          Enum.map(socket.assigns[:respiration_sensors] || [], & &1.sensor_id)
      )

    Enum.each(sensor_ids, fn sensor_id ->
      Sensocto.AttentionTracker.unregister_view(sensor_id, "composite_avatar", viewer_id)
    end)

    socket
  end

  # Sensors grid view: LobbyLive subscribes so it can call send_update on LiveComponents
  defp update_lens_subscription(socket, :sensors) do
    topic = socket.assigns[:priority_lens_topic]

    if topic && !socket.assigns[:lens_locally_subscribed] do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)
      assign(socket, :lens_locally_subscribed, true)
    else
      socket
    end
  end

  # All composite and graph views: ViewerDataChannel delivers data directly to browser.
  # LobbyLive unsubscribes so its mailbox stays clean.
  # Exception: floating mode with expanded tiles needs subscription for send_update.
  defp update_lens_subscription(socket, _action) do
    topic = socket.assigns[:priority_lens_topic]

    if socket.assigns.lobby_layout == :floating &&
         socket.assigns.floating_expanded_sensors != [] do
      # Stay subscribed for floating expanded tiles
      if topic && !socket.assigns[:lens_locally_subscribed] do
        Phoenix.PubSub.subscribe(Sensocto.PubSub, topic)
        assign(socket, :lens_locally_subscribed, true)
      else
        socket
      end
    else
      if topic && socket.assigns[:lens_locally_subscribed] do
        Phoenix.PubSub.unsubscribe(Sensocto.PubSub, topic)
        assign(socket, :lens_locally_subscribed, false)
      else
        socket
      end
    end
  end

  defp lens_page_title(:heartrate), do: "Heartrate"
  defp lens_page_title(:ecg), do: "ECG"
  defp lens_page_title(:respiration), do: "Breathing"
  defp lens_page_title(:hrv), do: "HRV"
  defp lens_page_title(:imu), do: "Motion"
  defp lens_page_title(:location), do: "Geolocation"
  defp lens_page_title(:battery), do: "Battery"
  defp lens_page_title(:skeleton), do: "Skeleton"
  defp lens_page_title(:gaze), do: "Gaze"
  defp lens_page_title(:graph), do: "Graph"
  defp lens_page_title(:graph3d), do: "3D Graph"
  defp lens_page_title(:hierarchy), do: "Hierarchy"
  defp lens_page_title(_), do: "Lobby"

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

          # ECG needs high fidelity
          Sensocto.Lenses.PriorityLens.set_quality(socket.id, :high)

        :gaze ->
          # Gaze visualization smoothly interpolates — medium quality is sufficient
          Sensocto.Lenses.PriorityLens.set_focused_sensor(socket.id, nil)
          Sensocto.Lenses.PriorityLens.set_quality(socket.id, :medium)

        action when action in [:graph, :graph3d] ->
          # Graph only needs activity indicators, not waveform data.
          # Medium quality (50ms flush) saves ~40% PriorityLens load per viewer
          # vs high (32ms flush) with no visible difference in pulsation.
          Sensocto.Lenses.PriorityLens.set_focused_sensor(socket.id, nil)
          Sensocto.Lenses.PriorityLens.set_quality(socket.id, :medium)

        _ ->
          # Clear focus for other views, restore high quality
          Sensocto.Lenses.PriorityLens.set_focused_sensor(socket.id, nil)
          Sensocto.Lenses.PriorityLens.set_quality(socket.id, :high)
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
       when action in [
              :heartrate,
              :ecg,
              :imu,
              :location,
              :battery,
              :skeleton,
              :respiration,
              :hrv,
              :gaze,
              :graph,
              :graph3d
            ] do
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
        :gaze -> Enum.map(socket.assigns.gaze_sensors, & &1.sensor_id)
        action when action in [:graph, :graph3d] -> socket.assigns.sensor_ids
      end

    attr_key = "composite_#{action}"

    # Use bulk registration for graph (all sensors) to avoid thundering herd.
    # Single cast vs N individual casts — critical when N > 50 sensors.
    if action in [:graph, :graph3d] do
      Sensocto.AttentionTracker.register_views_bulk(sensor_ids, attr_key, viewer_id)
    else
      Enum.each(sensor_ids, fn sensor_id ->
        Sensocto.AttentionTracker.register_view(sensor_id, attr_key, viewer_id)
      end)
    end

    # Activate SyncComputer when viewing breathing/HRV (demand-driven)
    # For :graph, SyncComputer activates on-demand via midi_toggled event
    if action in [:respiration, :hrv] do
      Sensocto.Bio.SyncComputer.register_viewer()
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "sync:updates")
    end
  end

  defp ensure_attention_for_composite_sensors(_socket, _action), do: :ok

  # Kick off async historical data loading for composite lens views.
  # The view renders immediately; seed data arrives via handle_async.
  defp start_seed_data_async(socket, action)
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

    sync_attr_id =
      case action do
        :respiration -> "breathing_sync"
        :hrv -> "hrv_sync"
        _ -> nil
      end

    start_async(socket, :seed_composite_data, fn ->
      # Collect all seed events as data (no socket access in async task)
      events =
        Enum.flat_map(sensor_ids, fn sensor_id ->
          Enum.flat_map(attr_ids, fn attr_id ->
            case Sensocto.AttributeStoreTiered.get_attribute(
                   sensor_id,
                   attr_id,
                   0,
                   :infinity,
                   500
                 ) do
              {:ok, data} when data != [] ->
                [
                  %{
                    sensor_id: sensor_id,
                    attribute_id: attr_id,
                    data: Enum.map(data, &%{payload: &1.payload, timestamp: &1.timestamp})
                  }
                ]

              _ ->
                []
            end
          end)
        end)

      # Also fetch sync history for breathing/HRV
      sync_events =
        if sync_attr_id do
          case Sensocto.AttributeStoreTiered.get_attribute(
                 "__composite_sync",
                 sync_attr_id,
                 0,
                 :infinity,
                 500
               ) do
            {:ok, data} when data != [] ->
              [
                %{
                  sensor_id: "__composite_sync",
                  attribute_id: sync_attr_id,
                  data: Enum.map(data, &%{payload: &1.payload, timestamp: &1.timestamp})
                }
              ]

            _ ->
              []
          end
        else
          []
        end

      events ++ sync_events
    end)
  end

  defp start_seed_data_async(socket, _action), do: socket

  @impl true
  def handle_async(:seed_composite_data, {:ok, events}, socket) do
    socket =
      Enum.reduce(events, socket, fn event, acc ->
        push_event(acc, "composite_seed_data", event)
      end)

    {:noreply, socket}
  end

  def handle_async(:seed_composite_data, {:exit, reason}, socket) do
    Logger.warning("[LobbyLive] Seed data async failed: #{inspect(reason)}")
    {:noreply, socket}
  end

  def handle_async(:refresh_sensors, {:ok, sensors}, socket) do
    {:noreply, apply_sensors_refresh(socket, sensors)}
  end

  def handle_async(:refresh_sensors, {:exit, _reason}, socket) do
    {:noreply, socket}
  end

  defp calculate_max_attributes(sensors) do
    sensors
    |> Enum.map(fn {_id, sensor} -> map_size(sensor.attributes || %{}) end)
    |> Enum.max(fn -> 0 end)
  end

  # Sort sensor IDs by the chosen strategy
  # All modes use sensor_name as secondary sort for stability
  @doc false
  def sort_sensors(sensor_ids, sensors, sort_by) do
    case sort_by do
      :activity ->
        Enum.sort_by(sensor_ids, fn sid ->
          level = Sensocto.AttentionTracker.get_sensor_attention_level(sid)
          pri = %{high: 0, medium: 1, low: 2, none: 3}
          sensor = Map.get(sensors, sid, %{})
          name = Map.get(sensor, :sensor_name, sid)
          {Map.get(pri, level, 3), name}
        end)

      :name ->
        Enum.sort_by(sensor_ids, fn sid ->
          sensor = Map.get(sensors, sid, %{})
          (Map.get(sensor, :sensor_name, sid) || sid) |> String.downcase()
        end)

      :type ->
        Enum.sort_by(sensor_ids, fn sid ->
          sensor = Map.get(sensors, sid, %{})
          type = (Map.get(sensor, :sensor_type, "unknown") || "unknown") |> String.downcase()
          name = (Map.get(sensor, :sensor_name, sid) || sid) |> String.downcase()
          {type, name}
        end)

      :battery ->
        Enum.sort_by(sensor_ids, fn sid ->
          sensor = Map.get(sensors, sid, %{})
          name = Map.get(sensor, :sensor_name, sid) || sid
          {extract_battery_level(sensor), name}
        end)

      _ ->
        Enum.sort(sensor_ids)
    end
  end

  defp extract_battery_level(sensor) do
    attrs = Map.get(sensor, :attributes, %{}) || %{}

    case Enum.find(attrs, fn {_attr_id, attr} -> attr.attribute_type == "battery" end) do
      {_attr_id, attr} ->
        payload = attr.lastvalue && attr.lastvalue.payload

        cond do
          is_map(payload) -> payload["level"] || payload[:level] || 999
          is_number(payload) -> payload
          true -> 999
        end

      nil ->
        999
    end
  end

  # Schedule a debounced re-sort when attention changes (only for :activity sort)
  defp maybe_schedule_resort(socket) do
    if socket.assigns[:sort_by] == :activity do
      if timer = socket.assigns[:sort_timer], do: Process.cancel_timer(timer)
      timer = Process.send_after(self(), :resort_sensors, 1500)
      assign(socket, :sort_timer, timer)
    else
      socket
    end
  end

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

    Enum.reduce(presences, {0, 0, 0, 0}, fn {_user_id, %{metas: metas}},
                                            {media, object3d, whiteboard, avatar} ->
      # Get the most recent presence meta (last one)
      case List.last(metas) do
        %{room_mode: :media} -> {media + 1, object3d, whiteboard, avatar}
        %{room_mode: :object3d} -> {media, object3d + 1, whiteboard, avatar}
        %{room_mode: :whiteboard} -> {media, object3d, whiteboard + 1, avatar}
        %{room_mode: :avatar} -> {media, object3d, whiteboard, avatar + 1}
        _ -> {media, object3d, whiteboard, avatar}
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

  # Strip `values` lists from sensor attributes before storing on socket.
  # Only `lastvalue` is needed for rendering — `values` is never read from @sensors.
  defp strip_sensor_values(sensors) do
    Map.new(sensors, fn {sensor_id, sensor} ->
      stripped_attrs =
        Map.new(sensor.attributes || %{}, fn {attr_id, attr_data} ->
          {attr_id, Map.delete(attr_data, :values)}
        end)

      {sensor_id, %{sensor | attributes: stripped_attrs}}
    end)
  end

  defp apply_sensors_refresh(socket, sensors) do
    # Extract composite data from full sensors (needs lastvalue), then strip for assign
    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors, gaze_sensors} =
      extract_composite_data(sensors)

    sensors = strip_sensor_values(sensors)

    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors,
        respiration_sensors,
        hrv_sensors,
        gaze_sensors
      )

    sorted_sensor_ids =
      sort_sensors(Map.keys(sensors), sensors, socket.assigns[:sort_by] || :name)

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
    |> assign(:gaze_sensors, gaze_sensors)
    |> assign(:available_lenses, available_lenses)
    |> assign(:sensors_by_user, group_sensors_by_user(sensors))
    |> assign(:sensor_ids, sorted_sensor_ids)
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

    gaze_sensors =
      sensors
      |> Enum.filter(fn {_id, sensor} ->
        attrs = sensor.attributes || %{}

        Enum.any?(attrs, fn {_attr_id, attr} ->
          attr.attribute_type in ["eye_gaze", "eye_aperture", "eye_blink", "eye_worn"]
        end)
      end)
      |> Enum.map(fn {sensor_id, sensor} ->
        attrs = sensor.attributes || %{}

        gaze_val = extract_attr_payload(attrs, "eye_gaze")
        aperture_val = extract_attr_payload(attrs, "eye_aperture")
        blink_val = extract_attr_payload(attrs, "eye_blink")
        worn_val = extract_attr_payload(attrs, "eye_worn")

        %{
          sensor_id: sensor_id,
          sensor_name: sensor.sensor_name,
          gaze_x: get_map_val(gaze_val, :x, "x", 0.5),
          gaze_y: get_map_val(gaze_val, :y, "y", 0.5),
          confidence: get_map_val(gaze_val, :confidence, "confidence", 0.0),
          aperture_left: get_map_val(aperture_val, :left, "left", 15.0),
          aperture_right: get_map_val(aperture_val, :right, "right", 15.0),
          blinking: if(is_number(blink_val), do: blink_val, else: 0.0),
          worn: if(is_number(worn_val), do: worn_val, else: 1.0)
        }
      end)

    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors, respiration_sensors, hrv_sensors, gaze_sensors}
  end

  defp extract_attr_payload(attrs, type) do
    case Enum.find(attrs, fn {_attr_id, attr} -> attr.attribute_type == type end) do
      {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || nil
      nil -> nil
    end
  end

  defp get_map_val(nil, _atom_key, _str_key, default), do: default
  defp get_map_val(val, _atom_key, _str_key, _default) when not is_map(val), do: val

  defp get_map_val(map, atom_key, str_key, default) do
    Map.get(map, atom_key) || Map.get(map, str_key) || default
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
         hrv_sensors,
         gaze_sensors
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
    lenses = if length(gaze_sensors) > 0, do: [:gaze | lenses], else: lenses
    # Graph lenses are always available (they show whatever sensors are present)
    lenses = [:graph3d, :graph | lenses]
    Enum.reverse(lenses)
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
    {media_count, object3d_count, whiteboard_count, avatar_count} =
      count_room_mode_presence("lobby")

    {synced_users, solo_users} = get_sync_mode_users("lobby")

    {:noreply,
     socket
     |> assign(:media_viewers, media_count)
     |> assign(:object3d_viewers, object3d_count)
     |> assign(:whiteboard_viewers, whiteboard_count)
     |> assign(:avatar_viewers, avatar_count)
     |> assign(:synced_users, synced_users)
     |> assign(:solo_users, solo_users)}
  end

  # Handle lobby mode sync broadcast — follow synced users' tab switches
  @impl true
  def handle_info(
        {:lobby_mode_sync, %{mode: new_mode, from_user_id: from_user_id}},
        socket
      ) do
    current_user = socket.assigns.current_user
    is_self = current_user && to_string(current_user.id) == to_string(from_user_id)

    if !is_self && socket.assigns.sync_mode == :synced && socket.assigns.lobby_mode != new_mode do
      old_mode = socket.assigns.lobby_mode
      user = socket.assigns.current_user

      # Release control when following a mode switch
      if user do
        release_control_for_mode(old_mode, user.id)
      end

      # Update presence
      presence_key = socket.assigns[:presence_key]

      if user && presence_key do
        Presence.update(self(), "room:lobby:mode_presence", presence_key, %{
          room_mode: new_mode,
          user_id: user.id,
          user_name: Map.get(user, :email) || Map.get(user, :display_name) || "Anonymous",
          sync_mode: socket.assigns.sync_mode
        })
      end

      {:noreply, apply_lobby_mode_switch(socket, new_mode, old_mode)}
    else
      {:noreply, socket}
    end
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

        # Update composite visualization data (needs full sensors)
        {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
         skeleton_sensors, respiration_sensors, hrv_sensors, gaze_sensors} =
          extract_composite_data(sensors)

        # Strip values for socket assign
        sensors = strip_sensor_values(sensors)

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
            hrv_sensors,
            gaze_sensors
          )

        sorted_sensor_ids =
          sort_sensors(new_sensor_ids, sensors, socket.assigns[:sort_by] || :name)

        updated_socket =
          socket
          |> assign(:sensors, sensors)
          |> assign(:sensors_online_count, sensors_count)
          |> assign(:sensor_ids, sorted_sensor_ids)
          |> assign(:heartrate_sensors, heartrate_sensors)
          |> assign(:imu_sensors, imu_sensors)
          |> assign(:location_sensors, location_sensors)
          |> assign(:ecg_sensors, ecg_sensors)
          |> assign(:battery_sensors, battery_sensors)
          |> assign(:skeleton_sensors, skeleton_sensors)
          |> assign(:respiration_sensors, respiration_sensors)
          |> assign(:hrv_sensors, hrv_sensors)
          |> assign(:gaze_sensors, gaze_sensors)
          |> assign(:available_lenses, available_lenses)
          |> assign(:sensors_by_user, group_sensors_by_user(sensors))

        # Update PriorityLens with new sensor list for adaptive streaming
        if updated_socket.assigns[:priority_lens_registered] do
          Sensocto.Lenses.PriorityLens.set_sensors(updated_socket.id, new_sensor_ids)
        end

        # Re-register attention for new sensors so they broadcast to data:attention:*
        # Without this, sensors added after handle_params stay at attention_level :none
        ensure_attention_for_composite_sensors(updated_socket, updated_socket.assigns.live_action)

        {:noreply, updated_socket}
      else
        # Sensor list unchanged - only update count if it actually changed
        # Avoid updating sensors_online map to prevent template re-evaluation
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
    Logger.debug("Lobby handled signal: #{inspect(msg)}")
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
  # Reduced from 15s to 8s — 15s was overly conservative, 8s still prevents oscillation
  @upgrade_check_delay_ms 8_000
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

    # Proactive quality downgrade: when system load is elevated/critical,
    # lower thresholds so degradation kicks in before mailbox fills up
    {backpressure_threshold, critical_threshold} =
      case Sensocto.SystemLoadMonitor.get_load_level() do
        :critical ->
          {div(@mailbox_backpressure_threshold, 4), div(@mailbox_critical_threshold, 4)}

        :high ->
          {div(@mailbox_backpressure_threshold, 3), div(@mailbox_critical_threshold, 3)}

        :elevated ->
          {div(@mailbox_backpressure_threshold, 2), div(@mailbox_critical_threshold, 2)}

        _ ->
          {@mailbox_backpressure_threshold, @mailbox_critical_threshold}
      end

    cond do
      # CRITICAL: Queue is severely backed up - pause entirely
      queue_len > critical_threshold ->
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

      # WARNING: Queue is growing - drain ALL pending batches at once (honey badger)
      queue_len > backpressure_threshold ->
        # Drain every pending {:lens_batch, _} and {:lens_digest, _} from mailbox
        # This is the key fix: instead of processing each message individually
        # (each hitting the backpressure check and wasting cycles), we flush them all
        drained = drain_lens_messages()

        Logger.warning(
          "LobbyLive #{socket.id}: mailbox backpressure (#{queue_len} msgs), drained #{drained} batches"
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
                reason: "Backpressure: drained #{drained} batches, queue was #{queue_len}"
              })
            else
              socket
            end
          else
            socket
          end

        {:noreply, socket}

      # Normal processing — ViewerDataChannel delivers data to all views directly.
      # LobbyLive only receives batches in :sensors view (for backpressure monitoring).
      true ->
        socket = assign(socket, :data_mode, :realtime)
        # Data delivery is handled by ViewerDataChannel → SensorGridHook → DOM.
        # No send_update calls needed here.
        {:noreply, socket}
    end
  end

  # Handle PriorityLens digest data (low/minimal quality)
  # All views receive digest via ViewerDataChannel; LobbyLive only tracks data_mode.
  @impl true
  def handle_info({:lens_digest, _digests}, socket) do
    {:noreply, assign(socket, :data_mode, :digest)}
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

    # Use cached count instead of traversing :pg table on every check
    sensor_count = socket.assigns.sensors_online_count

    sensor_ceiling =
      cond do
        sensor_count >= 40 -> :minimal
        sensor_count >= 20 -> :low
        sensor_count >= 10 -> :medium
        true -> :high
      end

    client_recommended =
      Sensocto.Lenses.PriorityLens.min_quality(client_recommended, sensor_ceiling)

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

  # Media, Object3D, Call, Whiteboard, and Guided Session handlers are now in
  # attach_hook modules under SensoctoWeb.LobbyLive.Hooks.*

  # AttentionTracker crashed and restarted — re-register all composite attention views
  # so GenServer state is rebuilt and sensors keep broadcasting
  @impl true
  def handle_info(:attention_tracker_restarted, socket) do
    Logger.warning("[LobbyLive] AttentionTracker restarted, re-registering attention views")
    ensure_attention_for_composite_sensors(socket, socket.assigns[:live_action])
    {:noreply, socket}
  end

  # Handle sensor attention changes — debounced re-sort for activity mode
  @impl true
  def handle_info({:attention_changed, %{sensor_id: sensor_id, level: level}}, socket) do
    # Push attention changes to graph view for attention radar mode
    socket =
      if socket.assigns.live_action in [:graph, :graph3d] do
        push_event(socket, "attention_changed", %{
          sensor_id: sensor_id,
          level: to_string(level)
        })
      else
        socket
      end

    {:noreply, maybe_schedule_resort(socket)}
  end

  @impl true
  def handle_info(:resort_sensors, socket) do
    sorted =
      sort_sensors(
        socket.assigns.sensor_ids,
        socket.assigns.sensors,
        socket.assigns[:sort_by] || :name
      )

    {:noreply, assign(socket, sensor_ids: sorted, sort_timer: nil)}
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

  # Push the viewer channel token after the first render so the JS hook's handleEvent
  # is registered before the event arrives. The hook uses this token to join ViewerDataChannel.
  def handle_info(:push_viewer_token, socket) do
    socket =
      if socket.assigns[:priority_lens_registered] do
        viewer_token = Phoenix.Token.sign(SensoctoWeb.Endpoint, "viewer_data", socket.id)
        push_event(socket, "viewer_channel_token", %{token: viewer_token})
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info(:deferred_subscriptions, socket) do
    # These subscriptions are deferred from mount to speed up first render.
    # They handle mode-specific features (media, calls, 3D, whiteboard),
    # per-sensor signals, and chat — none needed for the initial render.
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "media:lobby")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "call:lobby")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "object3d:lobby")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "whiteboard:lobby")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "avatar:lobby")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "lobby:mode_sync")
    Sensocto.Chat.ChatStore.subscribe("lobby")

    user = socket.assigns[:current_user]

    socket =
      if user do
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "call:lobby:user:#{user.id}")
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "user:#{user.id}:guidance")
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "lobby:guidance:available")

        # Check for active guided sessions and subscribe
        socket = subscribe_to_guided_session(socket, user)

        # Check for available pending sessions from other guides
        discover_available_guided_session(socket, user)
      else
        socket
      end

    # Per-sensor signal subscriptions (attribute schema change notifications)
    Enum.each(socket.assigns.sensor_ids, fn sensor_id ->
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
    end)

    {:noreply, socket}
  end

  def handle_info(:refresh_available_lenses, socket) do
    {:noreply,
     start_async(socket, :refresh_sensors, fn ->
       Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
     end)}
  end

  # Handle sensor state changes (e.g., new attributes registered)
  # This refreshes available lenses when attributes are auto-registered
  @impl true
  def handle_info({:new_state, _sensor_id}, socket) do
    # Fetch sensors async to avoid blocking the LV process
    {:noreply,
     start_async(socket, :refresh_sensors, fn ->
       Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
     end)}
  end

  # Flush timer removed — sensor data now delivered via ViewerDataChannel → SensorGridHook.

  # SyncComputer broadcasts real-time sync values — push them as composite_measurement
  # so MIDI hook and Svelte components receive breathing_sync/hrv_sync updates
  def handle_info({:sync_update, attr_id, value, timestamp}, socket) do
    socket =
      push_event(socket, "composite_measurement", %{
        sensor_id: "__composite_sync",
        attribute_id: attr_id,
        payload: value,
        timestamp: timestamp
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  # MIDI toggle — activate/deactivate SyncComputer on demand for non-sync views
  @impl true
  def handle_event("midi_toggled", %{"enabled" => enabled}, socket) do
    was_active = socket.assigns[:midi_sync_active] || false

    # Only register/unregister if not already on a sync-native view
    needs_sync = socket.assigns[:live_action] not in [:respiration, :hrv]

    socket =
      cond do
        enabled and !was_active and needs_sync ->
          Sensocto.Bio.SyncComputer.register_viewer()
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "sync:updates")
          assign(socket, :midi_sync_active, true)

        !enabled and was_active and needs_sync ->
          Sensocto.Bio.SyncComputer.unregister_viewer()
          Phoenix.PubSub.unsubscribe(Sensocto.PubSub, "sync:updates")
          assign(socket, :midi_sync_active, false)

        true ->
          socket
      end

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

    if is_nil(user) do
      {:noreply, put_flash(socket, :error, "You must be signed in to join a room")}
    else
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

    # Broadcast mode change to synced users
    if user && socket.assigns.sync_mode == :synced && old_mode != new_mode do
      Phoenix.PubSub.broadcast(Sensocto.PubSub, "lobby:mode_sync", {
        :lobby_mode_sync,
        %{mode: new_mode, from_user_id: user.id}
      })
    end

    {:noreply, apply_lobby_mode_switch(socket, new_mode, old_mode)}
  end

  # --- Avatar ecosystem control ---

  @impl true
  def handle_event("avatar_take_control", _, socket) do
    user = socket.assigns.current_user

    if user do
      user_name =
        Map.get(user, :email) || Map.get(user, :display_name) || Map.get(user, :name) || "Unknown"

      Sensocto.Avatar.AvatarEcosystemServer.take_control(user.id, user_name)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("avatar_release_control", _, socket) do
    user = socket.assigns.current_user

    if user do
      Sensocto.Avatar.AvatarEcosystemServer.release_control(user.id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("avatar_request_control", _, socket) do
    user = socket.assigns.current_user
    controller_user_id = socket.assigns.avatar_controller_user_id

    if user && controller_user_id && to_string(user.id) != to_string(controller_user_id) do
      user_name =
        Map.get(user, :email) || Map.get(user, :display_name) || Map.get(user, :name) ||
          "Someone"

      case Sensocto.Avatar.AvatarEcosystemServer.request_control(user.id, user_name) do
        {:ok, :control_granted} ->
          {:noreply, Phoenix.LiveView.put_flash(socket, :info, "You now have control")}

        {:ok, :request_pending} ->
          {:noreply,
           Phoenix.LiveView.put_flash(
             socket,
             :info,
             "Request sent — control transfers in 30s unless #{socket.assigns.avatar_controller_user_name} keeps control"
           )}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("avatar_keep_control", _, socket) do
    user = socket.assigns.current_user

    if user do
      Sensocto.Avatar.AvatarEcosystemServer.keep_control(user.id)
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("avatar_switch_world", %{"world" => world}, socket) do
    world_atom =
      case world do
        "bioluminescent" -> :bioluminescent
        "inferno" -> :inferno
        "meadow" -> :meadow
        _ -> :bioluminescent
      end

    socket =
      socket
      |> assign(:avatar_world, world_atom)
      |> push_event("avatar_switch_world", %{world: world})

    # Broadcast world change to synced users
    user = socket.assigns.current_user

    if user && socket.assigns.sync_mode == :synced do
      Phoenix.PubSub.broadcast(Sensocto.PubSub, "avatar:lobby", {
        :avatar_world_changed,
        %{world: world, from_user_id: user.id}
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("avatar_set_wind", %{"value" => val}, socket) do
    case Integer.parse(val) do
      {wind, _} when wind in 0..100 ->
        socket =
          socket
          |> assign(:avatar_wind, wind)
          |> push_event("avatar_set_wind", %{value: wind / 100})

        user = socket.assigns.current_user

        if user && socket.assigns.sync_mode == :synced do
          Phoenix.PubSub.broadcast(Sensocto.PubSub, "avatar:lobby", {
            :avatar_wind_changed,
            %{value: wind, from_user_id: user.id}
          })
        end

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_event("avatar_camera_changed", %{"position" => pos, "target" => tgt}, socket) do
    user = socket.assigns.current_user

    if user && socket.assigns.sync_mode == :synced do
      Phoenix.PubSub.broadcast(Sensocto.PubSub, "avatar:lobby", {
        :avatar_camera_changed,
        %{position: pos, target: tgt, from_user_id: user.id}
      })
    end

    {:noreply, socket}
  end

  @impl true
  def handle_event("avatar_toggle_fullscreen", _, socket) do
    fullscreen = !socket.assigns.avatar_fullscreen
    event = if fullscreen, do: "avatar_enter_fullscreen", else: "avatar_exit_fullscreen"

    {:noreply,
     socket
     |> assign(:avatar_fullscreen, fullscreen)
     |> push_event(event, %{})}
  end

  @impl true
  def handle_event("avatar_fullscreen_changed", %{"fullscreen" => state}, socket) do
    {:noreply, assign(socket, :avatar_fullscreen, state)}
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
  def handle_event(
        "toggle_favorite",
        _params,
        %{assigns: %{current_user: %{is_guest: true}}} = socket
      ) do
    {:noreply, socket}
  end

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

  def handle_event("toggle_lobby_layout", _params, socket) do
    new_layout =
      case socket.assigns.lobby_layout do
        :stacked -> :floating
        _ -> :stacked
      end

    socket =
      socket
      |> assign(:lobby_layout, new_layout)
      |> push_event("save_lobby_layout", %{layout: Atom.to_string(new_layout)})

    # Clear expanded sensors when leaving floating mode
    socket =
      if new_layout != :floating,
        do: assign(socket, :floating_expanded_sensors, []),
        else: socket

    {:noreply, socket}
  end

  def handle_event("restore_lobby_layout", %{"layout" => layout}, socket) do
    new_layout =
      case layout do
        "floating" -> :floating
        _ -> :stacked
      end

    {:noreply, assign(socket, :lobby_layout, new_layout)}
  end

  def handle_event("toggle_floating_dock", _params, socket) do
    {:noreply, assign(socket, :floating_dock_collapsed, !socket.assigns.floating_dock_collapsed)}
  end

  def handle_event("float_expand_sensor", %{"sensor-id" => sensor_id}, socket) do
    expanded = socket.assigns.floating_expanded_sensors

    expanded =
      if sensor_id in expanded do
        # Already expanded — collapse it (toggle behavior)
        List.delete(expanded, sensor_id)
      else
        # Add to expanded, cap at 3 (drop oldest)
        new = expanded ++ [sensor_id]
        if length(new) > 3, do: tl(new), else: new
      end

    {:noreply, assign(socket, :floating_expanded_sensors, expanded)}
  end

  def handle_event("float_collapse_sensor", %{"sensor-id" => sensor_id}, socket) do
    expanded = List.delete(socket.assigns.floating_expanded_sensors, sensor_id)
    {:noreply, assign(socket, :floating_expanded_sensors, expanded)}
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

  # Graph node hover → boost attention for that sensor
  @impl true
  def handle_event("graph_hover_enter", %{"sensor_id" => sensor_id}, socket) do
    Sensocto.AttentionTracker.register_hover(sensor_id, "composite_graph", socket.id)
    {:noreply, socket}
  end

  @impl true
  def handle_event("graph_hover_leave", %{"sensor_id" => sensor_id}, socket) do
    Sensocto.AttentionTracker.unregister_hover(sensor_id, "composite_graph", socket.id)
    {:noreply, socket}
  end

  # Minimum attention filter slider
  @impl true
  def handle_event("set_sort", %{"sort" => sort_str}, socket)
      when sort_str in ["activity", "name", "type", "battery"] do
    sort_by = String.to_existing_atom(sort_str)

    sorted =
      sort_sensors(socket.assigns.sensor_ids, socket.assigns.sensors, sort_by)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sensor_ids, sorted)
     |> push_event("save_sort_by", %{sort_by: sort_str})}
  end

  # Restore sort_by from localStorage (via JS hook)
  @impl true
  def handle_event("restore_sort_by", %{"sort_by" => sort_str}, socket)
      when sort_str in ["activity", "name", "type", "battery"] do
    sort_by = String.to_existing_atom(sort_str)

    sorted =
      sort_sensors(socket.assigns.sensor_ids, socket.assigns.sensors, sort_by)

    {:noreply,
     socket
     |> assign(:sort_by, sort_by)
     |> assign(:sensor_ids, sorted)}
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
        "gaze" -> ~p"/lobby/gaze"
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

  # ============================================================================
  # Guided Session Events (from UI)
  # ============================================================================

  def handle_event("start_guided_session", _params, socket) do
    user = socket.assigns[:current_user]

    is_guest = user && Map.get(user, :is_guest, false)

    if user && !is_guest && is_nil(socket.assigns.guiding_session) &&
         is_nil(socket.assigns.guided_session) do
      case Ash.create(Sensocto.Guidance.GuidedSession, %{guide_user_id: user.id},
             action: :create,
             authorize?: false
           ) do
        {:ok, session} ->
          invite_code = session.invite_code
          share_url = SensoctoWeb.Endpoint.url() <> "/guide/join?code=#{invite_code}"

          Sensocto.Guidance.SessionSupervisor.get_or_start_session(session.id,
            guide_user_id: user.id
          )

          Phoenix.PubSub.subscribe(Sensocto.PubSub, "guidance:#{session.id}")
          Sensocto.Guidance.SessionServer.connect(session.id, user.id)

          guide_name = user.display_name || "A guide"

          Phoenix.PubSub.broadcast(
            Sensocto.PubSub,
            "lobby:guidance:available",
            {:guidance_available,
             %{session_id: session.id, guide_user_id: user.id, guide_name: guide_name}}
          )

          {:noreply,
           socket
           |> assign(:guiding_session, session.id)
           |> assign(:show_guide_modal, true)
           |> assign(:guide_invite_code, invite_code)
           |> assign(:guide_share_url, share_url)}

        {:error, reason} ->
          require Logger
          Logger.error("Failed to create guided session: #{inspect(reason)}")
          {:noreply, put_flash(socket, :error, "Failed to start guided session")}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_guide_modal", _params, socket) do
    {:noreply, assign(socket, :show_guide_modal, false)}
  end

  def handle_event("toggle_guide_panel", _params, socket) do
    {:noreply, assign(socket, :guide_panel_expanded, !socket.assigns.guide_panel_expanded)}
  end

  def handle_event("open_guide_share", _params, socket) do
    {:noreply, assign(socket, :show_guide_modal, true)}
  end

  def handle_event("share_guide_to_chat", _params, socket) do
    user = socket.assigns[:current_user]
    share_url = socket.assigns.guide_share_url

    if user && share_url do
      display_name = user.email || user.display_name || "Guide"

      Sensocto.Chat.ChatStore.add_message("lobby", %{
        user_id: to_string(user.id),
        user_name: display_name,
        text: "Join my guided session: #{share_url}",
        type: :system
      })
    end

    {:noreply,
     socket
     |> assign(:show_guide_modal, false)
     |> put_flash(:info, "Shared to chat!")}
  end

  def handle_event("guide_set_lens", %{"lens" => lens_str}, socket) do
    with lens when lens != nil <- safe_to_lens(lens_str),
         session_id when session_id != nil <- socket.assigns.guiding_session do
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.set_lens(session_id, user_id, lens)
      {:noreply, push_patch(socket, to: lens_to_path(lens))}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("guide_focus_sensor", %{"sensor_id" => sensor_id}, socket) do
    if session_id = socket.assigns.guiding_session do
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.set_focused_sensor(session_id, user_id, sensor_id)
    end

    {:noreply, socket}
  end

  def handle_event("guide_set_layout", %{"layout" => layout_str}, socket) do
    if session_id = socket.assigns.guiding_session do
      layout = String.to_existing_atom(layout_str)
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.set_layout(session_id, user_id, layout)

      {:noreply,
       socket
       |> assign(:lobby_layout, layout)
       |> push_event("save_lobby_layout", %{layout: layout_str})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("guide_set_quality", %{"quality" => quality_str}, socket) do
    if session_id = socket.assigns.guiding_session do
      user_id = socket.assigns.current_user.id

      socket =
        if quality_str == "auto" do
          Sensocto.Guidance.SessionServer.set_quality(session_id, user_id, :auto)

          socket
          |> assign(:quality_override, nil)
          |> push_event("quality_changed", %{level: :auto, reason: "Guide override"})
        else
          quality = String.to_existing_atom(quality_str)
          Sensocto.Guidance.SessionServer.set_quality(session_id, user_id, quality)

          if socket.assigns[:priority_lens_registered] do
            Sensocto.Lenses.PriorityLens.set_quality(socket.id, quality)
          end

          socket
          |> assign(:quality_override, quality)
          |> assign(:current_quality, quality)
          |> push_event("quality_changed", %{level: quality, reason: "Guide override"})
        end

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  def handle_event("guide_set_sort", %{"sort_by" => sort_str}, socket)
      when sort_str in ["activity", "name", "type", "battery"] do
    if session_id = socket.assigns.guiding_session do
      sort_by = String.to_existing_atom(sort_str)
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.set_sort(session_id, user_id, sort_by)

      sorted = sort_sensors(socket.assigns.sensor_ids, socket.assigns.sensors, sort_by)

      {:noreply,
       socket
       |> assign(:sort_by, sort_by)
       |> assign(:sensor_ids, sorted)
       |> push_event("save_sort_by", %{sort_by: sort_str})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("guide_set_lobby_mode", %{"mode" => mode_str}, socket) do
    if session_id = socket.assigns.guiding_session do
      new_mode = String.to_existing_atom(mode_str)
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.set_lobby_mode(session_id, user_id, new_mode)

      old_mode = socket.assigns.lobby_mode
      user = socket.assigns.current_user

      if user && old_mode != new_mode do
        release_control_for_mode(old_mode, user.id)
      end

      {:noreply,
       socket
       |> assign(:lobby_mode, new_mode)
       |> push_event("save_lobby_mode", %{mode: mode_str})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("guide_suggest", %{"type" => type, "text" => text} = params, socket)
      when type in ["breathing_rhythm", "focus_sensor", "take_break", "custom"] do
    if session_id = socket.assigns.guiding_session do
      user_id = socket.assigns.current_user.id

      type_atom =
        case type do
          "breathing_rhythm" -> :breathing_rhythm
          "focus_sensor" -> :focus_sensor
          "take_break" -> :take_break
          "custom" -> :custom
        end

      action = %{type: type_atom, text: text, data: params["data"] || %{}}
      Sensocto.Guidance.SessionServer.suggest_action(session_id, user_id, action)
    end

    {:noreply, socket}
  end

  def handle_event("guide_end_session", _params, socket) do
    session_id = socket.assigns.guiding_session || socket.assigns.guided_session

    if session_id do
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.end_session(session_id, user_id)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "lobby:guidance:available",
        {:guidance_unavailable, %{session_id: session_id}}
      )
    end

    {:noreply, socket}
  end

  def handle_event("dismiss_available_guided_session", _params, socket) do
    {:noreply, assign(socket, :available_guided_session, nil)}
  end

  def handle_event("join_guided_session", %{"session_id" => session_id}, socket) do
    user = socket.assigns.current_user

    with false <- is_nil(user),
         false <- Map.get(user, :is_guest, false),
         true <- is_nil(socket.assigns.guided_session),
         true <- is_nil(socket.assigns.guiding_session),
         {:ok, session} <-
           Ash.get(Sensocto.Guidance.GuidedSession, session_id, authorize?: false),
         true <- session.status == :pending,
         {:ok, session} <-
           Ash.update(session, %{follower_user_id: user.id},
             action: :assign_follower,
             authorize?: false
           ),
         {:ok, session} <- Ash.update(session, %{}, action: :accept, authorize?: false) do
      follower_name = user.display_name || "Follower"

      Sensocto.Guidance.SessionSupervisor.get_or_start_session(session.id,
        guide_user_id: session.guide_user_id,
        follower_user_id: user.id,
        follower_user_name: follower_name
      )

      Phoenix.PubSub.subscribe(Sensocto.PubSub, "guidance:#{session.id}")
      Sensocto.Guidance.SessionServer.connect(session.id, user.id)

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "user:#{session.guide_user_id}:guidance",
        {:guidance_invitation_accepted, %{session_id: session.id, follower_name: follower_name}}
      )

      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "lobby:guidance:available",
        {:guidance_unavailable, %{session_id: session.id}}
      )

      {:noreply,
       socket
       |> assign(:guided_session, session.id)
       |> assign(:available_guided_session, nil)}
    else
      _ -> {:noreply, socket}
    end
  end

  def handle_event("follower_break_away", _params, socket) do
    if session_id = socket.assigns.guided_session do
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.break_away(session_id, user_id)
      {:noreply, assign(socket, :guided_following, false)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("follower_rejoin", _params, socket) do
    if session_id = socket.assigns.guided_session do
      user_id = socket.assigns.current_user.id

      case Sensocto.Guidance.SessionServer.rejoin(session_id, user_id) do
        {:ok, %{lens: lens} = state} ->
          {:noreply,
           socket
           |> assign(:guided_following, true)
           |> apply_guided_settings(state)
           |> push_patch(to: lens_to_path(lens))}

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  def handle_event("dismiss_suggestion", _params, socket) do
    {:noreply, assign(socket, :guided_suggestion, nil)}
  end

  def handle_event("follower_leave_session", _params, socket) do
    if session_id = socket.assigns.guided_session do
      user_id = socket.assigns.current_user.id
      Sensocto.Guidance.SessionServer.end_session(session_id, user_id)
    end

    {:noreply,
     socket
     |> assign(:guided_session, nil)
     |> assign(:guided_following, true)
     |> assign(:guided_annotations, [])
     |> assign(:guided_suggestion, nil)
     |> assign(:guided_focused_sensor_id, nil)
     |> assign(:guided_presence, %{guide_connected: false, follower_connected: false})}
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

    # Disconnect from guided session
    session_id = socket.assigns[:guiding_session] || socket.assigns[:guided_session]

    if session_id do
      Sensocto.Guidance.SessionServer.disconnect(session_id, socket.assigns.current_user.id)
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
        :gaze -> Enum.map(socket.assigns[:gaze_sensors] || [], & &1.sensor_id)
        action when action in [:graph, :graph3d] -> socket.assigns.sensor_ids
        _ -> []
      end

    if sensor_ids != [] do
      attr_key = "composite_#{action}"

      # Use bulk unregistration for graph to match bulk registration
      if action in [:graph, :graph3d] do
        Sensocto.AttentionTracker.unregister_views_bulk(sensor_ids, attr_key, viewer_id)
      else
        Enum.each(sensor_ids, fn sensor_id ->
          Sensocto.AttentionTracker.unregister_view(sensor_id, attr_key, viewer_id)
        end)
      end
    end

    # Deactivate SyncComputer when leaving breathing/HRV views
    if action in [:respiration, :hrv] do
      Sensocto.Bio.SyncComputer.unregister_viewer()
    end

    # Clean up MIDI-triggered SyncComputer registration
    if socket.assigns[:midi_sync_active] do
      Sensocto.Bio.SyncComputer.unregister_viewer()
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

  # Drain all pending lens batch/digest messages from the mailbox in one shot.
  # Returns count of drained messages. This prevents each queued message from
  # individually hitting the backpressure check (wasting CPU on 90+ no-op cycles).
  defp drain_lens_messages, do: drain_lens_messages(0)

  defp drain_lens_messages(count) do
    receive do
      {:lens_batch, _} -> drain_lens_messages(count + 1)
      {:lens_digest, _} -> drain_lens_messages(count + 1)
    after
      0 -> count
    end
  end

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

  # Apply a lobby mode switch: cleanup old mode, assign new mode, setup new mode
  defp world_label(:bioluminescent), do: "Bioluminescent"
  defp world_label(:inferno), do: "Inferno"
  defp world_label(:meadow), do: "Meadow"

  defp apply_lobby_mode_switch(socket, new_mode, old_mode) do
    socket =
      if old_mode == :avatar and new_mode != :avatar do
        cleanup_avatar_attention(socket)
      else
        socket
      end

    socket =
      socket
      |> assign(:lobby_mode, new_mode)
      |> push_event("save_lobby_mode", %{mode: Atom.to_string(new_mode)})

    if new_mode == :avatar do
      ctrl = Sensocto.Avatar.AvatarEcosystemServer.get_state()

      ensure_attention_for_avatar(socket)
      |> push_viewer_token_for_avatar()
      |> assign(:avatar_controller_user_id, ctrl.controller_user_id)
      |> assign(:avatar_controller_user_name, ctrl.controller_user_name)
      |> assign(:avatar_pending_request_user_id, ctrl.pending_request_user_id)
      |> assign(:avatar_pending_request_user_name, ctrl.pending_request_user_name)
    else
      socket
    end
  end

  # Release control for a specific mode when user navigates away
  # Playback continues without a controller - anyone can then take control
  @doc false
  def release_control_for_mode(:media, user_id) do
    alias Sensocto.Media.MediaPlayerServer
    MediaPlayerServer.release_control(:lobby, user_id)
  rescue
    _ -> :ok
  end

  def release_control_for_mode(:object3d, user_id) do
    alias Sensocto.Object3D.Object3DPlayerServer
    Object3DPlayerServer.release_control(:lobby, user_id)
  rescue
    _ -> :ok
  end

  def release_control_for_mode(:whiteboard, user_id) do
    alias Sensocto.Whiteboard.WhiteboardServer
    WhiteboardServer.release_control(:lobby, user_id)
  rescue
    _ -> :ok
  end

  def release_control_for_mode(:avatar, user_id) do
    Sensocto.Avatar.AvatarEcosystemServer.release_control(user_id)
  rescue
    _ -> :ok
  end

  def release_control_for_mode(_mode, _user_id), do: :ok

  # ============================================================================
  # Guided Session Helpers
  # ============================================================================

  @doc false
  def apply_guided_settings(socket, payload) do
    socket
    |> then(fn s ->
      case payload[:layout] do
        nil -> s
        layout -> assign(s, :lobby_layout, layout)
      end
    end)
    |> then(fn s ->
      case payload[:quality] do
        nil ->
          s

        :auto ->
          assign(s, :quality_override, nil)

        quality ->
          if s.assigns[:priority_lens_registered] do
            Sensocto.Lenses.PriorityLens.set_quality(s.id, quality)
          end

          s |> assign(:quality_override, quality) |> assign(:current_quality, quality)
      end
    end)
    |> then(fn s ->
      case payload[:sort_by] do
        nil ->
          s

        sort_by ->
          sorted = sort_sensors(s.assigns.sensor_ids, s.assigns.sensors, sort_by)
          s |> assign(:sort_by, sort_by) |> assign(:sensor_ids, sorted)
      end
    end)
    |> then(fn s ->
      case payload[:lobby_mode] do
        nil -> s
        mode -> assign(s, :lobby_mode, mode)
      end
    end)
  end

  defp discover_available_guided_session(socket, user) do
    if is_nil(socket.assigns.guided_session) && is_nil(socket.assigns.guiding_session) do
      case Ash.read(Sensocto.Guidance.GuidedSession,
             action: :pending_for_others,
             args: [user_id: user.id],
             authorize?: false
           ) do
        {:ok, [session | _]} ->
          guide_name =
            case Ash.get(Sensocto.Accounts.User, session.guide_user_id, authorize?: false) do
              {:ok, u} -> u.display_name || "A guide"
              _ -> "A guide"
            end

          assign(socket, :available_guided_session, %{
            session_id: session.id,
            guide_user_id: session.guide_user_id,
            guide_name: guide_name
          })

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp subscribe_to_guided_session(socket, user) do
    case Ash.read(Sensocto.Guidance.GuidedSession,
           action: :active_for_user,
           args: [user_id: user.id],
           authorize?: false
         ) do
      {:ok, [session | _]} ->
        Phoenix.PubSub.subscribe(Sensocto.PubSub, "guidance:#{session.id}")
        Sensocto.Guidance.SessionServer.connect(session.id, user.id)

        if to_string(session.guide_user_id) == to_string(user.id) do
          assign(socket, :guiding_session, session.id)
        else
          assign(socket, :guided_session, session.id)
        end

      _ ->
        socket
    end
  end

  defp safe_to_lens("sensors"), do: :sensors
  defp safe_to_lens("heartrate"), do: :heartrate
  defp safe_to_lens("imu"), do: :imu
  defp safe_to_lens("location"), do: :location
  defp safe_to_lens("ecg"), do: :ecg
  defp safe_to_lens("battery"), do: :battery
  defp safe_to_lens("skeleton"), do: :skeleton
  defp safe_to_lens("respiration"), do: :respiration
  defp safe_to_lens("hrv"), do: :hrv
  defp safe_to_lens("gaze"), do: :gaze
  defp safe_to_lens("favorites"), do: :favorites
  defp safe_to_lens("users"), do: :users
  defp safe_to_lens("graph"), do: :graph
  defp safe_to_lens("graph3d"), do: :graph3d
  defp safe_to_lens("hierarchy"), do: :hierarchy
  defp safe_to_lens(_), do: nil

  defp lens_to_path(:sensors), do: ~p"/lobby"
  defp lens_to_path(:heartrate), do: ~p"/lobby/heartrate"
  defp lens_to_path(:imu), do: ~p"/lobby/imu"
  defp lens_to_path(:location), do: ~p"/lobby/location"
  defp lens_to_path(:ecg), do: ~p"/lobby/ecg"
  defp lens_to_path(:battery), do: ~p"/lobby/battery"
  defp lens_to_path(:skeleton), do: ~p"/lobby/skeleton"
  defp lens_to_path(:respiration), do: ~p"/lobby/breathing"
  defp lens_to_path(:hrv), do: ~p"/lobby/hrv"
  defp lens_to_path(:gaze), do: ~p"/lobby/gaze"
  defp lens_to_path(:favorites), do: ~p"/lobby/favorites"
  defp lens_to_path(:users), do: ~p"/lobby/users"
  defp lens_to_path(:graph), do: ~p"/lobby/graph"
  defp lens_to_path(:graph3d), do: ~p"/lobby/graph3d"
  defp lens_to_path(:hierarchy), do: ~p"/lobby/hierarchy"
  defp lens_to_path(_), do: ~p"/lobby"
end

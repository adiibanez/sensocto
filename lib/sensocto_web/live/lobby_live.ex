defmodule SensoctoWeb.LobbyLive do
  @moduledoc """
  Full-page view of all sensors in the lobby.
  Shows all sensors from the SensorsDynamicSupervisor with real-time updates.
  """
  use SensoctoWeb, :live_view
  require Logger
  use LiveSvelte.Components
  alias SensoctoWeb.StatefulSensorLive
  alias SensoctoWeb.Live.Components.MediaPlayerComponent
  alias SensoctoWeb.Live.Components.Object3DPlayerComponent
  alias SensoctoWeb.Live.Components.WhiteboardComponent
  alias SensoctoWeb.Sensocto.Presence
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Calls

  @grid_cols_sm_default 2
  @grid_cols_lg_default 3
  @grid_cols_xl_default 4
  @grid_cols_2xl_default 5

  # Threshold for switching to summary mode (<=3 sensors = normal, >3 = summary)
  # Kept for future use when dynamic view mode switching is implemented
  @summary_mode_threshold 3
  _ = @summary_mode_threshold

  # Performance monitoring: batch flush interval in ms
  # Measurements are buffered and flushed at this interval to reduce push_event calls
  @measurement_flush_interval_ms 50

  # Performance telemetry: log interval in ms
  @perf_log_interval_ms 5_000

  # Suppress unused warnings - these are used in handle_info callbacks
  _ = @measurement_flush_interval_ms
  _ = @perf_log_interval_ms

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
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:global")

    # Subscribe to user-specific attention level updates for webcam backpressure
    user = socket.assigns[:current_user]

    if user do
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "call:lobby:user:#{user.id}")
    end

    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    sensors_count = Enum.count(sensors)
    # Extract stable list of sensor IDs - only changes when sensors are added/removed
    sensor_ids = sensors |> Map.keys() |> Enum.sort()

    # Subscribe to data topics for all sensors (for composite views)
    # Also subscribe to signal topics for attribute change notifications
    Enum.each(sensor_ids, fn sensor_id ->
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
      Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
    end)

    # Calculate max attributes across all sensors for view mode decision
    max_attributes = calculate_max_attributes(sensors)

    # Determine view mode: normal for <=3 sensors with few attributes, summary otherwise
    default_view_mode = determine_view_mode(sensors_count, max_attributes)

    # Extract composite visualization data
    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors} =
      extract_composite_data(sensors)

    # Compute available lenses based on actual sensor attributes
    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors
      )

    # Group sensors by connector (user)
    sensors_by_user = group_sensors_by_user(sensors)

    # Get available rooms for join UI
    user = socket.assigns[:current_user]
    public_rooms = if user, do: Sensocto.Rooms.list_public_rooms(), else: []

    # Check if there's an active call in the lobby
    call_active = Calls.call_exists?(:lobby)

    new_socket =
      socket
      |> assign(
        page_title: "Lobby",
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
        available_lenses: available_lenses,
        sensors_by_user: sensors_by_user,
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
        attention_filter_timer: nil
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

        new_socket
        |> assign(:presence_key, presence_key)
        |> assign(:media_viewers, media_count)
        |> assign(:object3d_viewers, object3d_count)
        |> assign(:whiteboard_viewers, whiteboard_count)
        |> assign(:synced_users, synced_users)
        |> assign(:solo_users, solo_users)
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
    {:noreply, socket}
  end

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

    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors}
  end

  # Compute which lens types are available based on actual sensor attributes
  defp compute_available_lenses(
         heartrate_sensors,
         imu_sensors,
         location_sensors,
         ecg_sensors,
         battery_sensors,
         skeleton_sensors
       ) do
    lenses = []
    lenses = if length(heartrate_sensors) > 0, do: [:heartrate | lenses], else: lenses
    lenses = if length(imu_sensors) > 0, do: [:imu | lenses], else: lenses
    lenses = if length(location_sensors) > 0, do: [:location | lenses], else: lenses
    lenses = if length(ecg_sensors) > 0, do: [:ecg | lenses], else: lenses
    lenses = if length(battery_sensors) > 0, do: [:battery | lenses], else: lenses
    lenses = if length(skeleton_sensors) > 0, do: [:skeleton | lenses], else: lenses
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
        # Subscribe to data topics for any new sensors
        new_sensors = new_sensor_ids -- current_sensor_ids

        Enum.each(new_sensors, fn sensor_id ->
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
          Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{sensor_id}")
        end)

        sensors_online = Map.merge(socket.assigns.sensors_online, payload.joins)

        # Update composite visualization data
        {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
         skeleton_sensors} =
          extract_composite_data(sensors)

        # Recompute available lenses when sensors change
        available_lenses =
          compute_available_lenses(
            heartrate_sensors,
            imu_sensors,
            location_sensors,
            ecg_sensors,
            battery_sensors,
            skeleton_sensors
          )

        # Filter sensor IDs based on current min_attention setting
        min_attention = socket.assigns[:min_attention] || 0
        filtered_sensor_ids = filter_sensors_by_attention(new_sensor_ids, min_attention)

        updated_socket =
          socket
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
          |> assign(:available_lenses, available_lenses)
          |> assign(:sensors_by_user, group_sensors_by_user(sensors))

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

  # Handle single measurement for composite views and individual sensors
  @impl true
  def handle_info(
        {:measurement,
         %{
           :payload => payload,
           :timestamp => timestamp,
           :attribute_id => attribute_id,
           :sensor_id => sensor_id
         }},
        socket
      ) do
    case socket.assigns.live_action do
      # Composite views use composite_measurement event
      action when action in [:heartrate, :imu, :location, :ecg, :battery, :skeleton] ->
        # Look up username from online sensors for display
        username =
          case Map.get(socket.assigns.sensors_online, sensor_id) do
            %{username: name} when not is_nil(name) -> name
            _ -> nil
          end

        {:noreply,
         push_event(socket, "composite_measurement", %{
           sensor_id: sensor_id,
           username: username,
           attribute_id: attribute_id,
           payload: payload,
           timestamp: timestamp
         })}

      # Sensors view uses measurement event for SensorDataAccumulator hook
      :sensors ->
        {:noreply,
         push_event(socket, "measurement", %{
           sensor_id: sensor_id,
           attribute_id: attribute_id,
           payload: payload,
           timestamp: timestamp
         })}

      _ ->
        {:noreply, socket}
    end
  end

  # Handle batch measurements for composite views
  @impl true
  def handle_info({:measurements_batch, {sensor_id, measurements_list}}, socket)
      when is_list(measurements_list) do
    case socket.assigns.live_action do
      # ECG needs ALL measurements for proper waveform visualization (high-frequency data)
      :ecg ->
        # Group by attribute and send all ECG measurements
        measurements_list
        |> Enum.group_by(& &1.attribute_id)
        |> Enum.reduce(socket, fn {attr_id, measurements}, acc ->
          if attr_id == "ecg" do
            # Send all measurements sorted by timestamp for proper waveform
            sorted = Enum.sort_by(measurements, & &1.timestamp)

            Enum.reduce(sorted, acc, fn m, sock ->
              push_event(sock, "composite_measurement", %{
                sensor_id: sensor_id,
                attribute_id: attr_id,
                payload: m.payload,
                timestamp: m.timestamp
              })
            end)
          else
            # Non-ECG attributes: just send latest
            latest = Enum.max_by(measurements, & &1.timestamp)

            push_event(acc, "composite_measurement", %{
              sensor_id: sensor_id,
              attribute_id: attr_id,
              payload: latest.payload,
              timestamp: latest.timestamp
            })
          end
        end)
        |> then(&{:noreply, &1})

      action when action in [:heartrate, :imu, :location, :battery, :skeleton] ->
        # For other composite views, get latest measurement per attribute
        latest_by_attr =
          measurements_list
          |> Enum.group_by(& &1.attribute_id)
          |> Enum.map(fn {attr_id, measurements} ->
            latest = Enum.max_by(measurements, & &1.timestamp)

            %{
              sensor_id: sensor_id,
              attribute_id: attr_id,
              payload: latest.payload,
              timestamp: latest.timestamp
            }
          end)

        new_socket =
          Enum.reduce(latest_by_attr, socket, fn measurement, acc ->
            push_event(acc, "composite_measurement", measurement)
          end)

        {:noreply, new_socket}

      # Sensors view uses measurements_batch for SensorDataAccumulator hook
      # Buffer measurements and flush periodically to reduce push_event calls
      :sensors ->
        attributes =
          measurements_list
          |> Enum.map(fn m ->
            %{
              attribute_id: m.attribute_id,
              payload: m.payload,
              timestamp: m.timestamp
            }
          end)

        # Add to buffer (append to existing measurements for this sensor)
        buffer = socket.assigns.measurement_buffer
        existing = Map.get(buffer, sensor_id, [])
        new_buffer = Map.put(buffer, sensor_id, existing ++ attributes)

        # Schedule flush if not already scheduled
        flush_timer = socket.assigns.measurement_flush_timer

        new_timer =
          if is_nil(flush_timer) do
            Process.send_after(self(), :flush_measurement_buffer, @measurement_flush_interval_ms)
          else
            flush_timer
          end

        {:noreply,
         socket
         |> assign(:measurement_buffer, new_buffer)
         |> assign(:measurement_flush_timer, new_timer)}

      _ ->
        {:noreply, socket}
    end
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
        {:object3d_camera_synced,
         %{camera_position: position, camera_target: target, user_id: user_id} = event},
        socket
      ) do
    # In solo mode, ignore camera syncs entirely
    if socket.assigns.sync_mode == :solo do
      {:noreply, socket}
    else
      current_user_id = socket.assigns.current_user && socket.assigns.current_user.id

      # Don't forward camera sync to the controller themselves - they're the source
      if user_id != current_user_id do
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
  def handle_info(:refresh_available_lenses, socket) do
    sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)

    {heartrate_sensors, imu_sensors, location_sensors, ecg_sensors, battery_sensors,
     skeleton_sensors} =
      extract_composite_data(sensors)

    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors
      )

    # Re-filter sensors based on current min_attention setting
    # This ensures sensors are removed when their attention drops below threshold
    all_sensor_ids = socket.assigns[:all_sensor_ids] || socket.assigns.sensor_ids
    min_attention = socket.assigns[:min_attention] || 0
    filtered_sensor_ids = filter_sensors_by_attention(all_sensor_ids, min_attention)

    {:noreply,
     socket
     |> assign(:heartrate_sensors, heartrate_sensors)
     |> assign(:imu_sensors, imu_sensors)
     |> assign(:location_sensors, location_sensors)
     |> assign(:ecg_sensors, ecg_sensors)
     |> assign(:battery_sensors, battery_sensors)
     |> assign(:skeleton_sensors, skeleton_sensors)
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
  def handle_info({:whiteboard_undo, _params}, socket) do
    send_update(WhiteboardComponent, id: "lobby-whiteboard")
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
     skeleton_sensors} =
      extract_composite_data(sensors)

    available_lenses =
      compute_available_lenses(
        heartrate_sensors,
        imu_sensors,
        location_sensors,
        ecg_sensors,
        battery_sensors,
        skeleton_sensors
      )

    {:noreply,
     socket
     |> assign(:heartrate_sensors, heartrate_sensors)
     |> assign(:imu_sensors, imu_sensors)
     |> assign(:location_sensors, location_sensors)
     |> assign(:ecg_sensors, ecg_sensors)
     |> assign(:battery_sensors, battery_sensors)
     |> assign(:skeleton_sensors, skeleton_sensors)
     |> assign(:available_lenses, available_lenses)
     |> assign(:sensors_by_user, group_sensors_by_user(sensors))}
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

    # Update presence to reflect new mode
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

  # Lens view selector (dropdown)
  @impl true
  def handle_event("select_view", %{"view" => view}, socket) do
    path =
      case view do
        "sensors" -> ~p"/lobby"
        "users" -> ~p"/lobby/users"
        "heartrate" -> ~p"/lobby/heartrate"
        "imu" -> ~p"/lobby/imu"
        "location" -> ~p"/lobby/location"
        "ecg" -> ~p"/lobby/ecg"
        "battery" -> ~p"/lobby/battery"
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

  @impl true
  def handle_event(type, params, socket) do
    Logger.debug("Lobby Unknown event: #{type} #{inspect(params)}")
    {:noreply, socket}
  end
end

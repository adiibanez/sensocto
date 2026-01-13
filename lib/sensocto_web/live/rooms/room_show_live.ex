defmodule SensoctoWeb.RoomShowLive do
  @moduledoc """
  LiveView for displaying a single room with its sensors.
  Shows sensor summaries with activity indicators and provides room management.
  """
  use SensoctoWeb, :live_view
  use LiveSvelte.Components
  require Logger

  alias Sensocto.Rooms
  alias Sensocto.Calls
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Types.AttributeType
  alias Phoenix.PubSub
  alias SensoctoWeb.Live.Components.MediaPlayerComponent

  @activity_check_interval 5000

  @impl true
  def mount(%{"id" => room_id}, _session, socket) do
    user = socket.assigns.current_user

    case Rooms.get_room_with_sensors(room_id) do
      {:ok, room} ->
        if connected?(socket) do
          PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}")

          Enum.each(room.sensors || [], fn sensor ->
            PubSub.subscribe(Sensocto.PubSub, "data:#{sensor.sensor_id}")
          end)

          # Subscribe to call events for this room
          PubSub.subscribe(Sensocto.PubSub, "call:#{room_id}")

          # Subscribe to media events for this room
          PubSub.subscribe(Sensocto.PubSub, "media:#{room_id}")

          # NOTE: Sensors must be manually added to rooms via the "Add Sensor" button.
          # Auto-registration has been removed - simulator sensors stay in the lobby only.

          Process.send_after(self(), :update_activity, @activity_check_interval)
        end

        available_sensors = get_available_sensors(room)

        # Check if there's an active call in this room
        call_active = Calls.call_exists?(room_id)

        # Get real-time sensor state for lens extraction
        sensors_state = get_sensors_state(room.sensors || [])
        available_lenses = extract_available_lenses(sensors_state)

        socket =
          socket
          |> assign(:page_title, room.name)
          |> assign(:room, room)
          |> assign(:sensors, room.sensors || [])
          |> assign(:sensors_state, sensors_state)
          |> assign(:available_sensors, available_sensors)
          |> assign(:show_share_modal, false)
          |> assign(:show_add_sensor_modal, false)
          |> assign(:show_edit_modal, false)
          |> assign(:show_settings, false)
          |> assign(:is_owner, Rooms.owner?(room, user))
          |> assign(:is_member, Rooms.member?(room, user))
          |> assign(:can_manage, Rooms.can_manage?(room, user))
          |> assign(:sensor_activity, build_activity_map(room.sensors || []))
          |> assign(:edit_form, build_edit_form(room))
          # Lens-related assigns
          |> assign(:available_lenses, available_lenses)
          |> assign(:current_lens, nil)
          |> assign(:lens_data, %{})
          # Call-related assigns
          |> assign(:call_active, call_active)
          |> assign(:in_call, false)
          |> assign(:call_participants, %{})

        {:ok, socket}

      {:error, _} ->
        socket =
          socket
          |> put_flash(:error, "Room not found")
          |> push_navigate(to: ~p"/rooms")

        {:ok, socket}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :show, _params) do
    socket
    |> assign(:show_settings, false)
  end

  defp apply_action(socket, :settings, _params) do
    if socket.assigns.can_manage do
      socket
      |> assign(:show_settings, true)
    else
      socket
      |> put_flash(:error, "You don't have permission to access settings")
      |> push_patch(to: ~p"/rooms/#{socket.assigns.room.id}")
    end
  end

  @impl true
  def handle_event("open_share_modal", _params, socket) do
    {:noreply, assign(socket, :show_share_modal, true)}
  end

  @impl true
  def handle_event("close_share_modal", _params, socket) do
    {:noreply, assign(socket, :show_share_modal, false)}
  end

  @impl true
  def handle_event("open_add_sensor_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_sensor_modal, true)}
  end

  @impl true
  def handle_event("close_add_sensor_modal", _params, socket) do
    {:noreply, assign(socket, :show_add_sensor_modal, false)}
  end

  @impl true
  def handle_event("open_edit_modal", _params, socket) do
    room = socket.assigns.room
    {:noreply, socket |> assign(:show_edit_modal, true) |> assign(:edit_form, build_edit_form(room))}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  @impl true
  def handle_event("validate_edit", params, socket) do
    form = to_form(%{
      "name" => params["name"] || "",
      "description" => params["description"] || "",
      "is_public" => Map.has_key?(params, "is_public"),
      "calls_enabled" => Map.has_key?(params, "calls_enabled")
    })
    {:noreply, assign(socket, :edit_form, form)}
  end

  @impl true
  def handle_event("save_room", params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    attrs = %{
      name: params["name"],
      description: params["description"],
      is_public: Map.has_key?(params, "is_public"),
      calls_enabled: Map.has_key?(params, "calls_enabled")
    }

    case Rooms.update_room(room, attrs, user) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, normalize_room(updated_room))
          |> assign(:page_title, updated_room.name)
          |> assign(:show_edit_modal, false)
          |> put_flash(:info, "Room updated successfully")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update room")}
    end
  end

  @impl true
  def handle_event("delete_room", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    case Rooms.delete_room(room, user) do
      :ok ->
        socket =
          socket
          |> put_flash(:info, "Room deleted successfully")
          |> push_navigate(to: ~p"/rooms")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to delete room")}
    end
  end

  @impl true
  def handle_event("leave_room", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    # Don't allow owner to leave their own room
    if Rooms.owner?(room, user) do
      {:noreply, put_flash(socket, :error, "Room owners cannot leave. Transfer ownership or delete the room.")}
    else
      case Rooms.leave_room(room, user) do
        :ok ->
          socket =
            socket
            |> put_flash(:info, "Left room: #{room.name}")
            |> push_navigate(to: ~p"/lobby")

          {:noreply, socket}

        {:error, :not_member} ->
          socket =
            socket
            |> put_flash(:info, "Left room: #{room.name}")
            |> push_navigate(to: ~p"/lobby")

          {:noreply, socket}

        {:error, _reason} ->
          {:noreply, put_flash(socket, :error, "Failed to leave room")}
      end
    end
  end

  @impl true
  def handle_event("join_room", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    case Rooms.join_room(room, user) do
      {:ok, _membership} ->
        socket =
          socket
          |> assign(:is_member, true)
          |> assign(:can_manage, Rooms.can_manage?(room, user))
          |> put_flash(:info, "Joined room: #{room.name}")

        {:noreply, socket}

      {:error, :already_member} ->
        socket =
          socket
          |> assign(:is_member, true)
          |> put_flash(:info, "You are already a member of this room")

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to join room")}
    end
  end

  @impl true
  def handle_event("add_sensor", %{"sensor_id" => sensor_id}, socket) do
    room = socket.assigns.room

    case Rooms.add_sensor_to_room(room, sensor_id) do
      :ok ->
        PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

        case Rooms.get_room_with_sensors(room.id) do
          {:ok, updated_room} ->
            socket =
              socket
              |> assign(:room, updated_room)
              |> assign(:sensors, updated_room.sensors || [])
              |> assign(:available_sensors, get_available_sensors(updated_room))
              |> assign(:show_add_sensor_modal, false)
              |> put_flash(:info, "Sensor added to room")

            {:noreply, socket}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to refresh room")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to add sensor")}
    end
  end

  @impl true
  def handle_event("remove_sensor", %{"sensor_id" => sensor_id}, socket) do
    room = socket.assigns.room

    case Rooms.remove_sensor_from_room(room, sensor_id) do
      :ok ->
        PubSub.unsubscribe(Sensocto.PubSub, "data:#{sensor_id}")

        case Rooms.get_room_with_sensors(room.id) do
          {:ok, updated_room} ->
            socket =
              socket
              |> assign(:room, updated_room)
              |> assign(:sensors, updated_room.sensors || [])
              |> assign(:available_sensors, get_available_sensors(updated_room))
              |> put_flash(:info, "Sensor removed from room")

            {:noreply, socket}

          _ ->
            {:noreply, put_flash(socket, :error, "Failed to refresh room")}
        end

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove sensor")}
    end
  end

  @impl true
  def handle_event("regenerate_code", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    case Rooms.regenerate_join_code(room, user) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, normalize_room(updated_room))
          |> put_flash(:info, "Join code regenerated")

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to regenerate code")}
    end
  end

  @impl true
  def handle_event("copy_link", _params, socket) do
    {:noreply, put_flash(socket, :info, "Link copied to clipboard!")}
  end

  @impl true
  def handle_event("select_lens", %{"lens" => lens_type}, socket) do
    lens_type = if lens_type == "", do: nil, else: lens_type

    lens_data = if lens_type do
      extract_lens_data(socket.assigns.sensors_state, lens_type)
    else
      %{}
    end

    {:noreply,
     socket
     |> assign(:current_lens, lens_type)
     |> assign(:lens_data, lens_data)}
  end

  @impl true
  def handle_event("clear_lens", _params, socket) do
    {:noreply,
     socket
     |> assign(:current_lens, nil)
     |> assign(:lens_data, %{})}
  end

  @impl true
  def handle_event("toggle_calls_enabled", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    new_calls_enabled = not Map.get(room, :calls_enabled, true)

    case Rooms.update_room(room, %{calls_enabled: new_calls_enabled}, user) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, normalize_room(updated_room))
          |> put_flash(:info, if(new_calls_enabled, do: "Calls enabled", else: "Calls disabled"))

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update room settings")}
    end
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

    socket = assign(socket, :in_call, false)

    if can_retry do
      {:noreply, put_flash(socket, :error, "#{message} Click Video/Voice to try again.")}
    else
      {:noreply, put_flash(socket, :error, "Call error: #{message}")}
    end
  end

  @impl true
  def handle_event("call_state_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("call_reconnecting", params, socket) do
    attempt = Map.get(params, "attempt", 1)
    max = Map.get(params, "max", 3)
    {:noreply, put_flash(socket, :info, "Reconnecting to call (#{attempt}/#{max})...")}
  end

  @impl true
  def handle_event("call_reconnected", _params, socket) do
    socket = socket |> clear_flash() |> put_flash(:info, "Reconnected to call")
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
  def handle_event("socket_error", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("connection_unhealthy", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("connection_state_changed", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("participant_joined", params, socket) do
    # Update participants from JS event (for WebRTC endpoint events)
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
  def handle_event("track_ready", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("track_removed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("connection_state_changed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("quality_changed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("participant_audio_changed", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("participant_video_changed", _params, socket) do
    {:noreply, socket}
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
    room_id = socket.assigns.room.id

    case MediaPlayerServer.get_state(room_id) do
      {:ok, state} ->
        socket = push_event(socket, "media_sync", %{
          state: state.state,
          position_seconds: state.position_seconds
        })

        {:noreply, socket}

      {:error, _} ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(
        {:measurement,
         %{
           sensor_id: sensor_id,
           attribute_id: attribute_id,
           payload: payload,
           timestamp: timestamp
         }},
        socket
      ) do
    activity = Map.put(socket.assigns.sensor_activity, sensor_id, DateTime.utc_now())
    socket = assign(socket, :sensor_activity, activity)

    # Push composite_measurement event when lens is active
    socket =
      if socket.assigns[:current_lens] do
        push_event(socket, "composite_measurement", %{
          sensor_id: sensor_id,
          attribute_id: attribute_id,
          payload: payload,
          timestamp: timestamp
        })
      else
        socket
      end

    {:noreply, socket}
  end

  # Fallback for measurement without full details
  @impl true
  def handle_info({:measurement, %{sensor_id: sensor_id}}, socket) do
    activity = Map.put(socket.assigns.sensor_activity, sensor_id, DateTime.utc_now())
    {:noreply, assign(socket, :sensor_activity, activity)}
  end

  @impl true
  def handle_info({:measurements_batch, {sensor_id, measurements_list}}, socket)
      when is_list(measurements_list) do
    activity = Map.put(socket.assigns.sensor_activity, sensor_id, DateTime.utc_now())
    socket = assign(socket, :sensor_activity, activity)

    # Push composite_measurement events when lens is active
    socket =
      if socket.assigns[:current_lens] do
        # Get latest measurement per attribute
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

        Enum.reduce(latest_by_attr, socket, fn measurement, acc ->
          push_event(acc, "composite_measurement", measurement)
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  # Fallback for measurements_batch without full list
  @impl true
  def handle_info({:measurements_batch, {sensor_id, _}}, socket) do
    activity = Map.put(socket.assigns.sensor_activity, sensor_id, DateTime.utc_now())
    {:noreply, assign(socket, :sensor_activity, activity)}
  end

  @impl true
  def handle_info({:room_update, _message}, socket) do
    case Rooms.get_room_with_sensors(socket.assigns.room.id) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, updated_room)
          |> assign(:sensors, updated_room.sensors || [])

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:update_activity, socket) do
    Process.send_after(self(), :update_activity, @activity_check_interval)
    {:noreply, assign(socket, :sensor_activity, socket.assigns.sensor_activity)}
  end

  # Handle call events from CallServer via PubSub
  @impl true
  def handle_info({:call_event, event}, socket) do
    socket =
      case event do
        {:participant_joined, participant} ->
          new_participants = Map.put(socket.assigns.call_participants, participant.user_id, participant)
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

  # NOTE: Auto-registration of sensors to rooms has been removed.
  # Sensors must be manually added via the "Add Sensor" button.
  # Simulator sensors stay in the lobby only.

  # Media player events - forward to component via send_update AND push events to JS hook
  @impl true
  def handle_info({:media_state_changed, state}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      player_state: state.state,
      position_seconds: state.position_seconds,
      current_item: state.current_item
    )

    # Push sync event directly to JS hook from parent LiveView
    socket = push_event(socket, "media_sync", %{
      state: state.state,
      position_seconds: state.position_seconds
    })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_video_changed, %{item: item}}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      current_item: item
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_playlist_updated, %{items: items}}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      playlist_items: items
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_controller_changed, %{controller_user_id: user_id, controller_user_name: user_name}}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      controller_user_id: user_id,
      controller_user_name: user_name
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("RoomShowLive received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end

  defp get_available_sensors(room) do
    room_sensor_ids =
      (room.sensors || [])
      |> Enum.map(& &1.sensor_id)
      |> MapSet.new()

    Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
    |> Map.values()
    |> Enum.reject(fn sensor -> MapSet.member?(room_sensor_ids, sensor.sensor_id) end)
  end

  defp build_activity_map(sensors) do
    sensors
    |> Enum.map(fn sensor ->
      {sensor.sensor_id, DateTime.utc_now()}
    end)
    |> Enum.into(%{})
  end

  defp build_edit_form(room) do
    to_form(%{
      "name" => room.name || "",
      "description" => room.description || "",
      "is_public" => Map.get(room, :is_public, true),
      "calls_enabled" => Map.get(room, :calls_enabled, true)
    })
  end

  # Get real-time state for room sensors from the supervisor
  defp get_sensors_state(room_sensors) do
    all_sensors = Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)

    room_sensor_ids = Enum.map(room_sensors, & &1.sensor_id) |> MapSet.new()

    all_sensors
    |> Enum.filter(fn {sensor_id, _} -> MapSet.member?(room_sensor_ids, sensor_id) end)
    |> Enum.into(%{})
  end

  # Extract available lenses from room sensors
  # Groups attribute types by category for organized display
  defp extract_available_lenses(sensors_state) do
    # Collect all attribute types from all sensors
    all_attr_types =
      sensors_state
      |> Enum.flat_map(fn {_sensor_id, sensor} ->
        (sensor.attributes || %{})
        |> Enum.map(fn {_attr_id, attr} -> attr.attribute_type end)
      end)
      |> Enum.uniq()

    # Group by category and build lens info
    all_attr_types
    |> Enum.map(fn attr_type ->
      category = AttributeType.category(attr_type)
      hints = AttributeType.render_hints(attr_type)
      sensor_count = count_sensors_with_attribute(sensors_state, attr_type)

      %{
        type: attr_type,
        category: category,
        label: format_lens_label(attr_type),
        icon: get_lens_icon(attr_type),
        color: Map.get(hints, :color, "#6b7280"),
        sensor_count: sensor_count,
        has_composite: has_composite_view?(attr_type)
      }
    end)
    |> Enum.sort_by(fn lens -> {category_order(lens.category), lens.label} end)
  end

  defp count_sensors_with_attribute(sensors_state, attr_type) do
    sensors_state
    |> Enum.count(fn {_sensor_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        normalize_attr_type(attr.attribute_type) == normalize_attr_type(attr_type)
      end)
    end)
  end

  defp normalize_attr_type(type) when type in ["hr", "heartrate"], do: "heartrate"
  defp normalize_attr_type(type), do: type

  defp format_lens_label(attr_type) do
    attr_type
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end

  defp get_lens_icon(attr_type) do
    case attr_type do
      t when t in ["heartrate", "hr"] -> "heart"
      "ecg" -> "chart-bar"
      "imu" -> "cube"
      "geolocation" -> "map-pin"
      "battery" -> "battery-50"
      "temperature" -> "sun"
      "humidity" -> "cloud"
      "pressure" -> "arrow-down-circle"
      "accelerometer" -> "arrows-pointing-out"
      "gyroscope" -> "arrow-path"
      "spo2" -> "beaker"
      "steps" -> "arrow-trending-up"
      _ -> "signal"
    end
  end

  defp has_composite_view?(attr_type) do
    # These attribute types have dedicated composite Svelte components
    attr_type in ["heartrate", "hr", "imu", "geolocation", "ecg", "battery", "spo2"]
  end

  defp category_order(category) do
    case category do
      :health -> 1
      :location -> 2
      :motion -> 3
      :environment -> 4
      :device -> 5
      :activity -> 6
      _ -> 99
    end
  end

  # Extract composite data for a specific lens type
  defp extract_lens_data(sensors_state, lens_type) do
    case normalize_attr_type(lens_type) do
      "heartrate" -> extract_heartrate_data(sensors_state)
      "geolocation" -> extract_location_data(sensors_state)
      "imu" -> extract_imu_data(sensors_state)
      "ecg" -> extract_ecg_data(sensors_state)
      "battery" -> extract_battery_data(sensors_state)
      "spo2" -> extract_spo2_data(sensors_state)
      _ -> extract_generic_data(sensors_state, lens_type)
    end
  end

  defp extract_heartrate_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type in ["heartrate", "hr"]
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      hr_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
        attr.attribute_type in ["heartrate", "hr"]
      end)
      bpm = case hr_attr do
        {_attr_id, attr} -> attr.lastvalue && attr.lastvalue.payload || 0
        nil -> 0
      end
      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, bpm: bpm}
    end)
  end

  defp extract_location_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == "geolocation"
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      geo_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
        attr.attribute_type == "geolocation"
      end)
      position = case geo_attr do
        {_attr_id, attr} ->
          payload = attr.lastvalue && attr.lastvalue.payload
          case payload do
            %{"latitude" => lat, "longitude" => lng} -> %{latitude: lat, longitude: lng}
            %{latitude: lat, longitude: lng} -> %{latitude: lat, longitude: lng}
            _ -> nil
          end
        nil -> nil
      end
      if position do
        %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, position: position}
      else
        nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp extract_imu_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == "imu"
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name}
    end)
  end

  defp extract_ecg_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == "ecg"
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name}
    end)
  end

  defp extract_battery_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == "battery"
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      batt_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
        attr.attribute_type == "battery"
      end)
      level = case batt_attr do
        {_attr_id, attr} ->
          payload = attr.lastvalue && attr.lastvalue.payload
          case payload do
            %{"level" => lvl} -> lvl
            %{level: lvl} -> lvl
            _ -> nil
          end
        nil -> nil
      end
      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, level: level || 0}
    end)
  end

  defp extract_spo2_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == "spo2"
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      spo2_attr = Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
        attr.attribute_type == "spo2"
      end)
      spo2 = case spo2_attr do
        {_attr_id, attr} -> attr.lastvalue && attr.lastvalue.payload || 0
        nil -> 0
      end
      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, spo2: spo2}
    end)
  end

  defp extract_generic_data(sensors_state, attr_type) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == attr_type
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name}
    end)
  end

  defp normalize_room(%Sensocto.Sensors.Room{} = room) do
    %{
      id: room.id,
      name: room.name,
      description: room.description,
      owner_id: room.owner_id,
      owner: room.owner,
      join_code: room.join_code,
      is_public: room.is_public,
      is_persisted: true,
      calls_enabled: room.calls_enabled,
      configuration: room.configuration
    }
  end

  defp normalize_room(room), do: room

  defp get_owner_name(room) do
    case Map.get(room, :owner) do
      %{email: email} when not is_nil(email) ->
        email |> to_string() |> String.split("@") |> List.first()

      _ ->
        "Unknown"
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.breadcrumbs>
        <:crumb navigate={~p"/rooms"}>Rooms</:crumb>
        <:crumb><%= @room.name %></:crumb>
      </.breadcrumbs>

      <div class="mb-6">
        <div class="flex items-center gap-4 mb-2">
          <h1 class="text-2xl font-bold"><%= @room.name %></h1>
          <div class="flex gap-2">
            <%= if @room.is_public do %>
              <span class="px-2 py-1 text-xs bg-green-600/20 text-green-400 rounded">Public</span>
            <% else %>
              <span class="px-2 py-1 text-xs bg-yellow-600/20 text-yellow-400 rounded">Private</span>
            <% end %>
            <%= if not Map.get(@room, :is_persisted, true) do %>
              <span class="px-2 py-1 text-xs bg-purple-600/20 text-purple-400 rounded">Temporary</span>
            <% end %>
          </div>
        </div>
        <p class="text-sm text-gray-500">
          by <%= get_owner_name(@room) %>
        </p>
        <%= if @room.description do %>
          <p class="text-gray-400 mt-1"><%= @room.description %></p>
        <% end %>
      </div>

      <div class="flex gap-4 mb-8">
        <button
          phx-click="open_share_modal"
          class="bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
        >
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z" />
          </svg>
          Share
        </button>
        <%= if @is_member do %>
          <button
            phx-click="open_add_sensor_modal"
            class="bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6m0 0v6m0-6h6m-6 0H6" />
            </svg>
            Add Sensor
          </button>
        <% end %>
        <%= if @is_owner do %>
          <button
            phx-click="open_edit_modal"
            class="bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z" />
            </svg>
            Edit
          </button>
          <button
            phx-click="delete_room"
            data-confirm="Are you sure you want to delete this room? This action cannot be undone."
            class="bg-red-600 hover:bg-red-500 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
          >
            <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16" />
            </svg>
            Delete
          </button>
        <% else %>
          <%= if @is_member do %>
            <button
              phx-click="leave_room"
              data-confirm="Are you sure you want to leave this room? Your sensors will be disconnected from the room."
              class="bg-orange-600 hover:bg-orange-500 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1" />
              </svg>
              Leave Room
            </button>
          <% else %>
            <button
              phx-click="join_room"
              class="bg-green-600 hover:bg-green-500 text-white font-semibold py-2 px-4 rounded-lg transition-colors flex items-center gap-2"
            >
              <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z" />
              </svg>
              Join Room
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- Main content area: Video + Sensors side by side when in call --%>
      <div class={if @in_call and Map.get(@room, :calls_enabled, true), do: "grid grid-cols-1 lg:grid-cols-2 gap-6", else: ""}>
        <%!-- Video Conference Panel - only shows when calls are enabled --%>
        <%= if Map.get(@room, :calls_enabled, true) do %>
          <.live_component
            module={SensoctoWeb.Live.Calls.CallContainerComponent}
            id="call-container"
            room={@room}
            user={@current_user}
            in_call={@in_call}
            participants={@call_participants}
          />
        <% end %>

        <%!-- Media Player Panel --%>
        <div class="mb-6">
          <.live_component
            module={MediaPlayerComponent}
            id={"room-media-player-#{@room.id}"}
            room_id={@room.id}
            current_user={@current_user}
            can_manage={@can_manage}
          />
        </div>

        <%!-- Sensors Panel --%>
        <div class={if @in_call and Map.get(@room, :calls_enabled, true), do: "order-2", else: ""}>
          <%!-- Header with Lens Selector --%>
          <div class="flex items-center justify-between mb-4">
            <h2 class="text-xl font-semibold">Sensors</h2>

            <%!-- Lens Selector - only show if there are sensors with attributes --%>
            <%= if length(@available_lenses) > 0 do %>
              <div class="flex items-center gap-3">
                <%!-- Quick lens chips for common types --%>
                <div class="hidden sm:flex items-center gap-2">
                  <%= for lens <- Enum.take(@available_lenses, 4) do %>
                    <button
                      phx-click="select_lens"
                      phx-value-lens={lens.type}
                      class={"px-2 py-1 text-xs rounded-full transition-colors flex items-center gap-1 " <>
                        if(@current_lens == lens.type,
                          do: "bg-orange-500 text-white",
                          else: "bg-gray-700 text-gray-300 hover:bg-gray-600")}
                      title={"#{lens.sensor_count} sensor(s)"}
                    >
                      <Heroicons.icon name={lens.icon} type="outline" class="h-3 w-3" />
                      {lens.label}
                    </button>
                  <% end %>
                </div>

                <%!-- Lens Dropdown for all types --%>
                <form phx-change="select_lens" class="flex items-center gap-2">
                  <select
                    name="lens"
                    class="bg-gray-700 border border-gray-600 text-white text-sm rounded-lg px-3 py-1.5 focus:ring-orange-500 focus:border-orange-500"
                  >
                    <option value="">All Sensors</option>
                    <optgroup label="Health">
                      <%= for lens <- Enum.filter(@available_lenses, & &1.category == :health) do %>
                        <option value={lens.type} selected={@current_lens == lens.type}>
                          {lens.label} ({lens.sensor_count})
                        </option>
                      <% end %>
                    </optgroup>
                    <optgroup label="Location">
                      <%= for lens <- Enum.filter(@available_lenses, & &1.category == :location) do %>
                        <option value={lens.type} selected={@current_lens == lens.type}>
                          {lens.label} ({lens.sensor_count})
                        </option>
                      <% end %>
                    </optgroup>
                    <optgroup label="Motion">
                      <%= for lens <- Enum.filter(@available_lenses, & &1.category == :motion) do %>
                        <option value={lens.type} selected={@current_lens == lens.type}>
                          {lens.label} ({lens.sensor_count})
                        </option>
                      <% end %>
                    </optgroup>
                    <optgroup label="Environment">
                      <%= for lens <- Enum.filter(@available_lenses, & &1.category == :environment) do %>
                        <option value={lens.type} selected={@current_lens == lens.type}>
                          {lens.label} ({lens.sensor_count})
                        </option>
                      <% end %>
                    </optgroup>
                    <optgroup label="Device">
                      <%= for lens <- Enum.filter(@available_lenses, & &1.category == :device) do %>
                        <option value={lens.type} selected={@current_lens == lens.type}>
                          {lens.label} ({lens.sensor_count})
                        </option>
                      <% end %>
                    </optgroup>
                    <optgroup label="Activity">
                      <%= for lens <- Enum.filter(@available_lenses, & &1.category == :activity) do %>
                        <option value={lens.type} selected={@current_lens == lens.type}>
                          {lens.label} ({lens.sensor_count})
                        </option>
                      <% end %>
                    </optgroup>
                  </select>
                </form>

                <%!-- Clear lens button --%>
                <%= if @current_lens do %>
                  <button
                    phx-click="clear_lens"
                    class="text-gray-400 hover:text-white p-1"
                    title="Show all sensors"
                  >
                    <Heroicons.icon name="x-mark" type="outline" class="h-4 w-4" />
                  </button>
                <% end %>
              </div>
            <% end %>
          </div>

          <%= if Enum.empty?(@sensors) do %>
            <div class="bg-gray-800 rounded-lg p-8 text-center">
              <svg class="w-16 h-16 mx-auto text-gray-600 mb-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
              </svg>
              <p class="text-gray-400 mb-4">No sensors in this room yet.</p>
              <%= if @can_manage do %>
                <button
                  phx-click="open_add_sensor_modal"
                  class="text-blue-400 hover:text-blue-300"
                >
                  Add your first sensor
                </button>
              <% end %>
            </div>
          <% else %>
            <%!-- Composite Lens View --%>
            <%= if @current_lens do %>
              <div class="mb-6">
                <.lens_composite_view
                  lens_type={@current_lens}
                  lens_data={@lens_data}
                  socket={@socket}
                />
              </div>
            <% end %>

            <%!-- Sensor Grid --%>
            <div class={
              if @in_call,
                do: "grid gap-3 grid-cols-1 xl:grid-cols-2",
                else: "grid gap-4 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 2xl:grid-cols-5"
            }>
              <%= for sensor <- @sensors do %>
                <div id={"room_sensor_container_#{sensor.sensor_id}"}>
                  {live_render(@socket, SensoctoWeb.StatefulSensorLive,
                    id: "room_sensor_#{sensor.sensor_id}",
                    session: %{"parent_pid" => self(), "sensor_id" => sensor.sensor_id}
                  )}
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      </div>

      <%= if @show_share_modal do %>
        <.share_modal room={@room} />
      <% end %>

      <%= if @show_add_sensor_modal do %>
        <.add_sensor_modal available_sensors={@available_sensors} />
      <% end %>

      <%= if @show_edit_modal do %>
        <.edit_room_modal form={@edit_form} room={@room} />
      <% end %>

      <%= if @show_settings do %>
        <.settings_panel room={@room} is_owner={@is_owner} />
      <% end %>
    </div>
    """
  end

  # Lens composite view component - renders the appropriate Svelte component for each lens type
  defp lens_composite_view(assigns) do
    ~H"""
    <div id="lens-composite-view" phx-hook="CompositeMeasurementHandler" class="bg-gray-800 rounded-lg p-4">
      <%= case normalize_attr_type(@lens_type) do %>
        <% "heartrate" -> %>
          <.svelte
            name="CompositeHeartrate"
            props={%{sensors: @lens_data}}
            socket={@socket}
            class="w-full"
          />
        <% "geolocation" -> %>
          <.svelte
            name="CompositeGeolocation"
            props={%{positions: Enum.map(@lens_data, fn d ->
              %{
                lat: d.position[:latitude] || d.position["latitude"],
                lng: d.position[:longitude] || d.position["longitude"],
                sensor_id: d.sensor_id,
                sensor_name: d.sensor_name
              }
            end)}}
            socket={@socket}
            class="w-full"
          />
        <% "imu" -> %>
          <.svelte
            name="CompositeIMU"
            props={%{sensors: @lens_data}}
            socket={@socket}
            class="w-full"
          />
        <% "ecg" -> %>
          <.svelte
            name="CompositeECG"
            props={%{sensors: @lens_data}}
            socket={@socket}
            class="w-full"
          />
        <% "battery" -> %>
          <.svelte
            name="CompositeBattery"
            props={%{sensors: @lens_data}}
            socket={@socket}
            class="w-full"
          />
        <% "spo2" -> %>
          <.svelte
            name="CompositeSpo2"
            props={%{sensors: @lens_data}}
            socket={@socket}
            class="w-full"
          />
        <% _ -> %>
          <%!-- Generic lens view - show list of matching sensors --%>
          <div class="text-gray-400">
            <p class="text-sm mb-2">Sensors with {format_lens_label(@lens_type)}:</p>
            <div class="grid grid-cols-2 sm:grid-cols-3 md:grid-cols-4 gap-2">
              <%= for sensor <- @lens_data do %>
                <div class="bg-gray-700 rounded px-3 py-2 text-sm">
                  <p class="text-white truncate">{sensor.sensor_name}</p>
                  <p class="text-xs text-gray-500">{sensor.sensor_id}</p>
                </div>
              <% end %>
            </div>
          </div>
      <% end %>
    </div>
    """
  end

  defp sensor_icon(assigns) do
    ~H"""
    <svg class="w-6 h-6 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <%= case @type do %>
        <% :ecg -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z" />
        <% :imu -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 10l-2 1m0 0l-2-1m2 1v2.5M20 7l-2 1m2-1l-2-1m2 1v2.5M14 4l-2-1-2 1M4 7l2-1M4 7l2 1M4 7v2.5M12 21l-2-1m2 1l2-1m-2 1v-2.5M6 18l-2-1v-2.5M18 18l2-1v-2.5" />
        <% _ -> %>
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z" />
      <% end %>
    </svg>
    """
  end

  defp share_modal(assigns) do
    share_url = Sensocto.Rooms.share_url(assigns.room)

    assigns = assign(assigns, :share_url, share_url)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4 sm:p-6" phx-click="close_share_modal">
      <div class="bg-gray-800 rounded-lg p-4 sm:p-6 w-full max-w-md max-h-[90vh] overflow-y-auto" phx-click-away="close_share_modal">
        <div class="flex justify-between items-center mb-4 sm:mb-6">
          <h2 class="text-lg sm:text-xl font-semibold">Share Room</h2>
          <button phx-click="close_share_modal" class="text-gray-400 hover:text-white p-1">
            <svg class="w-5 h-5 sm:w-6 sm:h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="text-center mb-4 sm:mb-6">
          <p class="text-gray-400 text-sm mb-2">Join Code</p>
          <p class="text-2xl sm:text-4xl font-mono font-bold tracking-wider"><%= @room.join_code %></p>
        </div>

        <div class="mb-4 sm:mb-6">
          <p class="text-gray-400 text-sm mb-2">Share Link</p>
          <div class="flex flex-col sm:flex-row gap-2">
            <input
              type="text"
              readonly
              value={@share_url}
              class="flex-1 bg-gray-700 border border-gray-600 rounded-lg px-3 sm:px-4 py-2 text-white text-xs sm:text-sm truncate"
              id="share-url-input"
            />
            <button
              phx-click="copy_link"
              phx-hook="CopyToClipboard"
              id="copy-link-btn"
              data-copy-text={@share_url}
              class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition-colors text-sm sm:text-base whitespace-nowrap"
            >
              Copy Link
            </button>
          </div>
        </div>

        <div class="flex justify-center p-3 sm:p-4 bg-white rounded-lg">
          <div id="qr-code" phx-hook="QRCode" data-value={@share_url} class="w-36 h-36 sm:w-48 sm:h-48"></div>
        </div>
      </div>
    </div>
    """
  end

  defp add_sensor_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50" phx-click="close_add_sensor_modal">
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md max-h-[80vh] overflow-y-auto" phx-click-away="close_add_sensor_modal">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Add Sensor</h2>
          <button phx-click="close_add_sensor_modal" class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <%= if Enum.empty?(@available_sensors) do %>
          <p class="text-gray-400 text-center py-8">No available sensors to add.</p>
        <% else %>
          <div class="space-y-2">
            <%= for sensor <- @available_sensors do %>
              <div class="flex items-center justify-between p-3 bg-gray-700 rounded-lg">
                <div class="flex items-center gap-3">
                  <div class="p-2 bg-gray-600 rounded">
                    <.sensor_icon type={sensor.sensor_type} />
                  </div>
                  <div>
                    <p class="font-medium"><%= sensor.sensor_name %></p>
                    <p class="text-xs text-gray-400"><%= sensor.sensor_type %></p>
                  </div>
                </div>
                <button
                  phx-click="add_sensor"
                  phx-value-sensor_id={sensor.sensor_id}
                  class="bg-blue-600 hover:bg-blue-700 text-white px-3 py-1 rounded text-sm transition-colors"
                >
                  Add
                </button>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp edit_room_modal(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50" phx-click="close_edit_modal">
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md" phx-click={%JS{}}>
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Edit Room</h2>
          <button phx-click="close_edit_modal" class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <.form for={@form} phx-submit="save_room" phx-change="validate_edit" class="space-y-4">
          <div>
            <label for="name" class="block text-sm font-medium text-gray-300 mb-1">Room Name</label>
            <input
              type="text"
              name="name"
              id="name"
              value={@form[:name].value}
              required
              class="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Enter room name..."
            />
          </div>

          <div>
            <label for="description" class="block text-sm font-medium text-gray-300 mb-1">Description</label>
            <textarea
              name="description"
              id="description"
              rows="3"
              class="w-full bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white focus:outline-none focus:ring-2 focus:ring-blue-500"
              placeholder="Optional description..."
            ><%= @form[:description].value %></textarea>
          </div>

          <div class="space-y-3">
            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="is_public"
                checked={@form[:is_public].value}
                class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
              />
              <span class="text-sm text-gray-300">Public room</span>
            </label>

            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="calls_enabled"
                checked={@form[:calls_enabled].value}
                class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
              />
              <span class="text-sm text-gray-300">Enable video/audio calls</span>
            </label>
          </div>

          <div class="flex gap-3 pt-4">
            <button
              type="button"
              phx-click="close_edit_modal"
              class="flex-1 bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-4 rounded-lg transition-colors"
            >
              Cancel
            </button>
            <button
              type="submit"
              class="flex-1 bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-4 rounded-lg transition-colors"
            >
              Save Changes
            </button>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp settings_panel(assigns) do
    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50">
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Room Settings</h2>
          <.link patch={~p"/rooms/#{@room.id}"} class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </.link>
        </div>

        <div class="space-y-4">
          <div class="p-4 bg-gray-700 rounded-lg">
            <h3 class="font-medium mb-2">Join Code</h3>
            <p class="text-2xl font-mono mb-3"><%= @room.join_code %></p>
            <%= if @is_owner and Map.get(@room, :is_persisted, true) do %>
              <button
                phx-click="regenerate_code"
                class="text-blue-400 hover:text-blue-300 text-sm"
              >
                Regenerate Code
              </button>
            <% end %>
          </div>

          <div class="p-4 bg-gray-700 rounded-lg">
            <h3 class="font-medium mb-2">Room Info</h3>
            <dl class="space-y-2 text-sm">
              <div class="flex justify-between">
                <dt class="text-gray-400">Type</dt>
                <dd><%= if Map.get(@room, :is_persisted, true), do: "Persisted", else: "Temporary" %></dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-400">Visibility</dt>
                <dd><%= if @room.is_public, do: "Public", else: "Private" %></dd>
              </div>
            </dl>
          </div>

          <%= if @is_owner do %>
            <div class="p-4 bg-gray-700 rounded-lg">
              <h3 class="font-medium mb-3">Features</h3>
              <label class="flex items-center justify-between cursor-pointer">
                <span class="text-sm text-gray-300">Video/Audio Calls</span>
                <button
                  type="button"
                  phx-click="toggle_calls_enabled"
                  class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors #{if Map.get(@room, :calls_enabled, true), do: "bg-blue-600", else: "bg-gray-600"}"}
                >
                  <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if Map.get(@room, :calls_enabled, true), do: "translate-x-6", else: "translate-x-1"}"} />
                </button>
              </label>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

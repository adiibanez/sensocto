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
  alias Sensocto.Accounts.UserPreferences
  alias Sensocto.AttentionTracker
  alias Sensocto.Media.MediaPlayerServer
  alias Sensocto.Object3D.Object3DPlayerServer
  alias Sensocto.Types.AttributeType
  alias Phoenix.PubSub
  alias SensoctoWeb.Live.Components.MediaPlayerComponent
  alias SensoctoWeb.Live.Components.Object3DPlayerComponent
  alias SensoctoWeb.Live.Calls.MiniCallIndicatorComponent
  alias SensoctoWeb.Sensocto.Presence

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

          # Subscribe to object3d events for this room
          PubSub.subscribe(Sensocto.PubSub, "object3d:#{room_id}")

          # Subscribe to global sensor events to auto-join web connector sensors
          PubSub.subscribe(Sensocto.PubSub, "sensors:global")

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
          |> assign(:call_speaking, false)
          # Room mode for tab switching (will be set properly by handle_params)
          |> assign(:room_mode, get_default_mode(room))
          # Room members (loaded when settings panel is opened)
          |> assign(:room_members, [])
          # Bump animation assigns for mode buttons
          |> assign(:media_bump, false)
          |> assign(:object3d_bump, false)
          # Control request modal state
          |> assign(:control_request_modal, nil)
          |> assign(:media_control_request_modal, nil)
          # Timer refs for auto-transfer on timeout
          |> assign(:media_control_request_timer, nil)
          # Initialize object3d controller from server state
          |> assign(:object3d_controller_user_id, get_object3d_controller(room_id))
          # Controller user IDs for request modals
          |> assign(:media_controller_user_id, nil)
          # Room mode presence counts
          |> assign(:media_viewers, 0)
          |> assign(:object3d_viewers, 0)

        # Track and subscribe to room mode presence
        # Generate a unique presence key for this connection (allows multiple tabs per user)
        presence_key = "#{user && user.id}:#{System.unique_integer([:positive])}"

        socket =
          if connected?(socket) and user do
            # Subscribe to room mode presence updates
            PubSub.subscribe(Sensocto.PubSub, "room:#{room_id}:mode_presence")

            # Track this connection's presence with their current room mode
            # Using a unique key per connection to count each tab separately
            default_mode = get_default_mode(room)

            Presence.track(self(), "room:#{room_id}:mode_presence", presence_key, %{
              room_mode: default_mode,
              user_id: user.id
            })

            # Get initial presence counts
            {media_count, object3d_count} = count_room_mode_presence(room_id)

            socket
            |> assign(:presence_key, presence_key)
            |> assign(:media_viewers, media_count)
            |> assign(:object3d_viewers, object3d_count)
          else
            assign(socket, :presence_key, presence_key)
          end

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

  defp apply_action(socket, :show, params) do
    # Get mode from query param, user preference, or default
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id
    room = socket.assigns.room

    mode =
      case params["mode"] do
        "media" ->
          :media

        "call" ->
          :call

        "object3d" ->
          :object3d

        "sensors" ->
          :sensors

        nil ->
          # Try user preference, then room default
          if user_id do
            saved_mode = UserPreferences.get_ui_state(user_id, "room_mode_#{room.id}")

            if saved_mode do
              String.to_existing_atom(saved_mode)
            else
              get_default_mode(room)
            end
          else
            get_default_mode(room)
          end

        _ ->
          get_default_mode(room)
      end

    # Update presence to reflect new mode
    user = socket.assigns[:current_user]
    presence_key = socket.assigns[:presence_key]

    if user && presence_key do
      Presence.update(self(), "room:#{room.id}:mode_presence", presence_key, %{
        room_mode: mode,
        user_id: user.id
      })
    end

    socket
    |> assign(:show_settings, false)
    |> assign(:room_mode, mode)
  end

  defp apply_action(socket, :settings, _params) do
    if socket.assigns.can_manage do
      # Load room members for the settings panel
      room_members =
        case Rooms.list_members(socket.assigns.room) do
          {:ok, members} -> members
          {:error, _} -> []
        end

      socket
      |> assign(:show_settings, true)
      |> assign(:room_members, room_members)
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

    {:noreply,
     socket |> assign(:show_edit_modal, true) |> assign(:edit_form, build_edit_form(room))}
  end

  @impl true
  def handle_event("close_edit_modal", _params, socket) do
    {:noreply, assign(socket, :show_edit_modal, false)}
  end

  @impl true
  def handle_event("producer_mode_changed", %{"mode" => _mode, "tier" => _tier}, socket) do
    # Handle producer mode changes from video call hook - just acknowledge the event
    {:noreply, socket}
  end

  @impl true
  def handle_event("speaking_changed", %{"speaking" => speaking}, socket) do
    # Handle speaking state changes from video call hook
    {:noreply, assign(socket, :call_speaking, speaking)}
  end

  @impl true
  def handle_event(
        "participant_speaking",
        %{"speaking" => _speaking, "user_id" => _user_id},
        socket
      ) do
    # Handle participant speaking state changes from video call hook - just acknowledge the event
    {:noreply, socket}
  end

  # Catch-all for video call hook events that don't need special handling
  @call_events ~w(
    my_tier_changed tier_changed quality_changed webrtc_stats
    call_state_changed call_joined call_left call_error call_reconnecting call_reconnected
    call_joining_retry connection_state_changed connection_unhealthy
    participant_joined participant_left participant_audio_changed participant_video_changed
    consumer_mode_changed track_ready track_removed channel_reconnecting socket_error
  )
  @impl true
  def handle_event(event, _params, socket) when event in @call_events do
    {:noreply, socket}
  end

  @impl true
  def handle_event("validate_edit", params, socket) do
    form =
      to_form(%{
        "name" => params["name"] || "",
        "description" => params["description"] || "",
        "is_public" => Map.has_key?(params, "is_public"),
        "calls_enabled" => Map.has_key?(params, "calls_enabled"),
        "media_playback_enabled" => Map.has_key?(params, "media_playback_enabled"),
        "object_3d_enabled" => Map.has_key?(params, "object_3d_enabled")
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
      calls_enabled: Map.has_key?(params, "calls_enabled"),
      media_playback_enabled: Map.has_key?(params, "media_playback_enabled"),
      object_3d_enabled: Map.has_key?(params, "object_3d_enabled")
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
      {:noreply,
       put_flash(
         socket,
         :error,
         "Room owners cannot leave. Transfer ownership or delete the room."
       )}
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
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id
    old_lens = socket.assigns[:current_lens]
    old_lens_data = socket.assigns[:lens_data] || []

    # Unregister attention for previous lens sensors
    if user_id && old_lens && is_list(old_lens_data) do
      normalized_old_attr = normalize_attr_type(old_lens)

      Enum.each(old_lens_data, fn sensor ->
        sensor_id = sensor[:sensor_id] || sensor["sensor_id"]

        if sensor_id do
          AttentionTracker.unregister_view(sensor_id, normalized_old_attr, user_id)
        end
      end)
    end

    lens_data =
      if lens_type do
        extract_lens_data(socket.assigns.sensors_state, lens_type)
      else
        []
      end

    # Register attention for new lens sensors
    if user_id && lens_type && is_list(lens_data) do
      normalized_attr = normalize_attr_type(lens_type)

      Enum.each(lens_data, fn sensor ->
        sensor_id = sensor[:sensor_id] || sensor["sensor_id"]

        if sensor_id do
          AttentionTracker.register_view(sensor_id, normalized_attr, user_id)
        end
      end)
    end

    {:noreply,
     socket
     |> assign(:current_lens, lens_type)
     |> assign(:lens_data, lens_data)}
  end

  @impl true
  def handle_event("clear_lens", _params, socket) do
    user_id = socket.assigns[:current_user] && socket.assigns.current_user.id
    old_lens = socket.assigns[:current_lens]
    old_lens_data = socket.assigns[:lens_data] || []

    # Unregister attention for lens sensors
    if user_id && old_lens && is_list(old_lens_data) do
      normalized_attr = normalize_attr_type(old_lens)

      Enum.each(old_lens_data, fn sensor ->
        sensor_id = sensor[:sensor_id] || sensor["sensor_id"]

        if sensor_id do
          AttentionTracker.unregister_view(sensor_id, normalized_attr, user_id)
        end
      end)
    end

    {:noreply,
     socket
     |> assign(:current_lens, nil)
     |> assign(:lens_data, [])}
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

  @impl true
  def handle_event("toggle_media_playback_enabled", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    new_value = not Map.get(room, :media_playback_enabled, true)

    case Rooms.update_room(room, %{media_playback_enabled: new_value}, user) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, normalize_room(updated_room))
          |> put_flash(
            :info,
            if(new_value, do: "Media playback enabled", else: "Media playback disabled")
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update room settings")}
    end
  end

  @impl true
  def handle_event("toggle_object_3d_enabled", _params, socket) do
    room = socket.assigns.room
    user = socket.assigns.current_user

    new_value = not Map.get(room, :object_3d_enabled, false)

    case Rooms.update_room(room, %{object_3d_enabled: new_value}, user) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, normalize_room(updated_room))
          |> put_flash(
            :info,
            if(new_value, do: "3D objects enabled", else: "3D objects disabled")
          )

        {:noreply, socket}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to update room settings")}
    end
  end

  # Member management events
  @impl true
  def handle_event("promote_to_admin", %{"user-id" => user_id}, socket) do
    room = socket.assigns.room
    acting_user = socket.assigns.current_user

    user_to_promote = %{id: user_id}

    case Rooms.promote_to_admin(room, user_to_promote, acting_user) do
      {:ok, _} ->
        # Reload members list
        room_members =
          case Rooms.list_members(room) do
            {:ok, members} -> members
            {:error, _} -> []
          end

        socket =
          socket
          |> assign(:room_members, room_members)
          |> put_flash(:info, "User promoted to admin")

        {:noreply, socket}

      {:error, :not_owner} ->
        {:noreply, put_flash(socket, :error, "Only the owner can promote members")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to promote user")}
    end
  end

  @impl true
  def handle_event("demote_to_member", %{"user-id" => user_id}, socket) do
    room = socket.assigns.room
    acting_user = socket.assigns.current_user

    user_to_demote = %{id: user_id}

    case Rooms.demote_to_member(room, user_to_demote, acting_user) do
      {:ok, _} ->
        # Reload members list
        room_members =
          case Rooms.list_members(room) do
            {:ok, members} -> members
            {:error, _} -> []
          end

        socket =
          socket
          |> assign(:room_members, room_members)
          |> put_flash(:info, "User demoted to member")

        {:noreply, socket}

      {:error, :not_owner} ->
        {:noreply, put_flash(socket, :error, "Only the owner can demote admins")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to demote user")}
    end
  end

  @impl true
  def handle_event("kick_member", %{"user-id" => user_id}, socket) do
    room = socket.assigns.room
    acting_user = socket.assigns.current_user

    user_to_kick = %{id: user_id}

    case Rooms.kick_member(room, user_to_kick, acting_user) do
      {:ok, _} ->
        # Reload members list
        room_members =
          case Rooms.list_members(room) do
            {:ok, members} -> members
            {:error, _} -> []
          end

        socket =
          socket
          |> assign(:room_members, room_members)
          |> put_flash(:info, "User removed from room")

        {:noreply, socket}

      {:error, :cannot_kick_self} ->
        {:noreply, put_flash(socket, :error, "You cannot kick yourself")}

      {:error, :cannot_kick_admin_or_owner} ->
        {:noreply, put_flash(socket, :error, "Admins cannot kick other admins or the owner")}

      {:error, :not_authorized} ->
        {:noreply, put_flash(socket, :error, "You don't have permission to kick members")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Failed to remove user")}
    end
  end

  # Room mode switching (tabs)
  @impl true
  def handle_event("switch_room_mode", %{"mode" => mode}, socket) do
    room_id = socket.assigns.room.id

    # Save preference if user is logged in
    if user = socket.assigns[:current_user] do
      UserPreferences.set_ui_state(user.id, "room_mode_#{room_id}", mode)
    end

    # Push patch to update URL (triggers handle_params)
    {:noreply, push_patch(socket, to: ~p"/rooms/#{room_id}?mode=#{mode}")}
  end

  # Object3D player hook events
  @impl true
  def handle_event("viewer_ready", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("loading_started", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("loading_complete", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("loading_error", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("camera_moved", _params, socket), do: {:noreply, socket}

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

  # Quick join call from persistent call controls bar (one-click join)
  @impl true
  def handle_event("quick_join_call", %{"mode" => mode}, socket) do
    # Join the call but DON'T switch tabs - user stays on current view (media, 3D object, etc.)
    # The call controls bar provides full access to call features regardless of active tab
    socket = push_event(socket, "join_call", %{mode: mode})
    {:noreply, socket}
  end

  # Leave call from persistent call controls bar
  @impl true
  def handle_event("leave_call", _params, socket) do
    socket = push_event(socket, "leave_call", %{})
    {:noreply, assign(socket, :in_call, false)}
  end

  # Toggle audio from persistent call controls bar
  @impl true
  def handle_event("toggle_call_audio", _params, socket) do
    socket = push_event(socket, "toggle_audio", %{})
    {:noreply, socket}
  end

  # Toggle video from persistent call controls bar
  @impl true
  def handle_event("toggle_call_video", _params, socket) do
    socket = push_event(socket, "toggle_video", %{})
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

  @impl true
  def handle_event("dismiss_control_request", _, socket) do
    # "Keep Control" - cancel the pending request timer on the server
    room_id = socket.assigns.room.id
    current_user = socket.assigns.current_user

    if current_user do
      alias Sensocto.Object3D.Object3DPlayerServer
      Object3DPlayerServer.keep_control(room_id, current_user.id)
    end

    {:noreply, assign(socket, :control_request_modal, nil)}
  end

  @impl true
  def handle_event("release_control_from_modal", _, socket) do
    room_id = socket.assigns.room.id
    current_user = socket.assigns.current_user
    modal_data = socket.assigns.control_request_modal

    if current_user && modal_data do
      # First release control from current user
      Object3DPlayerServer.release_control(room_id, current_user.id)

      # Then give control to the requester
      Object3DPlayerServer.take_control(
        room_id,
        modal_data.requester_id,
        modal_data.requester_name
      )

      Logger.info(
        "[RoomShowLive] Control transferred from #{current_user.id} to #{modal_data.requester_id}"
      )
    end

    {:noreply, assign(socket, :control_request_modal, nil)}
  end

  # Media control request modal handlers
  @impl true
  def handle_event("dismiss_media_control_request", _, socket) do
    room_id = socket.assigns.room.id
    current_user = socket.assigns[:current_user]

    # Use server's keep_control to cancel the request and notify others
    if current_user do
      alias Sensocto.Media.MediaPlayerServer
      MediaPlayerServer.keep_control(room_id, current_user.id)
    end

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  @impl true
  def handle_event("release_media_control_from_modal", _, socket) do
    room_id = socket.assigns.room.id
    current_user = socket.assigns.current_user
    modal_data = socket.assigns.media_control_request_modal

    if current_user && modal_data do
      alias Sensocto.Media.MediaPlayerServer

      # First release control from current user
      MediaPlayerServer.release_control(room_id, current_user.id)

      # Then give control to the requester
      MediaPlayerServer.take_control(
        room_id,
        modal_data.requester_id,
        modal_data.requester_name
      )
    end

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  # Handle room mode presence diffs (for viewer counts)
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{
          topic: "room:" <> _rest,
          event: "presence_diff"
        },
        socket
      ) do
    room_id = socket.assigns.room.id
    {media_count, object3d_count} = count_room_mode_presence(room_id)

    {:noreply,
     socket
     |> assign(:media_viewers, media_count)
     |> assign(:object3d_viewers, object3d_count)}
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

    socket =
      socket
      |> assign(:sensor_activity, activity)
      |> maybe_refresh_lenses()

    # Push composite_measurement event when lens is active
    socket =
      if socket.assigns[:current_lens] do
        # Look up username from sensors_state for display
        username =
          case Map.get(socket.assigns.sensors_state, sensor_id) do
            %{username: name} when not is_nil(name) -> name
            _ -> nil
          end

        push_event(socket, "composite_measurement", %{
          sensor_id: sensor_id,
          username: username,
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

    socket =
      socket
      |> assign(:sensor_activity, activity)
      |> maybe_refresh_lenses()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:measurements_batch, {sensor_id, measurements_list}}, socket)
      when is_list(measurements_list) do
    activity = Map.put(socket.assigns.sensor_activity, sensor_id, DateTime.utc_now())

    socket =
      socket
      |> assign(:sensor_activity, activity)
      |> maybe_refresh_lenses()

    # Push composite_measurement events when lens is active
    socket =
      if socket.assigns[:current_lens] do
        # Look up username from sensors_state for display
        username =
          case Map.get(socket.assigns.sensors_state, sensor_id) do
            %{username: name} when not is_nil(name) -> name
            _ -> nil
          end

        # Get latest measurement per attribute
        latest_by_attr =
          measurements_list
          |> Enum.group_by(& &1.attribute_id)
          |> Enum.map(fn {attr_id, measurements} ->
            latest = Enum.max_by(measurements, & &1.timestamp)

            %{
              sensor_id: sensor_id,
              username: username,
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

    socket =
      socket
      |> assign(:sensor_activity, activity)
      |> maybe_refresh_lenses()

    {:noreply, socket}
  end

  @impl true
  def handle_info({:room_update, _message}, socket) do
    case Rooms.get_room_with_sensors(socket.assigns.room.id) do
      {:ok, updated_room} ->
        sensors = updated_room.sensors || []
        sensors_state = get_sensors_state(sensors)
        available_lenses = extract_available_lenses(sensors_state)

        socket =
          socket
          |> assign(:room, updated_room)
          |> assign(:sensors, sensors)
          |> assign(:sensors_state, sensors_state)
          |> assign(:available_lenses, available_lenses)

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(:update_activity, socket) do
    Process.send_after(self(), :update_activity, @activity_check_interval)

    # Refresh sensors state and available lenses to detect new attributes
    sensors = socket.assigns.sensors
    sensors_state = get_sensors_state(sensors)
    new_lenses = extract_available_lenses(sensors_state)

    # Only update if lenses changed (avoid unnecessary re-renders)
    current_lens_types = Enum.map(socket.assigns.available_lenses, & &1.type) |> MapSet.new()
    new_lens_types = Enum.map(new_lenses, & &1.type) |> MapSet.new()

    socket =
      if MapSet.equal?(current_lens_types, new_lens_types) do
        socket
      else
        socket
        |> assign(:sensors_state, sensors_state)
        |> assign(:available_lenses, new_lenses)
      end

    {:noreply, assign(socket, :sensor_activity, socket.assigns.sensor_activity)}
  end

  # Handle global sensor online events - auto-join web connector sensors to room
  @impl true
  def handle_info({:sensor_online, sensor_id, configuration}, socket) do
    # Get the current user to check if this sensor belongs to them
    user = socket.assigns.current_user
    sensor_username = Map.get(configuration, :username)

    # Auto-join sensor if it belongs to the current user (matching username from email)
    user_username =
      if user && user.email do
        user.email |> to_string() |> String.split("@") |> List.first()
      else
        nil
      end

    # Only auto-join if:
    # 1. The sensor has a username that matches the current user
    # 2. OR the sensor doesn't have a username (legacy support)
    should_join =
      (sensor_username && user_username && sensor_username == user_username) ||
        (!sensor_username && user)

    if should_join do
      # Check if sensor is already in the room
      current_sensor_ids = Enum.map(socket.assigns.sensors, & &1.sensor_id) |> MapSet.new()

      if not MapSet.member?(current_sensor_ids, sensor_id) do
        Logger.debug("Auto-joining sensor #{sensor_id} to room #{socket.assigns.room.id}")

        # Subscribe to sensor data
        PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")

        # Create a minimal sensor struct for the list
        new_sensor = %{sensor_id: sensor_id}
        sensors = [new_sensor | socket.assigns.sensors]

        # Refresh sensor state and lenses
        sensors_state = get_sensors_state(sensors)
        available_lenses = extract_available_lenses(sensors_state)

        {:noreply,
         socket
         |> assign(:sensors, sensors)
         |> assign(:sensors_state, sensors_state)
         |> assign(:available_lenses, available_lenses)
         |> assign(:sensor_activity, build_activity_map(sensors))}
      else
        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  # Handle sensor offline events
  @impl true
  def handle_info({:sensor_offline, sensor_id}, socket) do
    # Remove sensor from the room's list
    sensors = Enum.reject(socket.assigns.sensors, &(&1.sensor_id == sensor_id))

    # Refresh sensor state and lenses
    sensors_state = get_sensors_state(sensors)
    available_lenses = extract_available_lenses(sensors_state)

    {:noreply,
     socket
     |> assign(:sensors, sensors)
     |> assign(:sensors_state, sensors_state)
     |> assign(:available_lenses, available_lenses)
     |> assign(:sensor_activity, build_activity_map(sensors))}
  end

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
  def handle_info(
        {:media_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name} = params},
        socket
      ) do
    room_id = socket.assigns.room.id
    pending_request_user_id = Map.get(params, :pending_request_user_id)

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
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

  # Object3D PubSub handlers
  @impl true
  def handle_info(
        {:object3d_item_changed,
         %{item: item, camera_position: camera_position, camera_target: camera_target}},
        socket
      ) do
    room_id = socket.assigns.room.id

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      current_item: item,
      camera_position: camera_position,
      camera_target: camera_target
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:object3d_camera_synced,
         %{camera_position: camera_position, camera_target: camera_target, user_id: user_id} =
           event},
        socket
      ) do
    room_id = socket.assigns.room.id
    current_user_id = socket.assigns.current_user && socket.assigns.current_user.id

    # Don't forward camera sync to the controller themselves - they're the source
    if user_id != current_user_id do
      send_update(Object3DPlayerComponent,
        id: "object3d-player-#{room_id}",
        synced_camera_position: camera_position,
        synced_camera_target: camera_target
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

  @impl true
  def handle_info({:object3d_playlist_updated, %{items: items}}, socket) do
    room_id = socket.assigns.room.id

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      playlist_items: items
    )

    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:object3d_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name}},
        socket
      ) do
    room_id = socket.assigns.room.id

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      controller_user_id: user_id,
      controller_user_name: user_name,
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    # Store controller info in socket for control request handling
    {:noreply,
     socket
     |> assign(:object3d_controller_user_id, user_id)}
  end

  # Handle object3d control request with 30s timeout (server-managed)
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
    room_id = socket.assigns.room.id
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:object3d_controller_user_id]

    # Update component with pending request info
    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      pending_request_user_id: requester_id,
      pending_request_user_name: requester_name
    )

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

  # Handle object3d control request denied (keep control was clicked)
  @impl true
  def handle_info(
        {:object3d_control_request_denied, %{requester_id: _requester_id}},
        socket
      ) do
    room_id = socket.assigns.room.id

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    # Also dismiss the modal if it's open
    {:noreply, assign(socket, :control_request_modal, nil)}
  end

  @impl true
  def handle_info(
        {:control_requested, %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:object3d_controller_user_id]

    Logger.debug(
      "[RoomShowLive] Control requested by #{requester_name} (#{requester_id}). " <>
        "Current user: #{inspect(current_user && current_user.id)}, Controller: #{inspect(controller_user_id)}"
    )

    # Only show the modal to the current controller
    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      Logger.info("[RoomShowLive] Showing control request modal to controller")

      {:noreply,
       socket
       |> assign(:control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      Logger.debug("[RoomShowLive] Not showing modal - user is not the controller")
      {:noreply, socket}
    end
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
    room_id = socket.assigns.room.id

    # Update all clients with pending request info (for requester countdown display)
    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
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
    room_id = socket.assigns.room.id

    # Clear pending request in component
    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      pending_request_user_id: nil
    )

    {:noreply, assign(socket, :media_control_request_modal, nil)}
  end

  # Handle media control request denied (keep control was clicked)
  @impl true
  def handle_info({:media_control_request_denied, _params}, socket) do
    room_id = socket.assigns.room.id

    # Clear pending request in component
    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      pending_request_user_id: nil
    )

    {:noreply, assign(socket, :media_control_request_modal, nil)}
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

  # Refresh lenses from current sensor state - returns socket with updated lenses if changed
  defp maybe_refresh_lenses(socket) do
    sensors = socket.assigns.sensors
    sensors_state = get_sensors_state(sensors)
    new_lenses = extract_available_lenses(sensors_state)

    current_lens_types = Enum.map(socket.assigns.available_lenses, & &1.type) |> MapSet.new()
    new_lens_types = Enum.map(new_lenses, & &1.type) |> MapSet.new()

    if MapSet.equal?(current_lens_types, new_lens_types) do
      socket
    else
      socket
      |> assign(:sensors_state, sensors_state)
      |> assign(:available_lenses, new_lenses)
    end
  end

  defp build_activity_map(sensors) do
    sensors
    |> Enum.map(fn sensor ->
      {sensor.sensor_id, DateTime.utc_now()}
    end)
    |> Enum.into(%{})
  end

  defp get_default_mode(room) do
    cond do
      Map.get(room, :calls_enabled, true) -> :call
      Map.get(room, :media_playback_enabled, true) -> :media
      Map.get(room, :object_3d_enabled, false) -> :object3d
      true -> :sensors
    end
  end

  defp count_room_mode_presence(room_id) do
    presences = Presence.list("room:#{room_id}:mode_presence")

    Enum.reduce(presences, {0, 0}, fn {_user_id, %{metas: metas}}, {media, object3d} ->
      # Get the most recent presence meta (last one)
      case List.last(metas) do
        %{room_mode: :media} -> {media + 1, object3d}
        %{room_mode: :object3d} -> {media, object3d + 1}
        _ -> {media, object3d}
      end
    end)
  end

  defp get_object3d_controller(room_id) do
    case Object3DPlayerServer.get_state(room_id) do
      {:ok, state} -> state.controller_user_id
      _ -> nil
    end
  end

  defp build_edit_form(room) do
    to_form(%{
      "name" => room.name || "",
      "description" => room.description || "",
      "is_public" => Map.get(room, :is_public, true),
      "calls_enabled" => Map.get(room, :calls_enabled, true),
      "media_playback_enabled" => Map.get(room, :media_playback_enabled, true),
      "object_3d_enabled" => Map.get(room, :object_3d_enabled, false)
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
    attr_type in ["heartrate", "hr", "imu", "geolocation", "ecg", "battery", "spo2", "skeleton"]
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
      "skeleton" -> extract_skeleton_data(sensors_state)
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
      hr_attr =
        Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type in ["heartrate", "hr"]
        end)

      bpm =
        case hr_attr do
          {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
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
      geo_attr =
        Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type == "geolocation"
        end)

      position =
        case geo_attr do
          {_attr_id, attr} ->
            payload = attr.lastvalue && attr.lastvalue.payload

            case payload do
              %{"latitude" => lat, "longitude" => lng} -> %{latitude: lat, longitude: lng}
              %{latitude: lat, longitude: lng} -> %{latitude: lat, longitude: lng}
              _ -> nil
            end

          nil ->
            nil
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
      batt_attr =
        Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type == "battery"
        end)

      level =
        case batt_attr do
          {_attr_id, attr} ->
            payload = attr.lastvalue && attr.lastvalue.payload

            case payload do
              %{"level" => lvl} -> lvl
              %{level: lvl} -> lvl
              _ -> nil
            end

          nil ->
            nil
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
      spo2_attr =
        Enum.find(sensor.attributes || %{}, fn {_attr_id, attr} ->
          attr.attribute_type == "spo2"
        end)

      spo2 =
        case spo2_attr do
          {_attr_id, attr} -> (attr.lastvalue && attr.lastvalue.payload) || 0
          nil -> 0
        end

      %{sensor_id: sensor_id, sensor_name: sensor.sensor_name, spo2: spo2}
    end)
  end

  defp extract_skeleton_data(sensors_state) do
    sensors_state
    |> Enum.filter(fn {_id, sensor} ->
      (sensor.attributes || %{})
      |> Enum.any?(fn {_attr_id, attr} ->
        attr.attribute_type == "skeleton"
      end)
    end)
    |> Enum.map(fn {sensor_id, sensor} ->
      %{sensor_id: sensor_id, username: sensor.username}
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
        <:crumb>{@room.name}</:crumb>
      </.breadcrumbs>

      <div class="mb-6">
        <div class="flex items-center gap-4 mb-2">
          <h1 class="text-2xl font-bold">{@room.name}</h1>
          <div class="flex gap-2">
            <%= if @room.is_public do %>
              <span class="px-2 py-1 text-xs bg-green-600/20 text-green-400 rounded">Public</span>
            <% else %>
              <span class="px-2 py-1 text-xs bg-yellow-600/20 text-yellow-400 rounded">Private</span>
            <% end %>
            <%= if not Map.get(@room, :is_persisted, true) do %>
              <span class="px-2 py-1 text-xs bg-purple-600/20 text-purple-400 rounded">
                Temporary
              </span>
            <% end %>
          </div>
        </div>
        <p class="text-sm text-gray-500">
          by {get_owner_name(@room)}
        </p>
        <%= if @room.description do %>
          <p class="text-gray-400 mt-1">{@room.description}</p>
        <% end %>
      </div>

      <div class="flex flex-wrap gap-2 sm:gap-4 mb-6">
        <button
          phx-click="open_share_modal"
          class="bg-blue-600 hover:bg-blue-700 text-white font-semibold py-2 px-3 sm:px-4 rounded-lg transition-colors flex items-center gap-2 text-sm sm:text-base"
        >
          <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              stroke-width="2"
              d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.368 2.684 3 3 0 00-5.368-2.684z"
            />
          </svg>
          <span class="hidden sm:inline">Share</span>
        </button>
        <%= if @is_member do %>
          <button
            phx-click="open_add_sensor_modal"
            class="bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-3 sm:px-4 rounded-lg transition-colors flex items-center gap-2 text-sm sm:text-base"
          >
            <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M12 6v6m0 0v6m0-6h6m-6 0H6"
              />
            </svg>
            <span class="hidden sm:inline">Add Sensor</span>
          </button>
        <% end %>
        <%= if @is_owner do %>
          <button
            phx-click="open_edit_modal"
            class="bg-gray-700 hover:bg-gray-600 text-white font-semibold py-2 px-3 sm:px-4 rounded-lg transition-colors flex items-center gap-2 text-sm sm:text-base"
          >
            <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"
              />
            </svg>
            <span class="hidden sm:inline">Edit</span>
          </button>
          <button
            phx-click="delete_room"
            data-confirm="Are you sure you want to delete this room? This action cannot be undone."
            class="bg-red-600 hover:bg-red-500 text-white font-semibold py-2 px-3 sm:px-4 rounded-lg transition-colors flex items-center gap-2 text-sm sm:text-base"
          >
            <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"
              />
            </svg>
            <span class="hidden sm:inline">Delete</span>
          </button>
        <% else %>
          <%= if @is_member do %>
            <button
              phx-click="leave_room"
              data-confirm="Are you sure you want to leave this room? Your sensors will be disconnected from the room."
              class="bg-gray-700 hover:bg-gray-600 text-gray-300 font-semibold py-2 px-3 sm:px-4 rounded-lg transition-colors flex items-center gap-2 text-sm sm:text-base"
            >
              <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M17 16l4-4m0 0l-4-4m4 4H7m6 4v1a3 3 0 01-3 3H6a3 3 0 01-3-3V7a3 3 0 013-3h4a3 3 0 013 3v1"
                />
              </svg>
              <span class="hidden sm:inline">Leave Room</span>
            </button>
          <% else %>
            <button
              phx-click="join_room"
              class="bg-green-600 hover:bg-green-500 text-white font-semibold py-2 px-3 sm:px-4 rounded-lg transition-colors flex items-center gap-2 text-sm sm:text-base"
            >
              <svg class="w-4 h-4 sm:w-5 sm:h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M18 9v3m0 0v3m0-3h3m-3 0h-3m-2-5a4 4 0 11-8 0 4 4 0 018 0zM3 20a6 6 0 0112 0v1H3v-1z"
                />
              </svg>
              <span class="hidden sm:inline">Join Room</span>
            </button>
          <% end %>
        <% end %>
      </div>

      <%!-- ================================================================== --%>
      <%!-- CALL CONTROLS - Always visible when calls enabled, independent of tabs --%>
      <%!-- ================================================================== --%>
      <%= if Map.get(@room, :calls_enabled, true) do %>
        <div class="mb-4 p-3 bg-gray-800/50 rounded-lg border border-gray-700">
          <div class="flex items-center justify-between">
            <div class="flex items-center gap-3">
              <Heroicons.icon name="phone" type="solid" class="h-5 w-5 text-gray-400" />
              <span class="text-sm text-gray-300 font-medium">Voice/Video Call</span>
            </div>

            <%= if @in_call do %>
              <%!-- In call: show status and controls --%>
              <div class="flex items-center gap-3">
                <div class="flex items-center gap-2 text-sm text-green-400">
                  <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
                  <span>Connected</span>
                  <span class="text-gray-500">
                    ({map_size(@call_participants) + 1} in call)
                  </span>
                </div>

                <%!-- Quick audio/video toggles --%>
                <div class="flex items-center gap-1">
                  <button
                    phx-click="toggle_call_audio"
                    class="p-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
                    title="Toggle microphone"
                  >
                    <Heroicons.icon name="microphone" type="solid" class="h-4 w-4" />
                  </button>
                  <button
                    phx-click="toggle_call_video"
                    class="p-2 rounded-lg bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
                    title="Toggle camera"
                  >
                    <Heroicons.icon name="video-camera" type="solid" class="h-4 w-4" />
                  </button>
                </div>

                <%!-- Expand call view / Leave call --%>
                <button
                  phx-click="switch_room_mode"
                  phx-value-mode="call"
                  class={"px-3 py-1.5 rounded-lg text-sm font-medium transition-all " <>
                    if(@room_mode == :call, do: "bg-green-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")}
                >
                  {if @room_mode == :call, do: "Viewing Call", else: "Show Call"}
                </button>

                <button
                  phx-click="leave_call"
                  class="px-3 py-1.5 rounded-lg text-sm font-medium bg-red-600 hover:bg-red-500 text-white transition-colors"
                >
                  Leave
                </button>
              </div>
            <% else %>
              <%!-- Not in call: show join buttons --%>
              <div class="flex items-center gap-2">
                <span class="text-sm text-gray-500">Not connected</span>
                <button
                  phx-click="quick_join_call"
                  phx-value-mode="video"
                  class="px-3 py-1.5 rounded-l-lg text-sm font-medium transition-all flex items-center gap-2 bg-green-600 hover:bg-green-500 text-white"
                  title="Join with video"
                >
                  <Heroicons.icon name="video-camera" type="solid" class="h-4 w-4" /> Join
                </button>
                <button
                  phx-click="quick_join_call"
                  phx-value-mode="audio"
                  class="px-2 py-1.5 rounded-r-lg text-sm font-medium transition-all flex items-center bg-green-700 hover:bg-green-600 text-white border-l border-green-800"
                  title="Join with voice only"
                >
                  <Heroicons.icon name="microphone" type="solid" class="h-4 w-4" />
                </button>
              </div>
            <% end %>
          </div>
        </div>
      <% end %>

      <%!-- Mode Switcher Tabs - only show if any collaboration feature is enabled --%>
      <%= if Map.get(@room, :media_playback_enabled, true) or Map.get(@room, :object_3d_enabled, false) do %>
        <div class="flex items-center justify-start gap-2 mb-6 flex-wrap">
          <%= if Map.get(@room, :media_playback_enabled, true) do %>
            <button
              phx-click="switch_room_mode"
              phx-value-mode="media"
              class={"px-4 py-2 rounded-lg text-sm font-medium transition-all flex items-center gap-2 " <>
                if(@room_mode == :media, do: "bg-blue-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600") <>
                if(@media_bump, do: " animate-bump ring-1 ring-blue-300/50", else: "")}
            >
              <Heroicons.icon name="play" type="solid" class="h-4 w-4" /> Media Playback
              <span
                :if={@media_viewers > 0}
                class="ml-1 px-1.5 py-0.5 text-xs rounded-full bg-white/20"
              >
                {@media_viewers}
              </span>
            </button>
          <% end %>
          <%= if Map.get(@room, :object_3d_enabled, false) do %>
            <button
              phx-click="switch_room_mode"
              phx-value-mode="object3d"
              class={"px-4 py-2 rounded-lg text-sm font-medium transition-all flex items-center gap-2 " <>
                if(@room_mode == :object3d, do: "bg-cyan-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600") <>
                if(@object3d_bump, do: " animate-bump ring-1 ring-cyan-300/50", else: "")}
            >
              <Heroicons.icon name="cube-transparent" type="solid" class="h-4 w-4" /> 3D Object
              <span
                :if={@object3d_viewers > 0}
                class="ml-1 px-1.5 py-0.5 text-xs rounded-full bg-white/20"
              >
                {@object3d_viewers}
              </span>
            </button>
          <% end %>
          <%= if @in_call do %>
            <button
              phx-click="switch_room_mode"
              phx-value-mode="call"
              class={"px-4 py-2 rounded-lg text-sm font-medium transition-all flex items-center gap-2 " <>
                if(@room_mode == :call, do: "bg-green-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")}
            >
              <Heroicons.icon name="video-camera" type="solid" class="h-4 w-4" /> Call View
            </button>
          <% end %>
          <button
            phx-click="switch_room_mode"
            phx-value-mode="sensors"
            class={"px-4 py-2 rounded-lg text-sm font-medium transition-colors flex items-center gap-2 " <>
              if(@room_mode == :sensors, do: "bg-orange-600 text-white", else: "bg-gray-700 text-gray-300 hover:bg-gray-600")}
          >
            <Heroicons.icon name="cpu-chip" type="solid" class="h-4 w-4" /> Sensors
          </button>
        </div>
      <% end %>

      <%!-- Persistent Call Hook Container - ALWAYS mounted to handle join_call events --%>
      <div
        :if={Map.get(@room, :calls_enabled, true)}
        id="call-hook-persistent"
        phx-hook="CallHook"
        data-room-id={@room.id}
        data-user-id={@current_user.id}
        data-in-call={to_string(@in_call)}
        data-user-name={@current_user.email |> to_string()}
        class="hidden"
      >
      </div>

      <%!-- Mini Call Indicator - shows when in call but NOT in call mode --%>
      <.live_component
        :if={@in_call && @room_mode != :call}
        module={MiniCallIndicatorComponent}
        id="mini-call-indicator"
        in_call={@in_call}
        participants={@call_participants}
        user={@current_user}
        speaking={@call_speaking}
      />

      <%!-- Video Call Panel - shown when in call mode --%>
      <div :if={@room_mode == :call and Map.get(@room, :calls_enabled, true)} class="mb-6">
        <.live_component
          module={SensoctoWeb.Live.Calls.CallContainerComponent}
          id="call-container"
          room={@room}
          user={@current_user}
          in_call={@in_call}
          participants={@call_participants}
          external_hook={@in_call}
        />
      </div>

      <%!-- Media Player Panel - shown when in media mode --%>
      <div :if={@room_mode == :media and Map.get(@room, :media_playback_enabled, true)} class="mb-6">
        <.live_component
          module={MediaPlayerComponent}
          id={"room-media-player-#{@room.id}"}
          room_id={@room.id}
          current_user={@current_user}
          can_manage={@can_manage}
        />
      </div>

      <%!-- 3D Object Viewer Panel - shown when in object3d mode --%>
      <div :if={@room_mode == :object3d and Map.get(@room, :object_3d_enabled, false)} class="mb-6">
        <.live_component
          module={Object3DPlayerComponent}
          id={"object3d-player-#{@room.id}"}
          room_id={@room.id}
          current_user={@current_user}
          can_manage={@can_manage}
        />
      </div>

      <%!-- Sensors Panel - always visible --%>
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
                          do: "bg-orange text-white",
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
            <svg
              class="w-16 h-16 mx-auto text-gray-600 mb-4"
              fill="none"
              stroke="currentColor"
              viewBox="0 0 24 24"
            >
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
              />
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
        <.settings_panel
          room={@room}
          is_owner={@is_owner}
          room_members={@room_members}
          current_user={@current_user}
        />
      <% end %>

      <%!-- Control Request Modal --%>
      <%= if @control_request_modal do %>
        <div
          id="control-request-modal"
          phx-hook="NotificationSound"
          class="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm"
        >
          <div class="bg-gray-800 rounded-xl shadow-2xl w-full max-w-md mx-4 overflow-hidden border border-gray-700">
            <%!-- Header --%>
            <div class="bg-gradient-to-r from-cyan-600 to-blue-600 px-6 py-4">
              <div class="flex items-center gap-3">
                <div class="p-2 bg-white/20 rounded-full">
                  <svg
                    class="w-6 h-6 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M15 12a3 3 0 11-6 0 3 3 0 016 0z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M2.458 12C3.732 7.943 7.523 5 12 5c4.478 0 8.268 2.943 9.542 7-1.274 4.057-5.064 7-9.542 7-4.477 0-8.268-2.943-9.542-7z"
                    />
                  </svg>
                </div>
                <h2 class="text-xl font-bold text-white">Control Request</h2>
              </div>
            </div>

            <%!-- Content --%>
            <div class="p-6">
              <div class="flex items-center gap-4 mb-6">
                <div class="w-14 h-14 bg-gray-700 rounded-full flex items-center justify-center">
                  <svg
                    class="w-8 h-8 text-gray-400"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                    />
                  </svg>
                </div>
                <div>
                  <p class="text-lg font-semibold text-white">
                    {@control_request_modal.requester_name}
                  </p>
                  <p class="text-sm text-gray-400">
                    wants to control the 3D viewer
                  </p>
                </div>
              </div>

              <p class="text-gray-300 text-sm mb-4">
                Transferring control will allow them to navigate the 3D scene while you follow their view.
              </p>

              <%!-- Auto-transfer warning with countdown --%>
              <div
                id="room-object3d-control-countdown"
                phx-hook="CountdownTimer"
                data-seconds="30"
                class="mb-6 p-3 bg-amber-900/30 border border-amber-600/50 rounded-lg"
              >
                <p class="text-amber-200 text-sm flex items-center gap-2">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  Control will auto-transfer in <span class="font-bold countdown-display">30</span>s
                </p>
              </div>

              <%!-- Actions --%>
              <div class="flex gap-3">
                <button
                  phx-click="dismiss_control_request"
                  class="flex-1 px-4 py-3 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors"
                >
                  Keep Control
                </button>
                <button
                  phx-click="release_control_from_modal"
                  class="flex-1 px-4 py-3 bg-cyan-600 hover:bg-cyan-500 text-white font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                    />
                  </svg>
                  Transfer Control
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>

      <%!-- Media Control Request Modal --%>
      <%= if @media_control_request_modal do %>
        <div
          id="media-control-request-modal"
          phx-hook="NotificationSound"
          class="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 backdrop-blur-sm"
        >
          <div class="bg-gray-800 rounded-xl shadow-2xl w-full max-w-md mx-4 overflow-hidden border border-gray-700">
            <%!-- Header --%>
            <div class="bg-gradient-to-r from-red-600 to-orange-600 px-6 py-4">
              <div class="flex items-center gap-3">
                <div class="p-2 bg-white/20 rounded-full">
                  <svg
                    class="w-6 h-6 text-white"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M14.752 11.168l-3.197-2.132A1 1 0 0010 9.87v4.263a1 1 0 001.555.832l3.197-2.132a1 1 0 000-1.664z"
                    />
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M21 12a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                </div>
                <h2 class="text-xl font-bold text-white">Media Control Request</h2>
              </div>
            </div>

            <%!-- Content --%>
            <div class="p-6">
              <div class="flex items-center gap-4 mb-6">
                <div class="w-14 h-14 bg-gray-700 rounded-full flex items-center justify-center">
                  <svg
                    class="w-8 h-8 text-gray-400"
                    fill="none"
                    stroke="currentColor"
                    viewBox="0 0 24 24"
                  >
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M16 7a4 4 0 11-8 0 4 4 0 018 0zM12 14a7 7 0 00-7 7h14a7 7 0 00-7-7z"
                    />
                  </svg>
                </div>
                <div>
                  <p class="text-lg font-semibold text-white">
                    {@media_control_request_modal.requester_name}
                  </p>
                  <p class="text-sm text-gray-400">
                    wants to control the media player
                  </p>
                </div>
              </div>

              <p class="text-gray-300 text-sm mb-4">
                Transferring control will allow them to play, pause, and navigate the media playlist.
              </p>

              <%!-- Auto-transfer warning with countdown --%>
              <div
                id="room-media-control-countdown"
                phx-hook="CountdownTimer"
                data-seconds="30"
                class="mb-6 p-3 bg-amber-900/30 border border-amber-600/50 rounded-lg"
              >
                <p class="text-amber-200 text-sm flex items-center gap-2">
                  <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z"
                    />
                  </svg>
                  Control will auto-transfer in <span class="font-bold countdown-display">30</span>s
                </p>
              </div>

              <%!-- Actions --%>
              <div class="flex gap-3">
                <button
                  phx-click="dismiss_media_control_request"
                  class="flex-1 px-4 py-3 bg-gray-700 hover:bg-gray-600 text-white font-medium rounded-lg transition-colors"
                >
                  Keep Control
                </button>
                <button
                  phx-click="release_media_control_from_modal"
                  class="flex-1 px-4 py-3 bg-red-600 hover:bg-red-500 text-white font-medium rounded-lg transition-colors flex items-center justify-center gap-2"
                >
                  <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path
                      stroke-linecap="round"
                      stroke-linejoin="round"
                      stroke-width="2"
                      d="M8 7h12m0 0l-4-4m4 4l-4 4m0 6H4m0 0l4 4m-4-4l4-4"
                    />
                  </svg>
                  Transfer Control
                </button>
              </div>
            </div>
          </div>
        </div>
      <% end %>
    </div>
    """
  end

  # Lens composite view component - renders the appropriate Svelte component for each lens type
  defp lens_composite_view(assigns) do
    ~H"""
    <div
      id="lens-composite-view"
      phx-hook="CompositeMeasurementHandler"
      class="bg-gray-800 rounded-lg p-4"
    >
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
            props={
              %{
                positions:
                  Enum.map(@lens_data, fn d ->
                    %{
                      lat: d.position[:latitude] || d.position["latitude"],
                      lng: d.position[:longitude] || d.position["longitude"],
                      sensor_id: d.sensor_id,
                      sensor_name: d.sensor_name
                    }
                  end)
              }
            }
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
        <% "skeleton" -> %>
          <div class="h-[500px]">
            <.svelte
              name="CompositeSkeletons"
              props={%{sensors: @lens_data}}
              socket={@socket}
              class="w-full h-full"
            />
          </div>
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
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
          />
        <% :imu -> %>
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M14 10l-2 1m0 0l-2-1m2 1v2.5M20 7l-2 1m2-1l-2-1m2 1v2.5M14 4l-2-1-2 1M4 7l2-1M4 7l2 1M4 7v2.5M12 21l-2-1m2 1l2-1m-2 1v-2.5M6 18l-2-1v-2.5M18 18l2-1v-2.5"
          />
        <% _ -> %>
          <path
            stroke-linecap="round"
            stroke-linejoin="round"
            stroke-width="2"
            d="M9 3v2m6-2v2M9 19v2m6-2v2M5 9H3m2 6H3m18-6h-2m2 6h-2M7 19h10a2 2 0 002-2V7a2 2 0 00-2-2H7a2 2 0 00-2 2v10a2 2 0 002 2zM9 9h6v6H9V9z"
          />
      <% end %>
    </svg>
    """
  end

  defp share_modal(assigns) do
    share_url = Sensocto.Rooms.share_url(assigns.room)

    share_text =
      "Join my room \"#{assigns.room.name}\" on Sensocto! Code: #{assigns.room.join_code}"

    encoded_url = URI.encode_www_form(share_url)
    encoded_text = URI.encode_www_form(share_text)

    assigns =
      assigns
      |> assign(:share_url, share_url)
      |> assign(:share_text, share_text)
      |> assign(:encoded_url, encoded_url)
      |> assign(:encoded_text, encoded_text)

    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-2 sm:p-4 md:p-6"
      phx-click="close_share_modal"
    >
      <div
        class="bg-gray-800 rounded-lg p-3 sm:p-4 md:p-6 w-full max-w-sm sm:max-w-md max-h-[95vh] overflow-y-auto"
        phx-click-away="close_share_modal"
      >
        <div class="flex justify-between items-center mb-3 sm:mb-4">
          <h2 class="text-base sm:text-lg md:text-xl font-semibold">Share Room</h2>
          <button phx-click="close_share_modal" class="text-gray-400 hover:text-white p-1 -mr-1">
            <svg class="w-5 h-5 sm:w-6 sm:h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </button>
        </div>

        <%!-- Join Code --%>
        <div class="text-center mb-3 sm:mb-4 p-3 bg-gray-700/50 rounded-lg">
          <p class="text-gray-400 text-xs sm:text-sm mb-1">Join Code</p>
          <p class="text-xl sm:text-2xl md:text-3xl font-mono font-bold tracking-wider text-white">
            {@room.join_code}
          </p>
        </div>

        <%!-- Share Link --%>
        <div class="mb-3 sm:mb-4">
          <p class="text-gray-400 text-xs sm:text-sm mb-2">Share Link</p>
          <div class="flex gap-2">
            <input
              type="text"
              readonly
              value={@share_url}
              class="flex-1 min-w-0 bg-gray-700 border border-gray-600 rounded-lg px-2 sm:px-3 py-2 text-white text-xs sm:text-sm truncate"
              id="share-url-input"
            />
            <button
              phx-click="copy_link"
              phx-hook="CopyToClipboard"
              id="copy-link-btn"
              data-copy-text={@share_url}
              class="bg-blue-600 hover:bg-blue-700 text-white px-2 sm:px-3 py-2 rounded-lg transition-colors text-xs sm:text-sm whitespace-nowrap flex items-center gap-1"
            >
              <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 5H6a2 2 0 00-2 2v12a2 2 0 002 2h10a2 2 0 002-2v-1M8 5a2 2 0 002 2h2a2 2 0 002-2M8 5a2 2 0 012-2h2a2 2 0 012 2m0 0h2a2 2 0 012 2v3m2 4H10m0 0l3-3m-3 3l3 3"
                />
              </svg>
              <span class="hidden sm:inline">Copy</span>
            </button>
          </div>
        </div>

        <%!-- Share via Apps --%>
        <div class="mb-3 sm:mb-4">
          <p class="text-gray-400 text-xs sm:text-sm mb-2">Share via</p>
          <div class="grid grid-cols-4 sm:grid-cols-5 gap-2">
            <%!-- WhatsApp --%>
            <a
              href={"https://wa.me/?text=#{@encoded_text}%20#{@encoded_url}"}
              target="_blank"
              rel="noopener noreferrer"
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-green-600/20 rounded-lg transition-colors group"
              title="Share via WhatsApp"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-green-500 group-hover:text-green-400"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M17.472 14.382c-.297-.149-1.758-.867-2.03-.967-.273-.099-.471-.148-.67.15-.197.297-.767.966-.94 1.164-.173.199-.347.223-.644.075-.297-.15-1.255-.463-2.39-1.475-.883-.788-1.48-1.761-1.653-2.059-.173-.297-.018-.458.13-.606.134-.133.298-.347.446-.52.149-.174.198-.298.298-.497.099-.198.05-.371-.025-.52-.075-.149-.669-1.612-.916-2.207-.242-.579-.487-.5-.669-.51-.173-.008-.371-.01-.57-.01-.198 0-.52.074-.792.372-.272.297-1.04 1.016-1.04 2.479 0 1.462 1.065 2.875 1.213 3.074.149.198 2.096 3.2 5.077 4.487.709.306 1.262.489 1.694.625.712.227 1.36.195 1.871.118.571-.085 1.758-.719 2.006-1.413.248-.694.248-1.289.173-1.413-.074-.124-.272-.198-.57-.347m-5.421 7.403h-.004a9.87 9.87 0 01-5.031-1.378l-.361-.214-3.741.982.998-3.648-.235-.374a9.86 9.86 0 01-1.51-5.26c.001-5.45 4.436-9.884 9.888-9.884 2.64 0 5.122 1.03 6.988 2.898a9.825 9.825 0 012.893 6.994c-.003 5.45-4.437 9.884-9.885 9.884m8.413-18.297A11.815 11.815 0 0012.05 0C5.495 0 .16 5.335.157 11.892c0 2.096.547 4.142 1.588 5.945L.057 24l6.305-1.654a11.882 11.882 0 005.683 1.448h.005c6.554 0 11.89-5.335 11.893-11.893a11.821 11.821 0 00-3.48-8.413z" />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">WhatsApp</span>
            </a>

            <%!-- Telegram --%>
            <a
              href={"https://t.me/share/url?url=#{@encoded_url}&text=#{@encoded_text}"}
              target="_blank"
              rel="noopener noreferrer"
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-blue-600/20 rounded-lg transition-colors group"
              title="Share via Telegram"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-blue-400 group-hover:text-blue-300"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M11.944 0A12 12 0 0 0 0 12a12 12 0 0 0 12 12 12 12 0 0 0 12-12A12 12 0 0 0 12 0a12 12 0 0 0-.056 0zm4.962 7.224c.1-.002.321.023.465.14a.506.506 0 0 1 .171.325c.016.093.036.306.02.472-.18 1.898-.962 6.502-1.36 8.627-.168.9-.499 1.201-.82 1.23-.696.065-1.225-.46-1.9-.902-1.056-.693-1.653-1.124-2.678-1.8-1.185-.78-.417-1.21.258-1.91.177-.184 3.247-2.977 3.307-3.23.007-.032.014-.15-.056-.212s-.174-.041-.249-.024c-.106.024-1.793 1.14-5.061 3.345-.48.33-.913.49-1.302.48-.428-.008-1.252-.241-1.865-.44-.752-.245-1.349-.374-1.297-.789.027-.216.325-.437.893-.663 3.498-1.524 5.83-2.529 6.998-3.014 3.332-1.386 4.025-1.627 4.476-1.635z" />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">Telegram</span>
            </a>

            <%!-- Signal (uses SMS/Messages link) --%>
            <a
              href={"sms:?body=#{@encoded_text}%20#{@encoded_url}"}
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-blue-600/20 rounded-lg transition-colors group"
              title="Share via SMS/Messages"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-blue-500 group-hover:text-blue-400"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
                />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">SMS</span>
            </a>

            <%!-- Email --%>
            <a
              href={"mailto:?subject=#{URI.encode_www_form("Join my Sensocto room")}&body=#{@encoded_text}%0A%0A#{@encoded_url}"}
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-purple-600/20 rounded-lg transition-colors group"
              title="Share via Email"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-purple-400 group-hover:text-purple-300"
                fill="none"
                stroke="currentColor"
                viewBox="0 0 24 24"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  stroke-width="2"
                  d="M3 8l7.89 5.26a2 2 0 002.22 0L21 8M5 19h14a2 2 0 002-2V7a2 2 0 00-2-2H5a2 2 0 00-2 2v10a2 2 0 002 2z"
                />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">Email</span>
            </a>

            <%!-- Twitter/X --%>
            <a
              href={"https://twitter.com/intent/tweet?text=#{@encoded_text}&url=#{@encoded_url}"}
              target="_blank"
              rel="noopener noreferrer"
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-gray-500/20 rounded-lg transition-colors group"
              title="Share on X (Twitter)"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-gray-300 group-hover:text-white"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M18.244 2.25h3.308l-7.227 8.26 8.502 11.24H16.17l-5.214-6.817L4.99 21.75H1.68l7.73-8.835L1.254 2.25H8.08l4.713 6.231zm-1.161 17.52h1.833L7.084 4.126H5.117z" />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">X</span>
            </a>

            <%!-- Facebook Messenger --%>
            <a
              href={"https://www.facebook.com/dialog/send?link=#{@encoded_url}&app_id=966242223397117&redirect_uri=#{@encoded_url}"}
              target="_blank"
              rel="noopener noreferrer"
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-blue-600/20 rounded-lg transition-colors group"
              title="Share via Messenger"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-blue-500 group-hover:text-blue-400"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M12 0C5.373 0 0 4.975 0 11.111c0 3.497 1.745 6.616 4.472 8.652V24l4.086-2.242c1.09.301 2.246.464 3.442.464 6.627 0 12-4.975 12-11.111C24 4.975 18.627 0 12 0zm1.193 14.963l-3.056-3.259-5.963 3.259 6.559-6.963 3.13 3.259 5.889-3.259-6.559 6.963z" />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">Messenger</span>
            </a>

            <%!-- LinkedIn --%>
            <a
              href={"https://www.linkedin.com/sharing/share-offsite/?url=#{@encoded_url}"}
              target="_blank"
              rel="noopener noreferrer"
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-blue-700/20 rounded-lg transition-colors group"
              title="Share on LinkedIn"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-blue-600 group-hover:text-blue-500"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M20.447 20.452h-3.554v-5.569c0-1.328-.027-3.037-1.852-3.037-1.853 0-2.136 1.445-2.136 2.939v5.667H9.351V9h3.414v1.561h.046c.477-.9 1.637-1.85 3.37-1.85 3.601 0 4.267 2.37 4.267 5.455v6.286zM5.337 7.433c-1.144 0-2.063-.926-2.063-2.065 0-1.138.92-2.063 2.063-2.063 1.14 0 2.064.925 2.064 2.063 0 1.139-.925 2.065-2.064 2.065zm1.782 13.019H3.555V9h3.564v11.452zM22.225 0H1.771C.792 0 0 .774 0 1.729v20.542C0 23.227.792 24 1.771 24h20.451C23.2 24 24 23.227 24 22.271V1.729C24 .774 23.2 0 22.222 0h.003z" />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">LinkedIn</span>
            </a>

            <%!-- Discord (copy with invite style) --%>
            <a
              href="https://discord.com/channels/@me"
              target="_blank"
              rel="noopener noreferrer"
              phx-hook="CopyToClipboard"
              id="discord-share-btn"
              data-copy-text={"#{@share_text} #{@share_url}"}
              class="flex flex-col items-center p-2 sm:p-3 bg-gray-700 hover:bg-indigo-600/20 rounded-lg transition-colors group cursor-pointer"
              title="Copy for Discord"
            >
              <svg
                class="w-5 h-5 sm:w-6 sm:h-6 text-indigo-400 group-hover:text-indigo-300"
                viewBox="0 0 24 24"
                fill="currentColor"
              >
                <path d="M20.317 4.3698a19.7913 19.7913 0 00-4.8851-1.5152.0741.0741 0 00-.0785.0371c-.211.3753-.4447.8648-.6083 1.2495-1.8447-.2762-3.68-.2762-5.4868 0-.1636-.3933-.4058-.8742-.6177-1.2495a.077.077 0 00-.0785-.037 19.7363 19.7363 0 00-4.8852 1.515.0699.0699 0 00-.0321.0277C.5334 9.0458-.319 13.5799.0992 18.0578a.0824.0824 0 00.0312.0561c2.0528 1.5076 4.0413 2.4228 5.9929 3.0294a.0777.0777 0 00.0842-.0276c.4616-.6304.8731-1.2952 1.226-1.9942a.076.076 0 00-.0416-.1057c-.6528-.2476-1.2743-.5495-1.8722-.8923a.077.077 0 01-.0076-.1277c.1258-.0943.2517-.1923.3718-.2914a.0743.0743 0 01.0776-.0105c3.9278 1.7933 8.18 1.7933 12.0614 0a.0739.0739 0 01.0785.0095c.1202.099.246.1981.3728.2924a.077.077 0 01-.0066.1276 12.2986 12.2986 0 01-1.873.8914.0766.0766 0 00-.0407.1067c.3604.698.7719 1.3628 1.225 1.9932a.076.076 0 00.0842.0286c1.961-.6067 3.9495-1.5219 6.0023-3.0294a.077.077 0 00.0313-.0552c.5004-5.177-.8382-9.6739-3.5485-13.6604a.061.061 0 00-.0312-.0286zM8.02 15.3312c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9555-2.4189 2.157-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.9555 2.4189-2.1569 2.4189zm7.9748 0c-1.1825 0-2.1569-1.0857-2.1569-2.419 0-1.3332.9554-2.4189 2.1569-2.4189 1.2108 0 2.1757 1.0952 2.1568 2.419 0 1.3332-.946 2.4189-2.1568 2.4189z" />
              </svg>
              <span class="text-[10px] sm:text-xs text-gray-400 mt-1">Discord</span>
            </a>
          </div>
        </div>

        <%!-- QR Code --%>
        <div class="flex justify-center p-2 sm:p-3 bg-white rounded-lg">
          <div
            id="qr-code"
            phx-hook="QRCode"
            data-value={@share_url}
            class="w-28 h-28 sm:w-36 sm:h-36 md:w-44 md:h-44"
          >
          </div>
        </div>
        <p class="text-center text-gray-500 text-[10px] sm:text-xs mt-2">Scan QR code to join</p>
      </div>
    </div>
    """
  end

  defp add_sensor_modal(assigns) do
    ~H"""
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-click="close_add_sensor_modal"
    >
      <div
        class="bg-gray-800 rounded-lg p-6 w-full max-w-md max-h-[80vh] overflow-y-auto"
        phx-click-away="close_add_sensor_modal"
      >
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Add Sensor</h2>
          <button phx-click="close_add_sensor_modal" class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
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
                    <p class="font-medium">{sensor.sensor_name}</p>
                    <p class="text-xs text-gray-400">{sensor.sensor_type}</p>
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
    <div
      class="fixed inset-0 z-50 flex items-center justify-center bg-black/50"
      phx-click="close_edit_modal"
    >
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md" phx-click={%JS{}}>
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Edit Room</h2>
          <button phx-click="close_edit_modal" class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
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
            <label for="description" class="block text-sm font-medium text-gray-300 mb-1">
              Description
            </label>
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

            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="media_playback_enabled"
                checked={@form[:media_playback_enabled].value}
                class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
              />
              <span class="text-sm text-gray-300">Enable media playback</span>
            </label>

            <label class="flex items-center gap-2 cursor-pointer">
              <input
                type="checkbox"
                name="object_3d_enabled"
                checked={@form[:object_3d_enabled].value}
                class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-500 focus:ring-blue-500"
              />
              <span class="text-sm text-gray-300">Enable 3D objects</span>
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
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-lg max-h-[90vh] overflow-y-auto">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Room Settings</h2>
          <.link patch={~p"/rooms/#{@room.id}"} class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path
                stroke-linecap="round"
                stroke-linejoin="round"
                stroke-width="2"
                d="M6 18L18 6M6 6l12 12"
              />
            </svg>
          </.link>
        </div>

        <div class="space-y-4">
          <div class="p-4 bg-gray-700 rounded-lg">
            <h3 class="font-medium mb-2">Join Code</h3>
            <p class="text-2xl font-mono mb-3">{@room.join_code}</p>
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
                <dd>{if Map.get(@room, :is_persisted, true), do: "Persisted", else: "Temporary"}</dd>
              </div>
              <div class="flex justify-between">
                <dt class="text-gray-400">Visibility</dt>
                <dd>{if @room.is_public, do: "Public", else: "Private"}</dd>
              </div>
            </dl>
          </div>

          <%!-- Members Management Section --%>
          <div class="p-4 bg-gray-700 rounded-lg">
            <h3 class="font-medium mb-3">Members ({length(@room_members)})</h3>
            <div class="space-y-2 max-h-48 overflow-y-auto">
              <%= for member <- @room_members do %>
                <div class="flex items-center justify-between p-2 bg-gray-600 rounded">
                  <div class="flex items-center gap-2">
                    <div class="w-8 h-8 rounded-full bg-gray-500 flex items-center justify-center text-sm">
                      {String.first(member.user.display_name || member.user.email || "?")
                      |> String.upcase()}
                    </div>
                    <div>
                      <p class="text-sm font-medium">
                        {member.user.display_name || member.user.email}
                        <%= if member.user_id == @current_user.id do %>
                          <span class="text-gray-400">(you)</span>
                        <% end %>
                      </p>
                      <p class="text-xs text-gray-400">
                        <%= case member.role do %>
                          <% :owner -> %>
                            <span class="text-yellow-400">Owner</span>
                          <% :admin -> %>
                            <span class="text-blue-400">Admin</span>
                          <% :member -> %>
                            <span class="text-gray-400">Member</span>
                        <% end %>
                      </p>
                    </div>
                  </div>

                  <%!-- Action buttons (only for owner, and not for self) --%>
                  <%= if @is_owner and member.user_id != @current_user.id do %>
                    <div class="flex gap-1">
                      <%= if member.role == :member do %>
                        <button
                          phx-click="promote_to_admin"
                          phx-value-user-id={member.user_id}
                          class="px-2 py-1 text-xs bg-blue-600 hover:bg-blue-500 rounded"
                          title="Promote to Admin"
                        >
                          Promote
                        </button>
                      <% end %>
                      <%= if member.role == :admin do %>
                        <button
                          phx-click="demote_to_member"
                          phx-value-user-id={member.user_id}
                          class="px-2 py-1 text-xs bg-gray-500 hover:bg-gray-400 rounded"
                          title="Demote to Member"
                        >
                          Demote
                        </button>
                      <% end %>
                      <%= if member.role != :owner do %>
                        <button
                          phx-click="kick_member"
                          phx-value-user-id={member.user_id}
                          class="px-2 py-1 text-xs bg-red-600 hover:bg-red-500 rounded"
                          title="Remove from room"
                        >
                          Kick
                        </button>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <%= if @is_owner do %>
            <div class="p-4 bg-gray-700 rounded-lg">
              <h3 class="font-medium mb-3">Collaboration Features</h3>
              <div class="space-y-3">
                <%!-- Video/Audio Calls --%>
                <label class="flex items-center justify-between cursor-pointer">
                  <div>
                    <span class="text-sm text-gray-300">Video/Audio Calls</span>
                    <p class="text-xs text-gray-500">Real-time voice and video communication</p>
                  </div>
                  <button
                    type="button"
                    phx-click="toggle_calls_enabled"
                    class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors #{if Map.get(@room, :calls_enabled, true), do: "bg-blue-600", else: "bg-gray-600"}"}
                  >
                    <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if Map.get(@room, :calls_enabled, true), do: "translate-x-6", else: "translate-x-1"}"} />
                  </button>
                </label>

                <%!-- Media Playback --%>
                <label class="flex items-center justify-between cursor-pointer">
                  <div>
                    <span class="text-sm text-gray-300">Media Playback</span>
                    <p class="text-xs text-gray-500">Synchronized YouTube and playlist sharing</p>
                  </div>
                  <button
                    type="button"
                    phx-click="toggle_media_playback_enabled"
                    class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors #{if Map.get(@room, :media_playback_enabled, true), do: "bg-blue-600", else: "bg-gray-600"}"}
                  >
                    <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if Map.get(@room, :media_playback_enabled, true), do: "translate-x-6", else: "translate-x-1"}"} />
                  </button>
                </label>

                <%!-- 3D Object Interaction --%>
                <label class="flex items-center justify-between cursor-pointer">
                  <div>
                    <span class="text-sm text-gray-300">3D Objects</span>
                    <p class="text-xs text-gray-500">Gaussian splats and 3D model interaction</p>
                  </div>
                  <button
                    type="button"
                    phx-click="toggle_object_3d_enabled"
                    class={"relative inline-flex h-6 w-11 items-center rounded-full transition-colors #{if Map.get(@room, :object_3d_enabled, false), do: "bg-blue-600", else: "bg-gray-600"}"}
                  >
                    <span class={"inline-block h-4 w-4 transform rounded-full bg-white transition-transform #{if Map.get(@room, :object_3d_enabled, false), do: "translate-x-6", else: "translate-x-1"}"} />
                  </button>
                </label>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </div>
    """
  end
end

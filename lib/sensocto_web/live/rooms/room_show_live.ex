defmodule SensoctoWeb.RoomShowLive do
  @moduledoc """
  LiveView for displaying a single room with its sensors.
  Shows sensor summaries with activity indicators and provides room management.
  """
  use SensoctoWeb, :live_view
  require Logger

  alias Sensocto.Rooms
  alias Sensocto.Calls
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

          # Subscribe to global sensor connections to auto-register sensors for this room
          PubSub.subscribe(Sensocto.PubSub, "presence:all")

          # Register all currently connected sensors to this room
          all_connected_sensors =
            Sensocto.SensorsDynamicSupervisor.get_all_sensors_state(:view)
            |> Map.keys()

          if Enum.any?(all_connected_sensors) do
            register_sensors_to_room(room_id, user.id, all_connected_sensors)
          end

          Process.send_after(self(), :update_activity, @activity_check_interval)
        end

        # Reload room with sensors after registration
        room =
          case Rooms.get_room_with_sensors(room_id) do
            {:ok, updated} -> updated
            _ -> room
          end

        available_sensors = get_available_sensors(room)

        # Check if there's an active call in this room
        call_active = Calls.call_exists?(room_id)

        socket =
          socket
          |> assign(:page_title, room.name)
          |> assign(:room, room)
          |> assign(:sensors, room.sensors || [])
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
    {:noreply, put_flash(socket, :error, "Call error: #{message}")}
  end

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

  @impl true
  def handle_info({:measurement, %{sensor_id: sensor_id}}, socket) do
    activity = Map.put(socket.assigns.sensor_activity, sensor_id, DateTime.utc_now())
    {:noreply, assign(socket, :sensor_activity, activity)}
  end

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

  # Handle presence_diff events for auto-registering sensors to the room
  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: %{joins: joins}}, socket) when map_size(joins) > 0 do
    room = socket.assigns.room
    user = socket.assigns.current_user

    # For each new sensor that joined globally, add it to the room's GenServer
    new_sensor_ids = Map.keys(joins)

    # Ensure the user is in the room's GenServer, then add the sensors
    register_sensors_to_room(room.id, user.id, new_sensor_ids)

    # Subscribe to data from these sensors
    Enum.each(new_sensor_ids, fn sensor_id ->
      PubSub.subscribe(Sensocto.PubSub, "data:#{sensor_id}")
    end)

    # Refresh the room to show the new sensors
    case Rooms.get_room_with_sensors(room.id) do
      {:ok, updated_room} ->
        socket =
          socket
          |> assign(:room, updated_room)
          |> assign(:sensors, updated_room.sensors || [])
          |> assign(:available_sensors, get_available_sensors(updated_room))

        {:noreply, socket}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    # Handle leaves or empty joins - just ignore
    {:noreply, socket}
  end

  # Media player events - forward to component via send_update
  @impl true
  def handle_info({:media_state_changed, state}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      player_state: state.state,
      position_seconds: state.position_seconds,
      current_item: state.current_item
    )

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
  def handle_info({:media_controller_changed, %{user_id: user_id, user_name: user_name}}, socket) do
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

  defp register_sensors_to_room(room_id, user_id, new_sensor_ids) do
    # Get current sensors for this room
    current_sensors = Sensocto.RoomPresenceServer.get_room_sensors(room_id)

    # Merge with new sensors
    all_sensors = Enum.uniq(current_sensors ++ new_sensor_ids)

    # Check if user is already in the room
    case Sensocto.RoomPresenceServer.in_room?(room_id, user_id) do
      true ->
        # User already in room, just update their sensors
        Sensocto.RoomPresenceServer.update_sensors(room_id, user_id, all_sensors)

      false ->
        # User not in room yet, join them with the sensors
        Sensocto.RoomPresenceServer.join_room(room_id, user_id, all_sensors, role: :member)
    end
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

  defp get_activity_status(sensor_id, activity_map) do
    case Map.get(activity_map, sensor_id) do
      nil ->
        :inactive

      last_activity ->
        diff_ms = DateTime.diff(DateTime.utc_now(), last_activity, :millisecond)

        cond do
          diff_ms < 5000 -> :active
          diff_ms < 60_000 -> :idle
          true -> :inactive
        end
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
        <%= if @can_manage do %>
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
          <h2 class="text-xl font-semibold mb-4">Sensors</h2>
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

  defp sensor_summary_card(assigns) do
    ~H"""
    <div class="bg-gray-800 rounded-lg p-4">
      <div class="flex items-start justify-between mb-3">
        <div class="flex items-center gap-3">
          <div class="p-2 bg-gray-700 rounded-lg">
            <.sensor_icon type={@sensor.sensor_type} />
          </div>
          <div>
            <h3 class="font-semibold truncate max-w-[120px]"><%= @sensor.sensor_name %></h3>
            <p class="text-xs text-gray-500"><%= @sensor.sensor_type %></p>
          </div>
        </div>
        <.activity_indicator status={@activity_status} />
      </div>

      <div class="text-sm text-gray-400">
        <%= length(Map.keys(@sensor.attributes || %{})) %> attributes
      </div>

      <%= if @can_manage do %>
        <div class="mt-3 pt-3 border-t border-gray-700">
          <button
            phx-click="remove_sensor"
            phx-value-sensor_id={@sensor.sensor_id}
            class="text-red-400 hover:text-red-300 text-sm"
          >
            Remove
          </button>
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

  defp activity_indicator(assigns) do
    ~H"""
    <div class="relative flex items-center gap-1">
      <%= case @status do %>
        <% :active -> %>
          <span class="relative flex h-3 w-3">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75"></span>
            <span class="relative inline-flex rounded-full h-3 w-3 bg-green-500"></span>
          </span>
          <span class="text-xs text-green-400">Active</span>
        <% :idle -> %>
          <span class="relative flex h-3 w-3">
            <span class="relative inline-flex rounded-full h-3 w-3 bg-yellow-500"></span>
          </span>
          <span class="text-xs text-yellow-400">Idle</span>
        <% _ -> %>
          <span class="relative flex h-3 w-3">
            <span class="relative inline-flex rounded-full h-3 w-3 bg-gray-500"></span>
          </span>
          <span class="text-xs text-gray-400">Inactive</span>
      <% end %>
    </div>
    """
  end

  defp share_modal(assigns) do
    share_url = Sensocto.Rooms.share_url(assigns.room)

    assigns = assign(assigns, :share_url, share_url)

    ~H"""
    <div class="fixed inset-0 z-50 flex items-center justify-center bg-black/50" phx-click="close_share_modal">
      <div class="bg-gray-800 rounded-lg p-6 w-full max-w-md" phx-click-away="close_share_modal">
        <div class="flex justify-between items-center mb-6">
          <h2 class="text-xl font-semibold">Share Room</h2>
          <button phx-click="close_share_modal" class="text-gray-400 hover:text-white">
            <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="text-center mb-6">
          <p class="text-gray-400 mb-2">Join Code</p>
          <p class="text-4xl font-mono font-bold tracking-wider"><%= @room.join_code %></p>
        </div>

        <div class="mb-6">
          <p class="text-gray-400 text-sm mb-2">Share Link</p>
          <div class="flex gap-2">
            <input
              type="text"
              readonly
              value={@share_url}
              class="flex-1 bg-gray-700 border border-gray-600 rounded-lg px-4 py-2 text-white text-sm"
              id="share-url-input"
            />
            <button
              phx-click="copy_link"
              phx-hook="CopyToClipboard"
              id="copy-link-btn"
              data-copy-text={@share_url}
              class="bg-blue-600 hover:bg-blue-700 text-white px-4 py-2 rounded-lg transition-colors"
            >
              Copy
            </button>
          </div>
        </div>

        <div class="flex justify-center p-4 bg-white rounded-lg">
          <div id="qr-code" phx-hook="QRCode" data-value={@share_url} class="w-48 h-48"></div>
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

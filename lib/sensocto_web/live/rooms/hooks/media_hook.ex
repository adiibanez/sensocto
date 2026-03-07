defmodule SensoctoWeb.RoomShowLive.Hooks.MediaHook do
  @moduledoc """
  attach_hook handler for media player PubSub events in RoomShowLive.
  Forwards MediaPlayerServer messages to MediaPlayerComponent via send_update.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias SensoctoWeb.Live.Components.MediaPlayerComponent

  def on_handle_info({:media_state_changed, state}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      player_state: state.state,
      position_seconds: state.position_seconds,
      current_item: state.current_item
    )

    socket =
      push_event(socket, "media_sync", %{
        state: state.state,
        position_seconds: state.position_seconds
      })

    is_active = Map.get(state, :is_active, false)

    socket =
      if is_active and not socket.assigns.media_bump do
        Process.send_after(self(), :clear_media_bump, 300)
        assign(socket, :media_bump, true)
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:media_video_changed, %{item: item}}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      current_item: item
    )

    {:halt, socket}
  end

  def on_handle_info({:media_playlist_updated, %{items: items}}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      playlist_items: items
    )

    {:halt, socket}
  end

  def on_handle_info(
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

    {:halt,
     socket
     |> assign(:media_controller_user_id, user_id)
     |> assign(:media_control_request_modal, nil)}
  end

  def on_handle_info(
        {:media_control_requested, %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:media_controller_user_id]
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      pending_request_user_id: requester_id
    )

    socket =
      if current_user && controller_user_id &&
           to_string(current_user.id) == to_string(controller_user_id) do
        assign(socket, :media_control_request_modal, %{
          requester_id: requester_id,
          requester_name: requester_name
        })
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:media_control_request_cancelled, _params}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      pending_request_user_id: nil
    )

    {:halt, assign(socket, :media_control_request_modal, nil)}
  end

  def on_handle_info({:media_control_request_denied, _params}, socket) do
    room_id = socket.assigns.room.id

    send_update(MediaPlayerComponent,
      id: "room-media-player-#{room_id}",
      pending_request_user_id: nil
    )

    {:halt, assign(socket, :media_control_request_modal, nil)}
  end

  def on_handle_info(:clear_media_bump, socket) do
    {:halt, assign(socket, :media_bump, false)}
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}
end

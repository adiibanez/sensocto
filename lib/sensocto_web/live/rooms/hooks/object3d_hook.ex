defmodule SensoctoWeb.RoomShowLive.Hooks.Object3DHook do
  @moduledoc """
  attach_hook handler for 3D object player PubSub events in RoomShowLive.
  Forwards Object3DPlayerServer messages to Object3DPlayerComponent via send_update.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias SensoctoWeb.Live.Components.Object3DPlayerComponent

  def on_handle_info(
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

    {:halt, socket}
  end

  def on_handle_info(
        {:object3d_camera_synced,
         %{camera_position: camera_position, camera_target: camera_target} = event},
        socket
      ) do
    room_id = socket.assigns.room.id
    controller_socket_id = Map.get(event, :controller_socket_id)
    is_controller_tab = controller_socket_id && socket.id == controller_socket_id

    unless is_controller_tab do
      send_update(Object3DPlayerComponent,
        id: "object3d-player-#{room_id}",
        synced_camera_position: camera_position,
        synced_camera_target: camera_target
      )
    end

    is_active = Map.get(event, :is_active, false)

    socket =
      if is_active and not socket.assigns.object3d_bump do
        Process.send_after(self(), :clear_object3d_bump, 300)
        assign(socket, :object3d_bump, true)
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:object3d_playlist_updated, %{items: items}}, socket) do
    room_id = socket.assigns.room.id

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      playlist_items: items
    )

    {:halt, socket}
  end

  def on_handle_info(
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

    {:halt, assign(socket, :object3d_controller_user_id, user_id)}
  end

  def on_handle_info(
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

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      pending_request_user_id: requester_id,
      pending_request_user_name: requester_name
    )

    socket =
      if current_user && controller_user_id &&
           to_string(current_user.id) == to_string(controller_user_id) do
        assign(socket, :control_request_modal, %{
          requester_id: requester_id,
          requester_name: requester_name
        })
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:object3d_control_request_denied, _params}, socket) do
    room_id = socket.assigns.room.id

    send_update(Object3DPlayerComponent,
      id: "object3d-player-#{room_id}",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:halt, assign(socket, :control_request_modal, nil)}
  end

  def on_handle_info(:clear_object3d_bump, socket) do
    {:halt, assign(socket, :object3d_bump, false)}
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}
end

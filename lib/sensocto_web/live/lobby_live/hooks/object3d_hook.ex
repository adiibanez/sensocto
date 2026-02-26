defmodule SensoctoWeb.LobbyLive.Hooks.Object3DHook do
  @moduledoc """
  attach_hook handler for 3D object player events in LobbyLive.
  Forwards PubSub messages from Object3DPlayerServer to Object3DPlayerComponent.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias SensoctoWeb.Live.Components.Object3DPlayerComponent

  def on_handle_info(
        {:object3d_item_changed, %{item: item, camera_position: pos, camera_target: target}},
        socket
      ) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
      current_item: item,
      camera_position: pos,
      camera_target: target
    )

    {:halt, socket}
  end

  def on_handle_info(
        {:object3d_camera_synced, %{camera_position: position, camera_target: target} = event},
        socket
      ) do
    if socket.assigns.sync_mode == :solo do
      {:halt, socket}
    else
      controller_socket_id = Map.get(event, :controller_socket_id)
      is_controller_tab = controller_socket_id && socket.id == controller_socket_id

      unless is_controller_tab do
        send_update(Object3DPlayerComponent,
          id: "lobby-object3d-player",
          synced_camera_position: position,
          synced_camera_target: target
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
  end

  def on_handle_info(
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

    {:halt, assign(socket, :object3d_controller_user_id, user_id)}
  end

  def on_handle_info({:object3d_playlist_updated, %{items: items}}, socket) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
      playlist_items: items
    )

    {:halt, socket}
  end

  def on_handle_info(
        {:control_requested, %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:object3d_controller_user_id]

    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      {:halt,
       assign(socket, :control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      {:halt, socket}
    end
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
    current_user = socket.assigns[:current_user]
    controller_user_id = socket.assigns[:object3d_controller_user_id]

    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      send_update(Object3DPlayerComponent,
        id: "lobby-object3d-player",
        pending_request_user_id: requester_id,
        pending_request_user_name: requester_name
      )

      {:halt,
       assign(socket, :control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      send_update(Object3DPlayerComponent,
        id: "lobby-object3d-player",
        pending_request_user_id: requester_id,
        pending_request_user_name: requester_name
      )

      {:halt, socket}
    end
  end

  def on_handle_info(
        {:object3d_control_request_denied, %{requester_id: _requester_id}},
        socket
      ) do
    send_update(Object3DPlayerComponent,
      id: "lobby-object3d-player",
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

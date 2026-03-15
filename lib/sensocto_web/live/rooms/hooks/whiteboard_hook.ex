defmodule SensoctoWeb.RoomShowLive.Hooks.WhiteboardHook do
  @moduledoc """
  attach_hook handler for whiteboard PubSub events in RoomShowLive.
  Forwards WhiteboardServer messages to WhiteboardComponent via send_update.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias SensoctoWeb.Live.Components.WhiteboardComponent

  def on_handle_info({:whiteboard_stroke_progress, %{stroke: stroke, user_id: user_id}}, socket) do
    room_id = socket.assigns.room.id

    if socket.assigns.current_user &&
         to_string(socket.assigns.current_user.id) != to_string(user_id) do
      send_update(WhiteboardComponent,
        id: "whiteboard-#{room_id}",
        stroke_progress: %{stroke: stroke, user_id: user_id}
      )
    end

    socket =
      if not socket.assigns.whiteboard_bump do
        Process.send_after(self(), :clear_whiteboard_bump, 300)
        assign(socket, :whiteboard_bump, true)
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:whiteboard_strokes_batch, %{strokes: strokes}}, socket) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      new_strokes: strokes
    )

    socket =
      if not socket.assigns.whiteboard_bump do
        Process.send_after(self(), :clear_whiteboard_bump, 300)
        assign(socket, :whiteboard_bump, true)
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:whiteboard_stroke_added, %{stroke: stroke}}, socket) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      new_stroke: stroke
    )

    socket =
      if not socket.assigns.whiteboard_bump do
        Process.send_after(self(), :clear_whiteboard_bump, 300)
        assign(socket, :whiteboard_bump, true)
      else
        socket
      end

    {:halt, socket}
  end

  def on_handle_info({:whiteboard_cleared, _params}, socket) do
    room_id = socket.assigns.room.id
    send_update(WhiteboardComponent, id: "whiteboard-#{room_id}", strokes: [])
    {:halt, socket}
  end

  def on_handle_info({:whiteboard_undo, _params}, socket) do
    room_id = socket.assigns.room.id
    send_update(WhiteboardComponent, id: "whiteboard-#{room_id}")
    {:halt, socket}
  end

  def on_handle_info({:whiteboard_background_changed, %{color: color}}, socket) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      background_color: color
    )

    {:halt, socket}
  end

  def on_handle_info(
        {:whiteboard_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name}},
        socket
      ) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      controller_user_id: user_id,
      controller_user_name: user_name,
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:halt, socket}
  end

  def on_handle_info(
        {:whiteboard_control_requested,
         %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      pending_request_user_id: requester_id,
      pending_request_user_name: requester_name
    )

    {:halt, socket}
  end

  def on_handle_info({:whiteboard_control_request_denied, _params}, socket) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:halt, socket}
  end

  def on_handle_info({:whiteboard_control_request_cancelled, _params}, socket) do
    room_id = socket.assigns.room.id

    send_update(WhiteboardComponent,
      id: "whiteboard-#{room_id}",
      pending_request_user_id: nil,
      pending_request_user_name: nil
    )

    {:halt, socket}
  end

  def on_handle_info(:clear_whiteboard_bump, socket) do
    {:halt, assign(socket, :whiteboard_bump, false)}
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}
end

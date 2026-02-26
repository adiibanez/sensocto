defmodule SensoctoWeb.LobbyLive.Hooks.MediaHook do
  @moduledoc """
  attach_hook handler for media player events in LobbyLive.
  Forwards PubSub messages from MediaPlayerServer to MediaPlayerComponent.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  alias SensoctoWeb.Live.Components.MediaPlayerComponent

  def on_handle_info({:media_state_changed, state}, socket) do
    if socket.assigns.sync_mode == :solo do
      send_update(MediaPlayerComponent,
        id: "lobby-media-player",
        player_state: state.state,
        position_seconds: state.position_seconds,
        current_item: state.current_item
      )

      {:halt, socket}
    else
      send_update(MediaPlayerComponent,
        id: "lobby-media-player",
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
  end

  def on_handle_info({:media_video_changed, %{item: item}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      current_item: item
    )

    socket =
      push_event(socket, "media_load_video", %{
        video_id: item.youtube_video_id,
        start_seconds: 0
      })

    {:halt, socket}
  end

  def on_handle_info({:media_playlist_updated, %{items: items}}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      playlist_items: items
    )

    {:halt, socket}
  end

  def on_handle_info(
        {:media_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name} = params},
        socket
      ) do
    pending_request_user_id = Map.get(params, :pending_request_user_id)

    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
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

    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      pending_request_user_id: requester_id
    )

    if current_user && controller_user_id &&
         to_string(current_user.id) == to_string(controller_user_id) do
      {:halt,
       assign(socket, :media_control_request_modal, %{
         requester_id: requester_id,
         requester_name: requester_name
       })}
    else
      {:halt, socket}
    end
  end

  def on_handle_info({:media_control_request_cancelled, _params}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      pending_request_user_id: nil
    )

    {:halt, assign(socket, :media_control_request_modal, nil)}
  end

  def on_handle_info({:media_control_request_denied, _params}, socket) do
    send_update(MediaPlayerComponent,
      id: "lobby-media-player",
      pending_request_user_id: nil
    )

    {:halt, assign(socket, :media_control_request_modal, nil)}
  end

  def on_handle_info(:clear_media_bump, socket) do
    {:halt, assign(socket, :media_bump, false)}
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}
end

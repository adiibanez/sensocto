defmodule SensoctoWeb.LobbyLive.Hooks.AvatarHook do
  @moduledoc """
  attach_hook handler for avatar ecosystem events in LobbyLive.
  Handles control state broadcasts from AvatarEcosystemServer.
  """
  import Phoenix.Component, only: [assign: 3]

  def on_handle_info(:clear_avatar_bump, socket) do
    {:halt, assign(socket, :avatar_bump, false)}
  end

  def on_handle_info(
        {:avatar_controller_changed,
         %{controller_user_id: user_id, controller_user_name: user_name}},
        socket
      ) do
    socket =
      socket
      |> assign(:avatar_controller_user_id, user_id)
      |> assign(:avatar_controller_user_name, user_name)
      |> assign(:avatar_pending_request_user_id, nil)
      |> assign(:avatar_pending_request_user_name, nil)

    {:halt, socket}
  end

  def on_handle_info(
        {:avatar_control_requested,
         %{requester_id: requester_id, requester_name: requester_name}},
        socket
      ) do
    socket =
      socket
      |> assign(:avatar_pending_request_user_id, requester_id)
      |> assign(:avatar_pending_request_user_name, requester_name)

    {:halt, socket}
  end

  def on_handle_info({:avatar_control_request_denied, _params}, socket) do
    socket =
      socket
      |> assign(:avatar_pending_request_user_id, nil)
      |> assign(:avatar_pending_request_user_name, nil)

    {:halt, socket}
  end

  def on_handle_info({:avatar_control_request_cancelled, _params}, socket) do
    socket =
      socket
      |> assign(:avatar_pending_request_user_id, nil)
      |> assign(:avatar_pending_request_user_name, nil)

    {:halt, socket}
  end

  def on_handle_info(
        {:avatar_world_changed, %{world: world, from_user_id: from_user_id}},
        socket
      ) do
    if not same_user?(socket, from_user_id) and socket.assigns.sync_mode == :synced do
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
        |> Phoenix.LiveView.push_event("avatar_switch_world", %{world: world})

      {:halt, socket}
    else
      {:cont, socket}
    end
  end

  def on_handle_info(
        {:avatar_wind_changed, %{value: value, from_user_id: from_user_id}},
        socket
      ) do
    if not same_user?(socket, from_user_id) and socket.assigns.sync_mode == :synced do
      socket =
        socket
        |> assign(:avatar_wind, value)
        |> Phoenix.LiveView.push_event("avatar_set_wind", %{value: value / 100})

      {:halt, socket}
    else
      {:cont, socket}
    end
  end

  def on_handle_info(
        {:avatar_camera_changed,
         %{position: position, target: target, from_user_id: from_user_id}},
        socket
      ) do
    if not same_user?(socket, from_user_id) and socket.assigns.sync_mode == :synced do
      socket =
        Phoenix.LiveView.push_event(socket, "avatar_update_camera", %{
          position: position,
          target: target
        })

      {:halt, socket}
    else
      {:cont, socket}
    end
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}

  defp same_user?(socket, from_user_id) do
    case socket.assigns[:current_user] do
      nil -> false
      user -> to_string(user.id) == to_string(from_user_id)
    end
  end
end

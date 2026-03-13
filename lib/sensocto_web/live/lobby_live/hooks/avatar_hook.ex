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

  def on_handle_info(_msg, socket), do: {:cont, socket}
end

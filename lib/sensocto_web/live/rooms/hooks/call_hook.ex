defmodule SensoctoWeb.RoomShowLive.Hooks.CallHook do
  @moduledoc """
  attach_hook handler for call-related PubSub events in RoomShowLive.
  Handles call participant events and push_event forwarding.
  """
  import Phoenix.LiveView
  import Phoenix.Component, only: [assign: 3]

  def on_handle_info({:call_event, event}, socket) do
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

    {:halt, socket}
  end

  def on_handle_info({:push_event, event, payload}, socket) do
    {:halt, push_event(socket, event, payload)}
  end

  def on_handle_info(_msg, socket), do: {:cont, socket}
end

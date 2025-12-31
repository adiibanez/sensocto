defmodule SensoctoWeb.CallChannel do
  @moduledoc """
  Phoenix Channel for WebRTC signaling.
  Handles SDP offers/answers, ICE candidates, and media events
  between browser clients and the Membrane RTC Engine.
  """
  use SensoctoWeb, :channel
  require Logger

  alias Sensocto.Calls
  alias Phoenix.PubSub

  # Intercept broadcast events so handle_out/3 is called
  intercept ["participant_audio_changed", "participant_video_changed"]

  @impl true
  def join("call:" <> room_id, params, socket) do
    user_id = params["user_id"]
    user_info = params["user_info"] || %{}

    if is_nil(user_id) do
      {:error, %{reason: "user_id required"}}
    else
      case Calls.can_join_call?(room_id, user_id) do
        :ok ->
          # Subscribe to call events for this room
          PubSub.subscribe(Sensocto.PubSub, "call:#{room_id}")
          # Subscribe to personal events for this user
          PubSub.subscribe(Sensocto.PubSub, "call:#{room_id}:#{user_id}")

          socket =
            socket
            |> assign(:room_id, room_id)
            |> assign(:user_id, user_id)
            |> assign(:user_info, user_info)
            |> assign(:joined_call, false)

          # Send ICE servers configuration
          ice_servers = Calls.get_ice_servers()

          {:ok, %{ice_servers: ice_servers}, socket}

        {:error, :call_full} ->
          {:error, %{reason: "call_full"}}

        {:error, :not_room_member} ->
          {:error, %{reason: "not_room_member"}}

        {:error, _reason} ->
          {:error, %{reason: "unauthorized"}}
      end
    end
  end

  @impl true
  def handle_in("join_call", _params, socket) do
    room_id = socket.assigns.room_id
    user_id = socket.assigns.user_id
    user_info = socket.assigns.user_info

    IO.puts(">>> CallChannel: User #{user_id} attempting to join call in room #{room_id}")

    case Calls.join_call(room_id, user_id, user_info: user_info) do
      {:ok, endpoint_id} ->
        socket = assign(socket, :joined_call, true)
        socket = assign(socket, :endpoint_id, endpoint_id)

        # Get current participants
        {:ok, participants} = Calls.get_participants(room_id)

        {:reply, {:ok, %{endpoint_id: endpoint_id, participants: participants}}, socket}

      {:error, :already_joined} ->
        {:reply, {:error, %{reason: "already_joined"}}, socket}

      {:error, :call_full} ->
        {:reply, {:error, %{reason: "call_full"}}, socket}

      {:error, reason} ->
        Logger.error("Failed to join call: #{inspect(reason)}")
        {:reply, {:error, %{reason: "join_failed"}}, socket}
    end
  end

  @impl true
  def handle_in("leave_call", _params, socket) do
    if socket.assigns.joined_call do
      room_id = socket.assigns.room_id
      user_id = socket.assigns.user_id

      Calls.leave_call(room_id, user_id)

      socket =
        socket
        |> assign(:joined_call, false)
        |> assign(:endpoint_id, nil)

      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "not_in_call"}}, socket}
    end
  end

  @impl true
  def handle_in("media_event", %{"data" => data}, socket) do
    if socket.assigns.joined_call do
      room_id = socket.assigns.room_id
      user_id = socket.assigns.user_id

      Logger.info("CallChannel: Received media event from #{user_id}: #{inspect(data, limit: 200)}")
      Calls.handle_media_event(room_id, user_id, data)

      {:noreply, socket}
    else
      {:reply, {:error, %{reason: "not_in_call"}}, socket}
    end
  end

  @impl true
  def handle_in("toggle_audio", %{"enabled" => enabled}, socket) do
    if socket.assigns.joined_call do
      # For now, just acknowledge. Audio track enabling/disabling
      # is handled client-side. We broadcast the state change.
      user_id = socket.assigns.user_id

      broadcast!(socket, "participant_audio_changed", %{
        user_id: user_id,
        audio_enabled: enabled
      })

      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "not_in_call"}}, socket}
    end
  end

  @impl true
  def handle_in("toggle_video", %{"enabled" => enabled}, socket) do
    if socket.assigns.joined_call do
      user_id = socket.assigns.user_id

      broadcast!(socket, "participant_video_changed", %{
        user_id: user_id,
        video_enabled: enabled
      })

      {:reply, :ok, socket}
    else
      {:reply, {:error, %{reason: "not_in_call"}}, socket}
    end
  end

  @impl true
  def handle_in("set_quality", %{"quality" => quality}, socket) do
    if socket.assigns.joined_call do
      room_id = socket.assigns.room_id

      quality_atom =
        case quality do
          "high" -> :high
          "medium" -> :medium
          "low" -> :low
          _ -> :auto
        end

      case Calls.set_quality_profile(room_id, quality_atom) do
        :ok -> {:reply, :ok, socket}
        {:error, _} -> {:reply, {:error, %{reason: "set_quality_failed"}}, socket}
      end
    else
      {:reply, {:error, %{reason: "not_in_call"}}, socket}
    end
  end

  @impl true
  def handle_in("get_participants", _params, socket) do
    room_id = socket.assigns.room_id

    case Calls.get_participants(room_id) do
      {:ok, participants} ->
        {:reply, {:ok, %{participants: participants}}, socket}

      {:error, _} ->
        {:reply, {:ok, %{participants: %{}}}, socket}
    end
  end

  # Handle PubSub messages from CallServer

  @impl true
  def handle_info({:call_event, event}, socket) do
    case event do
      {:participant_joined, participant} ->
        push(socket, "participant_joined", format_participant(participant))

      {:participant_left, user_id} ->
        push(socket, "participant_left", %{user_id: user_id})

      {:participant_crashed, user_id, _reason} ->
        push(socket, "participant_left", %{user_id: user_id, crashed: true})

      {:track_added, track_info} ->
        push(socket, "track_added", track_info)

      {:track_removed, track_id} ->
        push(socket, "track_removed", %{track_id: track_id})

      {:quality_changed, quality} ->
        push(socket, "quality_changed", %{quality: quality})

      :call_ended ->
        push(socket, "call_ended", %{})

      _ ->
        :ok
    end

    {:noreply, socket}
  end

  @impl true
  def handle_info({:media_event, event}, socket) do
    # Forward media events from RTC Engine to the client
    IO.puts(">>> CallChannel: Forwarding media event to #{socket.assigns.user_id}")
    push(socket, "media_event", %{data: event})
    {:noreply, socket}
  end

  @impl true
  def handle_info(msg, socket) do
    Logger.debug("CallChannel received unknown message: #{inspect(msg)}")
    {:noreply, socket}
  end

  # Handle outgoing broadcasts - these are required when using broadcast!/3
  @impl true
  def handle_out("participant_audio_changed", payload, socket) do
    push(socket, "participant_audio_changed", payload)
    {:noreply, socket}
  end

  @impl true
  def handle_out("participant_video_changed", payload, socket) do
    push(socket, "participant_video_changed", payload)
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns[:joined_call] do
      room_id = socket.assigns.room_id
      user_id = socket.assigns.user_id

      Calls.leave_call(room_id, user_id)
    end

    :ok
  end

  # Private functions

  defp format_participant(participant) do
    %{
      user_id: participant.user_id,
      endpoint_id: participant.endpoint_id,
      user_info: participant.user_info,
      joined_at: participant.joined_at,
      audio_enabled: participant.audio_enabled,
      video_enabled: participant.video_enabled
    }
  end
end

defmodule Sensocto.Calls.CallServer do
  @moduledoc """
  GenServer managing video/voice call state for a room.
  Wraps Membrane RTC Engine and handles participant management.
  """
  use GenServer
  require Logger

  alias Membrane.RTC.Engine
  alias Membrane.RTC.Engine.Endpoint.ExWebRTC
  alias Membrane.RTC.Engine.Message
  alias Sensocto.Calls.QualityManager

  @default_max_participants 20
  @inactivity_timeout_ms 30 * 60 * 1000

  defstruct [
    :room_id,
    :engine_pid,
    :inactivity_timer,
    participants: %{},
    track_registry: %{},
    quality_profile: :auto,
    max_participants: @default_max_participants,
    created_at: nil
  ]

  # Client API

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end

  def via_tuple(room_id) do
    {:via, Registry, {Sensocto.CallRegistry, room_id}}
  end

  @doc """
  Adds a participant to the call.
  Returns {:ok, endpoint_id} on success.
  """
  def add_participant(room_id, user_id, user_info \\ %{}) do
    GenServer.call(via_tuple(room_id), {:add_participant, user_id, user_info})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Removes a participant from the call.
  """
  def remove_participant(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:remove_participant, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Gets the current call state (participant list, etc.)
  """
  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Gets the list of participants in the call.
  """
  def get_participants(room_id) do
    GenServer.call(via_tuple(room_id), :get_participants)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Forwards a media event from a client to the RTC Engine.
  """
  def media_event(room_id, user_id, event) do
    GenServer.cast(via_tuple(room_id), {:media_event, user_id, event})
  end

  @doc """
  Updates the quality profile for the call.
  """
  def set_quality_profile(room_id, profile) when profile in [:auto, :high, :medium, :low] do
    GenServer.call(via_tuple(room_id), {:set_quality_profile, profile})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Gets the participant count.
  """
  def participant_count(room_id) do
    case get_participants(room_id) do
      {:ok, participants} -> {:ok, map_size(participants)}
      error -> error
    end
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    max_participants = Keyword.get(opts, :max_participants, @default_max_participants)

    Logger.info("Starting CallServer for room #{room_id}")

    # Register in the CallRegistry
    Registry.register(Sensocto.CallRegistry, room_id, self())

    # Start the RTC Engine
    {:ok, engine_pid} =
      Engine.start_link(
        [id: room_id, trace_ctx: %{}],
        []
      )

    # Subscribe to engine notifications
    Engine.register(engine_pid, self())

    # Start inactivity timer
    inactivity_timer = schedule_inactivity_check()

    state = %__MODULE__{
      room_id: room_id,
      engine_pid: engine_pid,
      max_participants: max_participants,
      created_at: DateTime.utc_now(),
      inactivity_timer: inactivity_timer
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:add_participant, user_id, user_info}, _from, state) do
    # Handle reconnection: if user is already in call, remove old endpoint first
    state =
      case Map.get(state.participants, user_id) do
        nil ->
          state

        old_participant ->
          Logger.info("User #{user_id} reconnecting - removing old endpoint #{old_participant.endpoint_id}")
          # Remove old endpoint from RTC Engine
          Engine.remove_endpoint(state.engine_pid, old_participant.endpoint_id)
          # Clean up tracks from old endpoint
          new_track_registry =
            state.track_registry
            |> Enum.reject(fn {_track_id, track_info} ->
              track_info.endpoint_id == old_participant.endpoint_id
            end)
            |> Map.new()
          # Remove from participants
          {_, new_participants} = Map.pop(state.participants, user_id)
          %{state | participants: new_participants, track_registry: new_track_registry}
      end

    cond do
      map_size(state.participants) >= state.max_participants ->
        {:reply, {:error, :call_full}, state}

      true ->
        endpoint_id = generate_endpoint_id(user_id)

        # Get quality settings based on current participant count
        quality = QualityManager.calculate_quality(map_size(state.participants) + 1, :good)
        _constraints = QualityManager.get_video_constraints(quality)

        # Create ExWebRTC endpoint struct
        # ICE servers are configured via :membrane_rtc_engine_ex_webrtc application config
        webrtc_endpoint = %ExWebRTC{
          rtc_engine: state.engine_pid,
          video_codec: :VP8,
          event_serialization: :json,
          subscribe_mode: :auto
        }

        # Add endpoint to RTC Engine
        :ok = Engine.add_endpoint(state.engine_pid, webrtc_endpoint, id: endpoint_id)

        participant = %{
          user_id: user_id,
          endpoint_id: endpoint_id,
          user_info: user_info,
          joined_at: DateTime.utc_now(),
          audio_enabled: true,
          video_enabled: true,
          quality_level: quality,
          tracks: %{}
        }

        new_participants = Map.put(state.participants, user_id, participant)
        new_state = %{state | participants: new_participants}

        # Broadcast participant joined
        broadcast_call_event(state.room_id, {:participant_joined, participant})

        # Cancel inactivity timer since we have participants
        if state.inactivity_timer do
          Process.cancel_timer(state.inactivity_timer)
        end

        Logger.info("Participant #{user_id} joined call in room #{state.room_id}")

        {:reply, {:ok, endpoint_id}, %{new_state | inactivity_timer: nil}}
    end
  end

  @impl true
  def handle_call({:remove_participant, user_id}, _from, state) do
    case Map.pop(state.participants, user_id) do
      {nil, _} ->
        {:reply, {:error, :not_in_call}, state}

      {participant, new_participants} ->
        # Remove endpoint from RTC Engine
        Engine.remove_endpoint(state.engine_pid, participant.endpoint_id)

        # Clean up tracks from this endpoint
        new_track_registry =
          state.track_registry
          |> Enum.reject(fn {_track_id, track_info} ->
            track_info.endpoint_id == participant.endpoint_id
          end)
          |> Map.new()

        new_state = %{state | participants: new_participants, track_registry: new_track_registry}

        # Broadcast participant left
        broadcast_call_event(state.room_id, {:participant_left, user_id})

        Logger.info("Participant #{user_id} left call in room #{state.room_id}")

        # If no participants left, start inactivity timer
        new_state =
          if map_size(new_participants) == 0 do
            timer = schedule_inactivity_check()
            %{new_state | inactivity_timer: timer}
          else
            # Update quality for remaining participants
            update_all_participants_quality(new_state)
          end

        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    view_state = %{
      room_id: state.room_id,
      participants: format_participants(state.participants),
      participant_count: map_size(state.participants),
      quality_profile: state.quality_profile,
      max_participants: state.max_participants,
      created_at: state.created_at,
      tracks: state.track_registry
    }

    {:reply, {:ok, view_state}, state}
  end

  @impl true
  def handle_call(:get_participants, _from, state) do
    {:reply, {:ok, format_participants(state.participants)}, state}
  end

  @impl true
  def handle_call({:set_quality_profile, profile}, _from, state) do
    new_state = %{state | quality_profile: profile}
    # Apply new quality to all participants
    new_state = update_all_participants_quality(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_cast({:media_event, user_id, event}, state) do
    case Map.get(state.participants, user_id) do
      nil ->
        Logger.warning("Media event from unknown participant #{user_id}")
        {:noreply, state}

      participant ->
        # Forward the media event to the WebRTC endpoint
        Engine.message_endpoint(state.engine_pid, participant.endpoint_id, {:media_event, event})
        {:noreply, state}
    end
  end

  # Handle RTC Engine notifications
  @impl true
  def handle_info(%Message.EndpointMessage{endpoint_id: endpoint_id, message: {:media_event, event}}, state) do
    IO.puts(">>> CallServer: EndpointMessage media_event from #{endpoint_id}")
    # Forward media event to the participant's channel
    case find_participant_by_endpoint(state.participants, endpoint_id) do
      nil ->
        IO.puts(">>> CallServer: No participant found for endpoint #{endpoint_id}")
        {:noreply, state}

      {user_id, _participant} ->
        IO.puts(">>> CallServer: Forwarding to user #{user_id}")
        broadcast_to_participant(state.room_id, user_id, {:media_event, event})
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(
        %Message.TrackAdded{
          endpoint_id: endpoint_id,
          track_id: track_id,
          track_type: track_type,
          track_encoding: track_encoding
        },
        state
      ) do
    IO.puts(">>> CallServer: TrackAdded #{track_type} from #{endpoint_id}")

    track_info = %{
      track_id: track_id,
      endpoint_id: endpoint_id,
      type: track_type,
      encoding: track_encoding
    }

    new_track_registry = Map.put(state.track_registry, track_id, track_info)

    # Broadcast track added to all participants
    broadcast_call_event(state.room_id, {:track_added, track_info})

    {:noreply, %{state | track_registry: new_track_registry}}
  end

  @impl true
  def handle_info(%Message.TrackRemoved{endpoint_id: endpoint_id, track_id: track_id}, state) do
    Logger.debug("Track removed: #{track_id} from endpoint #{endpoint_id}")

    new_track_registry = Map.delete(state.track_registry, track_id)

    # Broadcast track removed to all participants
    broadcast_call_event(state.room_id, {:track_removed, track_id})

    {:noreply, %{state | track_registry: new_track_registry}}
  end

  @impl true
  def handle_info(%Message.EndpointAdded{endpoint_id: endpoint_id}, state) do
    Logger.debug("Endpoint added: #{endpoint_id}")
    {:noreply, state}
  end

  @impl true
  def handle_info(%Message.EndpointRemoved{endpoint_id: endpoint_id}, state) do
    Logger.debug("Endpoint removed: #{endpoint_id}")

    # Clean up tracks from this endpoint
    new_track_registry =
      state.track_registry
      |> Enum.reject(fn {_track_id, track_info} ->
        track_info.endpoint_id == endpoint_id
      end)
      |> Map.new()

    state = %{state | track_registry: new_track_registry}

    # Clean up participant if endpoint was removed unexpectedly
    case find_participant_by_endpoint(state.participants, endpoint_id) do
      nil ->
        {:noreply, state}

      {user_id, _participant} ->
        {_, new_participants} = Map.pop(state.participants, user_id)
        broadcast_call_event(state.room_id, {:participant_left, user_id})
        {:noreply, %{state | participants: new_participants}}
    end
  end

  @impl true
  def handle_info(%Message.EndpointCrashed{endpoint_id: endpoint_id, reason: reason}, state) do
    Logger.error("Endpoint crashed: #{endpoint_id}, reason: #{inspect(reason)}")

    # Clean up tracks from this endpoint
    new_track_registry =
      state.track_registry
      |> Enum.reject(fn {_track_id, track_info} ->
        track_info.endpoint_id == endpoint_id
      end)
      |> Map.new()

    state = %{state | track_registry: new_track_registry}

    case find_participant_by_endpoint(state.participants, endpoint_id) do
      nil ->
        {:noreply, state}

      {user_id, _participant} ->
        {_, new_participants} = Map.pop(state.participants, user_id)
        broadcast_call_event(state.room_id, {:participant_crashed, user_id, reason})
        {:noreply, %{state | participants: new_participants}}
    end
  end

  @impl true
  def handle_info(:check_inactivity, state) do
    if map_size(state.participants) == 0 do
      Logger.info("Call in room #{state.room_id} has no participants, shutting down")
      {:stop, :normal, state}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("CallServer received unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("CallServer for room #{state.room_id} terminating: #{inspect(reason)}")

    if state.engine_pid && Process.alive?(state.engine_pid) do
      Engine.terminate(state.engine_pid, reason)
    end

    if state.inactivity_timer do
      Process.cancel_timer(state.inactivity_timer)
    end

    broadcast_call_event(state.room_id, :call_ended)

    :ok
  end

  # Private functions

  defp generate_endpoint_id(user_id) do
    "#{user_id}_#{System.unique_integer([:positive])}"
  end

  defp schedule_inactivity_check do
    Process.send_after(self(), :check_inactivity, @inactivity_timeout_ms)
  end

  defp find_participant_by_endpoint(participants, endpoint_id) do
    Enum.find(participants, fn {_user_id, participant} ->
      participant.endpoint_id == endpoint_id
    end)
  end

  defp format_participants(participants) do
    Map.new(participants, fn {user_id, participant} ->
      {user_id,
       %{
         user_id: participant.user_id,
         endpoint_id: participant.endpoint_id,
         user_info: participant.user_info,
         joined_at: participant.joined_at,
         audio_enabled: participant.audio_enabled,
         video_enabled: participant.video_enabled,
         quality_level: participant.quality_level
       }}
    end)
  end

  defp broadcast_call_event(room_id, event) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "call:#{room_id}", {:call_event, event})
  end

  defp broadcast_to_participant(room_id, user_id, message) do
    Phoenix.PubSub.broadcast(Sensocto.PubSub, "call:#{room_id}:#{user_id}", message)
  end

  defp update_all_participants_quality(state) do
    participant_count = map_size(state.participants)
    target_quality = QualityManager.calculate_quality(participant_count, :good)

    new_participants =
      Map.new(state.participants, fn {user_id, participant} ->
        # Update quality level for each participant
        {user_id, %{participant | quality_level: target_quality}}
      end)

    # Broadcast quality change
    broadcast_call_event(state.room_id, {:quality_changed, target_quality})

    %{state | participants: new_participants}
  end
end

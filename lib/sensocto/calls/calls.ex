defmodule Sensocto.Calls do
  @moduledoc """
  Context module for video/voice calls.
  Provides the public API for managing calls within rooms.
  """

  alias Sensocto.Calls.{CallServer, CallSupervisor, QualityManager}
  alias Sensocto.Rooms

  @doc """
  Starts or gets an existing call for a room.
  Returns {:ok, call_pid} on success.
  """
  def get_or_start_call(room_id, opts \\ []) do
    CallSupervisor.get_or_start_call(room_id, opts)
  end

  @doc """
  Stops a call for a room.
  """
  def stop_call(room_id) do
    CallSupervisor.stop_call(room_id)
  end

  @doc """
  Joins a user to a call in a room.
  Creates the call if it doesn't exist.

  ## Options
    - :user_info - Additional user information (name, avatar, etc.)

  Returns {:ok, endpoint_id} on success.
  """
  def join_call(room_id, user_id, opts \\ []) do
    user_info = Keyword.get(opts, :user_info, %{})

    with {:ok, _pid} <- get_or_start_call(room_id),
         {:ok, endpoint_id} <- CallServer.add_participant(room_id, user_id, user_info) do
      {:ok, endpoint_id}
    end
  end

  @doc """
  Leaves a call.
  """
  def leave_call(room_id, user_id) do
    CallServer.remove_participant(room_id, user_id)
  end

  @doc """
  Gets the current call state for a room.
  """
  def get_call_state(room_id) do
    CallServer.get_state(room_id)
  end

  @doc """
  Gets the list of participants in a call.
  """
  def get_participants(room_id) do
    CallServer.get_participants(room_id)
  end

  @doc """
  Gets the number of participants in a call.
  """
  def participant_count(room_id) do
    CallServer.participant_count(room_id)
  end

  @doc """
  Checks if a call exists for a room.
  """
  def call_exists?(room_id) do
    CallSupervisor.call_exists?(room_id)
  end

  @doc """
  Checks if a user is in a call.
  """
  def in_call?(room_id, user_id) do
    case get_participants(room_id) do
      {:ok, participants} -> Map.has_key?(participants, user_id)
      _ -> false
    end
  end

  @doc """
  Forwards a media event from a client to the RTC Engine.
  Called by the CallChannel when receiving media events from clients.
  """
  def handle_media_event(room_id, user_id, event) do
    CallServer.media_event(room_id, user_id, event)
  end

  @doc """
  Sets the quality profile for a call.
  """
  def set_quality_profile(room_id, profile) do
    CallServer.set_quality_profile(room_id, profile)
  end

  @doc """
  Updates a participant's speaking state for adaptive quality.
  Called by CallChannel when client detects audio activity.
  """
  def update_speaking_state(room_id, user_id, speaking?) do
    CallServer.update_speaking_state(room_id, user_id, speaking?)
  end

  @doc """
  Updates a participant's attention/visibility state for adaptive quality.
  Levels: :high (focused), :medium (visible), :low (hidden tab/AFK)
  """
  def update_attention(room_id, user_id, level) do
    CallServer.update_attention(room_id, user_id, level)
  end

  @doc """
  Gets the current quality tier for a participant.
  Returns {:ok, tier} where tier is :active, :recent, :viewer, or :idle
  """
  def get_participant_tier(room_id, user_id) do
    CallServer.get_participant_tier(room_id, user_id)
  end

  @doc """
  Enables or disables adaptive quality mode for a call.
  When disabled, all participants use the same quality based on count.
  """
  def set_adaptive_quality(room_id, enabled?) do
    CallServer.set_adaptive_quality(room_id, enabled?)
  end

  @doc """
  Updates the attention level for a participant's webcam quality.
  Called by AttentionTracker when system load changes.

  Attention levels map to webcam quality:
  - :none/:low - high quality allowed
  - :normal - medium quality
  - :high - low quality
  - :critical - minimal quality (for extreme load)
  """
  def set_attention_level(room_id, user_id, attention_level) do
    # Broadcast to the specific user's LiveView to push to their JS hook
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "call:#{room_id}:user:#{user_id}",
      {:attention_level_changed, attention_level}
    )
  end

  @doc """
  Broadcasts attention level to all participants in a call.
  Used for global load-based backpressure.
  """
  def broadcast_attention_level(room_id, attention_level) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "call:#{room_id}",
      {:global_attention_level, attention_level}
    )
  end

  @doc """
  Gets the recommended quality for a given participant count.
  """
  def recommended_quality(participant_count) do
    QualityManager.calculate_quality(participant_count)
  end

  @doc """
  Gets the video constraints for a quality level.
  """
  def video_constraints(quality) do
    QualityManager.get_video_constraints(quality)
  end

  @doc """
  Gets all quality profiles for UI display.
  """
  def quality_profiles do
    QualityManager.all_profiles()
  end

  @doc """
  Lists all active calls.
  """
  def list_active_calls do
    CallSupervisor.list_active_calls()
  end

  @doc """
  Gets the count of active calls.
  """
  def active_call_count do
    CallSupervisor.count()
  end

  @doc """
  Gets ICE server configuration.
  Used by the CallChannel to send to clients.
  """
  def get_ice_servers do
    Application.get_env(:sensocto, :calls, [])
    |> Keyword.get(:ice_servers, [%{urls: "stun:stun.l.google.com:19302"}])
  end

  @doc """
  Validates that a user can join a call in a room.
  Returns :ok if allowed, {:error, reason} otherwise.
  """
  def can_join_call?(room_id, user_id)

  # Special case: lobby is always accessible to authenticated users
  def can_join_call?("lobby", user_id) when is_binary(user_id) do
    case participant_count("lobby") do
      {:ok, count} when count >= 20 -> {:error, :call_full}
      _ -> :ok
    end
  end

  def can_join_call?(:lobby, user_id) when is_binary(user_id) do
    can_join_call?("lobby", user_id)
  end

  def can_join_call?(room_id, user_id) do
    # Create a user-like map for the member?/owner? functions
    user = %{id: user_id}

    with {:ok, room} <- Rooms.get_room(room_id),
         true <- room.is_public || Rooms.member?(room, user) || Rooms.owner?(room, user) do
      case participant_count(room_id) do
        {:ok, count} when count >= 20 -> {:error, :call_full}
        _ -> :ok
      end
    else
      false -> {:error, :not_room_member}
      {:error, _} = error -> error
    end
  end
end

defmodule Sensocto.Media.MediaPlayerServer do
  @moduledoc """
  GenServer managing synchronized media playback state for a room or lobby.
  Coordinates playback position, play/pause state, and playlist navigation
  across all connected clients.
  """
  use GenServer
  require Logger

  alias Sensocto.Media

  # Heartbeat interval for periodic sync broadcasts when playing
  @heartbeat_interval_ms 1_000

  defstruct [
    :room_id,
    :playlist_id,
    :current_item_id,
    :controller_user_id,
    :controller_user_name,
    state: :stopped,
    position_seconds: 0.0,
    position_updated_at: nil,
    volume: 100,
    is_lobby: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id))
  end

  def via_tuple(room_id) do
    {:via, Registry, {Sensocto.MediaRegistry, room_id}}
  end

  @doc """
  Gets the current player state.
  """
  def get_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Starts or resumes playback.
  """
  def play(room_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:play, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Pauses playback.
  """
  def pause(room_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:pause, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Seeks to a specific position in seconds.
  """
  def seek(room_id, position_seconds, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:seek, position_seconds, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Plays a specific item from the playlist.
  """
  def play_item(room_id, item_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:play_item, item_id, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Skips to the next item in the playlist.
  """
  def next(room_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:next, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Goes back to the previous item in the playlist.
  """
  def previous(room_id, user_id \\ nil) do
    GenServer.call(via_tuple(room_id), {:previous, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Takes control of playback.
  """
  def take_control(room_id, user_id, user_name) do
    GenServer.call(via_tuple(room_id), {:take_control, user_id, user_name})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Releases control of playback.
  """
  def release_control(room_id, user_id) do
    GenServer.call(via_tuple(room_id), {:release_control, user_id})
  catch
    :exit, _ -> {:error, :not_found}
  end

  @doc """
  Reports current position from a client (for sync verification).
  """
  def report_position(room_id, position_seconds) do
    GenServer.cast(via_tuple(room_id), {:report_position, position_seconds})
  end

  @doc """
  Reports video ended from a client.
  """
  def video_ended(room_id) do
    GenServer.cast(via_tuple(room_id), :video_ended)
  end

  @doc """
  Notifies the server that an item was added to the playlist.
  If there's no current item, auto-selects the new item.
  """
  def item_added(room_id, item) do
    GenServer.cast(via_tuple(room_id), {:item_added, item})
  end

  @doc """
  Updates the duration of the current item (from client).
  """
  def update_duration(room_id, duration_seconds) do
    GenServer.cast(via_tuple(room_id), {:update_duration, duration_seconds})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    is_lobby = Keyword.get(opts, :is_lobby, false)

    Logger.info(
      "Starting MediaPlayerServer for #{if is_lobby, do: "lobby", else: "room #{room_id}"}"
    )

    # Get or create the playlist
    playlist_result =
      if is_lobby do
        Media.get_or_create_lobby_playlist()
      else
        Media.get_or_create_room_playlist(room_id)
      end

    case playlist_result do
      {:ok, playlist} ->
        # Get the first item if any
        first_item = Media.get_first_item(playlist.id)

        state = %__MODULE__{
          room_id: room_id,
          playlist_id: playlist.id,
          current_item_id: first_item && first_item.id,
          is_lobby: is_lobby,
          state: :stopped,
          position_seconds: 0.0,
          position_updated_at: DateTime.utc_now()
        }

        # Start periodic heartbeat for sync (only when playing)
        schedule_heartbeat()

        {:ok, state}

      {:error, reason} ->
        Logger.error("Failed to create playlist: #{inspect(reason)}")
        {:stop, reason}
    end
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, @heartbeat_interval_ms)
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    playlist_items = Media.get_playlist_items(state.playlist_id)

    # If no current item but playlist has items, auto-select the first one
    {current_item, state} =
      case {state.current_item_id, playlist_items} do
        {nil, [first | _]} ->
          # Auto-select first item
          Logger.info("Auto-selecting first playlist item #{first.id} on get_state")
          new_state = %{state | current_item_id: first.id, position_seconds: 0.0}
          {first, new_state}

        {item_id, _} when not is_nil(item_id) ->
          {Media.get_item(item_id), state}

        _ ->
          {nil, state}
      end

    response = %{
      state: state.state,
      position_seconds: calculate_current_position(state),
      current_item: current_item,
      playlist_items: playlist_items,
      controller_user_id: state.controller_user_id,
      controller_user_name: state.controller_user_name,
      volume: state.volume
    }

    {:reply, {:ok, response}, state}
  end

  @impl true
  def handle_call({:play, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_play(state)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:pause, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_pause(state)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:seek, position_seconds, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_seek(state, position_seconds)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:play_item, item_id, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_play_item(state, item_id)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:next, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_next(state)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:previous, user_id}, _from, state) do
    if can_control?(state, user_id) do
      do_previous(state)
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_call({:take_control, user_id, user_name}, _from, state) do
    new_state = %{
      state
      | controller_user_id: user_id,
        controller_user_name: user_name
    }

    broadcast_controller_change(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:release_control, user_id}, _from, state) do
    if state.controller_user_id == user_id do
      new_state = %{
        state
        | controller_user_id: nil,
          controller_user_name: nil
      }

      broadcast_controller_change(new_state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :not_controller}, state}
    end
  end

  @impl true
  def handle_cast({:report_position, _position_seconds}, state) do
    # Could implement drift detection here if needed
    # For now, we trust the server's position calculation
    {:noreply, state}
  end

  @impl true
  def handle_cast(:video_ended, state) do
    # Auto-advance to next item
    case Media.get_next_item(state.playlist_id, state.current_item_id) do
      nil ->
        # End of playlist
        new_state = %{state | state: :stopped, position_seconds: 0.0}
        broadcast_state_change(new_state, nil)
        {:noreply, new_state}

      item ->
        Media.mark_item_played(item.id)

        new_state = %{
          state
          | current_item_id: item.id,
            state: :playing,
            position_seconds: 0.0,
            position_updated_at: DateTime.utc_now()
        }

        broadcast_video_change(new_state, item)
        {:noreply, new_state}
    end
  end

  @impl true
  def handle_cast({:update_duration, duration_seconds}, state) do
    if state.current_item_id do
      Media.update_item_duration(state.current_item_id, duration_seconds)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:item_added, item}, %{current_item_id: nil} = state) do
    # No current item - auto-select the newly added item
    Logger.info("Auto-selecting newly added item #{item.id} as current item")

    new_state = %{
      state
      | current_item_id: item.id,
        position_seconds: 0.0,
        position_updated_at: DateTime.utc_now()
    }

    # Broadcast the video change so clients load it
    broadcast_video_change(new_state, item)
    {:noreply, new_state}
  end

  @impl true
  def handle_cast({:item_added, _item}, state) do
    # Already have a current item, just ignore
    {:noreply, state}
  end

  @impl true
  def handle_info(:heartbeat, state) do
    # Reschedule next heartbeat
    schedule_heartbeat()

    # Only broadcast if playing - this keeps clients in sync
    # This is a passive sync, not active user interaction
    if state.state == :playing and state.current_item_id do
      current_item = Media.get_item(state.current_item_id)
      broadcast_state_change(state, current_item, false)
    end

    {:noreply, state}
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp calculate_current_position(%{state: :playing} = state) do
    elapsed =
      DateTime.diff(DateTime.utc_now(), state.position_updated_at, :millisecond) / 1000.0

    state.position_seconds + elapsed
  end

  defp calculate_current_position(state) do
    state.position_seconds
  end

  defp pubsub_topic(%{is_lobby: true}), do: "media:lobby"
  defp pubsub_topic(%{room_id: room_id}), do: "media:#{room_id}"

  defp broadcast_state_change(state, current_item, is_active \\ true) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:media_state_changed,
       %{
         state: state.state,
         position_seconds: calculate_current_position(state),
         current_item: current_item,
         is_active: is_active,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp broadcast_video_change(state, item) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:media_video_changed,
       %{
         item: item,
         state: state.state,
         position_seconds: 0.0,
         timestamp: DateTime.utc_now()
       }}
    )
  end

  defp broadcast_controller_change(state) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      pubsub_topic(state),
      {:media_controller_changed,
       %{
         controller_user_id: state.controller_user_id,
         controller_user_name: state.controller_user_name
       }}
    )
  end

  # Check if a user can control playback
  # Anyone can control if there's no controller assigned
  # Otherwise, only the current controller can control
  defp can_control?(%{controller_user_id: nil}, _user_id), do: true
  defp can_control?(%{controller_user_id: controller_id}, user_id), do: controller_id == user_id

  # Internal play implementation
  defp do_play(%{current_item_id: nil} = state) do
    case Media.get_first_item(state.playlist_id) do
      nil ->
        {:reply, {:error, :empty_playlist}, state}

      item ->
        new_state = %{
          state
          | current_item_id: item.id,
            state: :playing,
            position_seconds: 0.0,
            position_updated_at: DateTime.utc_now()
        }

        broadcast_state_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end

  defp do_play(state) do
    new_state = %{
      state
      | state: :playing,
        position_updated_at: DateTime.utc_now()
    }

    current_item = Media.get_item(state.current_item_id)
    broadcast_state_change(new_state, current_item)
    {:reply, :ok, new_state}
  end

  # Internal pause implementation
  defp do_pause(state) do
    current_position = calculate_current_position(state)

    new_state = %{
      state
      | state: :paused,
        position_seconds: current_position,
        position_updated_at: DateTime.utc_now()
    }

    current_item = Media.get_item(state.current_item_id)
    broadcast_state_change(new_state, current_item)
    {:reply, :ok, new_state}
  end

  # Internal seek implementation
  defp do_seek(state, position_seconds) do
    new_state = %{
      state
      | position_seconds: position_seconds,
        position_updated_at: DateTime.utc_now()
    }

    current_item = Media.get_item(state.current_item_id)
    broadcast_state_change(new_state, current_item)
    {:reply, :ok, new_state}
  end

  # Internal play_item implementation
  defp do_play_item(state, item_id) do
    case Media.get_item(item_id) do
      nil ->
        {:reply, {:error, :item_not_found}, state}

      item ->
        Media.mark_item_played(item_id)

        new_state = %{
          state
          | current_item_id: item_id,
            state: :playing,
            position_seconds: 0.0,
            position_updated_at: DateTime.utc_now()
        }

        broadcast_video_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end

  # Internal next implementation
  defp do_next(state) do
    case Media.get_next_item(state.playlist_id, state.current_item_id) do
      nil ->
        new_state = %{state | state: :stopped, position_seconds: 0.0}
        broadcast_state_change(new_state, nil)
        {:reply, {:ok, :end_of_playlist}, new_state}

      item ->
        Media.mark_item_played(item.id)

        new_state = %{
          state
          | current_item_id: item.id,
            state: :playing,
            position_seconds: 0.0,
            position_updated_at: DateTime.utc_now()
        }

        broadcast_video_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end

  # Internal previous implementation
  defp do_previous(state) do
    case Media.get_previous_item(state.playlist_id, state.current_item_id) do
      nil ->
        new_state = %{
          state
          | position_seconds: 0.0,
            position_updated_at: DateTime.utc_now()
        }

        current_item = Media.get_item(state.current_item_id)
        broadcast_state_change(new_state, current_item)
        {:reply, {:ok, :start_of_playlist}, new_state}

      item ->
        new_state = %{
          state
          | current_item_id: item.id,
            state: :playing,
            position_seconds: 0.0,
            position_updated_at: DateTime.utc_now()
        }

        broadcast_video_change(new_state, item)
        {:reply, :ok, new_state}
    end
  end
end

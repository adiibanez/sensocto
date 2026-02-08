defmodule Sensocto.Iroh.RoomStateBridge do
  @moduledoc """
  Bridges local room state with the CRDT-backed peer-to-peer sync layer.

  This module connects:
  - MediaPlayerServer (local synchronized playback state)
  - RoomStateCRDT (P2P Automerge-based CRDT state)

  It listens to local state changes via PubSub and propagates them to the CRDT,
  and vice versa - applying remote CRDT changes to local state.

  ## Usage

  The bridge is automatically started when a room is joined. It:
  1. Creates/gets the CRDT document for the room
  2. Subscribes to local PubSub events for media changes
  3. Applies local changes to the CRDT
  4. Syncs the CRDT with peers via gossip

  ## Architecture

      ┌─────────────────┐     PubSub      ┌──────────────────┐
      │ MediaPlayerServer│ ──────────────► │ RoomStateBridge  │
      └─────────────────┘                 └────────┬─────────┘
                                                   │
      ┌───────────────────┐    PubSub              │
      │Object3DPlayerServer│ ─────────────────────►│
      └───────────────────┘                        │
                                                   ▼
                                          ┌──────────────────┐
                                          │  RoomStateCRDT   │
                                          └────────┬─────────┘
                                                   │
                                                   ▼ (Iroh Gossip)
                                          ┌──────────────────┐
                                          │   Remote Peers   │
                                          └──────────────────┘
  """
  use GenServer
  require Logger

  alias Sensocto.Iroh.RoomStateCRDT
  alias Phoenix.PubSub

  defstruct [
    :room_id,
    :user_id,
    :doc_id,
    initialized: false,
    # When true, suppress local→CRDT propagation to avoid echo loops
    syncing_remote: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  @doc """
  Starts a bridge for a specific room and user.
  """
  def start_link(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    user_id = Keyword.fetch!(opts, :user_id)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(room_id, user_id))
  end

  def via_tuple(room_id, user_id) do
    {:via, Registry, {Sensocto.RoomRegistry, {:state_bridge, room_id, user_id}}}
  end

  @doc """
  Starts a bridge for a room (used when joining).
  Returns {:ok, pid} or {:error, reason}.
  """
  def start_for_room(room_id, user_id) do
    case start_link(room_id: room_id, user_id: user_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      error -> error
    end
  end

  @doc """
  Stops the bridge for a room (used when leaving).
  """
  def stop_for_room(room_id, user_id) do
    case GenServer.whereis(via_tuple(room_id, user_id)) do
      nil -> :ok
      pid -> GenServer.stop(pid, :normal)
    end
  end

  @doc """
  Syncs the current local state to the CRDT.
  Call this after joining a room to push the initial state.
  """
  def sync_local_to_crdt(room_id, user_id) do
    GenServer.cast(via_tuple(room_id, user_id), :sync_local_to_crdt)
  catch
    :exit, _ -> {:error, :not_running}
  end

  @doc """
  Syncs remote CRDT state to local state.
  Call this to pull the latest state from peers.
  """
  def sync_crdt_to_local(room_id, user_id) do
    GenServer.cast(via_tuple(room_id, user_id), :sync_crdt_to_local)
  catch
    :exit, _ -> {:error, :not_running}
  end

  @doc """
  Updates participant presence in the CRDT.
  """
  def update_presence(room_id, user_id, presence_data) do
    GenServer.cast(via_tuple(room_id, user_id), {:update_presence, presence_data})
  catch
    :exit, _ -> {:error, :not_running}
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(opts) do
    room_id = Keyword.fetch!(opts, :room_id)
    user_id = Keyword.fetch!(opts, :user_id)

    state = %__MODULE__{
      room_id: room_id,
      user_id: user_id
    }

    # Initialize asynchronously
    send(self(), :initialize)

    {:ok, state}
  end

  @impl true
  def handle_info(:initialize, state) do
    case initialize_bridge(state) do
      {:ok, new_state} ->
        Logger.debug("[RoomStateBridge] Initialized for room #{state.room_id}")
        {:noreply, new_state}

      {:error, reason} ->
        Logger.warning("[RoomStateBridge] Failed to initialize: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :initialize, 2000)
        {:noreply, state}
    end
  end

  # Handle media state changes from local PubSub
  # Skip propagation when syncing_remote is true (echo suppression)
  @impl true
  def handle_info({:media_state_changed, event_data}, state) do
    if state.initialized and not state.syncing_remote do
      apply_local_media_change(state, event_data)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:media_sync, event_data}, state) do
    if state.initialized and not state.syncing_remote do
      apply_local_media_change(state, event_data)
    end

    {:noreply, state}
  end

  # Handle Object3D item changes
  @impl true
  def handle_info({:object3d_item_changed, event_data}, state) do
    if state.initialized and not state.syncing_remote do
      apply_local_object3d_change(state, {:item_changed, event_data})
    end

    {:noreply, state}
  end

  # Handle Object3D camera sync
  @impl true
  def handle_info({:object3d_camera_synced, event_data}, state) do
    if state.initialized and not state.syncing_remote do
      apply_local_object3d_change(state, {:camera_synced, event_data})
    end

    {:noreply, state}
  end

  # Sentinel: clear the syncing_remote flag after all echo messages are processed
  def handle_info(:crdt_sync_complete, state) do
    {:noreply, %{state | syncing_remote: false}}
  end

  # Handle Object3D controller changes
  @impl true
  def handle_info({:object3d_controller_changed, _event_data}, state) do
    # Controller changes are local-only, no need to sync to CRDT
    {:noreply, state}
  end

  # Handle Object3D playlist updates
  @impl true
  def handle_info({:object3d_playlist_updated, _event_data}, state) do
    # Playlist is stored in PostgreSQL, not CRDT
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[RoomStateBridge] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_cast(:sync_local_to_crdt, state) do
    if state.initialized do
      do_sync_local_to_crdt(state)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast(:sync_crdt_to_local, state) do
    if state.initialized do
      do_sync_crdt_to_local(state)
      # Set flag to suppress echo messages, cleared by :crdt_sync_complete sentinel
      send(self(), :crdt_sync_complete)
      {:noreply, %{state | syncing_remote: true}}
    else
      {:noreply, state}
    end
  end

  @impl true
  def handle_cast({:update_presence, presence_data}, state) do
    if state.initialized do
      RoomStateCRDT.update_participant_presence(state.room_id, state.user_id, presence_data)
    end

    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.initialized do
      # Remove participant from CRDT on leave
      RoomStateCRDT.remove_participant(state.room_id, state.user_id)
    end

    :ok
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp initialize_bridge(state) do
    if RoomStateCRDT.ready?() do
      # Get or create the room's CRDT document
      case RoomStateCRDT.get_or_create_room_doc(state.room_id) do
        {:ok, doc_id} ->
          # Subscribe to local media events
          PubSub.subscribe(Sensocto.PubSub, "media:#{state.room_id}")

          # Subscribe to Object3D events
          PubSub.subscribe(Sensocto.PubSub, "object3d:#{state.room_id}")

          # Add ourselves as a participant
          RoomStateCRDT.update_participant_presence(state.room_id, state.user_id, %{
            "joined_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          })

          {:ok, %{state | doc_id: doc_id, initialized: true}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:error, :crdt_not_ready}
    end
  end

  defp apply_local_media_change(state, event_data) do
    case event_data do
      %{action: :play, position_seconds: pos} ->
        RoomStateCRDT.set_media_playing(state.room_id, true, state.user_id)
        RoomStateCRDT.set_media_position(state.room_id, round(pos * 1000), state.user_id)

      %{action: :pause, position_seconds: pos} ->
        RoomStateCRDT.set_media_playing(state.room_id, false, state.user_id)
        RoomStateCRDT.set_media_position(state.room_id, round(pos * 1000), state.user_id)

      %{action: :seek, position_seconds: pos} ->
        RoomStateCRDT.set_media_position(state.room_id, round(pos * 1000), state.user_id)

      %{action: :item_changed, url: url} when is_binary(url) ->
        RoomStateCRDT.set_media_url(state.room_id, url, state.user_id)

      %{position_seconds: pos} when is_number(pos) ->
        # Periodic sync heartbeat
        RoomStateCRDT.set_media_position(state.room_id, round(pos * 1000), state.user_id)

      _ ->
        :ok
    end

    # Trigger gossip sync after local change
    RoomStateCRDT.sync_room(state.room_id)
  end

  defp apply_local_object3d_change(state, change) do
    case change do
      {:item_changed, %{item: item, camera_position: pos, camera_target: target}} ->
        # Sync splat URL
        if item && item.splat_url do
          RoomStateCRDT.set_object3d_url(state.room_id, item.splat_url, state.user_id)
        end

        # Sync camera position
        if pos && target do
          RoomStateCRDT.set_object3d_camera(state.room_id, pos, target, state.user_id)
        end

      {:camera_synced, %{camera_position: pos, camera_target: target}} ->
        # Sync camera position to CRDT
        if pos && target do
          RoomStateCRDT.set_object3d_camera(state.room_id, pos, target, state.user_id)
        end

      _ ->
        :ok
    end

    # Trigger gossip sync after local change
    RoomStateCRDT.sync_room(state.room_id)
  end

  defp do_sync_local_to_crdt(state) do
    # Get current local media state
    case Sensocto.Media.MediaPlayerServer.get_state(state.room_id) do
      {:ok, media_state} ->
        # Sync playing state
        is_playing = media_state.state == :playing
        RoomStateCRDT.set_media_playing(state.room_id, is_playing, state.user_id)

        # Sync position
        if media_state.position_seconds do
          RoomStateCRDT.set_media_position(
            state.room_id,
            round(media_state.position_seconds * 1000),
            state.user_id
          )
        end

        # Trigger sync
        RoomStateCRDT.sync_room(state.room_id)

      {:error, _} ->
        :ok
    end
  end

  defp do_sync_crdt_to_local(state) do
    sync_crdt_media_to_local(state)
    sync_crdt_object3d_to_local(state)
  end

  defp sync_crdt_media_to_local(state) do
    with {:ok, crdt_media} <- RoomStateCRDT.get_media_state(state.room_id),
         {:ok, local_state} <- Sensocto.Media.MediaPlayerServer.get_state(state.room_id) do
      crdt_playing = crdt_media["is_playing"] == true
      local_playing = local_state.state == :playing

      # Sync play/pause state if different
      if crdt_playing and not local_playing do
        Sensocto.Media.MediaPlayerServer.play(state.room_id, state.user_id)
      end

      if not crdt_playing and local_playing do
        Sensocto.Media.MediaPlayerServer.pause(state.room_id, state.user_id)
      end

      # Sync position if significantly different (>2s drift)
      crdt_position_ms = crdt_media["position_ms"]

      if is_number(crdt_position_ms) do
        crdt_position_s = crdt_position_ms / 1000.0
        local_position_s = local_state.position_seconds || 0.0

        if abs(crdt_position_s - local_position_s) > 2.0 do
          Sensocto.Media.MediaPlayerServer.seek(
            state.room_id,
            crdt_position_s,
            state.user_id
          )
        end
      end
    else
      {:error, _} -> :ok
    end
  end

  defp sync_crdt_object3d_to_local(state) do
    case RoomStateCRDT.get_object3d_state(state.room_id) do
      {:ok, crdt_obj3d} when is_map(crdt_obj3d) and map_size(crdt_obj3d) > 0 ->
        # Broadcast CRDT object3d state to local subscribers via PubSub
        PubSub.broadcast(
          Sensocto.PubSub,
          "object3d:#{state.room_id}",
          {:object3d_remote_state, crdt_obj3d}
        )

      _ ->
        :ok
    end
  end
end

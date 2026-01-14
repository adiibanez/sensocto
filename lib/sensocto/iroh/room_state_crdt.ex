defmodule Sensocto.Iroh.RoomStateCRDT do
  @moduledoc """
  Manages room collaborative state using Automerge CRDTs via iroh_ex.

  This module provides a high-level API for managing real-time collaborative
  state within rooms, including:

  - Media playback synchronization (current video, position, playing state)
  - 3D object viewer state (camera position, selected object)
  - Participant cursors and presence
  - Shared annotations and markers

  The state is stored as an Automerge document that automatically merges
  concurrent changes from multiple participants without conflicts.

  ## Document Structure

  ```
  {
    "room_id": "uuid",
    "media": {
      "current_url": "https://...",
      "position_ms": 12345,
      "is_playing": false,
      "updated_by": "user-id",
      "updated_at": "timestamp"
    },
    "object_3d": {
      "splat_url": "https://...",
      "camera_position": {"x": 0, "y": 0, "z": 5},
      "camera_target": {"x": 0, "y": 0, "z": 0}
    },
    "participants": {
      "user-id-1": {
        "name": "Alice",
        "cursor": {"x": 100, "y": 200},
        "last_seen": "timestamp"
      }
    },
    "annotations": [
      {"id": "ann-1", "type": "marker", "data": {...}, "author": "user-id"}
    ]
  }
  ```
  """

  use GenServer
  require Logger
  alias IrohEx.Native
  alias IrohEx.NodeConfig

  @type room_id :: String.t()
  @type user_id :: String.t()

  defstruct [
    :node_ref,
    :docs,
    initialized: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates or gets the Automerge document for a room.
  Returns the doc_id for further operations.
  """
  @spec get_or_create_room_doc(room_id()) :: {:ok, String.t()} | {:error, term()}
  def get_or_create_room_doc(room_id) do
    GenServer.call(__MODULE__, {:get_or_create_doc, room_id})
  end

  @doc """
  Deletes the room document from memory.
  """
  @spec delete_room_doc(room_id()) :: :ok | {:error, term()}
  def delete_room_doc(room_id) do
    GenServer.call(__MODULE__, {:delete_doc, room_id})
  end

  @doc """
  Gets the current room state as a map.
  """
  @spec get_room_state(room_id()) :: {:ok, map()} | {:error, term()}
  def get_room_state(room_id) do
    GenServer.call(__MODULE__, {:get_state, room_id})
  end

  # ============================================================================
  # Media Playback Operations
  # ============================================================================

  @doc """
  Updates the media playback URL.
  """
  @spec set_media_url(room_id(), String.t(), user_id()) :: :ok | {:error, term()}
  def set_media_url(room_id, url, user_id) do
    GenServer.call(__MODULE__, {:set_media_url, room_id, url, user_id})
  end

  @doc """
  Updates the media playback position.
  """
  @spec set_media_position(room_id(), non_neg_integer(), user_id()) :: :ok | {:error, term()}
  def set_media_position(room_id, position_ms, user_id) do
    GenServer.call(__MODULE__, {:set_media_position, room_id, position_ms, user_id})
  end

  @doc """
  Sets the media playing state.
  """
  @spec set_media_playing(room_id(), boolean(), user_id()) :: :ok | {:error, term()}
  def set_media_playing(room_id, is_playing, user_id) do
    GenServer.call(__MODULE__, {:set_media_playing, room_id, is_playing, user_id})
  end

  @doc """
  Gets the current media state.
  """
  @spec get_media_state(room_id()) :: {:ok, map()} | {:error, term()}
  def get_media_state(room_id) do
    GenServer.call(__MODULE__, {:get_media_state, room_id})
  end

  # ============================================================================
  # 3D Object Viewer Operations
  # ============================================================================

  @doc """
  Sets the 3D object URL (Gaussian splat).
  """
  @spec set_object3d_url(room_id(), String.t(), user_id()) :: :ok | {:error, term()}
  def set_object3d_url(room_id, splat_url, user_id) do
    GenServer.call(__MODULE__, {:set_object3d_url, room_id, splat_url, user_id})
  end

  @doc """
  Updates the 3D camera position.
  """
  @spec set_object3d_camera(room_id(), map(), map(), user_id()) :: :ok | {:error, term()}
  def set_object3d_camera(room_id, position, target, user_id) do
    GenServer.call(__MODULE__, {:set_object3d_camera, room_id, position, target, user_id})
  end

  @doc """
  Gets the 3D object viewer state.
  """
  @spec get_object3d_state(room_id()) :: {:ok, map()} | {:error, term()}
  def get_object3d_state(room_id) do
    GenServer.call(__MODULE__, {:get_object3d_state, room_id})
  end

  # ============================================================================
  # Participant Presence Operations
  # ============================================================================

  @doc """
  Updates a participant's presence (cursor position, last seen).
  """
  @spec update_participant_presence(room_id(), user_id(), map()) :: :ok | {:error, term()}
  def update_participant_presence(room_id, user_id, presence_data) do
    GenServer.call(__MODULE__, {:update_presence, room_id, user_id, presence_data})
  end

  @doc """
  Removes a participant from the room.
  """
  @spec remove_participant(room_id(), user_id()) :: :ok | {:error, term()}
  def remove_participant(room_id, user_id) do
    GenServer.call(__MODULE__, {:remove_participant, room_id, user_id})
  end

  @doc """
  Gets all participants in a room.
  """
  @spec get_participants(room_id()) :: {:ok, map()} | {:error, term()}
  def get_participants(room_id) do
    GenServer.call(__MODULE__, {:get_participants, room_id})
  end

  # ============================================================================
  # Sync Operations
  # ============================================================================

  @doc """
  Syncs a room document with peers via gossip.
  """
  @spec sync_room(room_id()) :: :ok | {:error, term()}
  def sync_room(room_id) do
    GenServer.call(__MODULE__, {:sync_room, room_id})
  end

  @doc """
  Merges received document data into the room's document.
  """
  @spec merge_remote_changes(room_id(), binary()) :: :ok | {:error, term()}
  def merge_remote_changes(room_id, doc_bytes) do
    GenServer.call(__MODULE__, {:merge_changes, room_id, doc_bytes})
  end

  @doc """
  Exports the room document for sharing.
  """
  @spec export_room_doc(room_id()) :: {:ok, binary()} | {:error, term()}
  def export_room_doc(room_id) do
    GenServer.call(__MODULE__, {:export_doc, room_id})
  end

  @doc """
  Checks if the CRDT store is ready.
  """
  @spec ready?() :: boolean()
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    send(self(), :initialize)
    {:ok, %__MODULE__{docs: %{}}}
  end

  @impl true
  def handle_info(:initialize, state) do
    case initialize_node() do
      {:ok, node_ref} ->
        Logger.info("[RoomStateCRDT] Initialized iroh node")
        {:noreply, %{state | node_ref: node_ref, initialized: true}}

      {:error, reason} ->
        Logger.error("[RoomStateCRDT] Failed to initialize: #{inspect(reason)}")
        Process.send_after(self(), :initialize, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[RoomStateCRDT] Received: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_call({:get_or_create_doc, room_id}, _from, state) do
    if state.initialized do
      {result, new_state} = do_get_or_create_doc(state, room_id)
      {:reply, result, new_state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:delete_doc, room_id}, _from, state) do
    if state.initialized do
      {result, new_state} = do_delete_doc(state, room_id)
      {:reply, result, new_state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_state, room_id}, _from, state) do
    if state.initialized do
      result = do_get_state(state, room_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:set_media_url, room_id, url, user_id}, _from, state) do
    if state.initialized do
      result = do_set_media_field(state, room_id, "current_url", url, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:set_media_position, room_id, position_ms, user_id}, _from, state) do
    if state.initialized do
      result = do_set_media_field(state, room_id, "position_ms", position_ms, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:set_media_playing, room_id, is_playing, user_id}, _from, state) do
    if state.initialized do
      result = do_set_media_field(state, room_id, "is_playing", is_playing, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_media_state, room_id}, _from, state) do
    if state.initialized do
      result = do_get_nested_state(state, room_id, ["media"])
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:set_object3d_url, room_id, splat_url, user_id}, _from, state) do
    if state.initialized do
      result = do_set_object3d_field(state, room_id, "splat_url", splat_url, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:set_object3d_camera, room_id, position, target, user_id}, _from, state) do
    if state.initialized do
      case get_doc_id(state, room_id) do
        {:ok, doc_id} ->
          # Set camera position
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d", "camera_position"], "x", Map.get(position, :x, 0))
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d", "camera_position"], "y", Map.get(position, :y, 0))
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d", "camera_position"], "z", Map.get(position, :z, 5))

          # Set camera target
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d", "camera_target"], "x", Map.get(target, :x, 0))
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d", "camera_target"], "y", Map.get(target, :y, 0))
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d", "camera_target"], "z", Map.get(target, :z, 0))

          # Set metadata
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d"], "updated_by", user_id)
          Native.automerge_map_put(state.node_ref, doc_id, ["object_3d"], "updated_at", DateTime.utc_now() |> DateTime.to_iso8601())

          {:reply, :ok, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_object3d_state, room_id}, _from, state) do
    if state.initialized do
      result = do_get_nested_state(state, room_id, ["object_3d"])
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:update_presence, room_id, user_id, presence_data}, _from, state) do
    if state.initialized do
      result = do_update_presence(state, room_id, user_id, presence_data)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:remove_participant, room_id, user_id}, _from, state) do
    if state.initialized do
      result = do_remove_participant(state, room_id, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_participants, room_id}, _from, state) do
    if state.initialized do
      result = do_get_nested_state(state, room_id, ["participants"])
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:sync_room, room_id}, _from, state) do
    if state.initialized do
      case get_doc_id(state, room_id) do
        {:ok, doc_id} ->
          Native.automerge_sync_via_gossip(state.node_ref, doc_id)
          {:reply, :ok, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:merge_changes, room_id, doc_bytes}, _from, state) do
    if state.initialized do
      case get_doc_id(state, room_id) do
        {:ok, doc_id} ->
          result = Native.automerge_merge(state.node_ref, doc_id, doc_bytes)
          {:reply, result, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:export_doc, room_id}, _from, state) do
    if state.initialized do
      case get_doc_id(state, room_id) do
        {:ok, doc_id} ->
          doc_bytes = Native.automerge_save_doc(state.node_ref, doc_id)
          {:reply, {:ok, doc_bytes}, state}

        error ->
          {:reply, error, state}
      end
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp initialize_node do
    try do
      node_config = %NodeConfig{
        is_whale_node: false,
        active_view_capacity: 10,
        passive_view_capacity: 10,
        relay_urls: ["https://euw1-1.relay.iroh.network./"],
        discovery: ["n0", "local_network"]
      }

      node_ref = Native.create_node(self(), node_config)

      if is_reference(node_ref) do
        # Give the node time to initialize
        Process.sleep(500)
        {:ok, node_ref}
      else
        {:error, "Failed to create node: #{inspect(node_ref)}"}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp do_get_or_create_doc(state, room_id) do
    case Map.get(state.docs, room_id) do
      nil ->
        # Create new document
        doc_id = Native.automerge_create_doc(state.node_ref)

        # Initialize document structure
        initialize_doc_structure(state.node_ref, doc_id, room_id)

        new_docs = Map.put(state.docs, room_id, doc_id)
        {{:ok, doc_id}, %{state | docs: new_docs}}

      doc_id ->
        {{:ok, doc_id}, state}
    end
  end

  defp initialize_doc_structure(node_ref, doc_id, room_id) do
    # Set room ID
    Native.automerge_map_put(node_ref, doc_id, [], "room_id", room_id)

    # Create media state object
    Native.automerge_map_put_object(node_ref, doc_id, [], "media", "map")
    Native.automerge_map_put(node_ref, doc_id, ["media"], "current_url", "")
    Native.automerge_map_put(node_ref, doc_id, ["media"], "position_ms", 0)
    Native.automerge_map_put(node_ref, doc_id, ["media"], "is_playing", false)
    Native.automerge_map_put(node_ref, doc_id, ["media"], "updated_by", "")
    Native.automerge_map_put(node_ref, doc_id, ["media"], "updated_at", "")

    # Create 3D object state
    Native.automerge_map_put_object(node_ref, doc_id, [], "object_3d", "map")
    Native.automerge_map_put(node_ref, doc_id, ["object_3d"], "splat_url", "")
    Native.automerge_map_put_object(node_ref, doc_id, ["object_3d"], "camera_position", "map")
    Native.automerge_map_put(node_ref, doc_id, ["object_3d", "camera_position"], "x", 0)
    Native.automerge_map_put(node_ref, doc_id, ["object_3d", "camera_position"], "y", 0)
    Native.automerge_map_put(node_ref, doc_id, ["object_3d", "camera_position"], "z", 5)
    Native.automerge_map_put_object(node_ref, doc_id, ["object_3d"], "camera_target", "map")
    Native.automerge_map_put(node_ref, doc_id, ["object_3d", "camera_target"], "x", 0)
    Native.automerge_map_put(node_ref, doc_id, ["object_3d", "camera_target"], "y", 0)
    Native.automerge_map_put(node_ref, doc_id, ["object_3d", "camera_target"], "z", 0)

    # Create participants map
    Native.automerge_map_put_object(node_ref, doc_id, [], "participants", "map")

    # Create annotations list
    Native.automerge_map_put_object(node_ref, doc_id, [], "annotations", "list")

    :ok
  end

  defp do_delete_doc(state, room_id) do
    case Map.get(state.docs, room_id) do
      nil ->
        {{:error, :not_found}, state}

      doc_id ->
        Native.automerge_delete_doc(state.node_ref, doc_id)
        new_docs = Map.delete(state.docs, room_id)
        {:ok, %{state | docs: new_docs}}
    end
  end

  defp do_get_state(state, room_id) do
    case get_doc_id(state, room_id) do
      {:ok, doc_id} ->
        json_str = Native.automerge_to_json(state.node_ref, doc_id)
        Jason.decode(json_str)

      error ->
        error
    end
  end

  defp do_get_nested_state(state, room_id, path) do
    case do_get_state(state, room_id) do
      {:ok, full_state} ->
        nested = get_in(full_state, path)
        {:ok, nested || %{}}

      error ->
        error
    end
  end

  defp get_doc_id(state, room_id) do
    case Map.get(state.docs, room_id) do
      nil -> {:error, :doc_not_found}
      doc_id -> {:ok, doc_id}
    end
  end

  defp do_set_media_field(state, room_id, field, value, user_id) do
    case get_doc_id(state, room_id) do
      {:ok, doc_id} ->
        Native.automerge_map_put(state.node_ref, doc_id, ["media"], field, value)
        Native.automerge_map_put(state.node_ref, doc_id, ["media"], "updated_by", user_id)
        Native.automerge_map_put(state.node_ref, doc_id, ["media"], "updated_at", DateTime.utc_now() |> DateTime.to_iso8601())
        :ok

      error ->
        error
    end
  end

  defp do_set_object3d_field(state, room_id, field, value, user_id) do
    case get_doc_id(state, room_id) do
      {:ok, doc_id} ->
        Native.automerge_map_put(state.node_ref, doc_id, ["object_3d"], field, value)
        Native.automerge_map_put(state.node_ref, doc_id, ["object_3d"], "updated_by", user_id)
        Native.automerge_map_put(state.node_ref, doc_id, ["object_3d"], "updated_at", DateTime.utc_now() |> DateTime.to_iso8601())
        :ok

      error ->
        error
    end
  end

  defp do_update_presence(state, room_id, user_id, presence_data) do
    case get_doc_id(state, room_id) do
      {:ok, doc_id} ->
        # Create participant entry if needed
        participant_path = ["participants", user_id]

        # Check if participant exists, create if not
        existing = Native.automerge_map_get(state.node_ref, doc_id, ["participants"], user_id)

        if existing == :not_found do
          Native.automerge_map_put_object(state.node_ref, doc_id, ["participants"], user_id, "map")
        end

        # Update presence fields
        Enum.each(presence_data, fn {key, value} ->
          Native.automerge_map_put(state.node_ref, doc_id, participant_path, to_string(key), value)
        end)

        # Always update last_seen
        Native.automerge_map_put(state.node_ref, doc_id, participant_path, "last_seen", DateTime.utc_now() |> DateTime.to_iso8601())

        :ok

      error ->
        error
    end
  end

  defp do_remove_participant(state, room_id, user_id) do
    case get_doc_id(state, room_id) do
      {:ok, doc_id} ->
        Native.automerge_map_delete(state.node_ref, doc_id, ["participants"], user_id)
        :ok

      error ->
        error
    end
  end
end

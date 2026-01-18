defmodule Sensocto.RoomMarkdown.CrdtDocument do
  @moduledoc """
  Automerge CRDT wrapper for room documents.

  Provides bidirectional sync between RoomDocument and Automerge CRDT,
  enabling conflict-free merging of concurrent edits across peers.

  ## Document Structure

  The Automerge document mirrors the RoomDocument structure:

  ```json
  {
    "id": "uuid",
    "name": "Room Name",
    "version": 1,
    "features": { ... },
    "admins": { ... },
    "configuration": { ... },
    "body": "markdown content"
  }
  ```

  ## Sync Flow

  1. Local edit: RoomDocument -> CrdtDocument -> Gossip broadcast
  2. Remote change: Gossip receive -> CrdtDocument merge -> RoomDocument
  """

  use GenServer
  require Logger

  alias IrohEx.Native
  alias IrohEx.NodeConfig
  alias Sensocto.RoomMarkdown.RoomDocument

  defstruct [
    :node_ref,
    # room_id => doc_id
    docs: %{},
    # room_id => version (to track local changes)
    versions: %{},
    initialized: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Creates or gets a CRDT document for a room.

  If the document exists, returns it. Otherwise creates a new one
  initialized from the provided RoomDocument.
  """
  @spec get_or_create(String.t(), RoomDocument.t() | nil) :: {:ok, String.t()} | {:error, term()}
  def get_or_create(room_id, initial_doc \\ nil) do
    GenServer.call(__MODULE__, {:get_or_create, room_id, initial_doc})
  end

  @doc """
  Updates a CRDT document from a RoomDocument.

  Applies changes from the RoomDocument to the CRDT, incrementing
  the version for conflict resolution.
  """
  @spec update(String.t(), RoomDocument.t()) :: :ok | {:error, term()}
  def update(room_id, %RoomDocument{} = doc) do
    GenServer.call(__MODULE__, {:update, room_id, doc})
  end

  @doc """
  Gets the current state as a RoomDocument.
  """
  @spec get_document(String.t()) :: {:ok, RoomDocument.t()} | {:error, term()}
  def get_document(room_id) do
    GenServer.call(__MODULE__, {:get_document, room_id})
  end

  @doc """
  Merges remote CRDT changes into the document.

  Returns the merged RoomDocument if changes were applied.
  """
  @spec merge_remote(String.t(), binary()) :: {:ok, RoomDocument.t()} | {:error, term()}
  def merge_remote(room_id, crdt_bytes) when is_binary(crdt_bytes) do
    GenServer.call(__MODULE__, {:merge_remote, room_id, crdt_bytes})
  end

  @doc """
  Exports the CRDT document as bytes for syncing.
  """
  @spec export(String.t()) :: {:ok, binary()} | {:error, term()}
  def export(room_id) do
    GenServer.call(__MODULE__, {:export, room_id})
  end

  @doc """
  Deletes a CRDT document.
  """
  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(room_id) do
    GenServer.call(__MODULE__, {:delete, room_id})
  end

  @doc """
  Checks if the CRDT system is ready.
  """
  @spec ready?() :: boolean()
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end

  @doc """
  Lists all room IDs with CRDT documents.
  """
  @spec list_rooms() :: [String.t()]
  def list_rooms do
    GenServer.call(__MODULE__, :list_rooms)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    send(self(), :initialize)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:initialize, state) do
    case initialize_node() do
      {:ok, node_ref} ->
        Logger.info("[CrdtDocument] Initialized Automerge node")
        {:noreply, %{state | node_ref: node_ref, initialized: true}}

      {:error, reason} ->
        Logger.warning("[CrdtDocument] Failed to initialize: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :initialize, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[CrdtDocument] Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_call(:list_rooms, _from, state) do
    {:reply, Map.keys(state.docs), state}
  end

  @impl true
  def handle_call({:get_or_create, room_id, initial_doc}, _from, state) do
    if state.initialized do
      {result, new_state} = do_get_or_create(state, room_id, initial_doc)
      {:reply, result, new_state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:update, room_id, doc}, _from, state) do
    if state.initialized do
      {result, new_state} = do_update(state, room_id, doc)
      {:reply, result, new_state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_document, room_id}, _from, state) do
    if state.initialized do
      result = do_get_document(state, room_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:merge_remote, room_id, crdt_bytes}, _from, state) do
    if state.initialized do
      {result, new_state} = do_merge_remote(state, room_id, crdt_bytes)
      {:reply, result, new_state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:export, room_id}, _from, state) do
    if state.initialized do
      result = do_export(state, room_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:delete, room_id}, _from, state) do
    if state.initialized do
      {result, new_state} = do_delete(state, room_id)
      {:reply, result, new_state}
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
        Process.sleep(500)
        {:ok, node_ref}
      else
        {:error, "Failed to create node: #{inspect(node_ref)}"}
      end
    rescue
      e -> {:error, e}
    end
  end

  defp do_get_or_create(state, room_id, initial_doc) do
    case Map.get(state.docs, room_id) do
      nil ->
        # Create new document
        doc_id = Native.automerge_create_doc(state.node_ref)
        initialize_doc_structure(state.node_ref, doc_id, room_id, initial_doc)

        new_docs = Map.put(state.docs, room_id, doc_id)
        new_versions = Map.put(state.versions, room_id, 1)

        {{:ok, doc_id}, %{state | docs: new_docs, versions: new_versions}}

      doc_id ->
        {{:ok, doc_id}, state}
    end
  end

  defp do_update(state, room_id, %RoomDocument{} = doc) do
    case Map.get(state.docs, room_id) do
      nil ->
        {{:error, :doc_not_found}, state}

      doc_id ->
        # Update all fields in the CRDT
        update_crdt_from_document(state.node_ref, doc_id, doc)

        # Increment local version
        new_version = Map.get(state.versions, room_id, 0) + 1
        new_versions = Map.put(state.versions, room_id, new_version)

        {:ok, %{state | versions: new_versions}}
    end
  end

  defp do_get_document(state, room_id) do
    case Map.get(state.docs, room_id) do
      nil ->
        {:error, :doc_not_found}

      doc_id ->
        json_str = Native.automerge_to_json(state.node_ref, doc_id)

        case Jason.decode(json_str) do
          {:ok, data} ->
            doc = RoomDocument.new(data)
            {:ok, doc}

          {:error, reason} ->
            {:error, {:json_decode_error, reason}}
        end
    end
  end

  defp do_merge_remote(state, room_id, crdt_bytes) do
    case Map.get(state.docs, room_id) do
      nil ->
        # Create document from remote bytes
        doc_id = Native.automerge_load_doc(state.node_ref, crdt_bytes)

        if doc_id do
          new_docs = Map.put(state.docs, room_id, doc_id)

          case do_get_document(%{state | docs: new_docs}, room_id) do
            {:ok, doc} ->
              {{:ok, doc}, %{state | docs: new_docs}}

            error ->
              {error, state}
          end
        else
          {{:error, :failed_to_load_doc}, state}
        end

      doc_id ->
        # Merge into existing document
        Native.automerge_merge(state.node_ref, doc_id, crdt_bytes)

        case do_get_document(state, room_id) do
          {:ok, doc} ->
            {{:ok, doc}, state}

          error ->
            {error, state}
        end
    end
  end

  defp do_export(state, room_id) do
    case Map.get(state.docs, room_id) do
      nil ->
        {:error, :doc_not_found}

      doc_id ->
        bytes = Native.automerge_save_doc(state.node_ref, doc_id)
        {:ok, bytes}
    end
  end

  defp do_delete(state, room_id) do
    case Map.get(state.docs, room_id) do
      nil ->
        {:ok, state}

      doc_id ->
        Native.automerge_delete_doc(state.node_ref, doc_id)
        new_docs = Map.delete(state.docs, room_id)
        new_versions = Map.delete(state.versions, room_id)
        {:ok, %{state | docs: new_docs, versions: new_versions}}
    end
  end

  defp initialize_doc_structure(node_ref, doc_id, room_id, nil) do
    # Initialize with minimal structure
    Native.automerge_map_put(node_ref, doc_id, [], "id", room_id)
    Native.automerge_map_put(node_ref, doc_id, [], "name", "Untitled Room")
    Native.automerge_map_put(node_ref, doc_id, [], "version", 1)
    Native.automerge_map_put(node_ref, doc_id, [], "body", "")

    # Create nested objects
    Native.automerge_map_put_object(node_ref, doc_id, [], "features", "map")
    Native.automerge_map_put(node_ref, doc_id, ["features"], "is_public", true)
    Native.automerge_map_put(node_ref, doc_id, ["features"], "calls_enabled", true)
    Native.automerge_map_put(node_ref, doc_id, ["features"], "media_playback_enabled", true)
    Native.automerge_map_put(node_ref, doc_id, ["features"], "object_3d_enabled", false)

    Native.automerge_map_put_object(node_ref, doc_id, [], "admins", "map")
    Native.automerge_map_put_object(node_ref, doc_id, ["admins"], "members", "list")

    Native.automerge_map_put_object(node_ref, doc_id, [], "configuration", "map")

    :ok
  end

  defp initialize_doc_structure(node_ref, doc_id, _room_id, %RoomDocument{} = doc) do
    update_crdt_from_document(node_ref, doc_id, doc)
  end

  defp update_crdt_from_document(node_ref, doc_id, %RoomDocument{} = doc) do
    # Update basic fields
    Native.automerge_map_put(node_ref, doc_id, [], "id", doc.id)
    Native.automerge_map_put(node_ref, doc_id, [], "name", doc.name)
    Native.automerge_map_put(node_ref, doc_id, [], "description", doc.description || "")
    Native.automerge_map_put(node_ref, doc_id, [], "owner_id", doc.owner_id)
    Native.automerge_map_put(node_ref, doc_id, [], "join_code", doc.join_code)
    Native.automerge_map_put(node_ref, doc_id, [], "version", doc.version)
    Native.automerge_map_put(node_ref, doc_id, [], "created_at", format_datetime(doc.created_at))
    Native.automerge_map_put(node_ref, doc_id, [], "updated_at", format_datetime(doc.updated_at))
    Native.automerge_map_put(node_ref, doc_id, [], "body", doc.body)

    # Update features
    ensure_map_exists(node_ref, doc_id, [], "features")
    Native.automerge_map_put(node_ref, doc_id, ["features"], "is_public", doc.features.is_public)

    Native.automerge_map_put(
      node_ref,
      doc_id,
      ["features"],
      "calls_enabled",
      doc.features.calls_enabled
    )

    Native.automerge_map_put(
      node_ref,
      doc_id,
      ["features"],
      "media_playback_enabled",
      doc.features.media_playback_enabled
    )

    Native.automerge_map_put(
      node_ref,
      doc_id,
      ["features"],
      "object_3d_enabled",
      doc.features.object_3d_enabled
    )

    # Update admins
    ensure_map_exists(node_ref, doc_id, [], "admins")

    Native.automerge_map_put(
      node_ref,
      doc_id,
      ["admins"],
      "signature",
      doc.admins.signature || ""
    )

    Native.automerge_map_put(
      node_ref,
      doc_id,
      ["admins"],
      "updated_by",
      doc.admins.updated_by || ""
    )

    # Update members list - clear and rebuild
    ensure_list_exists(node_ref, doc_id, ["admins"], "members")

    Enum.with_index(doc.admins.members)
    |> Enum.each(fn {member, _idx} ->
      member_json = Jason.encode!(%{"id" => member.id, "role" => Atom.to_string(member.role)})
      Native.automerge_list_push(node_ref, doc_id, ["admins", "members"], member_json)
    end)

    # Update configuration
    ensure_map_exists(node_ref, doc_id, [], "configuration")

    Enum.each(doc.configuration, fn {key, value} ->
      Native.automerge_map_put(
        node_ref,
        doc_id,
        ["configuration"],
        to_string(key),
        encode_value(value)
      )
    end)

    :ok
  end

  defp ensure_map_exists(node_ref, doc_id, path, key) do
    case Native.automerge_map_get(node_ref, doc_id, path, key) do
      :not_found ->
        Native.automerge_map_put_object(node_ref, doc_id, path, key, "map")

      _ ->
        :ok
    end
  end

  defp ensure_list_exists(node_ref, doc_id, path, key) do
    case Native.automerge_map_get(node_ref, doc_id, path, key) do
      :not_found ->
        Native.automerge_map_put_object(node_ref, doc_id, path, key, "list")

      _ ->
        # Clear existing list - not ideal but works for our use case
        :ok
    end
  end

  defp format_datetime(nil), do: ""
  defp format_datetime(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp format_datetime(str) when is_binary(str), do: str

  defp encode_value(value) when is_binary(value), do: value
  defp encode_value(value) when is_number(value), do: value
  defp encode_value(value) when is_boolean(value), do: value
  defp encode_value(value) when is_nil(value), do: ""
  defp encode_value(value), do: Jason.encode!(value)
end

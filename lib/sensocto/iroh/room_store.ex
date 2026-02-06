defmodule Sensocto.Iroh.RoomStore do
  @moduledoc """
  Low-level iroh_ex document storage for rooms.

  Provides CRUD operations on iroh docs for room persistence.
  This module manages the iroh node and document namespaces for:
  - Room data storage
  - Membership data storage

  Key structure in iroh docs:
  - rooms_namespace:
    - "room:{room_id}" => JSON encoded room data
  - memberships_namespace:
    - "membership:{room_id}:{user_id}" => JSON encoded membership

  Note: This is a low-level module. Use Sensocto.RoomStore for the public API.
  """
  use GenServer
  require Logger
  alias IrohEx.Native
  alias Sensocto.Resilience.CircuitBreaker

  defstruct [
    :node_ref,
    :author_id,
    :rooms_namespace,
    :memberships_namespace,
    initialized: false,
    init_attempts: 0,
    nif_unavailable: false
  ]

  # Max initialization retry attempts before giving up
  @max_init_attempts 3
  @call_timeout 5_000

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Stores a room in iroh docs.
  """
  def store_room(room_data) do
    GenServer.call(__MODULE__, {:store_room, room_data}, @call_timeout)
  end

  @doc """
  Retrieves a room from iroh docs by ID.
  """
  def get_room(room_id) do
    GenServer.call(__MODULE__, {:get_room, room_id}, @call_timeout)
  end

  @doc """
  Deletes a room from iroh docs.
  """
  def delete_room(room_id) do
    GenServer.call(__MODULE__, {:delete_room, room_id}, @call_timeout)
  end

  @doc """
  Stores a membership in iroh docs.
  """
  def store_membership(room_id, user_id, role) do
    GenServer.call(__MODULE__, {:store_membership, room_id, user_id, role}, @call_timeout)
  end

  @doc """
  Retrieves a membership from iroh docs.
  """
  def get_membership(room_id, user_id) do
    GenServer.call(__MODULE__, {:get_membership, room_id, user_id}, @call_timeout)
  end

  @doc """
  Deletes a membership from iroh docs.
  """
  def delete_membership(room_id, user_id) do
    GenServer.call(__MODULE__, {:delete_membership, room_id, user_id}, @call_timeout)
  end

  @doc """
  Lists all rooms stored in iroh docs.
  Returns a list of room data maps.
  """
  def list_all_rooms do
    GenServer.call(__MODULE__, :list_all_rooms, @call_timeout)
  end

  @doc """
  Lists all memberships for a room.
  """
  def list_room_memberships(room_id) do
    GenServer.call(__MODULE__, {:list_room_memberships, room_id}, @call_timeout)
  end

  @doc """
  Checks if the iroh store is initialized and ready.
  """
  def ready? do
    GenServer.call(__MODULE__, :ready?, 2_000)
  catch
    :exit, _ -> false
  end

  @doc """
  Gets the iroh node reference for advanced operations.
  """
  def get_node_ref do
    GenServer.call(__MODULE__, :get_node_ref, @call_timeout)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Initialize asynchronously to not block application startup
    send(self(), :initialize_iroh)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_info(:initialize_iroh, %{nif_unavailable: true} = state) do
    # NIF is not available, don't retry
    {:noreply, state}
  end

  def handle_info(:initialize_iroh, %{init_attempts: attempts} = state)
      when attempts >= @max_init_attempts do
    Logger.warning(
      "[Iroh.RoomStore] Max initialization attempts (#{@max_init_attempts}) reached. " <>
        "IrohEx NIF may not be available. Iroh storage disabled."
    )

    {:noreply, %{state | nif_unavailable: true}}
  end

  def handle_info(:initialize_iroh, state) do
    # First check if the NIF is even loaded
    unless function_exported?(Native, :create_node, 2) do
      Logger.warning("[Iroh.RoomStore] IrohEx.Native NIF not loaded. Iroh storage disabled.")
      {:noreply, %{state | nif_unavailable: true}}
    else
      case initialize_iroh_node() do
        {:ok, new_state} ->
          Logger.info("[Iroh.RoomStore] Initialized iroh node successfully")
          {:noreply, new_state}

        {:error, reason} ->
          new_attempts = state.init_attempts + 1

          Logger.error(
            "[Iroh.RoomStore] Failed to initialize iroh node (attempt #{new_attempts}/#{@max_init_attempts}): #{inspect(reason)}"
          )

          # Retry after delay
          Process.send_after(self(), :initialize_iroh, 5000)
          {:noreply, %{state | init_attempts: new_attempts}}
      end
    end
  end

  @impl true
  def handle_info(msg, state) do
    # Handle iroh events (gossip, sync, etc.)
    case msg do
      {:iroh_gossip_message_received, _source, _message} ->
        Logger.debug("[Iroh.RoomStore] Received gossip message")
        {:noreply, state}

      {:iroh_gossip_neighbor_up, _source, _neighbor, _info, _count} ->
        Logger.debug("[Iroh.RoomStore] Neighbor connected")
        {:noreply, state}

      {:iroh_gossip_neighbor_down, _source, _neighbor} ->
        Logger.debug("[Iroh.RoomStore] Neighbor disconnected")
        {:noreply, state}

      _ ->
        Logger.debug("[Iroh.RoomStore] Unknown message: #{inspect(msg)}")
        {:noreply, state}
    end
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_call(:get_node_ref, _from, state) do
    {:reply, state.node_ref, state}
  end

  @impl true
  def handle_call({:store_room, room_data}, _from, state) do
    if state.initialized do
      result = do_store_room(state, room_data)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_room, room_id}, _from, state) do
    if state.initialized do
      result = do_get_room(state, room_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:delete_room, room_id}, _from, state) do
    if state.initialized do
      result = do_delete_room(state, room_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:store_membership, room_id, user_id, role}, _from, state) do
    if state.initialized do
      result = do_store_membership(state, room_id, user_id, role)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:get_membership, room_id, user_id}, _from, state) do
    if state.initialized do
      result = do_get_membership(state, room_id, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:delete_membership, room_id, user_id}, _from, state) do
    if state.initialized do
      result = do_delete_membership(state, room_id, user_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call(:list_all_rooms, _from, state) do
    if state.initialized do
      result = do_list_all_rooms(state)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:list_room_memberships, room_id}, _from, state) do
    if state.initialized do
      result = do_list_room_memberships(state, room_id)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  # ============================================================================
  # Private Functions - Initialization
  # ============================================================================

  defp initialize_iroh_node do
    try do
      # Create iroh node with default config
      node_config = build_node_config()
      node_ref = Native.create_node(self(), node_config)

      unless is_reference(node_ref) do
        raise "Failed to create iroh node: #{inspect(node_ref)}"
      end

      # Create author for writing docs
      author_id = Native.docs_create_author(node_ref)

      unless is_binary(author_id) do
        raise "Failed to create author: #{inspect(author_id)}"
      end

      # Create namespaces for rooms and memberships
      rooms_namespace = Native.docs_create(node_ref)
      memberships_namespace = Native.docs_create(node_ref)

      unless is_binary(rooms_namespace) and is_binary(memberships_namespace) do
        raise "Failed to create namespaces"
      end

      Logger.info(
        "[Iroh.RoomStore] Created rooms namespace: #{String.slice(rooms_namespace, 0, 16)}..."
      )

      Logger.info(
        "[Iroh.RoomStore] Created memberships namespace: #{String.slice(memberships_namespace, 0, 16)}..."
      )

      state = %__MODULE__{
        node_ref: node_ref,
        author_id: author_id,
        rooms_namespace: rooms_namespace,
        memberships_namespace: memberships_namespace,
        initialized: true
      }

      {:ok, state}
    rescue
      e ->
        Logger.error("[Iroh.RoomStore] Initialization error: #{inspect(e)}")
        {:error, e}
    end
  end

  defp build_node_config do
    # Use default config, can be customized via application config
    config = %IrohEx.NodeConfig{
      is_whale_node: false,
      active_view_capacity: 10,
      passive_view_capacity: 10,
      relay_urls: ["https://euw1-1.relay.iroh.network./"],
      discovery: ["n0", "local_network"]
    }

    # Allow override from application config
    Application.get_env(:sensocto, :iroh_node_config, config)
  end

  # ============================================================================
  # Private Functions - Room Operations
  # ============================================================================

  defp do_store_room(state, room_data) do
    room_id = Map.get(room_data, :id) || Map.get(room_data, "id")

    unless room_id do
      {:error, :missing_room_id}
    else
      key = "room:#{room_id}"
      value = Jason.encode!(room_data)

      case CircuitBreaker.call(:iroh_docs, fn ->
             Native.docs_set_entry(
               state.node_ref,
               state.rooms_namespace,
               state.author_id,
               key,
               value
             )
           end) do
        {:ok, content_hash} when is_binary(content_hash) ->
          {:ok, content_hash}

        {:error, :circuit_open} ->
          {:error, :circuit_open}

        {:ok, error} ->
          Logger.error("[Iroh.RoomStore] Failed to store room: #{inspect(error)}")
          {:error, error}

        {:error, reason} ->
          Logger.error("[Iroh.RoomStore] Failed to store room: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  defp do_get_room(state, room_id) do
    key = "room:#{room_id}"

    case CircuitBreaker.call(:iroh_docs, fn ->
           Native.docs_get_entry_value(
             state.node_ref,
             state.rooms_namespace,
             state.author_id,
             key
           )
         end) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 ->
        case Jason.decode(value) do
          {:ok, data} -> {:ok, atomize_keys(data)}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, ""} ->
        {:error, :not_found}

      {:ok, nil} ->
        {:error, :not_found}

      {:error, :circuit_open} ->
        {:error, :circuit_open}

      {:ok, error} ->
        {:error, error}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_delete_room(state, room_id) do
    # In iroh docs, we can't truly delete, but we can set to empty/tombstone
    key = "room:#{room_id}"
    tombstone = Jason.encode!(%{deleted: true, deleted_at: DateTime.utc_now()})

    case CircuitBreaker.call(:iroh_docs, fn ->
           Native.docs_set_entry(
             state.node_ref,
             state.rooms_namespace,
             state.author_id,
             key,
             tombstone
           )
         end) do
      {:ok, content_hash} when is_binary(content_hash) ->
        :ok

      {:error, :circuit_open} ->
        {:error, :circuit_open}

      other ->
        {:error, other}
    end
  end

  defp do_list_all_rooms(_state) do
    # List all docs and filter for room entries
    # Note: iroh docs don't have a native list-by-prefix, so we need to track room IDs separately
    # For now, return empty list - will be populated by RoomStore's in-memory index
    {:ok, []}
  end

  # ============================================================================
  # Private Functions - Membership Operations
  # ============================================================================

  defp do_store_membership(state, room_id, user_id, role) do
    key = "membership:#{room_id}:#{user_id}"

    membership_data = %{
      room_id: room_id,
      user_id: user_id,
      role: role,
      joined_at: DateTime.utc_now() |> DateTime.to_iso8601()
    }

    value = Jason.encode!(membership_data)

    case CircuitBreaker.call(:iroh_docs, fn ->
           Native.docs_set_entry(
             state.node_ref,
             state.memberships_namespace,
             state.author_id,
             key,
             value
           )
         end) do
      {:ok, content_hash} when is_binary(content_hash) ->
        {:ok, content_hash}

      {:error, :circuit_open} ->
        {:error, :circuit_open}

      other ->
        {:error, other}
    end
  end

  defp do_get_membership(state, room_id, user_id) do
    key = "membership:#{room_id}:#{user_id}"

    case CircuitBreaker.call(:iroh_docs, fn ->
           Native.docs_get_entry_value(
             state.node_ref,
             state.memberships_namespace,
             state.author_id,
             key
           )
         end) do
      {:ok, value} when is_binary(value) and byte_size(value) > 0 ->
        case Jason.decode(value) do
          {:ok, data} -> {:ok, atomize_keys(data)}
          {:error, reason} -> {:error, {:json_decode, reason}}
        end

      {:ok, ""} ->
        {:error, :not_found}

      {:ok, nil} ->
        {:error, :not_found}

      {:error, :circuit_open} ->
        {:error, :circuit_open}

      other ->
        {:error, other}
    end
  end

  defp do_delete_membership(state, room_id, user_id) do
    key = "membership:#{room_id}:#{user_id}"
    tombstone = Jason.encode!(%{deleted: true})

    case CircuitBreaker.call(:iroh_docs, fn ->
           Native.docs_set_entry(
             state.node_ref,
             state.memberships_namespace,
             state.author_id,
             key,
             tombstone
           )
         end) do
      {:ok, content_hash} when is_binary(content_hash) ->
        :ok

      {:error, :circuit_open} ->
        {:error, :circuit_open}

      other ->
        {:error, other}
    end
  end

  defp do_list_room_memberships(_state, _room_id) do
    # Similar to list_all_rooms, we need an index
    {:ok, []}
  end

  # ============================================================================
  # Private Functions - Utilities
  # ============================================================================

  # Safe atomize_keys using SafeKeys whitelist to prevent atom exhaustion.
  # Unknown keys are kept as strings rather than creating new atoms.
  defp atomize_keys(map) when is_map(map) do
    {:ok, converted} = Sensocto.Types.SafeKeys.safe_keys_to_atoms(map)

    # Recursively process nested maps and lists
    Map.new(converted, fn
      {key, value} when is_map(value) -> {key, atomize_keys(value)}
      {key, value} when is_list(value) -> {key, atomize_keys(value)}
      {key, value} -> {key, value}
    end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value
end

defmodule Sensocto.Iroh.ConnectionManager do
  @moduledoc """
  Maintains the single shared Iroh node connection.

  This is the ONLY component that creates or owns the Iroh node reference.
  All other iroh-dependent components request the node_ref from this manager
  via `get_node_ref/0`.

  ## Why a Single Node

  Previously, RoomStore, RoomStateCRDT, GossipTopic, and CrdtDocument each
  created their own iroh node with identical config. This wasted resources
  (4 relay connections, 4 sets of gossip neighbors) and prevented coordination.

  ## Crash Recovery

  If this process crashes, the rest_for_one supervisor restarts it and all
  downstream iroh-dependent processes. Consumers re-fetch the node_ref on
  their own restart.

  ## Graceful Degradation

  If the IrohEx NIF is not available (e.g., no binary for this platform),
  this module marks itself as unavailable. Consumer modules should check
  the result of `get_node_ref/0` and fall back to server-only storage.
  """

  use GenServer
  require Logger

  alias IrohEx.Native
  alias IrohEx.NodeConfig

  defstruct [
    :node_ref,
    :author_id,
    initialized: false,
    nif_unavailable: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Gets the shared Iroh node reference.

  Returns `{:ok, node_ref}` if the node is ready, or `{:error, reason}` if
  the NIF is unavailable or the manager is unreachable.
  """
  @spec get_node_ref() ::
          {:ok, reference()} | {:error, :not_initialized | :nif_unavailable | :unavailable}
  def get_node_ref do
    GenServer.call(__MODULE__, :get_node_ref, 10_000)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @doc """
  Gets the shared author ID for write operations on iroh docs.

  Returns `{:ok, author_id}` if ready, or `{:error, reason}` otherwise.
  """
  @spec get_author_id() ::
          {:ok, String.t()} | {:error, :not_initialized | :nif_unavailable | :unavailable}
  def get_author_id do
    GenServer.call(__MODULE__, :get_author_id, 5_000)
  catch
    :exit, _ -> {:error, :unavailable}
  end

  @doc """
  Checks if the iroh connection is initialized and available.
  """
  @spec available?() :: boolean()
  def available? do
    GenServer.call(__MODULE__, :available?, 2_000)
  catch
    :exit, _ -> false
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Synchronous init: by the time this returns, the node is either ready
    # or marked unavailable. This guarantees downstream consumers in the
    # rest_for_one supervisor can safely call get_node_ref() during their init.
    state = do_initialize()
    {:ok, state}
  end

  @impl true
  def handle_call(:get_node_ref, _from, %{initialized: true} = state) do
    {:reply, {:ok, state.node_ref}, state}
  end

  def handle_call(:get_node_ref, _from, %{nif_unavailable: true} = state) do
    {:reply, {:error, :nif_unavailable}, state}
  end

  def handle_call(:get_node_ref, _from, state) do
    {:reply, {:error, :not_initialized}, state}
  end

  @impl true
  def handle_call(:get_author_id, _from, %{initialized: true} = state) do
    {:reply, {:ok, state.author_id}, state}
  end

  def handle_call(:get_author_id, _from, %{nif_unavailable: true} = state) do
    {:reply, {:error, :nif_unavailable}, state}
  end

  def handle_call(:get_author_id, _from, state) do
    {:reply, {:error, :not_initialized}, state}
  end

  @impl true
  def handle_call(:available?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_info({:iroh_gossip_message_received, _source, _message}, state) do
    Logger.debug("[Iroh.ConnectionManager] Received gossip message")
    {:noreply, state}
  end

  def handle_info({:iroh_gossip_neighbor_up, _source, _neighbor, _info, _count}, state) do
    Logger.debug("[Iroh.ConnectionManager] Neighbor connected")
    {:noreply, state}
  end

  def handle_info({:iroh_gossip_neighbor_down, _source, _neighbor}, state) do
    Logger.debug("[Iroh.ConnectionManager] Neighbor disconnected")
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("[Iroh.ConnectionManager] Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp do_initialize do
    unless function_exported?(Native, :create_node, 2) do
      Logger.warning(
        "[Iroh.ConnectionManager] IrohEx.Native NIF not loaded. Iroh features disabled."
      )

      %__MODULE__{nif_unavailable: true}
    else
      case create_node() do
        {:ok, node_ref, author_id} ->
          Logger.info("[Iroh.ConnectionManager] Shared iroh node initialized")

          %__MODULE__{
            node_ref: node_ref,
            author_id: author_id,
            initialized: true
          }

        {:error, reason} ->
          Logger.warning(
            "[Iroh.ConnectionManager] Failed to create iroh node: #{inspect(reason)}. " <>
              "Iroh features disabled."
          )

          %__MODULE__{nif_unavailable: true}
      end
    end
  end

  defp create_node do
    try do
      node_config = build_node_config()
      node_ref = Native.create_node(self(), node_config)

      unless is_reference(node_ref) do
        raise "create_node returned non-reference: #{inspect(node_ref)}"
      end

      author_id = Native.docs_create_author(node_ref)

      unless is_binary(author_id) do
        raise "docs_create_author returned non-binary: #{inspect(author_id)}"
      end

      {:ok, node_ref, author_id}
    rescue
      e -> {:error, Exception.message(e)}
    end
  end

  defp build_node_config do
    default = %NodeConfig{
      is_whale_node: false,
      active_view_capacity: 10,
      passive_view_capacity: 10,
      relay_urls: ["https://euw1-1.relay.iroh.network./"],
      discovery: ["n0", "local_network"]
    }

    Application.get_env(:sensocto, :iroh_node_config, default)
  end
end

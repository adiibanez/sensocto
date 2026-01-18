defmodule Sensocto.RoomMarkdown.GossipTopic do
  @moduledoc """
  Manages per-room gossip topics for P2P synchronization.

  Each room gets its own gossip topic for broadcasting CRDT changes.
  This allows fine-grained sync where peers only receive updates for
  rooms they're interested in.

  ## Topic Naming

  Topics are named: `room:{room_id}:crdt`

  ## Message Types

  - `:crdt_update` - Full or partial CRDT state
  - `:member_change` - Member join/leave events
  - `:sync_request` - Request full state from peers
  """

  use GenServer
  require Logger

  alias IrohEx.Native
  alias Sensocto.RoomMarkdown.RoomDocument

  @topic_prefix "room:"
  @topic_suffix ":crdt"

  defstruct [
    :node_ref,
    # room_id => topic_id
    topics: %{},
    # room_id => [subscriber_pid]
    subscribers: %{},
    initialized: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Joins a room's gossip topic.

  Returns `{:ok, topic_id}` on success. The calling process will receive
  messages when updates arrive.
  """
  @spec join(String.t()) :: {:ok, String.t()} | {:error, term()}
  def join(room_id) do
    GenServer.call(__MODULE__, {:join, room_id, self()})
  end

  @doc """
  Leaves a room's gossip topic.
  """
  @spec leave(String.t()) :: :ok
  def leave(room_id) do
    GenServer.call(__MODULE__, {:leave, room_id, self()})
  end

  @doc """
  Broadcasts a CRDT update to all peers in the room's topic.
  """
  @spec broadcast_update(String.t(), binary()) :: :ok | {:error, term()}
  def broadcast_update(room_id, crdt_bytes) when is_binary(crdt_bytes) do
    GenServer.call(__MODULE__, {:broadcast, room_id, {:crdt_update, crdt_bytes}})
  end

  @doc """
  Broadcasts a room document change.
  """
  @spec broadcast_document(String.t(), RoomDocument.t()) :: :ok | {:error, term()}
  def broadcast_document(room_id, %RoomDocument{} = doc) do
    # Serialize document to JSON for broadcast
    json = Sensocto.RoomMarkdown.Serializer.to_json(doc)
    GenServer.call(__MODULE__, {:broadcast, room_id, {:document_update, json}})
  end

  @doc """
  Requests full state sync from peers.
  """
  @spec request_sync(String.t()) :: :ok | {:error, term()}
  def request_sync(room_id) do
    GenServer.call(__MODULE__, {:broadcast, room_id, :sync_request})
  end

  @doc """
  Gets the topic ID for a room.
  """
  @spec topic_id(String.t()) :: String.t()
  def topic_id(room_id) do
    "#{@topic_prefix}#{room_id}#{@topic_suffix}"
  end

  @doc """
  Checks if the gossip system is ready.
  """
  @spec ready?() :: boolean()
  def ready? do
    GenServer.call(__MODULE__, :ready?)
  end

  @doc """
  Lists all active room topics.
  """
  @spec list_topics() :: [String.t()]
  def list_topics do
    GenServer.call(__MODULE__, :list_topics)
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
        Logger.info("[GossipTopic] Initialized iroh gossip node")
        {:noreply, %{state | node_ref: node_ref, initialized: true}}

      {:error, reason} ->
        Logger.warning("[GossipTopic] Failed to initialize: #{inspect(reason)}, retrying...")
        Process.send_after(self(), :initialize, 5000)
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:gossip_message, topic_id, message}, state) do
    # Handle incoming gossip messages
    room_id = extract_room_id(topic_id)

    if room_id do
      notify_subscribers(state, room_id, message)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    # Clean up subscriptions when a subscriber process dies
    new_subscribers =
      state.subscribers
      |> Enum.map(fn {room_id, pids} ->
        {room_id, List.delete(pids, pid)}
      end)
      |> Enum.reject(fn {_room_id, pids} -> pids == [] end)
      |> Map.new()

    {:noreply, %{state | subscribers: new_subscribers}}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[GossipTopic] Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def handle_call(:ready?, _from, state) do
    {:reply, state.initialized, state}
  end

  @impl true
  def handle_call(:list_topics, _from, state) do
    {:reply, Map.keys(state.topics), state}
  end

  @impl true
  def handle_call({:join, room_id, pid}, _from, state) do
    if state.initialized do
      {result, new_state} = do_join(state, room_id, pid)
      {:reply, result, new_state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  @impl true
  def handle_call({:leave, room_id, pid}, _from, state) do
    new_state = do_leave(state, room_id, pid)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:broadcast, room_id, message}, _from, state) do
    if state.initialized do
      result = do_broadcast(state, room_id, message)
      {:reply, result, state}
    else
      {:reply, {:error, :not_initialized}, state}
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp initialize_node do
    try do
      node_config = %IrohEx.NodeConfig{
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

  defp do_join(state, room_id, pid) do
    topic = topic_id(room_id)

    # Subscribe to the gossip topic if not already
    new_topics =
      if Map.has_key?(state.topics, room_id) do
        state.topics
      else
        case subscribe_to_topic(state.node_ref, topic) do
          :ok ->
            Map.put(state.topics, room_id, topic)

          {:error, _reason} ->
            state.topics
        end
      end

    # Add subscriber
    new_subscribers =
      Map.update(state.subscribers, room_id, [pid], fn pids ->
        if pid in pids, do: pids, else: [pid | pids]
      end)

    # Monitor the subscriber
    Process.monitor(pid)

    {{:ok, topic}, %{state | topics: new_topics, subscribers: new_subscribers}}
  end

  defp do_leave(state, room_id, pid) do
    new_subscribers =
      Map.update(state.subscribers, room_id, [], fn pids ->
        List.delete(pids, pid)
      end)

    # If no more subscribers, unsubscribe from topic
    new_topics =
      case Map.get(new_subscribers, room_id) do
        [] ->
          topic = Map.get(state.topics, room_id)
          if topic, do: unsubscribe_from_topic(state.node_ref, topic)
          Map.delete(state.topics, room_id)

        _ ->
          state.topics
      end

    %{state | topics: new_topics, subscribers: new_subscribers}
  end

  defp do_broadcast(state, room_id, message) do
    case Map.get(state.topics, room_id) do
      nil ->
        {:error, :not_subscribed}

      topic ->
        encoded = encode_message(message)
        publish_to_topic(state.node_ref, topic, encoded)
    end
  end

  defp subscribe_to_topic(node_ref, topic) do
    try do
      # Third argument is the callback pid for messages
      Native.subscribe_to_topic(node_ref, topic, self())
      :ok
    rescue
      e -> {:error, e}
    end
  end

  defp unsubscribe_from_topic(node_ref, topic) do
    try do
      Native.unsubscribe_from_topic(node_ref, topic)
      :ok
    rescue
      _ -> :ok
    end
  end

  defp publish_to_topic(node_ref, topic, message) do
    try do
      Native.broadcast_message(node_ref, topic, message)
      :ok
    rescue
      e -> {:error, e}
    end
  end

  defp notify_subscribers(state, room_id, message) do
    case Map.get(state.subscribers, room_id) do
      nil ->
        :ok

      pids ->
        decoded = decode_message(message)

        Enum.each(pids, fn pid ->
          send(pid, {:room_gossip, room_id, decoded})
        end)
    end
  end

  defp extract_room_id(topic_id) do
    case String.split(topic_id, ":") do
      ["room", room_id, "crdt"] -> room_id
      _ -> nil
    end
  end

  defp encode_message({:crdt_update, bytes}) do
    <<1, bytes::binary>>
  end

  defp encode_message({:document_update, json}) do
    <<2, json::binary>>
  end

  defp encode_message(:sync_request) do
    <<3>>
  end

  defp encode_message(other) do
    :erlang.term_to_binary(other)
  end

  defp decode_message(<<1, bytes::binary>>) do
    {:crdt_update, bytes}
  end

  defp decode_message(<<2, json::binary>>) do
    {:document_update, json}
  end

  defp decode_message(<<3>>) do
    :sync_request
  end

  defp decode_message(binary) do
    try do
      :erlang.binary_to_term(binary, [:safe])
    rescue
      _ -> {:unknown, binary}
    end
  end
end

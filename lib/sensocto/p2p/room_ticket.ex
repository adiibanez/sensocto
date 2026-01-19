defmodule Sensocto.P2P.RoomTicket do
  @moduledoc """
  Room Ticket - Bootstrap data for P2P room connections.

  A RoomTicket contains everything needed to join a room's P2P network:
  - Iroh Docs namespace for persistent state sync
  - Gossip topic for live sensor data
  - Bootstrap peers for initial connection
  - Relay URL for NAT traversal fallback

  This is generated server-side and consumed by mobile apps via QR code
  or deep link.
  """
  require Logger
  alias Sensocto.Iroh.RoomStore, as: IrohStore
  alias IrohEx.Native

  @enforce_keys [:room_id, :room_name]
  defstruct [
    :room_id,
    :room_name,
    :docs_namespace,
    :gossip_topic,
    :docs_secret,
    :relay_url,
    :created_at,
    :expires_at,
    bootstrap_peers: []
  ]

  @type t :: %__MODULE__{
    room_id: String.t(),
    room_name: String.t(),
    docs_namespace: String.t() | nil,
    gossip_topic: String.t() | nil,
    docs_secret: String.t() | nil,
    bootstrap_peers: [peer_addr()],
    relay_url: String.t() | nil,
    created_at: integer(),
    expires_at: integer() | nil
  }

  @type peer_addr :: %{
    node_id: String.t(),
    addrs: [String.t()],
    relay_url: String.t() | nil
  }

  @doc """
  Generates a room ticket for P2P connection.

  Creates new Iroh docs namespace and gossip topic for the room,
  or retrieves existing ones if already created.

  Options:
    - :expires_in - seconds until ticket expires (default: 24 hours)
    - :include_secret - whether to include docs write secret (default: false)

  Returns {:ok, ticket} or {:error, reason}
  """
  def generate(room, opts \\ []) do
    room_id = to_string(Map.get(room, :id))
    room_name = Map.get(room, :name, "Room")
    expires_in = Keyword.get(opts, :expires_in, 24 * 60 * 60)
    include_secret = Keyword.get(opts, :include_secret, false)

    with {:ok, docs_namespace} <- get_or_create_docs_namespace(room_id),
         {:ok, gossip_topic} <- get_or_create_gossip_topic(room_id),
         {:ok, bootstrap_peers} <- get_bootstrap_peers() do

      now = System.system_time(:second)

      ticket = %__MODULE__{
        room_id: room_id,
        room_name: room_name,
        docs_namespace: docs_namespace,
        gossip_topic: gossip_topic,
        docs_secret: if(include_secret, do: get_docs_secret(room_id), else: nil),
        bootstrap_peers: bootstrap_peers,
        relay_url: get_relay_url(),
        created_at: now,
        expires_at: now + expires_in
      }

      {:ok, ticket}
    end
  end

  @doc """
  Encodes a ticket as base64 for QR codes and URLs.
  """
  def to_base64(%__MODULE__{} = ticket) do
    ticket
    |> to_map()
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decodes a ticket from base64.
  """
  def from_base64(encoded) when is_binary(encoded) do
    with {:ok, json} <- Base.url_decode64(encoded, padding: false),
         {:ok, data} <- Jason.decode(json) do
      {:ok, from_map(data)}
    else
      :error -> {:error, :invalid_base64}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Creates a deep link URL for this ticket.
  """
  def to_deep_link(%__MODULE__{} = ticket) do
    encoded = to_base64(ticket)
    "sensocto://room?ticket=#{encoded}"
  end

  @doc """
  Creates a web URL for this ticket (falls back to web join).
  """
  def to_web_url(%__MODULE__{} = ticket) do
    encoded = to_base64(ticket)
    base_url = SensoctoWeb.Endpoint.url()
    "#{base_url}/rooms/join?ticket=#{encoded}"
  end

  @doc """
  Checks if a ticket has expired.
  """
  def expired?(%__MODULE__{expires_at: nil}), do: false
  def expired?(%__MODULE__{expires_at: expires_at}) do
    System.system_time(:second) > expires_at
  end

  @doc """
  Converts ticket to a map (for JSON encoding).
  """
  def to_map(%__MODULE__{} = ticket) do
    %{
      room_id: ticket.room_id,
      room_name: ticket.room_name,
      docs_namespace: ticket.docs_namespace,
      gossip_topic: ticket.gossip_topic,
      docs_secret: ticket.docs_secret,
      bootstrap_peers: ticket.bootstrap_peers,
      relay_url: ticket.relay_url,
      created_at: ticket.created_at,
      expires_at: ticket.expires_at
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Creates ticket from a map (from JSON decoding).
  """
  def from_map(map) when is_map(map) do
    %__MODULE__{
      room_id: Map.get(map, "room_id") || Map.get(map, :room_id),
      room_name: Map.get(map, "room_name") || Map.get(map, :room_name) || "Room",
      docs_namespace: Map.get(map, "docs_namespace") || Map.get(map, :docs_namespace),
      gossip_topic: Map.get(map, "gossip_topic") || Map.get(map, :gossip_topic),
      docs_secret: Map.get(map, "docs_secret") || Map.get(map, :docs_secret),
      bootstrap_peers: parse_peers(Map.get(map, "bootstrap_peers") || Map.get(map, :bootstrap_peers) || []),
      relay_url: Map.get(map, "relay_url") || Map.get(map, :relay_url),
      created_at: Map.get(map, "created_at") || Map.get(map, :created_at),
      expires_at: Map.get(map, "expires_at") || Map.get(map, :expires_at)
    }
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  # Get or create the Iroh Docs namespace for a room
  # Each room gets its own namespace for syncing room state
  defp get_or_create_docs_namespace(room_id) do
    # Check if we have a cached namespace for this room
    case get_cached_namespace(room_id, :docs) do
      {:ok, namespace} ->
        {:ok, namespace}

      :not_found ->
        # Create a new namespace deterministically from room_id
        # This ensures the same room_id always gets the same namespace
        namespace = derive_namespace(room_id, "docs")
        cache_namespace(room_id, :docs, namespace)
        {:ok, namespace}
    end
  end

  # Get or create the gossip topic for a room
  # Each room gets its own topic for real-time sensor data
  defp get_or_create_gossip_topic(room_id) do
    case get_cached_namespace(room_id, :gossip) do
      {:ok, topic} ->
        {:ok, topic}

      :not_found ->
        # Create a new topic deterministically from room_id
        topic = derive_namespace(room_id, "gossip")
        cache_namespace(room_id, :gossip, topic)
        {:ok, topic}
    end
  end

  # Derive a deterministic namespace/topic from room_id
  # Uses HMAC-SHA256 with a salt to generate 32 bytes
  defp derive_namespace(room_id, salt) do
    secret_key = Application.get_env(:sensocto, :room_ticket_secret, "sensocto_default_secret")

    :crypto.mac(:hmac, :sha256, secret_key, "#{room_id}:#{salt}")
    |> Base.encode16(case: :lower)
  end

  # Get bootstrap peers from the current Iroh node
  defp get_bootstrap_peers do
    case IrohStore.get_node_ref() do
      nil ->
        # Iroh not initialized, return empty list
        {:ok, []}

      node_ref when is_reference(node_ref) ->
        # Get our own node info to include as bootstrap peer
        case get_our_peer_addr(node_ref) do
          {:ok, peer} -> {:ok, [peer]}
          :error -> {:ok, []}
        end
    end
  end

  # Get our node's address info
  defp get_our_peer_addr(node_ref) do
    try do
      # Get node ID (public key)
      node_id = Native.node_id(node_ref)

      if is_binary(node_id) do
        # Get known addresses
        addrs = get_node_addrs(node_ref)

        peer = %{
          node_id: node_id,
          addrs: addrs,
          relay_url: get_relay_url()
        }

        {:ok, peer}
      else
        :error
      end
    rescue
      _ -> :error
    end
  end

  # Get addresses the node is listening on
  defp get_node_addrs(_node_ref) do
    # TODO: Get actual listening addresses from Iroh
    # For now, return empty - peers will use relay
    []
  end

  # Get the docs write secret for a room (owner only)
  defp get_docs_secret(_room_id) do
    # TODO: Implement when we have proper key management
    nil
  end

  # Get the default relay URL
  defp get_relay_url do
    Application.get_env(:sensocto, :iroh_relay_url, "https://euw1-1.relay.iroh.network./")
  end

  # ============================================================================
  # Namespace Caching (using process dictionary for simplicity)
  # In production, consider using ETS or a GenServer
  # ============================================================================

  @namespace_table :room_ticket_namespaces

  defp ensure_cache_table do
    case :ets.whereis(@namespace_table) do
      :undefined ->
        :ets.new(@namespace_table, [:set, :public, :named_table])
      _ ->
        :ok
    end
  end

  defp get_cached_namespace(room_id, type) do
    ensure_cache_table()
    case :ets.lookup(@namespace_table, {room_id, type}) do
      [{_, namespace}] -> {:ok, namespace}
      [] -> :not_found
    end
  end

  defp cache_namespace(room_id, type, namespace) do
    ensure_cache_table()
    :ets.insert(@namespace_table, {{room_id, type}, namespace})
    :ok
  end

  # Parse peer addresses from JSON
  defp parse_peers(peers) when is_list(peers) do
    Enum.map(peers, fn peer ->
      %{
        node_id: Map.get(peer, "node_id") || Map.get(peer, :node_id),
        addrs: Map.get(peer, "addrs") || Map.get(peer, :addrs) || [],
        relay_url: Map.get(peer, "relay_url") || Map.get(peer, :relay_url)
      }
    end)
  end

  defp parse_peers(_), do: []
end

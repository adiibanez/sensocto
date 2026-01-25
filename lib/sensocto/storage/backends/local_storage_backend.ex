defmodule Sensocto.Storage.Backends.LocalStorageBackend do
  @moduledoc """
  Browser localStorage storage backend for room snapshots.

  Communicates with connected browsers via Phoenix Channel to store
  and retrieve room snapshots from browser localStorage.

  Priority 3 (lowest priority, offline-first fallback).

  ## Architecture

  This backend uses an ETS table to track:
  - Connected clients and their offered snapshots
  - Pending snapshot requests awaiting client response

  The HydrationChannel handles the actual WebSocket communication:
  - `snapshot:offer` - Client announces it has a snapshot
  - `snapshot:request` - Server requests snapshot data
  - `snapshot:data` - Client provides requested snapshot
  - `snapshot:store` - Server pushes snapshot to client

  ## Limitations

  - Requires at least one connected client to retrieve data
  - Storage limited by browser localStorage limits (~5-10MB)
  - Not suitable for large rooms with many sensors
  """

  @behaviour Sensocto.Storage.Backends.RoomBackend

  require Logger

  alias Sensocto.Storage.Backends.RoomBackend

  @ets_table :local_storage_backend
  @request_timeout 5_000

  defstruct [
    :enabled,
    :ets_table,
    ready: false
  ]

  # ============================================================================
  # Behaviour Callbacks
  # ============================================================================

  @impl true
  def backend_id, do: :local_storage

  @impl true
  def priority, do: 3

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, false)

    ets_table =
      if enabled do
        ensure_ets_table()
      else
        nil
      end

    state = %__MODULE__{
      enabled: enabled,
      ets_table: ets_table,
      ready: enabled && ets_table != nil
    }

    if state.ready do
      Logger.info("[LocalStorageBackend] Initialized and ready")
    else
      Logger.debug("[LocalStorageBackend] Initialized but disabled")
    end

    {:ok, state}
  end

  @impl true
  def ready?(%__MODULE__{enabled: false}), do: false
  def ready?(%__MODULE__{ready: ready}), do: ready

  @impl true
  def store_snapshot(_snapshot, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def store_snapshot(snapshot, state) do
    %{room_id: room_id} = snapshot

    # Broadcast to all connected clients
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "hydration:commands",
      {:store_snapshot, room_id, snapshot}
    )

    # Also store locally for offering to new clients
    store_local_snapshot(state.ets_table, snapshot)

    Logger.debug("[LocalStorageBackend] Broadcast snapshot store for room #{room_id}")
    {:ok, state}
  end

  @impl true
  def get_snapshot(_room_id, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def get_snapshot(room_id, state) do
    # First check if we have a locally cached snapshot
    case get_local_snapshot(state.ets_table, room_id) do
      {:ok, snapshot} ->
        {:ok, snapshot, state}

      :not_found ->
        # Request from connected clients
        request_from_clients(room_id, state)
    end
  end

  @impl true
  def delete_snapshot(_room_id, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def delete_snapshot(room_id, state) do
    # Broadcast delete to all connected clients
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "hydration:commands",
      {:delete_snapshot, room_id}
    )

    # Remove local cache
    delete_local_snapshot(state.ets_table, room_id)

    Logger.debug("[LocalStorageBackend] Broadcast snapshot delete for room #{room_id}")
    {:ok, state}
  end

  @impl true
  def list_snapshots(%__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def list_snapshots(state) do
    # List locally known room_ids from client offers
    room_ids = list_offered_rooms(state.ets_table)
    {:ok, room_ids, state}
  end

  @impl true
  def flush(state) do
    # Nothing to flush - stores are immediate broadcasts
    {:ok, state}
  end

  # ============================================================================
  # Public API for HydrationChannel
  # ============================================================================

  @doc """
  Called by HydrationChannel when a client offers a snapshot.
  """
  def client_offers_snapshot(room_id, version, checksum) do
    if table_exists?() do
      :ets.insert(@ets_table, {{:offer, room_id}, version, checksum, System.monotonic_time()})
      :ok
    else
      {:error, :not_initialized}
    end
  end

  @doc """
  Called by HydrationChannel when a client provides requested snapshot data.
  """
  def client_provides_snapshot(request_id, snapshot) do
    if table_exists?() do
      case :ets.lookup(@ets_table, {:request, request_id}) do
        [{{:request, ^request_id}, from_pid, _timestamp}] ->
          # Reply to the waiting process
          send(from_pid, {:snapshot_response, request_id, {:ok, snapshot}})
          :ets.delete(@ets_table, {:request, request_id})
          :ok

        [] ->
          # Request expired or already handled
          {:error, :request_not_found}
      end
    else
      {:error, :not_initialized}
    end
  end

  @doc """
  Called by HydrationChannel when a client connects.
  """
  def client_connected(client_id) do
    if table_exists?() do
      :ets.insert(@ets_table, {{:client, client_id}, System.monotonic_time()})
      :ok
    else
      {:error, :not_initialized}
    end
  end

  @doc """
  Called by HydrationChannel when a client disconnects.
  """
  def client_disconnected(client_id) do
    if table_exists?() do
      :ets.delete(@ets_table, {:client, client_id})
      :ok
    else
      :ok
    end
  end

  @doc """
  Returns the number of connected clients.
  """
  def connected_client_count do
    if table_exists?() do
      :ets.select_count(@ets_table, [
        {{{:client, :_}, :_}, [], [true]}
      ])
    else
      0
    end
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp ensure_ets_table do
    case :ets.whereis(@ets_table) do
      :undefined ->
        :ets.new(@ets_table, [:named_table, :public, :set, read_concurrency: true])

      tid ->
        tid
    end
  end

  defp table_exists? do
    :ets.whereis(@ets_table) != :undefined
  end

  defp store_local_snapshot(nil, _snapshot), do: :ok

  defp store_local_snapshot(table, snapshot) do
    %{room_id: room_id, version: version} = snapshot
    :ets.insert(table, {{:snapshot, room_id}, snapshot, version})
    :ok
  end

  defp get_local_snapshot(nil, _room_id), do: :not_found

  defp get_local_snapshot(table, room_id) do
    case :ets.lookup(table, {:snapshot, room_id}) do
      [{{:snapshot, ^room_id}, snapshot, _version}] ->
        {:ok, snapshot}

      [] ->
        :not_found
    end
  end

  defp delete_local_snapshot(nil, _room_id), do: :ok

  defp delete_local_snapshot(table, room_id) do
    :ets.delete(table, {:snapshot, room_id})
    :ok
  end

  defp list_offered_rooms(nil), do: []

  defp list_offered_rooms(table) do
    :ets.select(table, [
      {{{:offer, :"$1"}, :_, :_, :_}, [], [:"$1"]},
      {{{:snapshot, :"$1"}, :_, :_}, [], [:"$1"]}
    ])
    |> Enum.uniq()
  end

  defp request_from_clients(room_id, state) do
    # Check if any clients are connected
    if connected_client_count() == 0 do
      {:error, :no_clients, state}
    else
      request_id = generate_request_id()

      # Register the pending request
      :ets.insert(state.ets_table, {{:request, request_id}, self(), System.monotonic_time()})

      # Broadcast request to all clients
      Phoenix.PubSub.broadcast(
        Sensocto.PubSub,
        "hydration:commands",
        {:request_snapshot, room_id, request_id}
      )

      # Wait for response with timeout
      receive do
        {:snapshot_response, ^request_id, {:ok, snapshot}} ->
          # Verify and cache the received snapshot
          case RoomBackend.verify_checksum(snapshot) do
            :ok ->
              store_local_snapshot(state.ets_table, snapshot)
              {:ok, snapshot, state}

            {:error, :checksum_mismatch} ->
              Logger.warning("[LocalStorageBackend] Received snapshot with invalid checksum")
              {:error, :checksum_mismatch, state}
          end

        {:snapshot_response, ^request_id, {:error, reason}} ->
          {:error, reason, state}
      after
        @request_timeout ->
          :ets.delete(state.ets_table, {:request, request_id})
          {:error, :timeout, state}
      end
    end
  end

  defp generate_request_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end

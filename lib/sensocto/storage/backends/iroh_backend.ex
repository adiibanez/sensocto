defmodule Sensocto.Storage.Backends.IrohBackend do
  @moduledoc """
  Iroh P2P storage backend for room snapshots.

  Uses the existing `Sensocto.Iroh.RoomStore` for distributed storage.
  This backend provides P2P data distribution across nodes.

  Priority 2 (after PostgreSQL).

  ## Storage Model

  Room snapshots are stored as JSON documents in iroh's content-addressable
  storage with a key format of `snapshot:{room_id}`.
  """

  @behaviour Sensocto.Storage.Backends.RoomBackend

  require Logger

  alias Sensocto.Iroh.RoomStore, as: IrohStore
  alias Sensocto.Storage.Backends.RoomBackend

  defstruct [
    :enabled,
    ready: false
  ]

  # ============================================================================
  # Behaviour Callbacks
  # ============================================================================

  @impl true
  def backend_id, do: :iroh

  @impl true
  def priority, do: 2

  @impl true
  def init(opts) do
    enabled = Keyword.get(opts, :enabled, true)

    state = %__MODULE__{
      enabled: enabled,
      ready: false
    }

    if enabled do
      Logger.info("[IrohBackend] Initialized (waiting for Iroh.RoomStore to be ready)")
    else
      Logger.debug("[IrohBackend] Initialized but disabled")
    end

    {:ok, state}
  end

  @impl true
  def ready?(%__MODULE__{enabled: false}), do: false

  def ready?(%__MODULE__{} = state) do
    # Check if Iroh.RoomStore is ready
    ready =
      try do
        IrohStore.ready?()
      catch
        :exit, _ -> false
      end

    # Update internal state for caching (though we always check dynamically)
    if ready != state.ready do
      Logger.debug("[IrohBackend] Ready status changed to #{ready}")
    end

    ready
  end

  @impl true
  def store_snapshot(_snapshot, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def store_snapshot(snapshot, state) do
    unless ready?(state) do
      {:error, :not_ready, state}
    else
      %{room_id: room_id, data: data, version: version, timestamp: timestamp, checksum: checksum} =
        snapshot

      # Store as a combined document with snapshot metadata
      snapshot_doc = %{
        room_id: room_id,
        data: prepare_data_for_storage(data),
        version: version,
        timestamp: DateTime.to_iso8601(timestamp),
        checksum: checksum,
        stored_at: DateTime.to_iso8601(DateTime.utc_now())
      }

      case IrohStore.store_room(snapshot_doc) do
        {:ok, _hash} ->
          Logger.debug("[IrohBackend] Stored snapshot for room #{room_id}")
          {:ok, state}

        {:error, reason} ->
          Logger.warning("[IrohBackend] Failed to store snapshot: #{inspect(reason)}")
          {:error, reason, state}
      end
    end
  end

  @impl true
  def get_snapshot(_room_id, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def get_snapshot(room_id, state) do
    unless ready?(state) do
      {:error, :not_ready, state}
    else
      case IrohStore.get_room(room_id) do
        {:ok, doc} ->
          # Check if this is a tombstone (deleted room)
          if Map.get(doc, :deleted) || Map.get(doc, "deleted") do
            {:error, :not_found, state}
          else
            snapshot = parse_snapshot_from_doc(room_id, doc)
            {:ok, snapshot, state}
          end

        {:error, :not_found} ->
          {:error, :not_found, state}

        {:error, reason} ->
          Logger.warning("[IrohBackend] Failed to get snapshot: #{inspect(reason)}")
          {:error, reason, state}
      end
    end
  end

  @impl true
  def delete_snapshot(_room_id, %__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def delete_snapshot(room_id, state) do
    unless ready?(state) do
      {:error, :not_ready, state}
    else
      case IrohStore.delete_room(room_id) do
        :ok ->
          Logger.debug("[IrohBackend] Deleted snapshot for room #{room_id}")
          {:ok, state}

        {:error, reason} ->
          Logger.warning("[IrohBackend] Failed to delete snapshot: #{inspect(reason)}")
          {:error, reason, state}
      end
    end
  end

  @impl true
  def list_snapshots(%__MODULE__{enabled: false} = state) do
    {:error, :disabled, state}
  end

  def list_snapshots(state) do
    unless ready?(state) do
      {:error, :not_ready, state}
    else
      # Iroh.RoomStore.list_all_rooms currently returns empty list
      # This is a known limitation - we rely on PostgreSQL for listing
      case IrohStore.list_all_rooms() do
        {:ok, rooms} ->
          room_ids =
            rooms
            |> Enum.reject(fn r -> Map.get(r, :deleted) || Map.get(r, "deleted") end)
            |> Enum.map(fn r -> Map.get(r, :id) || Map.get(r, "id") || Map.get(r, :room_id) end)
            |> Enum.reject(&is_nil/1)

          {:ok, room_ids, state}

        {:error, reason} ->
          {:error, reason, state}
      end
    end
  end

  @impl true
  def flush(state) do
    # Iroh commits are immediate, nothing to flush
    {:ok, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp prepare_data_for_storage(data) do
    # Convert MapSet to list for JSON serialization
    data
    |> Map.update(:sensor_ids, [], fn
      %MapSet{} = set -> MapSet.to_list(set)
      list when is_list(list) -> list
      _ -> []
    end)
  end

  defp parse_snapshot_from_doc(room_id, doc) do
    # Handle both old format (room data directly) and new format (with snapshot metadata)
    {data, version, timestamp, checksum} =
      if Map.has_key?(doc, :version) || Map.has_key?(doc, "version") do
        # New snapshot format
        d = Map.get(doc, :data) || Map.get(doc, "data") || doc
        v = Map.get(doc, :version) || Map.get(doc, "version") || 0
        ts = parse_timestamp(Map.get(doc, :timestamp) || Map.get(doc, "timestamp"))
        cs = Map.get(doc, :checksum) || Map.get(doc, "checksum")
        {d, v, ts, cs}
      else
        # Old format - room data is the document itself
        # Create a version based on updated_at or current time
        v =
          case Map.get(doc, :updated_at) || Map.get(doc, "updated_at") do
            nil -> System.monotonic_time(:millisecond)
            ts -> parse_timestamp(ts) |> DateTime.to_unix(:millisecond)
          end

        {doc, v, DateTime.utc_now(), nil}
      end

    # Build snapshot, regenerating checksum if not present
    if checksum do
      %{
        room_id: room_id,
        data: normalize_data(data),
        version: version,
        timestamp: timestamp,
        checksum: checksum
      }
    else
      normalized_data = normalize_data(data)

      RoomBackend.create_snapshot(room_id, normalized_data)
      |> Map.put(:version, version)
      |> Map.put(:timestamp, timestamp)
    end
  end

  defp normalize_data(data) do
    # Convert sensor_ids back to MapSet if it's a list
    data
    |> Map.update(:sensor_ids, MapSet.new(), fn
      list when is_list(list) -> MapSet.new(list)
      %MapSet{} = set -> set
      _ -> MapSet.new()
    end)
    |> normalize_members()
  end

  defp normalize_members(data) do
    members = Map.get(data, :members) || Map.get(data, "members") || %{}

    normalized =
      Map.new(members, fn {user_id, role} ->
        normalized_role =
          case role do
            r when is_atom(r) -> r
            "owner" -> :owner
            "admin" -> :admin
            "member" -> :member
            _ -> :member
          end

        {user_id, normalized_role}
      end)

    Map.put(data, :members, normalized)
  end

  defp parse_timestamp(nil), do: DateTime.utc_now()
  defp parse_timestamp(%DateTime{} = dt), do: dt

  defp parse_timestamp(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _offset} -> dt
      _ -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()
end

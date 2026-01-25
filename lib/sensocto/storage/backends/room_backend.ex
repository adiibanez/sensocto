defmodule Sensocto.Storage.Backends.RoomBackend do
  @moduledoc """
  Behaviour defining the interface for room storage backends.

  Backends provide snapshot-based persistence for room state. The HydrationManager
  coordinates multiple backends to provide redundant storage and fallback hydration.

  ## Snapshot Format

  All backends store and retrieve snapshots in a consistent format:

      %{
        room_id: "uuid",
        data: %{...room_data...},
        version: 1706000000000,        # monotonic timestamp (milliseconds)
        timestamp: ~U[2026-01-25 20:00:00Z],
        checksum: "SHA256_HEX"
      }

  ## Implementation Notes

  - Backends should be stateless where possible, returning new state from each operation
  - The `ready?/1` callback must be non-blocking to avoid deadlocks during startup
  - Store operations should be idempotent (repeated stores with same version are safe)
  - Backends should handle network/storage failures gracefully, returning {:error, reason}
  """

  @type room_id :: String.t()
  @type room_data :: map()
  @type version :: non_neg_integer()
  @type checksum :: String.t()

  @type snapshot :: %{
          required(:room_id) => room_id(),
          required(:data) => room_data(),
          required(:version) => version(),
          required(:timestamp) => DateTime.t(),
          required(:checksum) => checksum()
        }

  @type state :: term()
  @type opts :: keyword()

  @doc """
  Returns the unique identifier for this backend.

  Used for logging, telemetry, and configuration.
  """
  @callback backend_id() :: atom()

  @doc """
  Returns the priority of this backend (lower = higher priority).

  Priority determines the order backends are tried during hydration
  with `:priority_fallback` strategy.
  """
  @callback priority() :: non_neg_integer()

  @doc """
  Initializes the backend with the given options.

  Called once when the HydrationManager starts. Returns initial state
  that will be passed to subsequent callbacks.
  """
  @callback init(opts()) :: {:ok, state()} | {:error, term()}

  @doc """
  Checks if the backend is ready to handle requests.

  Must be non-blocking. Called before operations to verify
  the backend is available.
  """
  @callback ready?(state()) :: boolean()

  @doc """
  Stores a room snapshot.

  Backends should use the version field to handle concurrent writes.
  A newer version should always supersede an older one.
  """
  @callback store_snapshot(snapshot(), state()) ::
              {:ok, state()} | {:error, term(), state()}

  @doc """
  Retrieves a room snapshot by room_id.

  Returns the most recent snapshot for the given room.
  """
  @callback get_snapshot(room_id(), state()) ::
              {:ok, snapshot(), state()} | {:error, term(), state()}

  @doc """
  Deletes a room snapshot.

  Backends may implement this as a soft-delete (tombstone) or hard-delete
  depending on their capabilities.
  """
  @callback delete_snapshot(room_id(), state()) ::
              {:ok, state()} | {:error, term(), state()}

  @doc """
  Lists all room IDs with stored snapshots.

  Used during bulk hydration. Returns only the room_ids, not full snapshots.
  """
  @callback list_snapshots(state()) ::
              {:ok, [room_id()], state()} | {:error, term(), state()}

  @doc """
  Flushes any pending writes to persistent storage.

  Called before shutdown or when immediate persistence is required.
  Backends without write buffering can return {:ok, state} immediately.
  """
  @callback flush(state()) :: {:ok, state()}

  # ============================================================================
  # Helper Functions
  # ============================================================================

  @doc """
  Creates a snapshot from room data with version and checksum.
  """
  @spec create_snapshot(room_id(), room_data()) :: snapshot()
  def create_snapshot(room_id, room_data) do
    version = System.monotonic_time(:millisecond)
    timestamp = DateTime.utc_now()

    # Compute checksum over room_id, data, and version for integrity verification
    checksum_data = :erlang.term_to_binary({room_id, room_data, version})
    checksum = Base.encode16(:crypto.hash(:sha256, checksum_data), case: :lower)

    %{
      room_id: room_id,
      data: room_data,
      version: version,
      timestamp: timestamp,
      checksum: checksum
    }
  end

  @doc """
  Verifies the checksum of a snapshot.
  """
  @spec verify_checksum(snapshot()) :: :ok | {:error, :checksum_mismatch}
  def verify_checksum(%{room_id: room_id, data: data, version: version, checksum: expected}) do
    checksum_data = :erlang.term_to_binary({room_id, data, version})
    actual = Base.encode16(:crypto.hash(:sha256, checksum_data), case: :lower)

    if actual == expected do
      :ok
    else
      {:error, :checksum_mismatch}
    end
  end

  @doc """
  Compares two snapshots and returns the one with higher version.
  """
  @spec latest_snapshot(snapshot() | nil, snapshot() | nil) :: snapshot() | nil
  def latest_snapshot(nil, snapshot), do: snapshot
  def latest_snapshot(snapshot, nil), do: snapshot

  def latest_snapshot(%{version: v1} = s1, %{version: v2}) when v1 >= v2, do: s1
  def latest_snapshot(_s1, s2), do: s2
end

defmodule Sensocto.RoomMarkdown.BackupWorker do
  @moduledoc """
  Periodic backup worker for room documents to Tigris storage.

  Runs on a configurable interval to sync room documents from the
  in-memory store to Tigris S3-compatible storage.

  ## Features

  - Periodic backups (default: every 5 minutes)
  - Dirty tracking to only backup changed rooms
  - Version backups before significant changes
  - Recovery from Tigris on startup

  ## Configuration

  ```elixir
  config :sensocto, :backup_worker,
    enabled: true,
    interval_ms: 300_000,  # 5 minutes
    batch_size: 10
  ```
  """

  use GenServer
  require Logger

  alias Sensocto.RoomMarkdown.{RoomDocument, TigrisStorage}
  alias Sensocto.RoomStore

  @default_interval_ms 300_000
  @default_batch_size 10

  defstruct [
    # room_id => last_backed_up_version
    backed_up_versions: %{},
    # MapSet of room_ids that need backup
    dirty_rooms: MapSet.new(),
    interval_ms: @default_interval_ms,
    batch_size: @default_batch_size,
    enabled: false,
    timer_ref: nil
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Marks a room as dirty (needs backup).
  Call this when a room is modified.
  """
  @spec mark_dirty(String.t()) :: :ok
  def mark_dirty(room_id) do
    GenServer.cast(__MODULE__, {:mark_dirty, room_id})
  end

  @doc """
  Forces an immediate backup of a specific room.
  """
  @spec backup_now(String.t()) :: :ok | {:error, term()}
  def backup_now(room_id) do
    GenServer.call(__MODULE__, {:backup_now, room_id})
  end

  @doc """
  Forces a backup of all dirty rooms immediately.
  """
  @spec flush() :: :ok
  def flush do
    GenServer.call(__MODULE__, :flush, 30_000)
  end

  @doc """
  Restores a room from Tigris backup.
  """
  @spec restore(String.t()) :: {:ok, RoomDocument.t()} | {:error, term()}
  def restore(room_id) do
    GenServer.call(__MODULE__, {:restore, room_id})
  end

  @doc """
  Restores all rooms from Tigris on startup.
  """
  @spec restore_all() :: {:ok, non_neg_integer()} | {:error, term()}
  def restore_all do
    GenServer.call(__MODULE__, :restore_all, 60_000)
  end

  @doc """
  Gets backup statistics.
  """
  @spec stats() :: map()
  def stats do
    GenServer.call(__MODULE__, :stats)
  end

  @doc """
  Enables or disables the backup worker.
  """
  @spec set_enabled(boolean()) :: :ok
  def set_enabled(enabled) do
    GenServer.call(__MODULE__, {:set_enabled, enabled})
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    config = Application.get_env(:sensocto, :backup_worker, [])

    state = %__MODULE__{
      interval_ms: Keyword.get(config, :interval_ms, @default_interval_ms),
      batch_size: Keyword.get(config, :batch_size, @default_batch_size),
      enabled: Keyword.get(config, :enabled, TigrisStorage.available?())
    }

    # Schedule first backup
    state = maybe_schedule_backup(state)

    Logger.info(
      "[BackupWorker] Started (enabled: #{state.enabled}, interval: #{state.interval_ms}ms)"
    )

    {:ok, state}
  end

  @impl true
  def handle_cast({:mark_dirty, room_id}, state) do
    new_dirty = MapSet.put(state.dirty_rooms, room_id)
    {:noreply, %{state | dirty_rooms: new_dirty}}
  end

  @impl true
  def handle_call({:backup_now, room_id}, _from, state) do
    result = do_backup_room(room_id)

    new_state =
      case result do
        :ok ->
          %{state | dirty_rooms: MapSet.delete(state.dirty_rooms, room_id)}

        _ ->
          state
      end

    {:reply, result, new_state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = do_backup_all_dirty(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call({:restore, room_id}, _from, state) do
    result = do_restore_room(room_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:restore_all, _from, state) do
    result = do_restore_all()
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    stats = %{
      enabled: state.enabled,
      dirty_count: MapSet.size(state.dirty_rooms),
      backed_up_count: map_size(state.backed_up_versions),
      interval_ms: state.interval_ms,
      tigris_available: TigrisStorage.available?()
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_call({:set_enabled, enabled}, _from, state) do
    new_state = %{state | enabled: enabled}
    new_state = maybe_schedule_backup(new_state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:backup_tick, state) do
    new_state =
      if state.enabled do
        do_backup_all_dirty(state)
      else
        state
      end

    # Schedule next backup
    new_state = maybe_schedule_backup(new_state)

    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[BackupWorker] Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp maybe_schedule_backup(%{enabled: false} = state), do: state

  defp maybe_schedule_backup(state) do
    # Cancel existing timer if any
    if state.timer_ref, do: Process.cancel_timer(state.timer_ref)

    timer_ref = Process.send_after(self(), :backup_tick, state.interval_ms)
    %{state | timer_ref: timer_ref}
  end

  defp do_backup_all_dirty(state) do
    if MapSet.size(state.dirty_rooms) == 0 do
      state
    else
      Logger.debug("[BackupWorker] Backing up #{MapSet.size(state.dirty_rooms)} dirty rooms")

      # Process in batches
      rooms_to_backup =
        state.dirty_rooms
        |> MapSet.to_list()
        |> Enum.take(state.batch_size)

      {successful, failed} =
        rooms_to_backup
        |> Enum.reduce({[], []}, fn room_id, {ok, err} ->
          case do_backup_room(room_id) do
            :ok -> {[room_id | ok], err}
            {:error, _} -> {ok, [room_id | err]}
          end
        end)

      if length(failed) > 0 do
        Logger.warning("[BackupWorker] Failed to backup #{length(failed)} rooms")
      end

      new_dirty = Enum.reduce(successful, state.dirty_rooms, &MapSet.delete(&2, &1))

      %{state | dirty_rooms: new_dirty}
    end
  end

  defp do_backup_room(room_id) do
    case RoomStore.get_room(room_id) do
      {:ok, room_data} ->
        doc = RoomDocument.from_room_store(room_data)

        case TigrisStorage.upload(doc) do
          {:ok, _} ->
            Logger.debug("[BackupWorker] Backed up room #{room_id}")
            :ok

          {:error, reason} ->
            Logger.warning("[BackupWorker] Failed to backup room #{room_id}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, :not_found} ->
        # Room no longer exists, try to delete from storage
        TigrisStorage.delete(room_id)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_restore_room(room_id) do
    case TigrisStorage.download(room_id) do
      {:ok, doc} ->
        # Convert to room store format and hydrate
        room_data = RoomDocument.to_room_store(doc)
        RoomStore.hydrate_room(room_data)
        {:ok, doc}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_restore_all do
    case TigrisStorage.list_rooms() do
      {:ok, room_ids} ->
        Logger.info("[BackupWorker] Restoring #{length(room_ids)} rooms from Tigris")

        restored_count =
          room_ids
          |> Enum.reduce(0, fn room_id, count ->
            case do_restore_room(room_id) do
              {:ok, _} -> count + 1
              {:error, _} -> count
            end
          end)

        Logger.info("[BackupWorker] Restored #{restored_count}/#{length(room_ids)} rooms")
        {:ok, restored_count}

      {:error, reason} ->
        {:error, reason}
    end
  end
end

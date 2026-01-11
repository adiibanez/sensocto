defmodule Sensocto.Iroh.RoomSync do
  @moduledoc """
  Async synchronization worker for room state with iroh docs.

  Responsibilities:
  - Batched/debounced writes to iroh docs
  - Hydrate RoomStore from iroh docs on startup
  - Handle sync failures with retry logic

  This worker ensures that the in-memory RoomStore state
  is eventually persisted to iroh docs without blocking
  the main operations.
  """
  use GenServer
  require Logger
  alias Sensocto.Iroh.RoomStore, as: IrohStore

  @debounce_ms 500
  @max_batch_size 50
  @retry_delay_ms 5000
  @max_retries 3

  defstruct [
    pending_rooms: %{},       # room_id => room_data (pending writes)
    pending_memberships: %{}, # {room_id, user_id} => {role, :add | :remove}
    debounce_ref: nil,
    retry_count: 0,
    hydrated: false
  ]

  # ============================================================================
  # Client API
  # ============================================================================

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Queue a room for async sync to iroh docs.
  """
  def sync_room(room_data) do
    GenServer.cast(__MODULE__, {:sync_room, room_data})
  end

  @doc """
  Queue a room deletion for async sync.
  """
  def sync_room_deletion(room_id) do
    GenServer.cast(__MODULE__, {:sync_room_deletion, room_id})
  end

  @doc """
  Queue a membership change for async sync.
  """
  def sync_membership(room_id, user_id, role) do
    GenServer.cast(__MODULE__, {:sync_membership, room_id, user_id, role})
  end

  @doc """
  Queue a membership removal for async sync.
  """
  def sync_membership_removal(room_id, user_id) do
    GenServer.cast(__MODULE__, {:sync_membership_removal, room_id, user_id})
  end

  @doc """
  Hydrate RoomStore from iroh docs.
  Called on startup to restore persisted state.
  """
  def hydrate do
    GenServer.call(__MODULE__, :hydrate, 30_000)
  end

  @doc """
  Check if initial hydration is complete.
  """
  def hydrated? do
    GenServer.call(__MODULE__, :hydrated?)
  end

  @doc """
  Force immediate flush of pending writes.
  """
  def flush do
    GenServer.call(__MODULE__, :flush, 10_000)
  end

  # ============================================================================
  # Server Callbacks
  # ============================================================================

  @impl true
  def init(_opts) do
    # Attempt hydration after a brief delay to allow iroh to initialize
    Process.send_after(self(), :attempt_hydration, 2000)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_cast({:sync_room, room_data}, state) do
    room_id = Map.get(room_data, :id)
    new_pending = Map.put(state.pending_rooms, room_id, room_data)
    new_state = %{state | pending_rooms: new_pending}
    {:noreply, schedule_flush(new_state)}
  end

  @impl true
  def handle_cast({:sync_room_deletion, room_id}, state) do
    # Mark as deleted by storing a tombstone
    tombstone = %{id: room_id, deleted: true, deleted_at: DateTime.utc_now()}
    new_pending = Map.put(state.pending_rooms, room_id, tombstone)
    new_state = %{state | pending_rooms: new_pending}
    {:noreply, schedule_flush(new_state)}
  end

  @impl true
  def handle_cast({:sync_membership, room_id, user_id, role}, state) do
    key = {room_id, user_id}
    new_pending = Map.put(state.pending_memberships, key, {role, :add})
    new_state = %{state | pending_memberships: new_pending}
    {:noreply, schedule_flush(new_state)}
  end

  @impl true
  def handle_cast({:sync_membership_removal, room_id, user_id}, state) do
    key = {room_id, user_id}
    new_pending = Map.put(state.pending_memberships, key, {nil, :remove})
    new_state = %{state | pending_memberships: new_pending}
    {:noreply, schedule_flush(new_state)}
  end

  @impl true
  def handle_call(:hydrate, _from, state) do
    case do_hydrate() do
      {:ok, count} ->
        Logger.info("[Iroh.RoomSync] Hydration complete, loaded #{count} rooms")
        {:reply, {:ok, count}, %{state | hydrated: true}}

      {:error, reason} ->
        Logger.warning("[Iroh.RoomSync] Hydration failed: #{inspect(reason)}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:hydrated?, _from, state) do
    {:reply, state.hydrated, state}
  end

  @impl true
  def handle_call(:flush, _from, state) do
    new_state = do_flush(state)
    {:reply, :ok, new_state}
  end

  @impl true
  def handle_info(:attempt_hydration, state) do
    if IrohStore.ready?() do
      case do_hydrate() do
        {:ok, count} ->
          Logger.info("[Iroh.RoomSync] Auto-hydration complete, loaded #{count} rooms")
          {:noreply, %{state | hydrated: true}}

        {:error, reason} ->
          Logger.warning("[Iroh.RoomSync] Auto-hydration failed: #{inspect(reason)}, will retry")
          Process.send_after(self(), :attempt_hydration, @retry_delay_ms)
          {:noreply, state}
      end
    else
      Logger.debug("[Iroh.RoomSync] Iroh not ready, will retry hydration")
      Process.send_after(self(), :attempt_hydration, @retry_delay_ms)
      {:noreply, state}
    end
  end

  @impl true
  def handle_info(:flush, state) do
    new_state = do_flush(%{state | debounce_ref: nil})
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:retry_flush, state) do
    if state.retry_count < @max_retries do
      new_state = do_flush(state)
      {:noreply, new_state}
    else
      Logger.error("[Iroh.RoomSync] Max retries exceeded, dropping #{map_size(state.pending_rooms)} rooms")
      {:noreply, %{state | pending_rooms: %{}, pending_memberships: %{}, retry_count: 0}}
    end
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("[Iroh.RoomSync] Unknown message: #{inspect(msg)}")
    {:noreply, state}
  end

  # ============================================================================
  # Private Functions
  # ============================================================================

  defp schedule_flush(state) do
    # Cancel existing timer if any
    if state.debounce_ref do
      Process.cancel_timer(state.debounce_ref)
    end

    # Check if we should flush immediately due to batch size
    total_pending = map_size(state.pending_rooms) + map_size(state.pending_memberships)

    if total_pending >= @max_batch_size do
      # Flush immediately
      do_flush(%{state | debounce_ref: nil})
    else
      # Schedule debounced flush
      ref = Process.send_after(self(), :flush, @debounce_ms)
      %{state | debounce_ref: ref}
    end
  end

  defp do_flush(state) do
    if not IrohStore.ready?() do
      Logger.debug("[Iroh.RoomSync] Iroh not ready, deferring flush")
      Process.send_after(self(), :retry_flush, @retry_delay_ms)
      %{state | retry_count: state.retry_count + 1}
    else
      # Flush rooms
      {succeeded_rooms, failed_rooms} = flush_rooms(state.pending_rooms)

      # Flush memberships
      {succeeded_memberships, failed_memberships} = flush_memberships(state.pending_memberships)

      if map_size(failed_rooms) > 0 or map_size(failed_memberships) > 0 do
        Logger.warning("[Iroh.RoomSync] Some items failed to sync, scheduling retry")
        Process.send_after(self(), :retry_flush, @retry_delay_ms)

        %{state |
          pending_rooms: failed_rooms,
          pending_memberships: failed_memberships,
          retry_count: state.retry_count + 1
        }
      else
        if succeeded_rooms > 0 or succeeded_memberships > 0 do
          Logger.debug("[Iroh.RoomSync] Flushed #{succeeded_rooms} rooms, #{succeeded_memberships} memberships")
        end

        %{state |
          pending_rooms: %{},
          pending_memberships: %{},
          retry_count: 0
        }
      end
    end
  end

  defp flush_rooms(pending_rooms) do
    Enum.reduce(pending_rooms, {0, %{}}, fn {room_id, room_data}, {succeeded, failed} ->
      result =
        if Map.get(room_data, :deleted) do
          IrohStore.delete_room(room_id)
        else
          IrohStore.store_room(room_data)
        end

      case result do
        {:ok, _} -> {succeeded + 1, failed}
        :ok -> {succeeded + 1, failed}
        {:error, reason} ->
          Logger.warning("[Iroh.RoomSync] Failed to sync room #{room_id}: #{inspect(reason)}")
          {succeeded, Map.put(failed, room_id, room_data)}
      end
    end)
  end

  defp flush_memberships(pending_memberships) do
    Enum.reduce(pending_memberships, {0, %{}}, fn {{room_id, user_id} = key, {role, action}}, {succeeded, failed} ->
      result =
        case action do
          :add -> IrohStore.store_membership(room_id, user_id, role)
          :remove -> IrohStore.delete_membership(room_id, user_id)
        end

      case result do
        {:ok, _} -> {succeeded + 1, failed}
        :ok -> {succeeded + 1, failed}
        {:error, reason} ->
          Logger.warning("[Iroh.RoomSync] Failed to sync membership #{room_id}:#{user_id}: #{inspect(reason)}")
          {succeeded, Map.put(failed, key, {role, action})}
      end
    end)
  end

  defp do_hydrate do
    if not IrohStore.ready?() do
      {:error, :iroh_not_ready}
    else
      # Get all rooms from iroh docs
      case IrohStore.list_all_rooms() do
        {:ok, rooms} ->
          # Filter out deleted rooms and load into RoomStore
          active_rooms =
            rooms
            |> Enum.reject(fn room -> Map.get(room, :deleted, false) end)

          # Load each room into the main RoomStore
          loaded_count =
            Enum.reduce(active_rooms, 0, fn room_data, count ->
              case Sensocto.RoomStore.hydrate_room(room_data) do
                :ok -> count + 1
                {:error, _} -> count
              end
            end)

          {:ok, loaded_count}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end
end

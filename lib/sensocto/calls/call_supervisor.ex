defmodule Sensocto.Calls.CallSupervisor do
  @moduledoc """
  DynamicSupervisor for managing CallServer processes.
  One CallServer per active call session in a room.
  """
  use DynamicSupervisor
  require Logger

  alias Sensocto.Calls.CallServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new call for a room.
  Returns `{:ok, pid}` if successful, `{:error, reason}` otherwise.
  """
  def start_call(room_id, opts \\ []) do
    opts = Keyword.put(opts, :room_id, room_id)

    case DynamicSupervisor.start_child(__MODULE__, {CallServer, opts}) do
      {:ok, pid} ->
        Logger.info("Started call for room #{room_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Call already exists for room #{room_id}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start call for room #{room_id}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops a call for a room.
  """
  def stop_call(room_id) do
    case get_call_pid(room_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Gets the CallServer process for a room.
  """
  def get_call(room_id) do
    case get_call_pid(room_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Gets the CallServer PID for a room, or nil if not found.
  """
  def get_call_pid(room_id) do
    case Registry.lookup(Sensocto.CallRegistry, room_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Checks if a call exists for a room.
  """
  def call_exists?(room_id) do
    get_call_pid(room_id) != nil
  end

  @doc """
  Lists all active calls.
  """
  def list_active_calls do
    Registry.select(Sensocto.CallRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {room_id, _pid} -> room_id end)
  end

  @doc """
  Gets the count of active calls.
  """
  def count do
    DynamicSupervisor.count_children(__MODULE__)[:active] || 0
  end

  @doc """
  Gets or creates a call for a room.
  """
  def get_or_start_call(room_id, opts \\ []) do
    case get_call(room_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> start_call(room_id, opts)
    end
  end
end

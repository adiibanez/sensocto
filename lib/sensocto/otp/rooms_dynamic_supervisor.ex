defmodule Sensocto.RoomsDynamicSupervisor do
  @moduledoc """
  DynamicSupervisor that manages RoomServer processes for temporary (in-memory) rooms.
  Provides an interface to create, find, and manage temporary rooms.
  """
  use DynamicSupervisor
  require Logger

  alias Sensocto.RoomServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Creates a new temporary room.

  Options:
  - :id - Room ID (generated if not provided)
  - :owner_id - Owner user ID (required)
  - :name - Room name (required)
  - :description - Room description (optional)
  - :is_public - Whether room is public (default: true)
  - :configuration - Room configuration map (optional)
  - :join_code - Join code (generated if not provided)
  - :expiry_ms - Expiry time in ms (default: 24 hours)
  """
  def create_room(opts) do
    room_id = Keyword.get(opts, :id, Ecto.UUID.generate())
    opts = Keyword.put(opts, :id, room_id)

    spec = {RoomServer, opts}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("Created temporary room #{room_id}")
        {:ok, room_id, pid}

      {:error, {:already_started, pid}} ->
        {:error, {:already_exists, pid}}

      {:error, reason} ->
        Logger.error("Failed to create room: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops a temporary room by its ID.
  """
  def stop_room(room_id) do
    case Registry.lookup(Sensocto.RoomRegistry, room_id) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
        :ok

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Finds a room by its join code.
  """
  def find_by_join_code(join_code) do
    case Registry.lookup(Sensocto.RoomJoinCodeRegistry, join_code) do
      [{_pid, room_id}] -> {:ok, room_id}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Gets the view state for a room.
  """
  def get_room_state(room_id) do
    RoomServer.get_view_state(room_id)
  end

  @doc """
  Lists all temporary rooms.
  """
  def list_rooms do
    Registry.select(Sensocto.RoomRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {room_id, _pid} -> room_id end)
  end

  @doc """
  Lists all temporary rooms with their view states.
  """
  def list_rooms_with_state do
    list_rooms()
    |> Enum.map(fn room_id ->
      case RoomServer.get_view_state(room_id) do
        {:ok, state} -> state
        {:error, _} -> nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  @doc """
  Lists temporary rooms for a specific user (owned or member of).
  """
  def list_user_rooms(user_id) do
    list_rooms_with_state()
    |> Enum.filter(fn room ->
      room.owner_id == user_id or Map.has_key?(room.members || %{}, user_id)
    end)
  end

  @doc """
  Lists public temporary rooms.
  """
  def list_public_rooms do
    list_rooms_with_state()
    |> Enum.filter(& &1.is_public)
  end

  @doc """
  Gets the count of active temporary rooms.
  """
  def count do
    length(list_rooms())
  end

  @doc """
  Checks if a room exists.
  """
  def exists?(room_id) do
    case Registry.lookup(Sensocto.RoomRegistry, room_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end
end

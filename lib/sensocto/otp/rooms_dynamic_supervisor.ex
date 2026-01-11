defmodule Sensocto.RoomsDynamicSupervisor do
  @moduledoc """
  Horde DynamicSupervisor that manages RoomServer processes distributed across the cluster.

  Uses Horde for:
  - Distributed process supervision across nodes
  - Automatic process redistribution when nodes join/leave
  - Cluster-wide unique processes per room_id

  Combined with Horde.Registry (Sensocto.DistributedRoomRegistry) for lookups.
  """
  use Horde.DynamicSupervisor
  require Logger

  alias Sensocto.RoomServer

  def start_link(init_arg) do
    Horde.DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    Horde.DynamicSupervisor.init(
      strategy: :one_for_one,
      members: :auto,
      distribution_strategy: Horde.UniformDistribution
    )
  end

  @doc """
  Creates a new room process distributed across the cluster.

  Options:
  - :id - Room ID (generated if not provided)
  - :owner_id - Owner user ID (required)
  - :name - Room name (required)
  - :description - Room description (optional)
  - :is_public - Whether room is public (default: true)
  - :configuration - Room configuration map (optional)
  - :join_code - Join code (generated if not provided)
  - :expiry_ms - Expiry time in ms (default: 24 hours, nil for no expiry)
  """
  def create_room(opts) do
    room_id = Keyword.get(opts, :id, Ecto.UUID.generate())
    opts = Keyword.put(opts, :id, room_id)

    spec = {RoomServer, opts}

    case Horde.DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} ->
        Logger.info("[RoomsDynamicSupervisor] Created room #{room_id} on #{node()}")
        broadcast_room_created(room_id)
        {:ok, room_id, pid}

      {:error, {:already_started, pid}} ->
        {:error, {:already_exists, pid}}

      {:error, reason} ->
        Logger.error("[RoomsDynamicSupervisor] Failed to create room: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Stops a room process by its ID.
  Works across the cluster - finds and terminates the process on any node.
  """
  def stop_room(room_id) do
    case lookup_room(room_id) do
      {:ok, pid} ->
        Horde.DynamicSupervisor.terminate_child(__MODULE__, pid)
        broadcast_room_deleted(room_id)
        :ok

      {:error, :not_found} ->
        {:error, :not_found}
    end
  end

  @doc """
  Looks up a room process by ID using the distributed registry.
  """
  def lookup_room(room_id) do
    case Horde.Registry.lookup(Sensocto.DistributedRoomRegistry, room_id) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Finds a room by its join code using the distributed registry.
  """
  def find_by_join_code(join_code) do
    case Horde.Registry.lookup(Sensocto.DistributedJoinCodeRegistry, join_code) do
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
  Lists all room IDs in the cluster.
  """
  def list_rooms do
    Horde.Registry.select(Sensocto.DistributedRoomRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  @doc """
  Lists all rooms with their view states.
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
  Lists rooms for a specific user (owned or member of).
  """
  def list_user_rooms(user_id) do
    list_rooms_with_state()
    |> Enum.filter(fn room ->
      room.owner_id == user_id or Map.has_key?(room.members || %{}, user_id)
    end)
  end

  @doc """
  Lists public rooms.
  """
  def list_public_rooms do
    list_rooms_with_state()
    |> Enum.filter(& &1.is_public)
  end

  @doc """
  Gets the count of active rooms in the cluster.
  """
  def count do
    length(list_rooms())
  end

  @doc """
  Checks if a room exists in the cluster.
  """
  def exists?(room_id) do
    case lookup_room(room_id) do
      {:ok, _pid} -> true
      {:error, :not_found} -> false
    end
  end

  @doc """
  Gets info about which node a room is running on.
  """
  def room_node(room_id) do
    case lookup_room(room_id) do
      {:ok, pid} -> {:ok, node(pid)}
      {:error, :not_found} -> {:error, :not_found}
    end
  end

  @doc """
  Gets distribution info for all rooms.
  Returns a map of node => [room_ids].
  """
  def distribution_info do
    list_rooms()
    |> Enum.reduce(%{}, fn room_id, acc ->
      case room_node(room_id) do
        {:ok, node} ->
          Map.update(acc, node, [room_id], &[room_id | &1])

        {:error, _} ->
          acc
      end
    end)
  end

  # Private helpers

  defp broadcast_room_created(room_id) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "rooms:cluster",
      {:room_created, room_id, node()}
    )
  end

  defp broadcast_room_deleted(room_id) do
    Phoenix.PubSub.broadcast(
      Sensocto.PubSub,
      "rooms:cluster",
      {:room_deleted, room_id, node()}
    )
  end
end

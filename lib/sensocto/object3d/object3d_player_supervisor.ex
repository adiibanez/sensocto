defmodule Sensocto.Object3D.Object3DPlayerSupervisor do
  @moduledoc """
  DynamicSupervisor for managing Object3DPlayerServer processes.
  One Object3DPlayerServer per room, plus one for the global lobby.
  """
  use DynamicSupervisor
  require Logger

  alias Sensocto.Object3D.Object3DPlayerServer

  @lobby_id :lobby

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts the lobby 3D object player on application startup.
  """
  def start_lobby_player do
    start_player(@lobby_id, is_lobby: true)
  end

  @doc """
  Starts a 3D object player for a room.
  Returns `{:ok, pid}` if successful, `{:error, reason}` otherwise.
  """
  def start_player(room_id, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:room_id, room_id)
      |> Keyword.put_new(:is_lobby, room_id == @lobby_id)

    case DynamicSupervisor.start_child(__MODULE__, {Object3DPlayerServer, opts}) do
      {:ok, pid} ->
        Logger.info("Started 3D object player for #{player_name(room_id)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("3D object player already exists for #{player_name(room_id)}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error(
          "Failed to start 3D object player for #{player_name(room_id)}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Stops a 3D object player for a room.
  """
  def stop_player(room_id) do
    case get_player_pid(room_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Gets the Object3DPlayerServer process for a room.
  """
  def get_player(room_id) do
    case get_player_pid(room_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Gets the Object3DPlayerServer PID for a room, or nil if not found.
  """
  def get_player_pid(room_id) do
    case Registry.lookup(Sensocto.Object3DRegistry, room_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Checks if a 3D object player exists for a room.
  """
  def player_exists?(room_id) do
    get_player_pid(room_id) != nil
  end

  @doc """
  Gets or creates a 3D object player for a room.
  """
  def get_or_start_player(room_id, opts \\ []) do
    case get_player(room_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> start_player(room_id, opts)
    end
  end

  @doc """
  Gets or creates the lobby 3D object player.
  """
  def get_or_start_lobby_player do
    get_or_start_player(@lobby_id, is_lobby: true)
  end

  @doc """
  Lists all active 3D object players.
  """
  def list_active_players do
    Registry.select(Sensocto.Object3DRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {room_id, _pid} -> room_id end)
  end

  @doc """
  Gets the count of active 3D object players.
  """
  def count do
    DynamicSupervisor.count_children(__MODULE__)[:active] || 0
  end

  @doc """
  Returns the lobby room ID constant.
  """
  def lobby_id, do: @lobby_id

  defp player_name(@lobby_id), do: "lobby"
  defp player_name(room_id), do: "room #{room_id}"
end

defmodule Sensocto.Media.MediaPlayerSupervisor do
  @moduledoc """
  DynamicSupervisor for managing MediaPlayerServer processes.
  One MediaPlayerServer per room, plus one for the global lobby.
  """
  use DynamicSupervisor
  require Logger

  alias Sensocto.Media.MediaPlayerServer

  @lobby_id :lobby

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts the lobby media player on application startup.
  """
  def start_lobby_player do
    start_player(@lobby_id, is_lobby: true)
  end

  @doc """
  Starts a media player for a room.
  Returns `{:ok, pid}` if successful, `{:error, reason}` otherwise.
  """
  def start_player(room_id, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:room_id, room_id)
      |> Keyword.put_new(:is_lobby, room_id == @lobby_id)

    case DynamicSupervisor.start_child(__MODULE__, {MediaPlayerServer, opts}) do
      {:ok, pid} ->
        Logger.info("Started media player for #{player_name(room_id)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Media player already exists for #{player_name(room_id)}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error("Failed to start media player for #{player_name(room_id)}: #{inspect(reason)}")
        error
    end
  end

  @doc """
  Stops a media player for a room.
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
  Gets the MediaPlayerServer process for a room.
  """
  def get_player(room_id) do
    case get_player_pid(room_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Gets the MediaPlayerServer PID for a room, or nil if not found.
  """
  def get_player_pid(room_id) do
    case Registry.lookup(Sensocto.MediaRegistry, room_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Checks if a media player exists for a room.
  """
  def player_exists?(room_id) do
    get_player_pid(room_id) != nil
  end

  @doc """
  Gets or creates a media player for a room.
  """
  def get_or_start_player(room_id, opts \\ []) do
    case get_player(room_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> start_player(room_id, opts)
    end
  end

  @doc """
  Gets or creates the lobby media player.
  """
  def get_or_start_lobby_player do
    get_or_start_player(@lobby_id, is_lobby: true)
  end

  @doc """
  Lists all active media players.
  """
  def list_active_players do
    Registry.select(Sensocto.MediaRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {room_id, _pid} -> room_id end)
  end

  @doc """
  Gets the count of active media players.
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

defmodule Sensocto.Whiteboard.WhiteboardSupervisor do
  @moduledoc """
  DynamicSupervisor for managing WhiteboardServer processes.
  One WhiteboardServer per room, plus one for the global lobby.
  """
  use DynamicSupervisor
  require Logger

  alias Sensocto.Whiteboard.WhiteboardServer

  @lobby_id :lobby

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts the lobby whiteboard on application startup.
  """
  def start_lobby_whiteboard do
    start_whiteboard(@lobby_id, is_lobby: true)
  end

  @doc """
  Starts a whiteboard for a room.
  Returns `{:ok, pid}` if successful, `{:error, reason}` otherwise.
  """
  def start_whiteboard(room_id, opts \\ []) do
    opts =
      opts
      |> Keyword.put(:room_id, room_id)
      |> Keyword.put_new(:is_lobby, room_id == @lobby_id)

    case DynamicSupervisor.start_child(__MODULE__, {WhiteboardServer, opts}) do
      {:ok, pid} ->
        Logger.info("Started whiteboard for #{whiteboard_name(room_id)}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Whiteboard already exists for #{whiteboard_name(room_id)}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error(
          "Failed to start whiteboard for #{whiteboard_name(room_id)}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Stops a whiteboard for a room.
  """
  def stop_whiteboard(room_id) do
    case get_whiteboard_pid(room_id) do
      nil ->
        {:error, :not_found}

      pid ->
        DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Gets the WhiteboardServer process for a room.
  """
  def get_whiteboard(room_id) do
    case get_whiteboard_pid(room_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Gets the WhiteboardServer PID for a room, or nil if not found.
  """
  def get_whiteboard_pid(room_id) do
    case Registry.lookup(Sensocto.WhiteboardRegistry, room_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Checks if a whiteboard exists for a room.
  """
  def whiteboard_exists?(room_id) do
    get_whiteboard_pid(room_id) != nil
  end

  @doc """
  Gets or creates a whiteboard for a room.
  """
  def get_or_start_whiteboard(room_id, opts \\ []) do
    case get_whiteboard(room_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> start_whiteboard(room_id, opts)
    end
  end

  @doc """
  Gets or creates the lobby whiteboard.
  """
  def get_or_start_lobby_whiteboard do
    get_or_start_whiteboard(@lobby_id, is_lobby: true)
  end

  @doc """
  Lists all active whiteboards.
  """
  def list_active_whiteboards do
    Registry.select(Sensocto.WhiteboardRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {room_id, _pid} -> room_id end)
  end

  @doc """
  Gets the count of active whiteboards.
  """
  def count do
    DynamicSupervisor.count_children(__MODULE__)[:active] || 0
  end

  @doc """
  Returns the lobby room ID constant.
  """
  def lobby_id, do: @lobby_id

  defp whiteboard_name(@lobby_id), do: "lobby"
  defp whiteboard_name(room_id), do: "room #{room_id}"
end

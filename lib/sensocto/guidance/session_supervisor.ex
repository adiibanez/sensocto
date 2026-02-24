defmodule Sensocto.Guidance.SessionSupervisor do
  @moduledoc """
  DynamicSupervisor for managing SessionServer processes.
  One SessionServer per active guided session.
  """
  use DynamicSupervisor
  require Logger

  alias Sensocto.Guidance.SessionServer

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a session server for a guided session.
  Returns `{:ok, pid}` if successful, `{:error, reason}` otherwise.
  """
  def start_session(session_id, opts \\ []) do
    opts = Keyword.put(opts, :session_id, session_id)

    case DynamicSupervisor.start_child(__MODULE__, {SessionServer, opts}) do
      {:ok, pid} ->
        Logger.info("Started guided session server for #{session_id}")
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        Logger.debug("Guided session server already exists for #{session_id}")
        {:ok, pid}

      {:error, reason} = error ->
        Logger.error(
          "Failed to start guided session server for #{session_id}: #{inspect(reason)}"
        )

        error
    end
  end

  @doc """
  Stops a session server.
  """
  def stop_session(session_id) do
    case get_session_pid(session_id) do
      nil -> {:error, :not_found}
      pid -> DynamicSupervisor.terminate_child(__MODULE__, pid)
    end
  end

  @doc """
  Gets the SessionServer process for a session.
  """
  def get_session(session_id) do
    case get_session_pid(session_id) do
      nil -> {:error, :not_found}
      pid -> {:ok, pid}
    end
  end

  @doc """
  Gets the SessionServer PID for a session, or nil if not found.
  """
  def get_session_pid(session_id) do
    case Registry.lookup(Sensocto.GuidanceRegistry, session_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc """
  Checks if a session server exists.
  """
  def session_exists?(session_id) do
    get_session_pid(session_id) != nil
  end

  @doc """
  Gets or creates a session server.
  """
  def get_or_start_session(session_id, opts \\ []) do
    case get_session(session_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> start_session(session_id, opts)
    end
  end

  @doc """
  Lists all active session IDs.
  """
  def list_active_sessions do
    Registry.select(Sensocto.GuidanceRegistry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {session_id, _pid} -> session_id end)
  end

  @doc """
  Gets the count of active sessions.
  """
  def count do
    DynamicSupervisor.count_children(__MODULE__)[:active] || 0
  end
end

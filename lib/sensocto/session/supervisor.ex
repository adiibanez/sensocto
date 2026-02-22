defmodule Sensocto.Session.Supervisor do
  @moduledoc """
  DynamicSupervisor for per-user session DocumentWorker processes.

  Workers are started on-demand when a user connects and shut down
  after an idle timeout with no connected devices.
  """

  use DynamicSupervisor

  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one, max_children: 10_000)
  end

  @doc """
  Ensure a DocumentWorker is running for the given user.
  Returns the existing worker or starts a new one.
  """
  def ensure_worker(user_id) do
    case Registry.lookup(Sensocto.Session.Registry, user_id) do
      [{pid, _}] ->
        {:ok, pid}

      [] ->
        case DynamicSupervisor.start_child(
               __MODULE__,
               {Sensocto.Session.DocumentWorker, user_id}
             ) do
          {:ok, pid} -> {:ok, pid}
          {:error, {:already_started, pid}} -> {:ok, pid}
          error -> error
        end
    end
  end
end

defmodule Sensocto.Simulator.Supervisor do
  @moduledoc """
  Top-level supervisor for the integrated simulator.
  Manages the data server pool, manager, and connector supervisor.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    config = Application.get_env(:sensocto, :simulator, [])
    config_path = Keyword.get(config, :config_path, "config/simulators.yaml")

    Logger.info("Starting Simulator Supervisor with config: #{config_path}")

    children = [
      # Registry for simulator processes
      {Registry, keys: :unique, name: Sensocto.Simulator.Registry},

      # Battery state manager (for realistic battery simulation)
      Sensocto.Simulator.BatteryState,

      # Track player for GPS track replay
      Sensocto.Simulator.TrackPlayer,

      # Data server pool (5 workers for parallel data generation)
      Supervisor.child_spec({Sensocto.Simulator.DataServer, 1}, id: :data_server_1),
      Supervisor.child_spec({Sensocto.Simulator.DataServer, 2}, id: :data_server_2),
      Supervisor.child_spec({Sensocto.Simulator.DataServer, 3}, id: :data_server_3),
      Supervisor.child_spec({Sensocto.Simulator.DataServer, 4}, id: :data_server_4),
      Supervisor.child_spec({Sensocto.Simulator.DataServer, 5}, id: :data_server_5),

      # Dynamic supervisor for connectors
      {DynamicSupervisor, strategy: :one_for_one, name: Sensocto.Simulator.ConnectorSupervisor},

      # Manager that loads config and starts connectors
      {Sensocto.Simulator.Manager, config_path}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Check if the simulator is enabled in config (for startup decision).
  """
  def config_enabled? do
    config = Application.get_env(:sensocto, :simulator, [])
    Keyword.get(config, :enabled, false)
  end

  @doc """
  Check if the simulator supervisor is currently running.
  """
  def enabled? do
    case Process.whereis(__MODULE__) do
      nil -> false
      pid when is_pid(pid) -> Process.alive?(pid)
    end
  end

  @doc """
  Stop the simulator supervisor and all its children.
  """
  def stop do
    case Process.whereis(__MODULE__) do
      nil ->
        {:error, :not_running}

      pid when is_pid(pid) ->
        Supervisor.stop(pid, :normal)
        :ok
    end
  end
end

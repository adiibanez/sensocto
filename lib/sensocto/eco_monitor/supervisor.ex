defmodule Sensocto.EcoMonitor.Supervisor do
  @moduledoc """
  Top-level supervisor for the EcoMonitor subsystem.

  Manages environmental data ingestion from external APIs (hydrology, weather, etc.)
  into the standard Sensocto sensor pipeline.

  Uses rest_for_one: the Registry must be alive before any poller starts.
  If the Registry crashes, all pollers restart to re-register.

  Supervision tree:
    EcoMonitor.Supervisor (rest_for_one)
    ├── EcoMonitor.Registry  (local Registry for poller process lookup)
    └── EcoMonitor.HydroSupervisor (one_for_one)
        └── HydroPoller {:reuss, config}
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    Logger.info("Starting EcoMonitor Supervisor")

    children = [
      {Registry, keys: :unique, name: Sensocto.EcoMonitor.Registry},
      Sensocto.EcoMonitor.HydroSupervisor
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end

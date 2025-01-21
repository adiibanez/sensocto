defmodule Sensocto.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # {NodeJS.Supervisor, [path: LiveSvelte.SSR.NodeJS.server_path(), pool_size: 4]},
      SensoctoWeb.Telemetry,
      Sensocto.Repo,
      # Registry added here
      {Registry, keys: :unique, name: Sensocto.Registry},
      {Sensocto.DeviceSupervisor, []},
      {DNSCluster, query: Application.get_env(:sensocto, :dns_cluster_query) || :ignore},
      # {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: Sensocto.ClusterSupervisor]]},

      {Phoenix.PubSub, name: Sensocto.PubSub},
      SensoctoWeb.Sensocto.Presence,
      # Start the Finch HTTP client for sending emails
      {Finch, name: Sensocto.Finch},
      # Start a worker by calling: Sensocto.Worker.start_link(arg)
      # {Sensocto.Worker, arg},
      # Start to serve requests, typically the last entry
      SensoctoWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :sensocto]}
      # Sensocto.Broadway.MyBroadway,
      # Sensocto.Broadway.Counter2
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Sensocto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SensoctoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

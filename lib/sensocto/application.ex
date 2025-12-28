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
      Sensocto.Otp.BleConnectorGenServer,
      # realitykit
      {SensorsStateAgent, name: SensorsStateAgent},
      {Registry, keys: :unique, name: Sensocto.TestRegistry},
      Sensocto.Otp.Connector,
      # Registry added here
      {Registry, keys: :unique, name: Sensocto.Sensors.Registry},
      {Registry, keys: :unique, name: Sensocto.Sensors.SensorRegistry},
      # {Registry, keys: :unique, name: Sensocto.Sensors.SensorAttributeRegistry},
      # Sensors
      # Sensocto.Sensors.SensorRegistry,
      # {Registry.Supervisor, [Sensocto.Sensors.SensorRegistry]},
      # Sensocto.Sensors.SensorAttributeRegistry,
      # {Registry.Supervisor, [Sensocto.Sensors.SensorAttributeRegistry]},
      # Sensocto.Sensors.SensorSupervisor,

      {Registry, keys: :unique, name: Sensocto.SimpleAttributeRegistry},
      {Registry, keys: :unique, name: Sensocto.SimpleSensorRegistry},
      {Registry, keys: :unique, name: Sensocto.SensorPairRegistry},

      # Rooms
      {Registry, keys: :unique, name: Sensocto.RoomRegistry},
      {Registry, keys: :unique, name: Sensocto.RoomJoinCodeRegistry},

      # {Horde.Registry, keys: :unique, name: Sensocto.SimpleAttributeRegistry},
      # {Horde.Registry, keys: :unique, name: Sensocto.SimpleSensorRegistry},
      # {Horde.Registry, keys: :unique, name: Sensocto.SensorPairRegistry},

      # {Horde.DynamicSupervisor, [name: Sensocto.SensorsDynamicSupervisor, strategy: :one_for_one]},

      # Sensors
      # {Horde.DynamicSupervisor, [name: Sensocto.DistributedSupervisor, strategy: :one_for_one]},
      # {Horde.Registry, [name: Sensocto.DistributedRegistry, keys: :unique]},

      {DNSCluster, query: Application.get_env(:sensocto, :dns_cluster_query) || :ignore},
      # {Cluster.Supervisor, [Application.get_env(:libcluster, :topologies), [name: Sensocto.ClusterSupervisor]]},

      {Phoenix.PubSub, name: Sensocto.PubSub},
      SensoctoWeb.Sensocto.Presence,

      # initialize after pubsub
      Sensocto.SensorsDynamicSupervisor,
      Sensocto.RoomsDynamicSupervisor,
      Sensocto.Otp.RepoReplicator,
      # Start the Finch HTTP client for sending emails
      {Finch, name: Sensocto.Finch},
      # Start a worker by calling: Sensocto.Worker.start_link(arg)
      # {Sensocto.Worker, arg},
      # Start to serve requests, typically the last entry
      SensoctoWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :sensocto]}
      # Sensocto.Broadway.MyBroadway,
      # Sensocto.Broadway.Counter2
      # elixir desktop bridge
      # Bridge
    ]

    # Conditionally add simulator if enabled in config
    children =
      if Sensocto.Simulator.Supervisor.config_enabled?() do
        IO.puts("Starting integrated simulator...")
        children ++ [{Sensocto.Simulator.Supervisor, []}]
      else
        children
      end

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

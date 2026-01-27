defmodule Sensocto.Infrastructure.Supervisor do
  @moduledoc """
  Supervisor for core infrastructure services.

  ## Failure Isolation Strategy

  This supervisor manages foundational services that other parts of the application
  depend on. Uses `:one_for_one` strategy because each child is independent:

  - **Telemetry**: Metrics collection - failure doesn't affect other processes
  - **TaskSupervisor**: Async task management - isolated pool
  - **Repos**: Database connections - each repo is independent
  - **DNSCluster**: Service discovery - optional, failure is graceful
  - **PubSub**: Message passing backbone - critical but independent
  - **Finch**: HTTP client pool - isolated connection pool
  - **Presence**: Real-time presence tracking - depends on PubSub but starts after

  ## Restart Semantics

  With `:one_for_one`, a flapping Finch pool (network issues) won't affect
  the database repos. Each process has its own restart budget within this
  supervisor's intensity (3 restarts in 5 seconds by default).

  ## Blast Radius

  If this entire supervisor crashes (exhausts restart budget), the root
  supervisor will restart it with `:rest_for_one`, taking down dependent
  supervisors (Registry, Storage, Domain) and restarting them in order.
  This is the correct behavior - if infrastructure dies, dependent systems
  need a clean restart.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Telemetry for observability - start first to capture startup metrics
      SensoctoWeb.Telemetry,

      # Task.Supervisor for async operations (DB sync, background jobs)
      {Task.Supervisor, name: Sensocto.TaskSupervisor},

      # Database repos - Primary (Neon.tech) and Read Replica
      # Independent connections, each can fail without affecting the other
      Sensocto.Repo,
      Sensocto.Repo.Replica,

      # DNS-based service discovery for clustering
      {DNSCluster, query: Application.get_env(:sensocto, :dns_cluster_query) || :ignore},

      # PubSub for real-time messaging across the application
      # pool_size: 8 for high-throughput scenarios (50K+ concurrent users)
      # Note: pool_size must be the same across all cluster nodes
      {Phoenix.PubSub, name: Sensocto.PubSub, pool_size: 8},

      # Presence tracking (depends on PubSub, hence after it)
      SensoctoWeb.Sensocto.Presence,

      # HTTP client for external API calls
      {Finch, name: Sensocto.Finch}
    ]

    # one_for_one: each child is independent
    # intensity 3, period 5: allows 3 restarts in 5 seconds before escalating
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 3, max_seconds: 5)
  end
end

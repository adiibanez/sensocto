defmodule Sensocto.Application do
  @moduledoc """
  OTP Application for Sensocto.

  ## Supervision Tree Architecture

  The application uses a hierarchical supervision tree with intermediate
  supervisors to create failure isolation domains. This prevents a flapping
  process in one domain from exhausting the restart budget and bringing
  down unrelated functionality.

  ```
  Sensocto.Supervisor (root, :rest_for_one)
    |
    |-- Infrastructure.Supervisor (:one_for_one)
    |     |-- Repos, PubSub, Telemetry, Finch, DNSCluster, Presence
    |
    |-- Registry.Supervisor (:one_for_one)
    |     |-- All Registry processes (Sensor, Room, Call, Media, Object3D)
    |
    |-- Storage.Supervisor (:rest_for_one)
    |     |-- Iroh.RoomStore, RoomStore, Iroh.RoomSync, RoomStateCRDT
    |
    |-- Bio.Supervisor (:one_for_one) [biomimetic layer]
    |     |-- NoveltyDetector, PredictiveLoadBalancer, HomeostaticTuner, etc.
    |
    |-- Domain.Supervisor (:one_for_one)
    |     |-- SensorsDynamicSupervisor, RoomsDynamicSupervisor
    |     |-- CallSupervisor, MediaPlayerSupervisor, Object3DPlayerSupervisor
    |
    |-- SensoctoWeb.Endpoint (last - depends on everything above)
    |-- AshAuthentication.Supervisor
  ```

  ## Strategy Rationale

  **Root supervisor uses `:rest_for_one`** because later children depend on
  earlier ones. If Infrastructure crashes, Registries lose their PubSub.
  If Registries crash, Domain supervisors lose their lookup mechanism.
  The cascading restart ensures consistency.

  **Intermediate supervisors use `:one_for_one`** (mostly) because their
  children are independent within each domain. A crashed sensor registry
  doesn't affect the room registry.

  **Storage uses `:rest_for_one`** because RoomStore depends on Iroh.RoomStore,
  and RoomSync depends on both. Dependencies flow downward.

  ## Blast Radius Examples

  - Media player crash: Only that room's player restarts. No other impact.
  - Sensor registry crash: Sensor lookups fail briefly. Rooms unaffected.
  - Iroh.RoomStore crash: All storage processes restart. Domains stay up.
  - Infrastructure crash: Everything restarts in order. Full recovery.
  """

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Reapply hot code changes after container restart (FlyDeploy)
    if Code.ensure_loaded?(FlyDeploy) do
      FlyDeploy.startup_reapply_current(Application.app_dir(:sensocto))
    end

    children = [
      # Layer 1: Core infrastructure (repos, pubsub, telemetry, HTTP clients)
      # Must start first - everything depends on these
      Sensocto.Infrastructure.Supervisor,

      # Layer 2: Process registries for lookup
      # Must start before dynamic supervisors that register processes
      Sensocto.Registry.Supervisor,

      # Layer 3: Persistent storage and state synchronization
      # Depends on PubSub (in Infrastructure) for cluster sync
      Sensocto.Storage.Supervisor,

      # Layer 4: Biomimetic layer (adaptive resource management)
      # Depends on AttentionTracker and SystemLoadMonitor (now in Domain)
      # But Bio.Supervisor is independent - it observes, doesn't control
      Sensocto.Bio.Supervisor,

      # Layer 5: Domain logic and dynamic process management
      # Depends on registries (Layer 2) and storage (Layer 3)
      Sensocto.Domain.Supervisor,

      # Layer 5.5: Guest user store (in-memory only)
      # Independent of domain logic, used for temporary guest sessions
      Sensocto.Accounts.GuestUserStore,

      # Layer 6: Web interface (serves HTTP/WebSocket requests)
      # Must be last - depends on all business logic being available
      SensoctoWeb.Endpoint,

      # Layer 7: Authentication (external supervisor, runs independently)
      {AshAuthentication.Supervisor, [otp_app: :sensocto]}
    ]

    # Conditionally add simulator if enabled in config
    children =
      if Sensocto.Simulator.Supervisor.config_enabled?() do
        Logger.info("Starting integrated simulator...")
        children ++ [{Sensocto.Simulator.Supervisor, []}]
      else
        children
      end

    # rest_for_one: if Infrastructure crashes, restart everything after it
    # This ensures dependent supervisors get a clean restart with fresh
    # infrastructure (new PubSub, new repos, etc.)
    opts = [
      strategy: :rest_for_one,
      name: Sensocto.Supervisor,
      max_restarts: 5,
      max_seconds: 10
    ]

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

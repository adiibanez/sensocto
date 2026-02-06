defmodule Sensocto.Domain.Supervisor do
  @moduledoc """
  Supervisor for domain-level dynamic supervisors and services.

  ## Failure Isolation Strategy

  Uses `:one_for_one` because each domain is independent:

  - **Sensors**: IoT sensor data processing (SensorsDynamicSupervisor)
  - **Rooms**: Collaborative room sessions (RoomsDynamicSupervisor)
  - **Calls**: Video/voice communication (CallSupervisor)
  - **Media**: YouTube/Spotify playback (MediaPlayerSupervisor)
  - **Object3D**: 3D Gaussian splat viewing (Object3DPlayerSupervisor)
  - **Search**: Global search index
  - **Replication**: Database sync pool

  A crash in media playback shouldn't affect sensor processing.
  A flapping call server shouldn't bring down room management.

  ## Why Not rest_for_one?

  While you might think rooms should restart if sensors crash, that's
  incorrect. Sensors and rooms are parallel domains that happen to
  interact via PubSub messages. Neither "owns" the other. They can
  operate independently and gracefully handle the temporary absence
  of their counterpart.

  ## Dynamic Supervisor Pattern

  Each child here is itself a DynamicSupervisor (or Horde.DynamicSupervisor)
  that manages ephemeral processes (individual sensors, rooms, calls).
  This creates a clean hierarchy:

  ```
  Domain.Supervisor (static, :one_for_one)
    |-- SensorsDynamicSupervisor (dynamic, :one_for_one)
    |     |-- SensorProcess1, SensorProcess2, ...
    |-- RoomsDynamicSupervisor (dynamic/Horde, :one_for_one)
    |     |-- RoomServer1, RoomServer2, ...
    |-- CallSupervisor (dynamic, :one_for_one)
    |     |-- CallServer1, CallServer2, ...
  ```

  ## Blast Radius

  If SensorsDynamicSupervisor exhausts its restart budget (many sensors
  crashing rapidly), only sensor functionality is affected. Rooms,
  calls, and media continue operating normally.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Legacy OTP components
      Sensocto.Otp.BleConnectorGenServer,
      {SensorsStateAgent, name: SensorsStateAgent},
      Sensocto.Otp.Connector,

      # Attention tracking for back-pressure
      Sensocto.AttentionTracker,

      # System load monitoring for back-pressure
      Sensocto.SystemLoadMonitor,

      # Adaptive data lenses - must start before sensors so Router can receive data
      Sensocto.Lenses.Supervisor,

      # Attribute storage ETS tables - must exist before any sensors start
      Sensocto.AttributeStoreTiered.TableOwner,

      # Sensor domain - manages individual sensor processes
      Sensocto.SensorsDynamicSupervisor,

      # Discovery domain - cluster-wide entity discovery cache and sync
      # Must start after SensorsDynamicSupervisor to sync existing sensors
      Sensocto.Discovery.DiscoveryCache,
      Sensocto.Discovery.SyncWorker,

      # Connector domain - distributed connector coordination
      # Uses :pg for cluster-wide connector discovery and ETS for local storage
      Sensocto.Sensors.ConnectorManager,

      # Room domain - distributed room processes (Horde)
      Sensocto.RoomsDynamicSupervisor,

      # Communication domain - video/voice calls
      Sensocto.Calls.CallSupervisor,

      # Media domain - YouTube/Spotify playback
      Sensocto.Media.MediaPlayerSupervisor,

      # 3D visualization domain - Gaussian splat viewers
      Sensocto.Object3D.Object3DPlayerSupervisor,

      # Whiteboard domain - collaborative drawing
      Sensocto.Whiteboard.WhiteboardSupervisor,

      # Database replication pool - scalable sync operations
      {Sensocto.Otp.RepoReplicatorPool, pool_size: 8},

      # Search index for global search (must be after dynamic supervisors)
      Sensocto.Search.SearchIndex,

      # Guest user store (in-memory, for temporary guest sessions)
      Sensocto.Accounts.GuestUserStore,

      # Chat store (ETS-based, for room/lobby chat messages)
      Sensocto.Chat.ChatStore
    ]

    # one_for_one: each domain is independent
    # Moderate restart tolerance - domain supervisors are robust
    Supervisor.init(children, strategy: :one_for_one, max_restarts: 5, max_seconds: 10)
  end
end

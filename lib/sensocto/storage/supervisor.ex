defmodule Sensocto.Storage.Supervisor do
  @moduledoc """
  Supervisor for room state storage and synchronization.

  ## Failure Isolation Strategy

  Uses `:rest_for_one` because these processes have explicit dependencies:

  1. `Iroh.ConnectionManager` - Shared iroh node (all iroh processes depend on this)
  2. `Iroh.RoomStore` - Low-level iroh document storage
  3. `HydrationManager` - Coordinates multiple storage backends
  4. `RoomStore` - In-memory room state cache (uses HydrationManager for persistence)
  5. `Iroh.RoomSync` - Async persistence layer (writes to Iroh.RoomStore)
  6. `Iroh.RoomStateCRDT` - Real-time collaborative state using Automerge

  If `Iroh.ConnectionManager` crashes, all downstream iroh-dependent processes
  must restart to re-fetch the new node_ref. This is the textbook use case
  for `:rest_for_one`.

  ## State Recovery

  - `Iroh.ConnectionManager`: Creates a new iroh node (identity persistence planned)
  - `Iroh.RoomStore`: Re-creates namespaces using the shared node
  - `HydrationManager`: Re-initializes backends (PostgreSQL, Iroh, LocalStorage)
  - `RoomStore`: Rebuilds in-memory cache via HydrationManager
  - `Iroh.RoomSync`: Resumes async sync operations
  - `Iroh.RoomStateCRDT`: Reloads CRDT state from storage

  ## Blast Radius

  A crash here is isolated from sensors, calls, and media players.
  Room processes may experience temporary unavailability during restart,
  but they can recover state from the restarted storage layer.
  """

  use Supervisor

  def start_link(opts \\ []) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      # Shared iroh node connection - MUST start first.
      # All iroh-dependent processes below get their node_ref from this manager.
      Sensocto.Iroh.ConnectionManager,

      # Room storage: iroh docs (low-level) -> HydrationManager -> RoomStore (in-memory)
      # Order matters! Later processes depend on earlier ones.
      Sensocto.Iroh.RoomStore,

      # Multi-backend hydration coordinator (PostgreSQL, Iroh, LocalStorage)
      # Must start before RoomStore so it can handle hydration requests
      Sensocto.Storage.HydrationManager,

      # In-memory room state cache - uses HydrationManager for persistence
      Sensocto.RoomStore,

      # Async persistence layer (writes to Iroh.RoomStore)
      Sensocto.Iroh.RoomSync,

      # Real-time collaborative state using Automerge CRDTs (media sync, 3D viewer, presence)
      Sensocto.Iroh.RoomStateCRDT,

      # Room presence tracking (in-memory) - depends on storage being available
      Sensocto.RoomPresenceServer
    ]

    # rest_for_one: if storage crashes, dependent processes must restart
    # Conservative restart tolerance - storage issues need investigation
    Supervisor.init(children, strategy: :rest_for_one, max_restarts: 3, max_seconds: 5)
  end
end

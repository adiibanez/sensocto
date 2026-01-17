defmodule Sensocto.Storage.Supervisor do
  @moduledoc """
  Supervisor for room state storage and synchronization.

  ## Failure Isolation Strategy

  Uses `:rest_for_one` because these processes have explicit dependencies:

  1. `Iroh.RoomStore` - Low-level iroh document storage
  2. `RoomStore` - In-memory room state cache (reads from Iroh.RoomStore)
  3. `Iroh.RoomSync` - Async persistence layer (writes to Iroh.RoomStore)
  4. `Iroh.RoomStateCRDT` - Real-time collaborative state using Automerge

  If `Iroh.RoomStore` crashes, the downstream processes that depend on it
  (RoomStore, RoomSync, RoomStateCRDT) must be restarted to maintain
  consistency. This is the textbook use case for `:rest_for_one`.

  ## State Recovery

  - `Iroh.RoomStore`: Recovers from persistent storage on restart
  - `RoomStore`: Rebuilds in-memory cache from Iroh.RoomStore
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
      # Room storage: iroh docs (low-level) -> RoomStore (in-memory) -> RoomSync (async persistence)
      # Order matters! Later processes depend on earlier ones.
      Sensocto.Iroh.RoomStore,
      Sensocto.RoomStore,
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

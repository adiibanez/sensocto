# Iroh Room Storage Architecture

**Status:** Design Document
**Last Updated:** January 2026
**Related Issue:** #31

## Executive Summary

This document describes the architecture for migrating room state storage from single-node ETS to Iroh documents with Automerge CRDTs, enabling true peer-to-peer room synchronization across distributed nodes and clients.

## Current State Analysis

### Existing Components

The codebase already contains several Iroh-related modules:

| Module | Purpose | Status |
|--------|---------|--------|
| `Sensocto.Iroh.RoomStore` | Low-level Iroh document storage | Implemented |
| `Sensocto.Iroh.RoomSync` | Async persistence with debouncing | Implemented |
| `Sensocto.Iroh.RoomStateCRDT` | Real-time collaborative state (media, presence) | Implemented |
| `Sensocto.Iroh.RoomStateBridge` | Bridges local state with CRDT layer | Implemented |
| `Sensocto.RoomStore` | In-memory cache with PostgreSQL primary | Implemented |
| `Sensocto.RoomServer` | Per-room GenServer (Horde-distributed) | Implemented |

### Current Architecture

```
                                   ┌────────────────────────────────┐
                                   │      Storage.Supervisor        │
                                   │        (rest_for_one)          │
                                   └────────────────┬───────────────┘
                                                    │
          ┌─────────────────────────────────────────┼─────────────────────────────────────────┐
          │                                         │                                         │
          ▼                                         ▼                                         ▼
┌─────────────────────┐               ┌─────────────────────┐               ┌─────────────────────┐
│  Iroh.RoomStore     │               │     RoomStore       │               │  Iroh.RoomSync      │
│  (Low-level docs)   │◄──────────────│   (In-memory)       │───────────────│  (Async persist)    │
│                     │               │                     │               │                     │
│  - Node management  │               │  - Fast reads       │               │  - Debounced writes │
│  - Doc CRUD ops     │               │  - PostgreSQL sync  │               │  - Retry logic      │
│  - Author creation  │               │  - Cluster PubSub   │               │  - Batch operations │
└─────────────────────┘               └──────────┬──────────┘               └─────────────────────┘
                                                 │
                                    ┌────────────┴────────────┐
                                    │                         │
                                    ▼                         ▼
                          ┌─────────────────┐       ┌─────────────────┐
                          │   PostgreSQL    │       │   Iroh Docs     │
                          │    (Primary)    │       │   (Secondary)   │
                          └─────────────────┘       └─────────────────┘
```

### Identified Gaps

1. **No persistent Iroh document IDs** - Each startup creates new namespaces, losing document continuity
2. **No cross-node sync** - Iroh nodes are isolated; changes don't propagate between server instances
3. **No client-side sync** - Clients cannot participate in Iroh document synchronization
4. **Missing BlobStorage** - Large sensor data batches not integrated with Iroh blobs
5. **Room metadata vs live state confusion** - `RoomStore` and `RoomStateCRDT` have overlapping concerns

## Target Architecture

### Design Principles

Following Joe Armstrong's guidance: "The right supervision tree is more important than any amount of defensive coding."

1. **One process, one responsibility** - Clear separation between document management, sync, and state
2. **Let it crash** - Supervisors handle failure recovery; processes should not paper over errors
3. **Explicit dependencies** - The supervision tree reflects actual process dependencies
4. **Back-pressure everywhere** - Never overwhelm downstream consumers

### Proposed Supervision Tree

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                         IrohStorageSupervisor                                │
│                           (rest_for_one)                                     │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────┐    ┌────────────────────────────────────────┐   │
│  │   IrohConnectionManager │    │           DocumentRegistry              │   │
│  │      (GenServer)        │    │              (Horde)                    │   │
│  │                         │    │                                        │   │
│  │  - Maintains Iroh node  │    │  - Tracks active document syncs        │   │
│  │  - Reconnection logic   │    │  - Cluster-wide unique registration    │   │
│  │  - Health monitoring    │    │  - Maps room_id -> DocumentSyncWorker  │   │
│  │  - Node ID persistence  │    │                                        │   │
│  │  - Relay configuration  │    │                                        │   │
│  └────────────┬───────────┘    └────────────────────────────────────────┘   │
│               │                                                              │
│               ▼                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │                    DocumentSyncSupervisor                          │     │
│  │                      (DynamicSupervisor)                           │     │
│  └────────────────────────────────────────────────┬───────────────────┘     │
│                                                   │                          │
│        ┌──────────────────────────────────────────┼───────────────────┐     │
│        │                                          │                   │     │
│        ▼                                          ▼                   ▼     │
│  ┌───────────────────┐                 ┌───────────────────┐   ┌──────────┐ │
│  │ DocumentSyncWorker │                 │ DocumentSyncWorker │   │   ...    │ │
│  │   (room_id: A)     │                 │   (room_id: B)     │   │          │ │
│  │                    │                 │                    │   │          │ │
│  │  - One per room    │                 │  - Automerge ops   │   │          │ │
│  │  - CRDT operations │                 │  - Gossip sync     │   │          │ │
│  │  - Conflict merge  │                 │  - State recovery  │   │          │ │
│  │  - Change events   │                 │                    │   │          │ │
│  └───────────────────┘                 └───────────────────┘   └──────────┘ │
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │                      BlobStorageWorker                              │     │
│  │                        (GenServer)                                  │     │
│  │                                                                     │     │
│  │  - Large sensor data batches as Iroh blobs                         │     │
│  │  - Content-addressed storage                                        │     │
│  │  - Garbage collection for old blobs                                 │     │
│  │  - Ticket generation for blob references                           │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

#### IrohConnectionManager

The foundational component that owns the Iroh node connection.

```elixir
defmodule Sensocto.Iroh.ConnectionManager do
  @moduledoc """
  Maintains the Iroh node connection with proper lifecycle management.

  This is the ONLY component that creates or owns the Iroh node reference.
  All other components must request the node_ref from this manager.

  ## Crash Recovery

  If this process crashes:
  1. The supervisor restarts it (and all downstream processes)
  2. On init, it attempts to reconnect using persisted node identity
  3. If identity exists, documents remain addressable on the network
  4. If identity is lost, new identity is generated (documents start fresh)

  ## Health Monitoring

  Periodically checks:
  - Connection to relay nodes
  - Gossip neighbor count
  - Document sync health metrics

  Publishes health status to PubSub for observability.
  """

  use GenServer
  require Logger

  @health_check_interval_ms 30_000
  @reconnect_delay_ms 5_000
  @identity_file "priv/iroh/node_identity"

  defstruct [
    :node_ref,
    :author_id,
    :node_id,
    connected: false,
    health: %{
      relay_connected: false,
      neighbor_count: 0,
      last_sync: nil
    }
  ]

  # Client API

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Gets the Iroh node reference. Blocks if not yet connected."
  def get_node_ref, do: GenServer.call(__MODULE__, :get_node_ref, 10_000)

  @doc "Gets the author ID for write operations."
  def get_author_id, do: GenServer.call(__MODULE__, :get_author_id, 5_000)

  @doc "Checks if the connection is healthy."
  def healthy?, do: GenServer.call(__MODULE__, :healthy?)

  @doc "Gets current health metrics."
  def health_metrics, do: GenServer.call(__MODULE__, :health_metrics)

  # ... implementation details
end
```

**Key Design Decisions:**

1. **Persistent node identity** - Store node identity to disk so the same node ID is used across restarts. This allows other peers to find us after restart.

2. **Single owner** - Only this process creates/owns the Iroh node. All other processes request the reference.

3. **Health monitoring** - Periodically checks connection health and publishes metrics to PubSub for observability dashboards.

4. **Graceful degradation** - If Iroh is unavailable, other storage layers (PostgreSQL) continue to function.

#### DocumentSyncWorker

One worker per active room, managing the Automerge document.

```elixir
defmodule Sensocto.Iroh.DocumentSyncWorker do
  @moduledoc """
  Manages a single room's Automerge document with Iroh synchronization.

  ## Lifecycle

  1. Started when a room becomes "active" (has connected members)
  2. Loads or creates the room's Automerge document
  3. Joins the gossip topic for real-time sync
  4. Applies local changes, merges remote changes
  5. Stopped when room becomes inactive (configurable idle timeout)

  ## Document Structure

  The room document contains:
  - Room metadata (name, description, owner - LWW registers)
  - Member list (Map CRDT - user_id -> {role, joined_at})
  - Sensor bindings (Set CRDT - sensor_ids)
  - Media state (LWW map - playing, position, current_url)
  - 3D viewer state (LWW map - camera_pos, camera_target, splat_url)
  - Presence (expiring entries - user_id -> {cursor, last_seen})
  - Annotations (List CRDT - timestamped annotations)

  ## Conflict Resolution

  Uses Automerge's built-in conflict resolution:
  - Last-writer-wins for scalar values
  - Union for sets
  - Merge for maps
  - Append for lists

  ## Back-pressure

  Implements rate limiting on local changes to prevent overwhelming
  the gossip network. Remote changes are always accepted immediately.
  """

  use GenServer
  require Logger

  @idle_timeout_ms 5 * 60 * 1000  # 5 minutes
  @local_change_debounce_ms 100
  @sync_heartbeat_ms 10_000

  defstruct [
    :room_id,
    :doc_id,
    :node_ref,
    :gossip_topic,
    pending_changes: [],
    last_local_change: nil,
    last_remote_sync: nil,
    subscribers: []
  ]

  # Client API

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts)

  @doc "Applies a local change to the document."
  def apply_change(worker, change_spec), do: GenServer.cast(worker, {:apply_change, change_spec})

  @doc "Gets the current document state."
  def get_state(worker), do: GenServer.call(worker, :get_state)

  @doc "Subscribes to document change events."
  def subscribe(worker, pid), do: GenServer.call(worker, {:subscribe, pid})

  # ... implementation details
end
```

**Key Design Decisions:**

1. **Lazy initialization** - Workers are only started for rooms with active members. Idle rooms don't consume resources.

2. **Change debouncing** - Local changes are debounced to prevent overwhelming the sync network during rapid updates (e.g., scrubbing video position).

3. **Event broadcasting** - Subscribers receive change events, enabling LiveViews to react to remote changes.

4. **Idle timeout** - Workers shut down after inactivity to free resources. State persists in the Iroh document.

#### BlobStorageWorker

Handles large binary data (sensor batches, media files).

```elixir
defmodule Sensocto.Iroh.BlobStorageWorker do
  @moduledoc """
  Manages large binary data as Iroh blobs.

  ## Use Cases

  - Sensor data batches (aggregated measurements)
  - Large configuration files
  - User-uploaded media (thumbnails, previews)

  ## NOT for:

  - Real-time sensor data (use regular PubSub)
  - Small state updates (use Automerge documents)
  - Streaming media (use dedicated media servers)

  ## Garbage Collection

  Blobs are reference-counted. When no documents reference a blob,
  it becomes eligible for garbage collection after a grace period.

  ## Tickets

  Each blob has a ticket (content hash + provider info) that can be
  shared with clients for direct download from the Iroh network.
  """

  use GenServer
  require Logger

  @gc_interval_ms 60 * 60 * 1000  # 1 hour
  @gc_grace_period_ms 24 * 60 * 60 * 1000  # 24 hours

  defstruct [
    :node_ref,
    blobs: %{},  # content_hash -> {size, created_at, ref_count}
    pending_gc: []
  ]

  # Client API

  def store_blob(data, opts \\ [])
  def get_blob(content_hash)
  def get_ticket(content_hash)
  def add_reference(content_hash)
  def remove_reference(content_hash)

  # ... implementation details
end
```

### Data Model

The room document uses Automerge's CRDT types:

```
Room Document {
  // Metadata (LWW registers for each field)
  id: UUID,
  name: Text,
  description: Text,
  owner_id: UUID,
  join_code: Text,
  is_public: Boolean,
  created_at: Timestamp,
  updated_at: LWW-Register<Timestamp>,

  // Members (Map CRDT)
  members: Map<user_id, {
    role: Enum<owner|admin|member>,
    joined_at: Timestamp
  }>,

  // Sensors (Set CRDT)
  sensor_ids: Set<sensor_id>,

  // Media playback state (LWW map)
  media: {
    current_url: Text,
    position_ms: Integer,
    is_playing: Boolean,
    updated_by: UUID,
    updated_at: Timestamp
  },

  // 3D viewer state (LWW map)
  object_3d: {
    splat_url: Text,
    camera_position: { x: Float, y: Float, z: Float },
    camera_target: { x: Float, y: Float, z: Float },
    updated_by: UUID,
    updated_at: Timestamp
  },

  // Presence (Map with expiring entries)
  participants: Map<user_id, {
    name: Text,
    cursor: { x: Float, y: Float } | null,
    last_seen: Timestamp
  }>,

  // Annotations (List CRDT)
  annotations: List<{
    id: UUID,
    type: Enum<marker|note|highlight>,
    data: JSON,
    author: UUID,
    created_at: Timestamp
  }>
}
```

### Integration Points

#### With Existing RoomStore

The `RoomStore` remains the primary source of truth for PostgreSQL persistence. `DocumentSyncWorker` handles real-time collaborative state.

```
                     ┌─────────────────────┐
                     │      RoomStore      │
                     │   (PostgreSQL sync) │
                     └──────────┬──────────┘
                                │
                    ┌───────────┼───────────┐
                    │           │           │
                    ▼           ▼           ▼
             Room Metadata    Members    Configuration
           (name, public)   (join/leave) (settings)
                    │           │           │
                    └───────────┴───────────┘
                                │
                                ▼
                     ┌─────────────────────┐
                     │ DocumentSyncWorker  │
                     │ (Real-time CRDT)    │
                     └─────────────────────┘
                                │
                    ┌───────────┼───────────┐
                    │           │           │
                    ▼           ▼           ▼
              Media State   3D Viewer    Presence
            (position, play) (camera)   (cursors)
```

**Responsibility Split:**

| Data | Primary Storage | Sync Method |
|------|-----------------|-------------|
| Room metadata | PostgreSQL (via RoomStore) | Cluster PubSub |
| Member list | PostgreSQL (via RoomStore) | Cluster PubSub |
| Sensor bindings | In-memory (RoomStore) | Cluster PubSub |
| Media state | Automerge (DocumentSyncWorker) | Iroh Gossip |
| 3D viewer state | Automerge (DocumentSyncWorker) | Iroh Gossip |
| Presence | Automerge (DocumentSyncWorker) | Iroh Gossip |
| Annotations | Automerge (DocumentSyncWorker) | Iroh Gossip |

#### With LiveView

LiveViews subscribe to document changes and receive push updates:

```elixir
defmodule SensoctoWeb.RoomLive do
  use SensoctoWeb, :live_view

  def mount(%{"room_id" => room_id}, _session, socket) do
    if connected?(socket) do
      # Subscribe to document changes
      {:ok, worker} = get_or_start_doc_worker(room_id)
      DocumentSyncWorker.subscribe(worker, self())
    end

    {:ok, assign(socket, room_id: room_id)}
  end

  # Handle remote changes
  def handle_info({:doc_change, path, value}, socket) do
    case path do
      ["media", "position_ms"] ->
        {:noreply, update_media_position(socket, value)}
      ["participants", user_id] ->
        {:noreply, update_participant(socket, user_id, value)}
      _ ->
        {:noreply, socket}
    end
  end

  # Apply local changes
  def handle_event("seek", %{"position" => pos}, socket) do
    worker = get_doc_worker(socket.assigns.room_id)
    DocumentSyncWorker.apply_change(worker, {:set, ["media", "position_ms"], pos})
    {:noreply, socket}
  end
end
```

### Migration Path

#### Phase 1: Connection Manager (Week 1)

1. Implement `IrohConnectionManager` with persistent identity
2. Migrate `Iroh.RoomStore` to use shared connection
3. Migrate `RoomStateCRDT` to use shared connection
4. Add health monitoring and metrics

#### Phase 2: Document Workers (Week 2)

1. Implement `DocumentSyncWorker` with Automerge operations
2. Implement `DocumentSyncSupervisor` (DynamicSupervisor)
3. Add `DocumentRegistry` for cluster-wide worker lookup
4. Migrate `RoomStateBridge` to use new workers

#### Phase 3: Dual-Write (Week 3)

1. Update `RoomStore` to write real-time state to DocumentSyncWorker
2. Read from DocumentSyncWorker for collaborative state
3. Fall back to RoomStore/PostgreSQL for persistence
4. Validate data consistency between layers

#### Phase 4: Client Integration (Week 4+)

1. Design client-side Iroh integration (Flutter/web)
2. Implement ticket exchange for direct P2P sync
3. Test client-to-client synchronization
4. Remove server-only assumptions from protocol

### Failure Scenarios

| Scenario | Impact | Recovery |
|----------|--------|----------|
| IrohConnectionManager crash | All document workers restart | Automatic via supervision |
| DocumentSyncWorker crash | Single room loses real-time sync temporarily | Worker restarts, reloads from persisted doc |
| Iroh relay unreachable | Local changes continue, sync delayed | Automatic reconnection when relay returns |
| Network partition | Rooms partition by network segment | Merge on reconnection (CRDT guarantees) |
| PostgreSQL unavailable | Real-time sync continues, persistence queued | Retry persistence when DB returns |
| Full node crash | All rooms restart from PostgreSQL | Sync catches up via Iroh gossip |

### Observability

#### Telemetry Events

```elixir
# Connection health
[:sensocto, :iroh, :connection, :health_check]
[:sensocto, :iroh, :connection, :reconnect]

# Document operations
[:sensocto, :iroh, :document, :create]
[:sensocto, :iroh, :document, :change]
[:sensocto, :iroh, :document, :merge]

# Sync metrics
[:sensocto, :iroh, :sync, :send]
[:sensocto, :iroh, :sync, :receive]
[:sensocto, :iroh, :sync, :conflict]

# Blob operations
[:sensocto, :iroh, :blob, :store]
[:sensocto, :iroh, :blob, :fetch]
[:sensocto, :iroh, :blob, :gc]
```

#### Dashboard Metrics

- Active document workers (gauge)
- Sync latency percentiles (histogram)
- Gossip neighbor count (gauge)
- Conflict rate (counter)
- Blob storage size (gauge)

### Open Questions

1. **Document pruning** - How do we handle document growth for long-lived rooms? Automerge documents grow with history.

2. **Client authentication** - How do we authenticate clients joining the Iroh gossip network? Current design assumes server-mediated access.

3. **Blob replication** - What's the replication strategy for blobs? All nodes? On-demand?

4. **Cross-region sync** - How does sync latency affect UX for globally distributed users?

## Appendix A: Current Module Analysis

### Sensocto.Iroh.RoomStore

**Location:** `lib/sensocto/iroh/room_store.ex`

**Purpose:** Low-level Iroh document operations

**Issues Identified:**
- Creates new namespaces on each startup (no persistence)
- Single document per namespace (not per room)
- No cleanup of deleted rooms (tombstones accumulate)

**Recommended Changes:**
- Use `IrohConnectionManager` for node reference
- Persist namespace IDs for continuity
- Implement proper document lifecycle management

### Sensocto.Iroh.RoomSync

**Location:** `lib/sensocto/iroh/room_sync.ex`

**Purpose:** Async batched persistence to Iroh docs

**Issues Identified:**
- Good debouncing implementation
- Missing back-pressure when Iroh is slow
- Retry logic could lose changes on max retries

**Recommended Changes:**
- Add write queue with bounded size
- Persist failed changes to disk for recovery
- Add metrics for queue depth

### Sensocto.Iroh.RoomStateCRDT

**Location:** `lib/sensocto/iroh/room_state_crdt.ex`

**Purpose:** Real-time collaborative state using Automerge

**Issues Identified:**
- Good document structure
- Creates its own Iroh node (should share)
- In-memory only (documents don't persist across restarts)

**Recommended Changes:**
- Use `IrohConnectionManager` for shared node
- Persist document IDs for recovery
- Add subscriber notifications for change events

### Sensocto.Iroh.RoomStateBridge

**Location:** `lib/sensocto/iroh/room_state_bridge.ex`

**Purpose:** Bridges local state with CRDT layer

**Issues Identified:**
- Good PubSub integration
- Doesn't handle remote->local propagation fully
- Per-user bridge (should be per-room?)

**Recommended Changes:**
- Consider merging into DocumentSyncWorker
- Add bidirectional sync (not just local->remote)
- Clarify ownership of state updates

## Appendix B: Related Iroh Concepts

### Iroh Docs

Iroh documents are mutable key-value stores synchronized via the QUIC protocol. Each document has:

- **Namespace ID** - Unique identifier for the document
- **Author ID** - Identity used for write operations
- **Entries** - Key-value pairs with content hashes

### Automerge

Automerge is a CRDT library that provides:

- **Automatic merging** - Concurrent changes merge without conflicts
- **History** - Full history of changes is preserved
- **Types** - Maps, lists, text, counters with CRDT semantics

### Gossip

Iroh uses a gossip protocol for document synchronization:

- **Topics** - Channels for broadcasting updates
- **Neighbors** - Peer connections in the gossip network
- **Relays** - Public servers for NAT traversal

### Blobs

Iroh blobs are content-addressed binary data:

- **Content hash** - Unique identifier based on content
- **Tickets** - Portable references for fetching blobs
- **Providers** - Nodes that can serve the blob

## Appendix C: Supervision Strategy Comparison

| Strategy | Use When | Current Usage |
|----------|----------|---------------|
| `one_for_one` | Children are independent | Registry, Bio |
| `rest_for_one` | Later children depend on earlier ones | Storage (current) |
| `one_for_all` | All children must restart together | Not used |

**Recommendation:** Keep `rest_for_one` for the storage layer but with clearer dependency ordering as shown in the proposed architecture.

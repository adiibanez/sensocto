# Sensocto Architecture

Sensocto is a real-time sensor data platform built with Phoenix/Elixir, using the Ash framework for domain modeling and LiveView for reactive UI. The system features attention-aware back-pressure control, biomimetic resource management, and distributed room coordination via Horde.

**Last Updated:** January 2026

## System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                           SENSOCTO                                       │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────────────┐  │
│  │   Browser    │    │  Native App  │    │   External Connectors    │  │
│  │  (LiveView)  │    │   (SwiftUI)  │    │  (WebSocket/Channels)    │  │
│  └──────┬───────┘    └──────┬───────┘    └───────────┬──────────────┘  │
│         │                   │                        │                  │
│         └───────────────────┴────────────────────────┘                  │
│                             │                                           │
│                    ┌────────▼────────┐                                  │
│                    │  Phoenix/Web    │                                  │
│                    │   Endpoint      │                                  │
│                    └────────┬────────┘                                  │
│         ┌───────────────────┼───────────────────┐                       │
│         │                   │                   │                       │
│  ┌──────▼──────┐    ┌───────▼───────┐   ┌──────▼──────┐               │
│  │  LiveView   │    │   Channels    │   │   REST API  │               │
│  │  (UI)       │    │ (WebSocket)   │   │ (Auth/Data) │               │
│  └──────┬──────┘    └───────┬───────┘   └─────────────┘               │
│         │                   │                                           │
│         └───────────────────┴───────────────────┐                       │
│                                                 │                       │
│  ┌──────────────────────────────────────────────▼────────────────────┐ │
│  │                   7-Layer OTP Supervision Tree                     │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │ │
│  │  │ Bio Layer   │  │  Domain     │  │   Storage   │               │ │
│  │  │ (Adaptive)  │  │ (Sensors/   │  │   (Iroh/    │               │ │
│  │  │             │  │  Rooms)     │  │    CRDT)    │               │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                 │                       │
│                    ┌────────────────────────────▼──────────────────┐   │
│                    │              Ash Resources                     │   │
│                    │  Sensor | SensorAttribute | Room | User       │   │
│                    └────────────────────────────┬──────────────────┘   │
│                                                 │                       │
│  ┌──────────────────────────────────────────────▼────────────────────┐ │
│  │                      Persistence Layer                             │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │ │
│  │  │ PostgreSQL  │  │  In-Memory  │  │  P2P/Iroh   │               │ │
│  │  │ (Primary +  │  │  (RoomStore │  │  (Document  │               │ │
│  │  │  Replica)   │  │   Guest)    │  │   Sync)     │               │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

## OTP Supervision Tree

The application uses a hierarchical supervision tree with intermediate supervisors to create failure isolation domains. This prevents a flapping process in one domain from exhausting the restart budget and bringing down unrelated functionality.

See `lib/sensocto/application.ex` for the complete implementation:

```
Sensocto.Supervisor (root, :rest_for_one)
│
├── Layer 1: Infrastructure.Supervisor (:one_for_one)
│   ├── SensoctoWeb.Telemetry          # Metrics collection
│   ├── Task.Supervisor                # Async task pool
│   ├── Sensocto.Repo                  # Primary DB (Neon.tech PostgreSQL)
│   ├── Sensocto.Repo.Replica          # Read replica DB
│   ├── DNSCluster                     # Service discovery (Fly.io)
│   ├── Phoenix.PubSub                 # Inter-process messaging backbone
│   ├── SensoctoWeb.Presence           # User presence tracking
│   └── Finch                          # HTTP client pool
│
├── Layer 2: Registry.Supervisor (:one_for_one)
│   ├── Sensor Domain:
│   │   ├── SimpleSensorRegistry       # Sensor process lookup
│   │   ├── SimpleAttributeRegistry    # Attribute process lookup
│   │   ├── SensorPairRegistry         # Sensor pair coordination
│   │   └── Sensors.Registry (legacy)
│   ├── Room Domain:
│   │   ├── RoomRegistry               # Local room lookup
│   │   ├── RoomJoinCodeRegistry       # Join code mapping
│   │   ├── DistributedRoomRegistry (Horde)      # Cluster-wide room lookup
│   │   └── DistributedJoinCodeRegistry (Horde)  # Cluster-wide join codes
│   └── Feature Domains:
│       ├── CallRegistry               # WebRTC call processes
│       ├── MediaRegistry              # Media player processes
│       └── Object3DRegistry           # 3D viewer processes
│
├── Layer 3: Storage.Supervisor (:rest_for_one)
│   ├── Iroh.RoomStore                 # Low-level P2P document storage
│   ├── RoomStore                      # In-memory room state cache
│   ├── Iroh.RoomSync                  # Async persistence layer
│   ├── Iroh.RoomStateCRDT             # Real-time CRDT-based state
│   └── RoomPresenceServer             # Room presence tracking
│
├── Layer 4: Bio.Supervisor (:one_for_one) [Biomimetic Layer]
│   ├── NoveltyDetector                # Locus Coeruleus - anomaly detection
│   ├── PredictiveLoadBalancer         # Cerebellum - predictive resource mgmt
│   ├── HomeostaticTuner               # Synaptic Plasticity - homeostasis
│   ├── ResourceArbiter                # Lateral Inhibition - resource negotiation
│   └── CircadianScheduler             # SCN - temporal scheduling
│
├── Layer 5: Domain.Supervisor (:one_for_one)
│   ├── AttentionTracker               # Back-pressure control (ETS-backed)
│   ├── SystemLoadMonitor              # CPU/PubSub/Memory load tracking
│   ├── SensorsStateAgent              # Sensor state cache
│   ├── SensorsDynamicSupervisor       # Manages individual sensors
│   │   └── SensorSupervisor (per sensor, :one_for_one)
│   │       ├── SimpleSensor           # Per-sensor GenServer
│   │       └── AttributeStore         # Per-attribute data cache (Agent)
│   ├── RoomsDynamicSupervisor (Horde) # Distributed room management
│   │   └── RoomServer (per room, via Horde.Registry)
│   ├── CallSupervisor                 # WebRTC call management
│   ├── MediaPlayerSupervisor          # Media playback management
│   ├── Object3DPlayerSupervisor       # 3D object streaming
│   ├── RepoReplicatorPool             # Database sync pool (8 workers)
│   └── Search.SearchIndex             # Global search index
│
├── Layer 5.5: Accounts.GuestUserStore # In-memory guest user sessions (2h TTL)
│
├── Layer 6: SensoctoWeb.Endpoint      # Phoenix HTTP/WebSocket endpoint
│
├── Layer 7: AshAuthentication.Supervisor  # External auth supervisor
│
└── [Optional] Sensocto.Simulator.Supervisor (if enabled)
    ├── Simulator.Manager
    └── ConnectorSupervisor
        └── SensorServer (per simulated sensor)
```

### Supervision Strategy Rationale

**Root supervisor uses `:rest_for_one`** because later children depend on earlier ones. If Infrastructure crashes, Registries lose their PubSub. If Registries crash, Domain supervisors lose their lookup mechanism. The cascading restart ensures consistency.

**Intermediate supervisors use `:one_for_one`** (mostly) because their children are independent within each domain. A crashed sensor registry doesn't affect the room registry.

**Storage uses `:rest_for_one`** because RoomStore depends on Iroh.RoomStore, and RoomSync depends on both. Dependencies flow downward.

### Blast Radius Examples

| Crash Location | Impact | Recovery |
|----------------|--------|----------|
| Single sensor | Only that sensor restarts | Other sensors and rooms unaffected |
| Sensor registry | Brief lookup failure | Room processes survive and re-register |
| RoomServer | Only that room restarts | Other rooms continue, members reconnect |
| Iroh.RoomStore | All storage processes restart (rest_for_one) | Room domain stays up, temporary unavailability |
| Bio.NoveltyDetector | Novelty detection offline | Sensors continue at current settings |
| PubSub | Infrastructure restarts + all downstream | Full recovery via rest_for_one cascade |
| System load spike | SystemLoadMonitor broadcasts multipliers | AttentionTracker adjusts batch windows |

See `docs/supervision-tree.md` for interactive Mermaid diagrams of the supervision tree.

## Persistence Layer

Sensocto uses a multi-tier persistence architecture combining PostgreSQL, in-memory stores, and P2P distributed storage.

### Database Layer (PostgreSQL)

| Repository | Purpose | Configuration |
|------------|---------|---------------|
| `Sensocto.Repo` | Primary read/write | Neon.tech PostgreSQL 16+ |
| `Sensocto.Repo.Replica` | Read-only queries | Offloads read-heavy operations |

**Key files:**
- `lib/sensocto/repo.ex` - AshPostgres.Repo configuration

### In-Memory Storage

| Store | Type | Purpose | Persistence |
|-------|------|---------|-------------|
| `RoomStore` | GenServer | Room state cache | Synced to Iroh.RoomStore |
| `GuestUserStore` | GenServer | Temporary guest sessions | None (2-hour TTL) |
| `AttentionTracker` | GenServer + ETS | Attention levels | None (ephemeral) |
| `SystemLoadMonitor` | GenServer + ETS | Load metrics | None (ephemeral) |
| `NoveltyDetector` | GenServer + ETS | Anomaly statistics | None (ephemeral) |
| `AttributeStore` | Agent | Per-attribute data cache | None (latest values only) |

### P2P Distributed Storage (Iroh)

The Iroh layer provides distributed document sync for room state:

```
Iroh.RoomStore (low-level)
    ↓
RoomStore (in-memory cache)
    ↓
Iroh.RoomSync (async persistence)
    ↓
Iroh.RoomStateCRDT (real-time collaborative state)
```

**Key features:**
- CRDT-based conflict-free merging (Automerge)
- P2P sync without central coordination
- Used for media sync, 3D viewer state, presence

### ETS Tables

| Table | Owner | Purpose | Access |
|-------|-------|---------|--------|
| `:attention_tracker` | AttentionTracker | Attention levels | Fast O(1) lookup |
| `:system_load` | SystemLoadMonitor | Load metrics | Fast O(1) lookup |
| `:novelty_detector` | NoveltyDetector | Anomaly scores | Fast O(1) lookup |

**Why ETS?** Hot-path lookups (attention level per sensor) must avoid GenServer bottlenecks. ETS provides O(1) concurrent reads.

## GenServer Inventory

### Core GenServers

| GenServer | Location | Purpose | State Type |
|-----------|----------|---------|------------|
| `AttentionTracker` | `otp/attention_tracker.ex` | Back-pressure coordination | ETS + process state |
| `SystemLoadMonitor` | `otp/system_load_monitor.ex` | CPU/memory/PubSub monitoring | ETS + metrics |
| `SimpleSensor` | `otp/simple_sensor.ex` | Per-sensor data management | In-process map |
| `RoomServer` | `otp/room_server.ex` | Per-room state (Horde) | In-process map |
| `GuestUserStore` | `accounts/guest_user_store.ex` | Guest sessions | In-process map |

### Biomimetic GenServers

| GenServer | Biological Inspiration | Function |
|-----------|------------------------|----------|
| `NoveltyDetector` | Locus Coeruleus | Anomaly detection via Welford's algorithm |
| `PredictiveLoadBalancer` | Cerebellum | Predictive resource management |
| `HomeostaticTuner` | Synaptic Plasticity | System balance maintenance |
| `ResourceArbiter` | Lateral Inhibition | Competitive resource allocation |
| `CircadianScheduler` | SCN (Suprachiasmatic Nucleus) | Time-of-day scheduling |

### Dynamic Supervisors

| Supervisor | Child Type | Distribution |
|------------|------------|--------------|
| `SensorsDynamicSupervisor` | SensorSupervisor | Local (per-node) |
| `RoomsDynamicSupervisor` | RoomServer | Horde (cluster-wide) |
| `CallSupervisor` | CallServer | Local (per-node) |
| `MediaPlayerSupervisor` | MediaPlayerServer | Local (per-node) |
| `Object3DPlayerSupervisor` | Object3DPlayerServer | Local (per-node) |

## Key Components

### 1. Sensor Data Flow

```
External Device → WebSocket Channel → SimpleSensor → AttributeStore → LiveView
                                           │
                                           ↓
                                    AttentionTracker
                                    (adjusts batch rates)
```

**Key files:**
- `lib/sensocto/otp/simple_sensor.ex` - Per-sensor GenServer
- `lib/sensocto/otp/attribute_store.ex` - Per-attribute data cache
- `lib/sensocto_web/channels/sensor_data_channel.ex` - WebSocket protocol

### 2. Attention System

The attention system provides intelligent back-pressure to reduce resource usage:

| Level | Trigger | Batch Window | Use Case |
|-------|---------|--------------|----------|
| `:high` | User focused | 100ms | Active interaction |
| `:medium` | In viewport | 500ms | Viewing sensor |
| `:low` | Connected, not viewed | 2000ms | Background |
| `:none` | Disconnected | 5000ms | Idle |

**Key files:**
- `lib/sensocto/otp/attention_tracker.ex` - Central coordinator (ETS-backed)
- `assets/js/hooks/attention_tracker.js` - Browser visibility tracking
- See `docs/attention-system.md` for detailed documentation

### 3. Rooms & Collaboration

Rooms allow multiple users to share sensor data:

```
Room (Ash Resource)
├── RoomServer (GenServer) - In-memory state
├── RoomMembership - User access control
└── Sensors - Shared sensor references
```

**Key files:**
- `lib/sensocto/rooms.ex` - Room domain module
- `lib/sensocto_web/live/rooms/` - Room LiveViews

### 4. Ash Framework Integration

The project uses [Ash](https://ash-hq.org) for domain modeling:

**Domains:**

| Domain | Purpose |
|--------|---------|
| `Sensocto.Accounts` | User authentication, OAuth, tokens, preferences |
| `Sensocto.Sensors` | Sensors, rooms, connectors, types, attributes |

**Accounts Domain Resources:**
| Resource | Purpose |
|----------|---------|
| `User` | Authentication (OAuth, magic links, password) |
| `Token` | JWT tokens with 14-day lifetime |
| `UserPreference` | User settings and preferences |

**Sensors Domain Resources:**
| Resource | Purpose |
|----------|---------|
| `Sensor` | Sensor metadata (name, type, MAC address) |
| `SensorAttribute` | Attribute definitions per sensor type |
| `SensorAttributeData` | Historical data points |
| `SensorType` | Sensor categories |
| `Connector` | Connection protocols (BLE, WiFi, Simulator) |
| `ConnectorSensorType` | Connector ↔ SensorType relationships |
| `Room` | Collaboration spaces |
| `RoomMembership` | User access to rooms |
| `RoomSensorType` | Room-specific sensor configuration |
| `SensorConnection` | Sensor connectivity tracking |
| `SensorSensorConnection` | Sensor-to-sensor relationships |
| `SimulatorScenario` | Simulation scenarios |
| `SimulatorConnector` | Simulator connector instances |
| `SimulatorTrackPosition` | Simulated position tracking |
| `SimulatorBatteryState` | Simulated battery state |

**Authentication:**
- Ash Authentication with Google OAuth, magic links, password reset
- 14-day token lifetime with stored tokens for revocation
- GuestUserStore for session-only guest users (not Ash-managed)

### 5. Web Layer

**Route Structure:**
| Path | Module | Description |
|------|--------|-------------|
| `/` | `IndexLive` | Landing page (authenticated) |
| `/sense` | `SenseLive` | Main sensor dashboard |
| `/sensors` | `SensorLive.Index` | Sensor list |
| `/sensors/:id` | `SensorLive.Show` | Sensor detail view |
| `/lobby` | `LobbyLive` | Sensor lobby (with sub-routes for heartrate, imu, etc.) |
| `/rooms` | `RoomListLive` | Room listing |
| `/rooms/new` | `RoomListLive` | Create new room |
| `/rooms/:id` | `RoomShowLive` | Room detail view |
| `/rooms/:id/settings` | `RoomShowLive` | Room settings |
| `/rooms/join/:code` | `RoomJoinLive` | Join room via code (auth optional) |
| `/simulator` | `SimulatorLive` | Simulator controls |
| `/playground` | `PlaygroundLive` | Development playground |
| `/realitykit` | `RealitykitLive` | RealityKit integration |
| `/iroh-gossip` | `IrohGossipLive` | P2P gossip viewer |
| `/admin/dashboard` | Phoenix LiveDashboard | System monitoring |
| `/admin/ash-admin` | AshAdmin | Database admin |
| `/dev/mailbox` | Swoosh MailboxPreview | Dev email preview |

**Authentication:**
- Ash Authentication with Google OAuth support
- Bearer token for API access
- Magic link sign-in (with confirmation page)
- Session-based authentication for LiveViews

## Data Flow Examples

### Sensor Data Ingestion

```
1. External connector joins channel: "sensor:ABC123"
2. Connector sends: {"data": {"temp": 23.5, "humidity": 65}}
3. SensorDataChannel receives and routes to SimpleSensor
4. SimpleSensor updates AttributeStore(s)
5. SimpleSensor broadcasts via PubSub: "sensor:ABC123:data"
6. Subscribed LiveViews receive and update UI
```

### Attention-Aware Updates

```
1. User scrolls sensor into viewport
2. JS Hook detects visibility, sends "view_enter" event
3. LiveView calls AttentionTracker.register_view/3
4. AttentionTracker updates ETS, broadcasts attention change
5. SimpleSensor receives attention change via PubSub
6. SimpleSensor adjusts batch_window accordingly
7. Connector receives backpressure_config via channel
```

## Configuration

### Environment-Based

| Environment | Config File | Key Differences |
|-------------|-------------|-----------------|
| dev | `config/dev.exs` | Local PostgreSQL, hot reload, debug |
| test | `config/test.exs` | Sandbox pool, async tests |
| prod | `config/runtime.exs` | Env vars, SSL, clustering |

### Runtime Configuration

Key environment variables (see `.env.sample`):
- `DATABASE_URL` - PostgreSQL connection
- `SECRET_KEY_BASE` - Phoenix signing key
- `GOOGLE_CLIENT_*` - OAuth credentials
- `SIMULATOR_ENABLED` - Enable sensor simulation
- `FLY_DEPLOY_BUCKET` - Hot code upgrade storage

## Technology Stack

| Layer | Technology |
|-------|------------|
| Language | Elixir 1.19.4, OTP 27 |
| Web Framework | Phoenix 1.7 |
| Real-time UI | Phoenix LiveView 1.0 |
| Frontend | Svelte 5 (via live_svelte), Tailwind CSS, DaisyUI |
| Domain Framework | Ash 3.0 |
| Database | PostgreSQL 16+ (Neon.tech) with AshPostgres |
| Authentication | Ash Authentication (OAuth, magic links, password) |
| Process Management | OTP GenServers, DynamicSupervisors, Horde |
| P2P Storage | Iroh (distributed document sync) with Automerge CRDTs |
| WebRTC | Membrane RTC Engine with ex_webrtc |
| Deployment | Fly.io with hot code upgrades (FlyDeploy) |
| HTTP Client | Finch, Req |
| Clustering | Horde, DNSCluster, libcluster |

## Further Reading

**Core Documentation:**
- `docs/attention-system.md` - Back-pressure system details
- `docs/deployment.md` - Production deployment
- `docs/simulator-integration.md` - Sensor simulation
- `docs/scalability.md` - Scaling characteristics and tuning
- `docs/beam-vm-tuning.md` - BEAM VM optimization
- `docs/supervision-tree.md` - Mermaid diagrams of supervision tree

**Architecture & Planning:**
- `docs/CLUSTERING_PLAN.md` - Distributed clustering roadmap
- `docs/room-markdown-format.md` - Room document format specification
- `docs/attributes.md` - Supported sensor attribute types
- `docs/letsgobio.md` - Biomimetic layer documentation

**Agent Reports (`.claude/agents/reports/`):**
- `resilient-systems-architect-report.md` - OTP architecture assessment
- `security-advisor-report.md` - Security posture analysis
- `livebook-tester-report.md` - Testing strategy and coverage
- `interdisciplinary-innovator-report.md` - Biomimetic patterns analysis
- `api-client-developer-report.md` - API client development guide
- `elixir-test-accessibility-expert-report.md` - Testing and accessibility audit

**External Documentation:**
- [Ash Framework Docs](https://hexdocs.pm/ash)
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Membrane RTC Engine](https://hexdocs.pm/membrane_rtc_engine)
- [Iroh Docs](https://iroh.computer/docs)
- [Horde Documentation](https://hexdocs.pm/horde)

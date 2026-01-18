# Sensocto Architecture

Sensocto is a real-time sensor data platform built with Phoenix/Elixir, using the Ash framework for domain modeling and LiveView for reactive UI.

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
│  │                        OTP Layer                                   │ │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐               │ │
│  │  │ Attention   │  │  Sensors    │  │   Rooms     │               │ │
│  │  │ Tracker     │  │ Supervisor  │  │ Supervisor  │               │ │
│  │  └─────────────┘  └─────────────┘  └─────────────┘               │ │
│  └───────────────────────────────────────────────────────────────────┘ │
│                                                 │                       │
│                    ┌────────────────────────────▼──────────────────┐   │
│                    │              Ash Resources                     │   │
│                    │  Sensor | SensorAttribute | Room | User       │   │
│                    └────────────────────────────┬──────────────────┘   │
│                                                 │                       │
│                    ┌────────────────────────────▼──────────────────┐   │
│                    │              PostgreSQL                        │   │
│                    └───────────────────────────────────────────────┘   │
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
│   ├── Sensocto.Repo                  # Database connection pool
│   ├── Phoenix.PubSub                 # Inter-process messaging
│   ├── SensoctoWeb.Sensocto.Presence  # User presence tracking
│   ├── DNSCluster                     # Service discovery (Fly.io)
│   └── Finch                          # HTTP client pool
│
├── Layer 2: Registry.Supervisor (:one_for_one)
│   ├── Sensocto.SimpleSensorRegistry
│   ├── Sensocto.SimpleAttributeRegistry
│   ├── Sensocto.RoomRegistry
│   ├── Sensocto.RoomJoinCodeRegistry
│   ├── Sensocto.CallRegistry
│   ├── Sensocto.MediaRegistry
│   └── Sensocto.Object3DRegistry
│
├── Layer 3: Storage.Supervisor (:rest_for_one)
│   ├── Iroh.RoomStore                 # P2P room document storage
│   ├── RoomStore                      # Room state persistence
│   ├── Iroh.RoomSync                  # Room sync coordination
│   └── RoomStateCRDT                  # CRDT-based state merging
│
├── Layer 4: Bio.Supervisor (:one_for_one)
│   ├── NoveltyDetector                # Adaptive novelty detection
│   ├── PredictiveLoadBalancer         # Predictive resource management
│   ├── HomeostaticTuner               # System homeostasis
│   └── [Biomimetic layer processes]
│
├── Layer 5: Domain.Supervisor (:one_for_one)
│   ├── Sensocto.AttentionTracker      # Back-pressure control (ETS-backed)
│   ├── Sensocto.SensorsDynamicSupervisor
│   │   └── SensorSupervisor (per sensor)
│   │       ├── SimpleSensor (GenServer)
│   │       └── AttributeStore (Agent per attribute)
│   ├── Sensocto.RoomsDynamicSupervisor
│   │   └── RoomServer (per room)
│   ├── Sensocto.CallSupervisor        # WebRTC call management
│   ├── Sensocto.MediaPlayerSupervisor # Media playback
│   └── Sensocto.Object3DPlayerSupervisor  # 3D object streaming
│
├── Layer 6: SensoctoWeb.Endpoint      # Phoenix endpoint
├── Layer 7: AshAuthentication.Supervisor  # Auth management
│
└── [Optional] Sensocto.Simulator.Supervisor
    ├── Sensocto.Simulator.Manager
    └── ConnectorSupervisor
        └── SensorServer (per simulated sensor)
            └── AttributeServer (per attribute)
```

### Supervision Strategy Rationale

**Root supervisor uses `:rest_for_one`** because later children depend on earlier ones. If Infrastructure crashes, Registries lose their PubSub. If Registries crash, Domain supervisors lose their lookup mechanism. The cascading restart ensures consistency.

**Intermediate supervisors use `:one_for_one`** (mostly) because their children are independent within each domain. A crashed sensor registry doesn't affect the room registry.

**Storage uses `:rest_for_one`** because RoomStore depends on Iroh.RoomStore, and RoomSync depends on both. Dependencies flow downward.

### Blast Radius Examples

- Media player crash: Only that room's player restarts. No other impact.
- Sensor registry crash: Sensor lookups fail briefly. Rooms unaffected.
- Iroh.RoomStore crash: All storage processes restart. Domains stay up.
- Infrastructure crash: Everything restarts in order. Full recovery.

See `docs/supervision-tree.md` for interactive Mermaid diagrams of the supervision tree.

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

**Resources:**
| Resource | Location | Purpose |
|----------|----------|---------|
| `User` | `lib/sensocto/accounts/user.ex` | Authentication |
| `Sensor` | `lib/sensocto/sensors/sensor.ex` | Sensor metadata |
| `SensorAttribute` | `lib/sensocto/sensors/sensor_attribute.ex` | Attribute definitions |
| `SensorAttributeData` | `lib/sensocto/sensors/sensor_attribute_data.ex` | Historical data |
| `SensorType` | `lib/sensocto/sensors/sensor_type.ex` | Sensor categories |
| `Connector` | `lib/sensocto/sensors/connector.ex` | Connection protocols |
| `Room` | `lib/sensocto/sensors/room.ex` | Collaboration spaces |

**Domains:**
- `Sensocto.Accounts` - User management
- `Sensocto.Sensors` - Sensor domain

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
| Database | PostgreSQL with Ecto |
| Authentication | Ash Authentication (OAuth, magic links) |
| Process Management | OTP GenServers, DynamicSupervisors, Horde |
| P2P Storage | Iroh (distributed document sync) |
| WebRTC | Membrane RTC Engine with ex_webrtc |
| Deployment | Fly.io with hot code upgrades (FlyDeploy) |
| HTTP Client | Finch, Req |

## Further Reading

**Core Documentation:**
- `docs/attention-system.md` - Back-pressure system details
- `docs/deployment.md` - Production deployment
- `docs/simulator-integration.md` - Sensor simulation
- `docs/scalability.md` - Scaling characteristics and tuning
- `docs/beam-vm-tuning.md` - BEAM VM optimization

**Architecture & Planning:**
- `docs/CLUSTERING_PLAN.md` - Distributed clustering roadmap
- `docs/room-markdown-format.md` - Room document format specification
- `docs/attributes.md` - Supported sensor attribute types

**External Documentation:**
- [Ash Framework Docs](https://hexdocs.pm/ash)
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)
- [Membrane RTC Engine](https://hexdocs.pm/membrane_rtc_engine)
- [Iroh Docs](https://iroh.computer/docs)

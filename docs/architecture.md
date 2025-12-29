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

The application starts the following processes (see `lib/sensocto/application.ex`):

```
Sensocto.Supervisor (one_for_one)
│
├── SensoctoWeb.Telemetry          # Metrics collection
├── Sensocto.Repo                  # Database connection pool
├── Sensocto.Otp.BleConnectorGenServer  # BLE device connector
├── SensorsStateAgent              # RealityKit state
│
├── Registries (process discovery)
│   ├── Sensocto.TestRegistry
│   ├── Sensocto.Sensors.Registry
│   ├── Sensocto.Sensors.SensorRegistry
│   ├── Sensocto.SimpleAttributeRegistry
│   ├── Sensocto.SimpleSensorRegistry
│   ├── Sensocto.SensorPairRegistry
│   ├── Sensocto.RoomRegistry
│   └── Sensocto.RoomJoinCodeRegistry
│
├── Sensocto.Otp.Connector         # Connection manager
├── DNSCluster                     # Service discovery (Fly.io)
├── Phoenix.PubSub                 # Inter-process messaging
├── SensoctoWeb.Sensocto.Presence  # User presence tracking
├── Sensocto.AttentionTracker      # Back-pressure control
│
├── Sensocto.SensorsDynamicSupervisor  # Dynamic sensor processes
│   └── SensorSupervisor (per sensor)
│       ├── SimpleSensor (GenServer)
│       └── AttributeStore (Agent per attribute)
│
├── Sensocto.RoomsDynamicSupervisor    # Dynamic room processes
│   └── RoomServer (per room)
│
├── Sensocto.Otp.RepoReplicator    # DB sync helper
├── Finch                          # HTTP client pool
├── SensoctoWeb.Endpoint           # Phoenix endpoint
├── AshAuthentication.Supervisor   # Auth management
│
└── [Optional] Sensocto.Simulator.Supervisor
    ├── Sensocto.Simulator.Manager
    └── ConnectorSupervisor
        └── SensorServer (per simulated sensor)
            └── AttributeServer (per attribute)
```

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
| `/` | `IndexLive` | Landing page |
| `/sense` | `SenseLive` | Main sensor dashboard |
| `/sensors` | `SensorLive.Index` | Sensor list |
| `/rooms/*` | `RoomListLive`, `RoomShowLive` | Room management |
| `/simulator` | `SimulatorLive` | Simulator controls |
| `/admin/dashboard` | Phoenix LiveDashboard | System monitoring |
| `/admin/ash-admin` | AshAdmin | Database admin |

**Authentication:**
- Ash Authentication with Google OAuth support
- Bearer token for API access
- Magic link sign-in

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
| Process Management | OTP GenServers, DynamicSupervisors |
| Deployment | Fly.io with hot code upgrades |

## Further Reading

- `docs/attention-system.md` - Back-pressure system details
- `docs/deployment.md` - Production deployment
- `docs/simulator-integration.md` - Sensor simulation
- [Ash Framework Docs](https://hexdocs.pm/ash)
- [Phoenix LiveView Docs](https://hexdocs.pm/phoenix_live_view)

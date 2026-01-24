# SensOcto Project Structure Analysis

## Overview

SensOcto is a real-time sensor data platform built with Phoenix/Elixir that enables:
- BLE sensor connectivity via Web Bluetooth API
- Real-time data visualization with Svelte components
- Collaborative "rooms" for sharing sensor streams
- P2P synchronization via Iroh
- WebRTC-based audio/video calls

## Directory Structure

```
sensocto/
├── lib/
│   ├── sensocto/                    # Core business logic
│   │   ├── accounts/                # User authentication (Ash)
│   │   ├── sensors/                 # Sensor domain models (Ash resources)
│   │   ├── media/                   # Playlists for 3D objects
│   │   ├── iroh/                    # P2P sync via Iroh protocol
│   │   ├── otp/                     # GenServers & supervision
│   │   │   ├── simple_sensor.ex     # Per-sensor state GenServer
│   │   │   ├── room_store.ex        # In-memory room state (1300+ lines)
│   │   │   ├── attribute_store_tiered.ex  # Hot/warm/cold data tiers
│   │   │   └── repo_replicator_pool.ex    # Batched DB writes
│   │   └── types/                   # Custom Ecto/Ash types
│   ├── sensocto_web/
│   │   ├── channels/                # Phoenix Channels
│   │   │   └── sensor_data_channel.ex  # Main sensor WebSocket
│   │   ├── live/                    # LiveView modules
│   │   │   ├── index_live.ex        # Dashboard
│   │   │   ├── lobby_live.ex        # Landing/room list
│   │   │   ├── sense_live.ex        # Sensor visualization
│   │   │   ├── stateful_sensor_live.ex  # Individual sensor view
│   │   │   └── rooms/               # Room management views
│   │   ├── components/              # Reusable components
│   │   └── controllers/             # Traditional HTTP controllers
│   └── sensocto.ex                  # Application entry point
├── assets/
│   ├── js/
│   │   ├── app.js                   # Main JS entry
│   │   ├── hooks.js                 # LiveView JS hooks
│   │   ├── ble.js                   # Web Bluetooth integration
│   │   └── webrtc/                  # WebRTC call hooks
│   ├── svelte/                      # Svelte components (32 files)
│   │   ├── SenseApp.svelte          # Main sensor container
│   │   ├── ECGVisualization.svelte  # ECG waveform canvas
│   │   ├── HeartbeatVisualization.svelte
│   │   ├── IMU.svelte               # 3D orientation
│   │   ├── Map.svelte               # Geolocation display
│   │   └── bluetooth-utils.js       # BLE UUID mapping & decoders
│   └── css/                         # Tailwind CSS
├── priv/
│   └── repo/migrations/             # Ecto migrations
└── config/                          # Runtime configuration
```

## Key Dependencies

### Core Framework
- **Phoenix 1.7+**: Web framework with LiveView
- **Ash Framework 3.x**: Declarative domain modeling
- **Ecto**: Database layer with PostgreSQL

### Real-Time & Networking
- **Phoenix PubSub**: Internal event distribution
- **Phoenix Channels**: WebSocket-based sensor data ingestion
- **Iroh (iroh_ex)**: P2P document synchronization
- **ex_webrtc**: WebRTC for audio/video calls

### Frontend
- **LiveView**: Server-rendered reactive UI
- **Svelte**: Client-side visualizations (compiled via esbuild)
- **TailwindCSS**: Utility-first styling

### Sensor Integration
- **Web Bluetooth API**: BLE connectivity (JS-side)
- **Custom decoders**: Per-device data parsing (Thingy:52, Movesense, Polar)

### Storage
- **PostgreSQL**: Primary persistence
- **ETS**: Hot data tier (in-memory)
- **Tiered AttributeStore**: Hot/warm/cold data management

## Supervision Tree

```
Application
├── Sensocto.Repo (PostgreSQL)
├── Sensocto.Repo.Replica (Read replica)
├── SensoctoWeb.Telemetry
├── Sensocto.PubSub
├── SensoctoWeb.Presence
├── Registry (SimpleSensorRegistry)
├── DynamicSupervisor (SimpleSensorSupervisor)
├── Sensocto.Otp.RepoReplicatorPool
├── Sensocto.Otp.RoomStore
├── Sensocto.Iroh.Supervisor
│   ├── Iroh Node
│   └── RoomSync workers
└── SensoctoWeb.Endpoint
```

## Data Flow Architecture

```
┌─────────────┐     ┌─────────────────┐     ┌──────────────────┐
│   Browser   │     │  Phoenix        │     │   GenServer      │
│   (BLE)     │────>│  Channel        │────>│   SimpleSensor   │
│             │     │                 │     │                  │
└─────────────┘     └─────────────────┘     └────────┬─────────┘
                                                      │
                    ┌─────────────────┐               │
                    │   PubSub        │<──────────────┘
                    │                 │
                    └────────┬────────┘
                             │
              ┌──────────────┼──────────────┐
              ▼              ▼              ▼
       ┌──────────┐   ┌──────────┐   ┌──────────┐
       │ LiveView │   │ LiveView │   │  Iroh    │
       │ Client A │   │ Client B │   │  Sync    │
       └──────────┘   └──────────┘   └──────────┘
```

## Build & Development

```bash
# Install dependencies
mix deps.get
npm install --prefix assets

# Database setup
mix ecto.create
mix ecto.migrate

# Run development server
mix phx.server

# Build assets
npm run build --prefix assets
```

## Environment Configuration

Key environment variables:
- `DATABASE_URL`: PostgreSQL connection
- `SECRET_KEY_BASE`: Phoenix secret
- `IROH_*`: P2P sync configuration
- `PHX_HOST`: Public hostname

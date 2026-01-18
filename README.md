# Sensocto

A real-time sensor data platform built with Phoenix/Elixir, featuring intelligent back-pressure control, multi-user collaboration rooms, and seamless sensor simulation.

## Features

- **Real-time Sensor Monitoring** - LiveView-powered dashboard with sub-second updates
- **Attention-Aware Back-Pressure** - Intelligent batching based on user viewport/focus
- **Collaboration Rooms** - Share sensor data with team members via QR codes
- **P2P Storage** - Distributed room state via Iroh document sync
- **Video/Voice Calls** - WebRTC calling via Membrane RTC Engine
- **Sensor Simulation** - Built-in simulator for development and testing
- **Hot Code Deployment** - Zero-downtime updates on Fly.io
- **Biomimetic Resource Management** - Adaptive system load balancing

## Quick Start

```bash
# Install dependencies and set up database
cp .env.sample .env
# Edit .env with your credentials
source .env
mix setup

# Start the server
mix phx.server
```

Visit [http://localhost:4000](http://localhost:4000)

See [docs/getting-started.md](docs/getting-started.md) for detailed setup instructions.

## Documentation

| Document | Description |
|----------|-------------|
| [Getting Started](docs/getting-started.md) | Local development setup |
| [Architecture](docs/architecture.md) | System overview, OTP supervision tree |
| [Supervision Tree](docs/supervision-tree.md) | Mermaid diagrams of supervision tree |
| [Attention System](docs/attention-system.md) | Back-pressure and viewport tracking |
| [Scalability](docs/scalability.md) | Performance analysis and tuning |
| [Deployment](docs/deployment.md) | Fly.io deployment, hot code upgrades |
| [Simulator Integration](docs/simulator-integration.md) | Sensor simulation system |
| [BEAM VM Tuning](docs/beam-vm-tuning.md) | BEAM VM optimization guide |
| [Clustering Plan](docs/CLUSTERING_PLAN.md) | Distributed clustering roadmap |

## Technology Stack

- **Backend:** Elixir 1.19.4, OTP 27, Phoenix 1.7, Ash Framework 3.0
- **Frontend:** Phoenix LiveView 1.0, Svelte 5, Tailwind CSS, DaisyUI
- **Database:** PostgreSQL with Ecto
- **Real-time:** Phoenix Channels, PubSub
- **P2P:** Iroh distributed document sync
- **WebRTC:** Membrane RTC Engine with ex_webrtc
- **Deployment:** Fly.io with hot code upgrades

## Project Structure

```
lib/
├── sensocto/              # Business logic
│   ├── infrastructure/    # Core infrastructure supervisor
│   ├── registry/          # Process registries
│   ├── storage/           # Iroh & room storage
│   ├── bio/               # Biomimetic layer
│   ├── domain/            # Domain supervisor
│   ├── otp/               # GenServers, supervisors
│   ├── sensors/           # Ash resources
│   ├── rooms/             # Collaboration
│   ├── calls/             # WebRTC calling
│   └── simulator/         # Sensor simulation
└── sensocto_web/          # Web layer
    ├── live/              # LiveView modules
    ├── components/        # UI components
    └── channels/          # WebSocket handlers
```

## Development

```bash
# Run tests
mix test

# Code quality
mix credo

# Interactive console
iex -S mix phx.server
```

## License

Proprietary

# Sensocto

A real-time sensor data platform built with Phoenix/Elixir, featuring intelligent back-pressure control, multi-user collaboration rooms, and seamless sensor simulation.

## Features

- **Real-time Sensor Monitoring** - LiveView-powered dashboard with sub-second updates
- **Attention-Aware Back-Pressure** - Intelligent batching based on user viewport/focus
- **Collaboration Rooms** - Share sensor data with team members via QR codes
- **Sensor Simulation** - Built-in simulator for development and testing
- **Hot Code Deployment** - Zero-downtime updates on Fly.io

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
| [Attention System](docs/attention-system.md) | Back-pressure and viewport tracking |
| [Deployment](docs/deployment.md) | Fly.io deployment, hot code upgrades |
| [Simulator Integration](docs/simulator-integration.md) | Sensor simulation system |

## Technology Stack

- **Backend:** Elixir 1.19, Phoenix 1.7, Ash Framework 3.0
- **Frontend:** Phoenix LiveView, Svelte 5, Tailwind CSS, DaisyUI
- **Database:** PostgreSQL with Ecto
- **Real-time:** Phoenix Channels, PubSub
- **Deployment:** Fly.io with hot code upgrades

## Project Structure

```
lib/
├── sensocto/           # Business logic
│   ├── otp/            # GenServers, supervisors
│   ├── sensors/        # Ash resources
│   ├── rooms/          # Collaboration
│   └── simulator/      # Sensor simulation
└── sensocto_web/       # Web layer
    ├── live/           # LiveView modules
    ├── components/     # UI components
    └── channels/       # WebSocket handlers
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

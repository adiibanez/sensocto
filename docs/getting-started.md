# Getting Started with Sensocto

This guide will get you from zero to a running development environment in about 10 minutes.

## Prerequisites

### Required
- **Elixir 1.19.4** with OTP 27 (see `.tool-versions`)
- **PostgreSQL 16+** running locally
- **Node.js 20+** (for asset building)

### Recommended
- **asdf** for version management
- **VS Code** with ElixirLS extension

## Quick Start

### 1. Install Elixir/Erlang (using asdf)

```bash
# Install asdf plugins
asdf plugin add erlang
asdf plugin add elixir

# Install versions from .tool-versions
asdf install

# Verify
elixir --version  # Should show 1.19.4
```

### 2. Set Up Environment Variables

```bash
# Copy the sample env file
cp .env.sample .env
```

Edit `.env` and set at minimum:
```bash
export MIX_ENV=dev
export AUTH_USERNAME=admin
export AUTH_PASSWORD=your_password_here
export ERLANG_COOKIE=sensocto_dev_cookie
```

**Optional for full features:**
- `GOOGLE_CLIENT_ID` / `GOOGLE_CLIENT_SECRET` - Google OAuth login
- `SMTP2GO_APIKEY` - Email sending

### 3. Start PostgreSQL

If using Docker:
```bash
docker-compose up -d db
```

Or ensure PostgreSQL is running locally on port 5432 with:
- Username: `postgres`
- Password: `postgres`

### 4. Install Dependencies and Set Up Database

```bash
# Source environment
source .env

# Run setup (installs deps, creates DB, runs migrations, builds assets)
mix setup
```

### 5. Start the Development Server

```bash
# Option A: Standard Phoenix server
mix phx.server

# Option B: Interactive shell (recommended)
iex -S mix phx.server

# Option C: Using the run script
./run.sh
```

### 6. Access the Application

- **Main App:** http://localhost:4000
- **HTTPS:** https://localhost:4001 (self-signed cert)
- **Live Dashboard:** http://localhost:4000/admin/dashboard (requires AUTH_USERNAME/PASSWORD)
- **Dev Mailbox:** http://localhost:4000/dev/mailbox

## What's Next?

### Key Files to Explore

| File | Description |
|------|-------------|
| `lib/sensocto/application.ex` | OTP supervision tree - see all running processes |
| `lib/sensocto_web/router.ex` | All routes and authentication setup |
| `lib/sensocto_web/live/sense_live.ex` | Main dashboard LiveView |
| `mix.exs` | Dependencies and mix aliases |

### Documentation

| Doc | Description |
|-----|-------------|
| `docs/architecture.md` | System overview and OTP processes |
| `docs/attention-system.md` | Back-pressure and attention tracking |
| `docs/scalability.md` | Scaling characteristics and performance |
| `docs/deployment.md` | Fly.io deployment and hot code upgrades |
| `docs/simulator-integration.md` | Sensor simulation system |
| `docs/beam-vm-tuning.md` | BEAM VM optimization guide |
| `docs/CLUSTERING_PLAN.md` | Distributed clustering roadmap |
| `docs/attributes.md` | Supported sensor attribute types |

### Common Tasks

```bash
# Run tests
mix test

# Run code quality checks
mix credo

# Generate a new migration
mix ecto.gen.migration add_something

# Reset database
mix ecto.reset

# Update dependencies
mix deps.update --all
```

## Troubleshooting

### Database Connection Failed
- Ensure PostgreSQL is running: `pg_isready`
- Check credentials in `config/dev.exs`
- Try: `docker-compose up -d db`

### Asset Build Errors
```bash
cd assets && npm install && cd ..
mix assets.build
```

### Port Already in Use
```bash
# Kill process on port 4000
lsof -i :4000 | awk 'NR>1 {print $2}' | xargs kill
```

### Environment Variables Not Loaded
```bash
# Make sure to source before running mix
source .env
mix phx.server
```

## Development Tools

### Interactive Console
```bash
iex -S mix phx.server
```

Useful IEx commands:
```elixir
# List running sensors
Registry.select(Sensocto.SimpleSensorRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}])

# Check attention levels
Sensocto.AttentionTracker.get_all_states()

# Trigger recompilation
recompile()
```

### Live Dashboard
Access at `/admin/dashboard` to see:
- Process memory usage
- ETS table stats
- Custom sensor metrics

### LiveDebugger
Enabled in dev mode - see floating debug panel in browser.

## Project Structure Overview

```
sensocto/
├── lib/
│   ├── sensocto/                  # Business logic
│   │   ├── application.ex         # Root supervision tree
│   │   ├── infrastructure/        # Core infrastructure supervisor
│   │   ├── registry/              # Process registries supervisor
│   │   ├── storage/               # Storage & Iroh supervisor
│   │   ├── bio/                   # Biomimetic layer supervisor
│   │   ├── domain/                # Domain logic supervisor
│   │   ├── otp/                   # GenServers, supervisors
│   │   ├── sensors/               # Ash resources for sensors
│   │   ├── rooms/                 # Collaboration features
│   │   ├── calls/                 # WebRTC video/voice calling
│   │   └── simulator/             # Sensor simulation
│   └── sensocto_web/              # Web layer
│       ├── live/                  # LiveView modules
│       ├── components/            # UI components
│       └── channels/              # WebSocket channels
├── assets/                        # Frontend (Svelte + Tailwind)
├── config/                        # Environment configs
├── priv/repo/migrations/          # Database migrations
├── test/                          # Test suite
└── docs/                          # Documentation
```

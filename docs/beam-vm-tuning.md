# BEAM VM Tuning Guide

This guide documents BEAM (Erlang VM) configuration options for optimizing Sensocto's performance and memory usage.

## Quick Start

The `run.sh` script supports BEAM VM flags through the `ERL_FLAGS` environment variable:

```bash
# In run.sh
ERL_FLAGS="+hms 8388608"
iex --erl "$ERL_FLAGS" --name $NODE_NAME --cookie testlitest -S mix phx.server
```

## Common Tuning Scenarios

### 1. High Memory Availability (Performance Mode)

Use this when you have plenty of RAM and want maximum performance:

```bash
ERL_FLAGS="+hms 8388608 +hmbs 46422 +A 128 +SDio 128"
```

| Flag | Value | Description |
|------|-------|-------------|
| `+hms` | 8388608 | 8MB default heap per process (default: ~233 words) |
| `+hmbs` | 46422 | Binary virtual heap size |
| `+A` | 128 | Async thread pool size (default: 1) |
| `+SDio` | 128 | Dirty IO schedulers |

### 2. Low Memory Mode (Constrained Environments)

Use this on systems with limited RAM:

```bash
ERL_FLAGS="+hms 233 +hmbs 46422 +MBas aoffcbf +MMmcs 30"
```

| Flag | Value | Description |
|------|-------|-------------|
| `+hms` | 233 | Small default heap (more frequent GC) |
| `+hmbs` | 46422 | Binary virtual heap size |
| `+MBas` | aoffcbf | Address order first-fit carrier best-fit allocator |
| `+MMmcs` | 30 | Max cached memory segments |

### 3. Real-time/Low Latency Mode

Optimize for consistent response times:

```bash
ERL_FLAGS="+sbwt very_short +swt very_low +spp true +scl false"
```

| Flag | Value | Description |
|------|-------|-------------|
| `+sbwt` | very_short | Scheduler busy wait threshold |
| `+swt` | very_low | Scheduler wakeup threshold |
| `+spp` | true | Enable scheduler poll for IO |
| `+scl` | false | Disable scheduler compaction of load |

### 4. Production Defaults

Balanced settings for production:

```bash
ERL_FLAGS="+K true +A 64 +SDio 64 +sbwt none"
```

| Flag | Value | Description |
|------|-------|-------------|
| `+K` | true | Enable kernel poll (epoll/kqueue) |
| `+A` | 64 | Async thread pool size |
| `+SDio` | 64 | Dirty IO schedulers |
| `+sbwt` | none | No busy waiting (save CPU) |

## Complete Flag Reference

### Memory Management

| Flag | Description | Default | Example |
|------|-------------|---------|---------|
| `+hms Size` | Default heap size in words | 233 | `+hms 8388608` |
| `+hmbs Size` | Default binary virtual heap size | 46422 | `+hmbs 100000` |
| `+hpds Size` | Default process dictionary size | 8 | `+hpds 16` |
| `+P Number` | Maximum number of processes | 262144 | `+P 1000000` |

### Scheduler Configuration

| Flag | Description | Default | Values |
|------|-------------|---------|--------|
| `+S Schedulers:SchedulersOnline` | Number of schedulers | CPU cores | `+S 8:8` |
| `+SDcpu DirtyCPU:Online` | Dirty CPU schedulers | CPU cores | `+SDcpu 4:4` |
| `+SDio DirtyIO` | Dirty IO schedulers | 10 | `+SDio 128` |
| `+A Size` | Async thread pool size | 1 | `+A 64` |
| `+sbwt Threshold` | Scheduler busy wait | medium | none/very_short/short/medium/long/very_long |
| `+swt Threshold` | Scheduler wakeup | medium | very_low/low/medium/high/very_high |
| `+spp Bool` | Scheduler poll for IO | false | true/false |
| `+scl Bool` | Scheduler compaction of load | true | true/false |

### Memory Allocators

| Flag | Description | Example |
|------|-------------|---------|
| `+MBas Strategy` | Binary allocator strategy | `+MBas aoffcbf` |
| `+MHas Strategy` | Heap allocator strategy | `+MHas aoffcbf` |
| `+MMmcs Size` | Max cached memory segments | `+MMmcs 30` |
| `+MBlmbcs Size` | Binary largest multiblock carrier size | `+MBlmbcs 512` |

**Allocator Strategies:**
- `bf` - Best fit
- `aobf` - Address order best fit
- `aoff` - Address order first fit
- `aoffcbf` - Address order first fit carrier best fit (recommended)
- `gf` - Good fit
- `af` - A fit

### IO and Networking

| Flag | Description | Default | Example |
|------|-------------|---------|---------|
| `+K Bool` | Enable kernel poll | false | `+K true` |
| `+zdbbl Size` | Distribution buffer busy limit | 1024 | `+zdbbl 32768` |

## Integration with run.sh

### Option 1: Environment Variable

Edit `run.sh` to set `ERL_FLAGS`:

```bash
#!/bin/bash
source .env

# Choose your tuning profile
ERL_FLAGS="+hms 8388608 +A 64 +K true"

iex --erl "$ERL_FLAGS" --name $NODE_NAME --cookie testlitest -S mix phx.server
```

### Option 2: Profile-based Configuration

Create tuning profiles in `run.sh`:

```bash
#!/bin/bash
source .env

# Tuning profiles
PROFILE_PERFORMANCE="+hms 8388608 +A 128 +SDio 128 +K true"
PROFILE_LOW_MEMORY="+hms 233 +MBas aoffcbf +MMmcs 30"
PROFILE_LOW_LATENCY="+sbwt very_short +swt very_low +spp true"
PROFILE_PRODUCTION="+K true +A 64 +SDio 64 +sbwt none"

# Select profile (default: production)
BEAM_PROFILE=${BEAM_PROFILE:-PROFILE_PRODUCTION}
ERL_FLAGS="${!BEAM_PROFILE}"

echo "Starting with BEAM profile: $BEAM_PROFILE"
echo "ERL_FLAGS: $ERL_FLAGS"

iex --erl "$ERL_FLAGS" --name $NODE_NAME --cookie testlitest -S mix phx.server
```

Usage:
```bash
# Use production profile (default)
./run.sh

# Use performance profile
BEAM_PROFILE=PROFILE_PERFORMANCE ./run.sh

# Use low memory profile
BEAM_PROFILE=PROFILE_LOW_MEMORY ./run.sh
```

### Option 3: Separate Config File

Create `beam_config.sh`:

```bash
# beam_config.sh - BEAM VM configuration

# Uncomment ONE profile or customize your own

# Performance mode (lots of RAM)
# export ERL_FLAGS="+hms 8388608 +A 128 +SDio 128 +K true"

# Low memory mode
# export ERL_FLAGS="+hms 233 +MBas aoffcbf +MMmcs 30"

# Production defaults
export ERL_FLAGS="+K true +A 64 +SDio 64 +sbwt none"
```

Then source it in `run.sh`:

```bash
#!/bin/bash
source .env
source beam_config.sh

iex --erl "$ERL_FLAGS" --name $NODE_NAME --cookie testlitest -S mix phx.server
```

## Monitoring Memory Usage

### From IEx Console

```elixir
# Total memory usage
:erlang.memory()

# Process count
length(:erlang.processes())

# Top memory-consuming processes
Process.list()
|> Enum.map(fn pid -> {pid, Process.info(pid, :memory)} end)
|> Enum.filter(fn {_, info} -> info != nil end)
|> Enum.map(fn {pid, {:memory, mem}} -> {pid, mem} end)
|> Enum.sort_by(fn {_, mem} -> mem end, :desc)
|> Enum.take(10)

# Scheduler utilization
:scheduler.utilization(1000)
```

### From Command Line

```bash
# Watch BEAM process memory
watch -n 1 'ps aux | grep beam.smp'

# Use observer (GUI)
iex> :observer.start()
```

## Troubleshooting

### High Memory Usage

1. **Check for message queue buildup:**
   ```elixir
   Process.list()
   |> Enum.map(fn pid -> {pid, Process.info(pid, :message_queue_len)} end)
   |> Enum.filter(fn {_, {:message_queue_len, len}} -> len > 100 end)
   ```

2. **Force garbage collection:**
   ```elixir
   :erlang.garbage_collect()
   ```

3. **Reduce heap sizes:** Use `+hms 233` to force more frequent GC

### High CPU Usage

1. **Check scheduler utilization:**
   ```elixir
   :scheduler.utilization(1000)
   ```

2. **Reduce busy waiting:** Use `+sbwt none`

3. **Check reductions:** Look for runaway processes
   ```elixir
   Process.list()
   |> Enum.map(fn pid -> {pid, Process.info(pid, :reductions)} end)
   |> Enum.sort_by(fn {_, {:reductions, r}} -> r end, :desc)
   |> Enum.take(5)
   ```

### Slow Response Times

1. **Enable kernel poll:** `+K true`
2. **Increase async threads:** `+A 64` or higher
3. **Tune scheduler wake-up:** `+swt very_low`

## References

- [Erlang System Flags](https://www.erlang.org/doc/man/erl.html)
- [BEAM Book - Memory Management](https://blog.stenmans.org/theBeamBook/)
- [Phoenix Performance Guide](https://hexdocs.pm/phoenix/performance.html)

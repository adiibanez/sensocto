# Startup Time Optimization Plan

**Status: IMPLEMENTED** (2026-01-31)

## Changes Made

1. **Increased hydration delays** (Phase 1.1):
   - `Manager`: 100ms → 5,000ms
   - `BatteryState`: 200ms → 5,500ms
   - `TrackPlayer`: 200ms → 6,000ms

2. **Converted all DB loads to async patterns** (Phase 2):
   - `Manager.load_running_scenarios_from_db()` → async via Task.Supervisor
   - `BatteryState.load_battery_states_from_db()` → async via Task.Supervisor
   - `TrackPlayer.load_positions_from_db()` → async via Task.Supervisor

3. **Deferred filesystem I/O** (Phase 3):
   - `Manager.discover_scenarios()` now runs in background task at T+1s
   - Results delivered via `{:scenarios_discovered, scenarios}` message

4. **RoomStore hydration** was already async (uses Task.Supervisor)

## New Startup Sequence

```
T+0ms     Application.start() - Supervisor tree begins
T+0ms     RoomStore starts - schedules async hydration via Task.Supervisor
T+100ms   RoomStore hydration runs in background (non-blocking)
T+1000ms  Manager: scenario discovery starts (async, non-blocking)
T+5000ms  Manager: hydration from PostgreSQL (async, non-blocking)
T+5500ms  BatteryState: hydration from PostgreSQL (async, non-blocking)
T+6000ms  TrackPlayer: hydration from PostgreSQL (async, non-blocking)
```

HTTP server is now responsive within ~1-2 seconds. Simulator hydrates in background.

---

## Problem Statement

The web application takes too long to start on Fly.io, causing reverse proxy routing difficulties. The root cause is a cascade of synchronous database operations scheduled during startup with short delays (100-200ms).

## Root Cause Analysis

### Current Startup Sequence (Problematic)

```
T+0ms     Application.start() - Supervisor tree begins
T+0ms     RoomStore starts - synchronous call to HydrationManager.hydrate_all() (30s timeout!)
T+100ms   Simulator.Manager scheduled operations:
          - discover_scenarios() - synchronous filesystem I/O
          - load_running_scenarios_from_db() - blocking Ash.read!()
T+200ms   BatteryState: load_battery_states_from_db() - blocking Ash.read!()
T+200ms   TrackPlayer: load_positions_from_db() - blocking Ash.read!()
```

### Identified Issues

| File | Problem | Impact |
|------|---------|--------|
| `lib/sensocto/otp/room_store.ex:268-269` | Synchronous `HydrationManager.hydrate_all()` with 30s timeout | Blocks entire startup |
| `lib/sensocto/simulator/manager.ex:619-647` | `discover_scenarios()` reads all YAML files synchronously | Filesystem I/O during init |
| `lib/sensocto/simulator/manager.ex:715-728` | `load_running_scenarios_from_db()` uses `Ash.read!()` | Blocking DB query |
| `lib/sensocto/simulator/battery_state.ex:249-260` | `load_battery_states_from_db()` uses `Ash.read!()` | Blocking DB query |
| `lib/sensocto/simulator/track_player.ex:432-443` | `load_positions_from_db()` uses `Ash.read!()` | Blocking DB query |

## Implementation Plan

### Phase 1: Quick Wins (Immediate Impact)

#### 1.1 Defer Simulator Hydration to Post-Startup

Change hydration delays from 100-200ms to 5000ms+ to allow the HTTP server to become responsive first.

**Files to modify:**
- `lib/sensocto/simulator/manager.ex` - Change line 166 from `100` to `5_000`
- `lib/sensocto/simulator/battery_state.ex` - Change line 84 from `200` to `5_500`
- `lib/sensocto/simulator/track_player.ex` - Change line 116 from `200` to `6_000`

#### 1.2 Make RoomStore Hydration Async

Convert `HydrationManager.hydrate_all()` from synchronous to async call.

**Before:**
```elixir
# room_store.ex:268-269
case HydrationManager.hydrate_all() do
  :ok -> :ok
  {:error, reason} -> Logger.warning("Hydration failed: #{inspect(reason)}")
end
```

**After:**
```elixir
# Schedule hydration after init completes
Process.send_after(self(), :hydrate_rooms, 3_000)

# Add handle_info callback
def handle_info(:hydrate_rooms, state) do
  case HydrationManager.hydrate_all() do
    :ok -> :ok
    {:error, reason} -> Logger.warning("Hydration failed: #{inspect(reason)}")
  end
  {:noreply, state}
end
```

### Phase 2: Convert Blocking Reads to Async (Medium Priority)

#### 2.1 Manager.load_running_scenarios_from_db/1

**Current (blocking):**
```elixir
defp load_running_scenarios_from_db(state) do
  case Ash.read!(Scenario, action: :read, page: false) do
    scenarios -> ...
  end
end
```

**Proposed (async):**
```elixir
defp schedule_load_running_scenarios do
  Process.send_after(self(), :load_running_scenarios, 5_000)
end

def handle_info(:load_running_scenarios, state) do
  case Ash.read(Scenario, action: :read, page: false) do
    {:ok, scenarios} ->
      # Process scenarios
      {:noreply, state_with_scenarios}
    {:error, reason} ->
      Logger.warning("Failed to load scenarios: #{inspect(reason)}")
      {:noreply, state}
  end
end
```

#### 2.2 BatteryState.load_battery_states_from_db/0

Similar pattern - convert `Ash.read!()` to async `handle_info` with `Ash.read()`.

#### 2.3 TrackPlayer.load_positions_from_db/0

Similar pattern - convert `Ash.read!()` to async `handle_info` with `Ash.read()`.

### Phase 3: Defer Filesystem I/O (Medium Priority)

#### 3.1 Manager.discover_scenarios/0

Move scenario discovery to a background task that runs after startup.

**Current:**
```elixir
# Called during init via Process.send_after(self(), :hydrate, 100)
def handle_info(:hydrate, state) do
  discover_scenarios()  # Synchronous filesystem I/O
  ...
end
```

**Proposed:**
```elixir
def handle_info(:hydrate, state) do
  # Just mark as ready, don't block
  {:noreply, %{state | ready: true}}
end

def handle_info(:discover_scenarios, state) do
  # Run after HTTP server is responsive
  scenarios = do_discover_scenarios()
  {:noreply, %{state | scenarios: scenarios}}
end
```

### Phase 4: Production-Specific Optimizations (Optional)

#### 4.1 Disable Simulator in Production

If simulator is not needed in production Fly.io deployments, disable it entirely:

```elixir
# config/runtime.exs
config :sensocto, :simulator_enabled, System.get_env("SIMULATOR_ENABLED", "false") == "true"

# application.ex
children = [
  # ... other children
] ++ if Application.get_env(:sensocto, :simulator_enabled, false) do
  [Sensocto.Simulator.Supervisor]
else
  []
end
```

#### 4.2 Lazy Load Scenarios on Demand

Instead of loading all scenarios at startup, load them when first requested:

```elixir
def get_scenario(name) do
  case :ets.lookup(:scenarios_cache, name) do
    [{^name, scenario}] -> {:ok, scenario}
    [] -> load_and_cache_scenario(name)
  end
end
```

## Implementation Order

1. **Immediate (Phase 1)** - Increase hydration delays and make RoomStore async
   - Estimated effort: 30 minutes
   - Impact: HTTP server responsive within 1-2 seconds

2. **Short-term (Phase 2)** - Convert Ash.read! to async patterns
   - Estimated effort: 2-3 hours
   - Impact: No blocking during startup

3. **Medium-term (Phase 3)** - Defer filesystem I/O
   - Estimated effort: 1-2 hours
   - Impact: Faster cold starts

4. **Optional (Phase 4)** - Production-specific optimizations
   - Estimated effort: 1-2 hours
   - Impact: Minimal startup for production UI-only deployments

## Verification

After each phase, verify:

1. `fly logs` shows HTTP server ready within 2-3 seconds
2. Health check endpoint responds before simulator hydration completes
3. No startup timeouts or reverse proxy errors
4. Simulator functionality works correctly after delayed hydration

## Rollback Plan

If issues occur, revert hydration delays to original values:
- Manager: 100ms
- BatteryState: 200ms
- TrackPlayer: 200ms

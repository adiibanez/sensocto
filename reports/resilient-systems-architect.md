# Sensocto Resilient Systems Architecture Analysis

**Analysis Date:** January 12, 2026 (Updated: January 20, 2026)
**Analyst:** Resilient Systems Architect (Claude Opus 4.5)
**Codebase:** Sensocto IoT Sensor Platform
**Version:** 0.1.0

---

## 🆕 Update: January 20, 2026

### Transformational Improvement: Hierarchical Supervision Tree

The supervision tree has been **completely restructured** from a flat 30+ child design to a properly layered **6-tier architecture**.

### Critical Issues Resolved

| Issue | Resolution |
|-------|------------|
| **Flat Supervision Tree** | ✅ Now has hierarchical structure: Infrastructure → Registry → Storage → Bio → Domain → Web |
| **Task.Supervisor for Async** | ✅ `Sensocto.TaskSupervisor` in Infrastructure.Supervisor, used by RoomStore |
| **Atom Table Exhaustion** | ✅ AttributeStoreTiered uses single global ETS with composite keys `{sensor_id, attribute_id}` |
| **Explicit GenServer Timeouts** | ✅ RoomStore uses `@call_timeout 5_000` on all calls |
| **Simulator Atom Creation** | ✅ Now uses `SafeKeys.safe_keys_to_atoms/1` with whitelist |

### New Supervision Architecture

The application now uses `rest_for_one` at root level with 6 intermediate supervisors:

1. **Infrastructure.Supervisor** (`:one_for_one`) - Repos, PubSub, Telemetry, Finch
2. **Registry.Supervisor** (`:one_for_one`) - 13 registries including Horde for distribution
3. **Storage.Supervisor** (`:rest_for_one`) - Iroh.RoomStore → RoomStore → RoomSync → RoomStateCRDT
4. **Bio.Supervisor** (`:one_for_one`) - Biomimetic components (5 modules, 1,147 LOC)
5. **Domain.Supervisor** (`:one_for_one`) - DynamicSupervisors for sensors, rooms, calls, media, 3D
6. **Web Layer** - Endpoint, AshAuthentication

### Remaining Issues (Minor)

**High Priority:**
- 14 instances of `IO.puts` in production code should be replaced with `Logger.debug`

**Medium Priority:**
- SimpleSensor still blocks in `init/1` - should use `{:continue, :post_init}`
- Message timestamp list unbounded between MPS calculations
- RoomStateCRDT should have explicit call timeouts

**Low Priority:**
- Consider per-room CRDT processes for scaling
- Add telemetry for GenServer call latencies
- Add health check endpoints

### Scalability Assessment

| Resource | Current Limit | Notes |
|----------|---------------|-------|
| Concurrent Sensors | ~100,000+ | ETS fix + proper supervision |
| Messages/Second | ~50,000 | RepoReplicatorPool pool limit |
| Concurrent Rooms | ~5,000 | RoomStore GenServer bottleneck |

### Overall Assessment

**Production Ready** (with minor improvements recommended)

The platform demonstrates mature understanding of OTP principles with:
- Properly layered supervision with appropriate restart strategies
- Task.Supervisor for supervised background work
- SafeKeys whitelist for atom table protection
- Explicit timeouts on critical GenServer calls

The remaining IO.puts instances should be addressed before production deployment but do not affect system reliability.

---

## Previous Update: January 17, 2026

### Issues Resolved in January 17 Assessment

| Issue | Status | Details |
|-------|--------|---------|
| **Task.Supervisor for Async Operations** | ✅ **RESOLVED** | `Sensocto.TaskSupervisor` now properly added to supervision tree |
| **Atom Table Exhaustion in AttributeStoreTiered** | ✅ **RESOLVED** | Uses single global ETS table with composite keys |
| **Explicit GenServer Timeouts** | ✅ **RESOLVED** | `@call_timeout 5_000` and explicit timeouts in all public API functions |

---

## Original Assessment (January 12, 2026)

## Executive Summary

Sensocto is a sophisticated IoT sensor platform built on Elixir/Phoenix that demonstrates a solid understanding of OTP principles. The codebase shows evidence of thoughtful architecture decisions around process supervision, back-pressure mechanisms, and scalability patterns. However, the analysis reveals several areas where improvements would significantly enhance fault tolerance and operational resilience.

### Key Strengths

1. **Mature Back-Pressure Architecture** - The AttentionTracker and SystemLoadMonitor provide adaptive data rate control based on user attention and system load
2. **Tiered Storage Design** - The AttributeStoreTiered implementation correctly separates hot (Agent) and warm (ETS) data tiers
3. **Proper Registry Usage** - Multiple registries for process lookup with appropriate naming conventions
4. **Pooled Workers** - RepoReplicatorPool uses consistent hashing for work distribution across 8 workers
5. **Horde for Distribution** - Distributed registries for cluster-wide room lookups

### Critical Concerns

1. **Flat Supervision Tree** - Application startup uses `:one_for_one` with 30+ children at the root level
2. **Mixed Responsibilities in GenServers** - Several GenServers combine data, state, and async operations
3. **Unsupervised Tasks** - Multiple `Task.start/1` calls for database sync that are fire-and-forget
4. **Missing Timeout Handling** - Several GenServer calls lack explicit timeouts
5. **Atom Creation from External Input** - Potential atom table exhaustion in simulator config parsing

---

## Architecture Overview

### Supervision Tree Analysis

The application's supervision tree, as defined in `lib/sensocto/application.ex`, is concerning. All 30+ processes are direct children of the root supervisor with `:one_for_one` strategy:

```
Sensocto.Supervisor (one_for_one)
|
+-- SensoctoWeb.Telemetry
+-- Sensocto.Repo
+-- Sensocto.Repo.Replica
+-- Boltx (Neo4j)
+-- Sensocto.Otp.BleConnectorGenServer
+-- SensorsStateAgent
+-- Registry (TestRegistry)
+-- Sensocto.Otp.Connector
+-- Registry (Sensors.Registry)
+-- Registry (SensorRegistry)
+-- Registry (SimpleAttributeRegistry)
+-- Registry (SimpleSensorRegistry)
+-- Registry (SensorPairRegistry)
+-- Registry (RoomRegistry)
+-- Registry (RoomJoinCodeRegistry)
+-- Horde.Registry (DistributedRoomRegistry)
+-- Horde.Registry (DistributedJoinCodeRegistry)
+-- Registry (CallRegistry)
+-- Registry (MediaRegistry)
+-- DNSCluster
+-- Phoenix.PubSub
+-- SensoctoWeb.Sensocto.Presence
+-- Sensocto.Iroh.RoomStore
+-- Sensocto.RoomStore
+-- Sensocto.Iroh.RoomSync
+-- Sensocto.RoomPresenceServer
+-- Sensocto.AttentionTracker
+-- Sensocto.SystemLoadMonitor
+-- Sensocto.SensorsDynamicSupervisor
+-- Sensocto.RoomsDynamicSupervisor
+-- Sensocto.Calls.CallSupervisor
+-- Sensocto.Media.MediaPlayerSupervisor
+-- Sensocto.Otp.RepoReplicatorPool
+-- Sensocto.Search.SearchIndex
+-- Finch
+-- SensoctoWeb.Endpoint
+-- AshAuthentication.Supervisor
+-- [Optional] Sensocto.Simulator.Supervisor
```

**Problems:**

1. **No Isolation Boundaries** - A crash in one component (e.g., Neo4j connection) could trigger cascading restarts of unrelated processes
2. **Missing Dependency Ordering** - Components that depend on each other (e.g., RoomStore depends on PubSub) are not grouped
3. **No Resource Tiering** - Database connections, registries, and business logic all at same level

**Recommended Restructuring:**

```
Sensocto.Supervisor (one_for_one)
|
+-- Sensocto.Infrastructure (rest_for_one)
|   +-- Sensocto.Repo
|   +-- Sensocto.Repo.Replica
|   +-- Boltx
|   +-- Phoenix.PubSub
|   +-- DNSCluster
|   +-- Finch
|
+-- Sensocto.Registries (one_for_all)
|   +-- Registry (SimpleSensorRegistry)
|   +-- Registry (SimpleAttributeRegistry)
|   +-- Registry (SensorPairRegistry)
|   +-- Registry (RoomRegistry)
|   +-- Registry (CallRegistry)
|   +-- Registry (MediaRegistry)
|   +-- Horde.Registry (DistributedRoomRegistry)
|   +-- Horde.Registry (DistributedJoinCodeRegistry)
|
+-- Sensocto.Core (rest_for_one)
|   +-- Sensocto.AttentionTracker
|   +-- Sensocto.SystemLoadMonitor
|   +-- Sensocto.RoomStore
|   +-- Sensocto.Search.SearchIndex
|   +-- SensoctoWeb.Sensocto.Presence
|
+-- Sensocto.DynamicWorkloads (one_for_one)
|   +-- Sensocto.SensorsDynamicSupervisor
|   +-- Sensocto.RoomsDynamicSupervisor
|   +-- Sensocto.Calls.CallSupervisor
|   +-- Sensocto.Media.MediaPlayerSupervisor
|   +-- Sensocto.Otp.RepoReplicatorPool
|
+-- Sensocto.Web (one_for_one)
|   +-- SensoctoWeb.Telemetry
|   +-- SensoctoWeb.Endpoint
|   +-- AshAuthentication.Supervisor
|
+-- [Optional] Sensocto.Simulator.Supervisor
```

---

## OTP Pattern Review

### GenServer Implementations

#### SimpleSensor (`lib/sensocto/otp/simple_sensor.ex`)

This is the core sensor process. Analysis:

**Positive Patterns:**
- Uses Registry for process lookup via `via_tuple/1`
- Proper `init/1` returning `{:ok, state}` pattern
- Implements `terminate/2` for cleanup
- Emits telemetry for MPS (messages per second) monitoring

**Concerns:**

1. **No `handle_continue/2`** - Initialization work (Ash.create, RepoReplicatorPool.sensor_up) happens in `init/1`, blocking the caller:

```elixir
# Current - blocks during init
def init(%{:sensor_id => sensor_id, :sensor_name => sensor_name} = state) do
  Sensor
  |> Ash.Changeset.for_create(:create, %{name: sensor_id})
  |> Ash.create()  # Blocks!

  RepoReplicatorPool.sensor_up(sensor_id)  # Blocks!
  {:ok, state}
end
```

**Recommendation:** Use `{:ok, state, {:continue, :post_init}}` pattern:

```elixir
def init(state) do
  {:ok, state, {:continue, :post_init}}
end

def handle_continue(:post_init, state) do
  # Async initialization here
  {:noreply, state}
end
```

2. **Unbounded Message Timestamp List** - The `message_timestamps` list grows without limit between MPS calculations:

```elixir
{:noreply,
 state
 |> Map.update!(:message_timestamps, &[now | &1])}
```

At high message rates (1000+ msg/sec), this list can consume significant memory before being trimmed. Consider using a ring buffer or bounded queue.

3. **Cast for get_attribute** - Line 157-159 uses `GenServer.cast` for a "get" operation, meaning the caller never receives a response:

```elixir
def get_attribute(sensor_id, attribute_id, limit) do
  GenServer.cast(  # Should be call!
    via_tuple(sensor_id),
    {:get_attribute, attribute_id, limit}
  )
end
```

#### AttributeStoreTiered (`lib/sensocto/otp/attribute_store_tiered.ex`)

**Excellent Design:**
- Tiered memory model (hot in Agent, warm in ETS)
- Configurable limits via Application env
- `read_concurrency: true` and `write_concurrency: true` on ETS tables
- Automatic overflow from hot to warm tier

**Concerns:**

1. **ETS Table Creation in start_link** - If the ETS table already exists (e.g., during restart), the check prevents recreation but doesn't handle table ownership properly:

```elixir
if :ets.whereis(warm_table) == :undefined do
  :ets.new(warm_table, [...])
end
```

If the Agent process crashes and restarts, the ETS table may be owned by the previous (now dead) process. Use `:ets.new/2` with `heir` option or a separate ETS manager process.

2. **Dynamic Atom Creation** - `warm_table_name/1` creates atoms from sensor IDs:

```elixir
defp warm_table_name(sensor_id) do
  safe_id = sensor_id |> to_string() |> String.replace("-", "_")
  :"#{@warm_table_prefix}#{safe_id}"  # Creates new atom!
end
```

With thousands of sensors, this exhausts the atom table (1,048,576 limit by default). **Use ETS tables keyed by sensor_id instead of separate tables per sensor.**

#### RoomStore (`lib/sensocto/otp/room_store.ex`)

**Strong Points:**
- Clean separation of concerns
- Multi-node cluster sync via PubSub
- Dual persistence (PostgreSQL primary, Iroh secondary)
- Proper hydration on startup from PostgreSQL

**Serious Concerns:**

1. **Fire-and-Forget Database Writes** - All PostgreSQL syncs use `Task.start/1` which creates unsupervised, unmonitored tasks:

```elixir
defp sync_room_and_owner_to_postgres(room, owner_id) do
  Task.start(fn ->  # Unsupervised!
    try do
      create_room_in_postgres(room)
      create_membership_in_postgres(room.id, owner_id, :owner)
    rescue
      e -> Logger.error(...)
    end
  end)
end
```

If the task crashes or the database is unavailable, data is silently lost. This should use:
- `Task.Supervisor` with `start_child/2` for monitoring
- Or a proper queue (Broadway, GenStage, or Oban) for persistent retries

2. **Blocking GenServer Calls** - All RoomStore operations go through a single GenServer, creating a potential bottleneck:

```elixir
def create_room(attrs, owner_id) do
  GenServer.call(__MODULE__, {:create_room, attrs, owner_id})
end
```

With high room creation rates, this serializes all operations. Consider:
- Sharding by room_id hash
- Using ETS for reads with GenServer only for writes
- Implementing read-through cache pattern

3. **No Timeout on GenServer Calls** - All public API functions use default 5-second timeout. Under load, this could cause cascading failures.

#### AttentionTracker (`lib/sensocto/otp/attention_tracker.ex`)

**Excellent Implementation:**
- ETS for fast concurrent reads (attention levels, config)
- Sophisticated attention decay with timers
- Battery state awareness for mobile devices
- Proper cleanup of stale records

**Minor Improvements:**

1. The `rescue ArgumentError` in `get_sensor_attention_level/1` is a code smell:

```elixir
def get_sensor_attention_level(sensor_id) do
  case :ets.lookup(@sensor_attention_table, sensor_id) do
    [{_, level}] -> level
    [] -> :none
  end
rescue
  ArgumentError -> :none  # ETS table might not exist
end
```

Better: ensure ETS tables exist before any caller can access them, or use a read-through pattern with fallback.

#### SystemLoadMonitor (`lib/sensocto/otp/system_load_monitor.ex`)

**Solid Implementation:**
- Uses `:os_mon` for system metrics
- Weighted combination of CPU, PubSub, queue, and memory pressure
- Configurable weights via Application config

**Good for observability, integrates well with AttentionTracker.**

---

## Simulator Architecture Review

The simulator subsystem (`lib/sensocto/simulator/`) demonstrates good hierarchical supervision:

```
Simulator.Supervisor (one_for_one)
|
+-- Registry
+-- BatteryState (GenServer)
+-- TrackPlayer (GenServer)
+-- DataServer (5 pooled workers)
+-- ConnectorSupervisor (DynamicSupervisor)
    +-- ConnectorServer...
        +-- SensorServer...
            +-- AttributeServer...
+-- Manager (GenServer)
```

**Positive Patterns:**

1. **Process.flag(:trap_exit, true)** in SensorServer for graceful cleanup:

```elixir
def init(config) do
  Process.flag(:trap_exit, true)
  {:ok, supervisor} = DynamicSupervisor.start_link(strategy: :one_for_one)
  {:ok, state, {:continue, :create_real_sensor}}
end
```

2. **Proper use of {:continue, ...}** for async initialization
3. **Local DynamicSupervisor per sensor** - Each SensorServer manages its own attribute servers

**Concerns:**

1. **Atom Creation from YAML** - `string_keys_to_atom_keys/1` converts all string keys to atoms:

```elixir
defp string_keys_to_atom_keys(map) when is_map(map) do
  Map.new(map, fn
    {k, v} when is_binary(k) -> {String.to_atom(k), string_keys_to_atom_keys(v)}
    {k, v} -> {k, string_keys_to_atom_keys(v)}
  end)
end
```

Malicious or large YAML configurations could exhaust the atom table. Use `String.to_existing_atom/1` with a whitelist, or keep keys as strings.

2. **Fixed Pool Size** - DataServer pool has 5 hardcoded workers. Consider making this configurable and using Poolboy or NimblePool for proper pool management.

---

## Phoenix Channel Analysis

### CallChannel (`lib/sensocto_web/channels/call_channel.ex`)

**Good Patterns:**
- Uses `intercept` for outgoing message filtering
- Proper `terminate/2` for cleanup on disconnect
- PubSub subscriptions for real-time updates

**Concerns:**

1. **Debug IO.puts in Production Code**:

```elixir
def handle_in("join_call", _params, socket) do
  IO.puts(">>> CallChannel: User #{user_id} attempting to join call...")
```

Use `Logger.debug/1` instead, which respects log levels.

2. **Missing Rate Limiting** - No protection against message flooding:

```elixir
def handle_in("media_event", %{"data" => data}, socket) do
  Calls.handle_media_event(room_id, user_id, data)  # No rate limit
  {:noreply, socket}
end
```

WebRTC events can be high-frequency. Consider token bucket or sliding window rate limiting.

---

## Database and Resource Management

### Connection Pooling

Configuration in `config/runtime.exs` shows awareness of pooling:

```elixir
config :sensocto, Sensocto.Repo,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  queue_target: 5000,
  queue_interval: 1000
```

**Good:** Queue settings for connection pressure handling.

**Concern:** Pool size of 10 is conservative but may be insufficient under load. Neon.tech pooler has its own limits - ensure coordination.

### Read Replica Usage

The `Sensocto.Repo.Replica` module is defined but appears underutilized. The `Sensocto.Repo.replica/0` function exists but I found limited usage in the codebase. This is an opportunity for read scaling.

---

## State Management Evaluation

### ETS Usage

The codebase uses ETS appropriately in several places:

| Module | Table | Purpose | Options |
|--------|-------|---------|---------|
| AttributeStoreTiered | `:attribute_store_warm_*` | Warm tier data | public, set, read/write concurrency |
| AttentionTracker | `:attention_levels_cache` | Attention levels | public, read concurrency |
| AttentionTracker | `:attention_config_cache` | Static config | public, read concurrency |
| AttentionTracker | `:sensor_attention_table` | Sensor-level attention | public, read concurrency |
| BatteryState | `:battery_state` | Simulator battery state | public, set |

**Good Pattern:** Using ETS for read-heavy, concurrent access data.

**Anti-Pattern:** Creating ETS tables with dynamically generated atom names (AttributeStoreTiered).

### :persistent_term Usage

Used correctly in RepoReplicatorPool for pool size:

```elixir
:persistent_term.put({__MODULE__, :pool_size}, pool_size)
```

This is appropriate for rarely-changing configuration data.

### Registry Usage

Multiple registries are properly configured:

```elixir
{Registry, keys: :unique, name: Sensocto.SimpleSensorRegistry}
{Registry, keys: :unique, name: Sensocto.SimpleAttributeRegistry}
{Horde.Registry, [name: Sensocto.DistributedRoomRegistry, keys: :unique, members: :auto]}
```

**Good:** Using Horde for distributed registries enables cluster-wide process lookup.

---

## Fault Tolerance Assessment

### What Happens When Things Fail

| Failure Mode | Current Behavior | Impact | Severity |
|--------------|------------------|--------|----------|
| PostgreSQL unavailable | Unsupervised Task.start fails silently | Data loss for new rooms/memberships | HIGH |
| Neo4j unavailable | Boltx connection fails, application crashes | Complete system outage | CRITICAL |
| SimpleSensor crashes | DynamicSupervisor restarts it | Brief data gap, ETS table orphaned | MEDIUM |
| RoomStore crashes | Supervisor restarts, loses in-memory state | Rooms temporarily unavailable until rehydrated | MEDIUM |
| AttentionTracker crashes | ETS tables destroyed | Back-pressure disabled until restart | MEDIUM |
| PubSub unavailable | Many features break | Real-time updates stop | HIGH |

### Missing Fault Tolerance Patterns

1. **No Circuit Breakers** - External service calls (Neo4j, PostgreSQL, Iroh) have no circuit breakers to prevent cascade failures

2. **No Bulkhead Pattern** - All database operations share the same pool without isolation

3. **No Retry with Backoff** - Failed operations are either not retried or use simple linear retry

4. **Limited Health Checks** - The SystemLoadMonitor provides metrics but doesn't trigger protective actions

---

## Scalability Analysis

### Current Bottlenecks

1. **RoomStore Single Process** - All room operations serialized through one GenServer

2. **Atom Table Exhaustion Risk** - Dynamic atom creation in AttributeStoreTiered and Simulator

3. **ETS Table Proliferation** - One ETS table per sensor in warm tier could reach OS limits

4. **Unsupervised Background Tasks** - No backpressure on database sync tasks

### Positive Scalability Features

1. **Pooled RepoReplicator** - 8 workers with consistent hashing
2. **Attention-Based Throttling** - Reduces load for unviewed sensors
3. **System Load Multiplier** - Automatic throttling under pressure
4. **Horde for Distribution** - Ready for multi-node deployment

### Estimated Capacity

Based on the current architecture:

| Resource | Estimated Limit | Limiting Factor |
|----------|-----------------|-----------------|
| Concurrent Sensors | ~10,000 | ETS table count, atom table |
| Messages/Second | ~50,000 | RepoReplicator pool throughput |
| Concurrent Rooms | ~5,000 | RoomStore GenServer serialization |
| WebSocket Connections | ~100,000 | Bandit/Phoenix tuning |

---

## Recommendations

### Priority 1: Critical (Address Immediately)

#### 1.1 Restructure Supervision Tree

Create intermediate supervisors with appropriate strategies as outlined in the Architecture Overview section.

#### 1.2 Replace Unsupervised Tasks with Task.Supervisor

In `lib/sensocto/otp/room_store.ex`, replace all `Task.start/1` calls:

```elixir
# Before
Task.start(fn -> sync_room_to_postgres(room) end)

# After
Task.Supervisor.start_child(Sensocto.TaskSupervisor, fn ->
  sync_room_to_postgres(room)
end)
```

Add `{Task.Supervisor, name: Sensocto.TaskSupervisor}` to the supervision tree.

#### 1.3 Fix Atom Creation from External Input

In `lib/sensocto/otp/attribute_store_tiered.ex`:

```elixir
# Before - creates atoms
defp warm_table_name(sensor_id) do
  :"#{@warm_table_prefix}#{safe_id}"
end

# After - use single ETS table with composite keys
@warm_table_name :attribute_store_warm

def start_link(%{sensor_id: sensor_id} = config) do
  # Single global ETS table, created by supervisor
  Agent.start_link(fn -> %{sensor_id: sensor_id} end, name: via_tuple(sensor_id))
end

defp push_to_warm_tier(sensor_id, attribute_id, entries) do
  key = {sensor_id, attribute_id}
  # Use single table with composite key
  existing = :ets.lookup(@warm_table_name, key) |> ...
end
```

### Priority 2: High (Address This Sprint)

#### 2.1 Add Circuit Breakers for External Services

Use `:fuse` library for circuit breaking:

```elixir
def create_room_in_postgres(room) do
  case :fuse.check(:postgres_fuse) do
    :ok ->
      # Proceed with operation
      :fuse.reset(:postgres_fuse)
    :blown ->
      Logger.warning("PostgreSQL circuit breaker open, skipping write")
      {:error, :circuit_open}
  end
end
```

#### 2.2 Add Explicit Timeouts to GenServer Calls

```elixir
# Before
def get_room(room_id) do
  GenServer.call(__MODULE__, {:get_room, room_id})
end

# After
@call_timeout 5_000

def get_room(room_id) do
  GenServer.call(__MODULE__, {:get_room, room_id}, @call_timeout)
catch
  :exit, {:timeout, _} ->
    Logger.warning("RoomStore.get_room timeout for #{room_id}")
    {:error, :timeout}
end
```

#### 2.3 Implement Bounded Message Buffer in SimpleSensor

```elixir
# Use a ring buffer instead of unbounded list
defmodule Sensocto.RingBuffer do
  defstruct [:max_size, :items]

  def new(max_size), do: %__MODULE__{max_size: max_size, items: :queue.new()}

  def push(%{max_size: max, items: q} = buffer, item) do
    q = :queue.in(item, q)
    q = if :queue.len(q) > max, do: :queue.drop(q), else: q
    %{buffer | items: q}
  end
end
```

### Priority 3: Medium (Address This Quarter)

#### 3.1 Add Health Check Endpoints

```elixir
# lib/sensocto_web/controllers/health_controller.ex
defmodule SensoctoWeb.HealthController do
  use SensoctoWeb, :controller

  def liveness(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def readiness(conn, _params) do
    checks = %{
      database: check_database(),
      neo4j: check_neo4j(),
      room_store: check_room_store()
    }

    status = if Enum.all?(checks, fn {_, v} -> v == :ok end), do: 200, else: 503
    conn |> put_status(status) |> json(checks)
  end
end
```

#### 3.2 Add Telemetry for GenServer Call Latencies

```elixir
# In GenServer modules
def handle_call({:get_room, room_id}, _from, state) do
  start_time = System.monotonic_time()
  result = do_get_room(state, room_id)

  :telemetry.execute(
    [:sensocto, :room_store, :call],
    %{duration: System.monotonic_time() - start_time},
    %{operation: :get_room}
  )

  {:reply, result, state}
end
```

#### 3.3 Implement Read-Through Cache for RoomStore

```elixir
# Use ETS as read cache, GenServer for writes
def get_room(room_id) do
  case :ets.lookup(:room_cache, room_id) do
    [{^room_id, room}] -> {:ok, room}
    [] -> GenServer.call(__MODULE__, {:get_room, room_id})
  end
end
```

---

## Anti-Patterns Found

| Anti-Pattern | Location | Impact | Fix |
|--------------|----------|--------|-----|
| Atom creation from external input | `AttributeStoreTiered.warm_table_name/1` | Atom table exhaustion | Use composite ETS keys |
| Atom creation from external input | `Simulator.SensorServer.string_keys_to_atom_keys/1` | Atom table exhaustion | Use `String.to_existing_atom/1` or keep strings |
| Fire-and-forget database writes | `RoomStore.sync_*_to_postgres` | Silent data loss | Use Task.Supervisor or queue |
| IO.puts in production code | `CallChannel.handle_in/3` | Log pollution | Use Logger.debug |
| Missing GenServer timeouts | Multiple modules | Cascade failures | Add explicit timeouts |
| Flat supervision tree | `Application.start/2` | No fault isolation | Create subtrees |
| Blocking init | `SimpleSensor.init/1` | Slow startup | Use handle_continue |
| Unbounded list growth | `SimpleSensor.message_timestamps` | Memory pressure | Use ring buffer |

---

## Conclusion

Sensocto demonstrates a solid foundation in OTP principles with sophisticated features like attention-based back-pressure and tiered storage. The development team clearly understands Elixir/Phoenix patterns and has built thoughtful abstractions.

However, the flat supervision tree and unsupervised background tasks represent significant operational risks. The atom table exhaustion issues could cause production outages as sensor counts grow. Addressing the Priority 1 recommendations should be the immediate focus.

The platform is well-positioned for scale with the pooled worker pattern, Horde-based distribution, and attention-aware throttling. After addressing the structural issues, this architecture can support enterprise-grade IoT deployments.

---

## Appendix: Files Reviewed

### Core Application
- `lib/sensocto/application.ex` - Application supervision tree
- `lib/sensocto.ex` - Module facade

### OTP Components
- `lib/sensocto/otp/simple_sensor.ex` - Core sensor process
- `lib/sensocto/otp/attribute_store_tiered.ex` - Tiered storage
- `lib/sensocto/otp/room_store.ex` - Room management
- `lib/sensocto/otp/room_server.ex` - Room process
- `lib/sensocto/otp/room_presence_server.ex` - Presence tracking
- `lib/sensocto/otp/attention_tracker.ex` - Back-pressure system
- `lib/sensocto/otp/system_load_monitor.ex` - Load monitoring
- `lib/sensocto/otp/repo_replicator_pool.ex` - Worker pool
- `lib/sensocto/otp/repo_replicator_worker.ex` - Pool workers
- `lib/sensocto/otp/sensors_dynamic_supervisor.ex` - Sensor supervision
- `lib/sensocto/otp/rooms_dynamic_supervisor.ex` - Room supervision

### Simulator
- `lib/sensocto/simulator/supervisor.ex` - Simulator supervision tree
- `lib/sensocto/simulator/manager.ex` - Configuration management
- `lib/sensocto/simulator/connector_server.ex` - Connector process
- `lib/sensocto/simulator/sensor_server.ex` - Simulated sensor
- `lib/sensocto/simulator/attribute_server.ex` - Attribute simulation
- `lib/sensocto/simulator/data_generator.ex` - Data generation
- `lib/sensocto/simulator/data_server.ex` - Data server pool
- `lib/sensocto/simulator/battery_state.ex` - Battery simulation
- `lib/sensocto/simulator/track_player.ex` - GPS track playback

### Calls/Media
- `lib/sensocto/calls/call_supervisor.ex` - Call supervision
- `lib/sensocto/calls/call_server.ex` - Call management
- `lib/sensocto/media/media_player_supervisor.ex` - Media supervision
- `lib/sensocto/media/media_player_server.ex` - Media playback

### Phoenix/Web
- `lib/sensocto_web/channels/call_channel.ex` - WebRTC channel
- `lib/sensocto_web/channels/user_socket.ex` - WebSocket handler
- `lib/sensocto_web/telemetry.ex` - Telemetry configuration

### Configuration
- `mix.exs` - Project configuration
- `config/config.exs` - Application configuration
- `config/runtime.exs` - Runtime configuration

---

*Report generated by Resilient Systems Architect analysis tool*

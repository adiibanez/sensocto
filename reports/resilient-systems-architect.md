# Sensocto OTP Architecture and Resilience Assessment

**Generated:** 2026-02-08
**Author:** Resilient Systems Architect Agent
**Codebase Version:** Based on commit dc7c0ce (main branch)
**Previous Report:** 2026-02-07 (Monolith Split Analysis -- preserved in git history)

---

## Executive Summary

Sensocto is a real-time sensor platform built on Phoenix/LiveView with a sophisticated biomimetic adaptive layer. The system demonstrates strong architectural instincts -- layered supervision, attention-aware data routing, multi-layer backpressure, and ETS-backed concurrent state. It is clear the developers understand OTP patterns and have applied them thoughtfully.

However, several structural issues create latent failure modes that will surface under load or during partial failures. The most critical are: a supervision mismatch where sensors are locally supervised but globally registered (creating ghost entries on node crashes), a Domain.Supervisor that uses `:one_for_one` despite having ordering dependencies between children, and a complete absence of `code_change/3` implementations that blocks safe hot code upgrades.

**Overall Resilience Grade: B+**

The system is well above average for Elixir applications. The attention-aware routing and five-layer backpressure system are genuinely innovative. The primary risks are in the gaps between components rather than in the components themselves.

---

## Table of Contents

1. [Supervision Tree Architecture](#1-supervision-tree-architecture)
2. [Data Pipeline Analysis](#2-data-pipeline-analysis)
3. [Backpressure and Flow Control](#3-backpressure-and-flow-control)
4. [Process State and Lifecycle](#4-process-state-and-lifecycle)
5. [Distribution and Clustering](#5-distribution-and-clustering)
6. [ETS Usage and Safety](#6-ets-usage-and-safety)
7. [Resilience Patterns Inventory](#7-resilience-patterns-inventory)
8. [Anti-Patterns and Risks](#8-anti-patterns-and-risks)
9. [Biomimetic Layer Assessment](#9-biomimetic-layer-assessment)
10. [Recommendations](#10-recommendations)
11. [Planned Work: Resilience Implications](#11-planned-work-resilience-implications)

---

## 1. Supervision Tree Architecture

### 1.1 Root Tree (Application.ex)

Strategy: `:rest_for_one`, `max_restarts: 5`, `max_seconds: 10`

The root uses `:rest_for_one`, which is the correct choice here. Each layer depends on the layers before it: Domain needs Storage, Storage needs Registries, Registries need Infrastructure. If Infrastructure crashes, everything downstream restarts in order.

```
Sensocto.Supervisor (root, :rest_for_one, 5/10s)
  |-- L1: Infrastructure.Supervisor    (:one_for_one, 3/5s)
  |     |-- SensoctoWeb.Telemetry
  |     |-- Sensocto.TaskSupervisor
  |     |-- Sensocto.Repo
  |     |-- Sensocto.Repo.Replica
  |     |-- DNSCluster
  |     |-- Phoenix.PubSub (pool_size: 16)
  |     |-- SensoctoWeb.Presence
  |     |-- Finch (SensoctoFinch)
  |     |-- CircuitBreaker.TableOwner
  |
  |-- L2: Registry.Supervisor          (:one_for_one, 3/5s)
  |     |-- 5x Horde.Registry (distributed)
  |     |     |-- DistributedSensorRegistry (sync_interval: 100ms)
  |     |     |-- DistributedRoomRegistry
  |     |     |-- DistributedJoinCodeRegistry
  |     |     |-- DistributedConnectorRegistry
  |     |     |-- DistributedChatRegistry
  |     |-- 10x Registry (local)
  |           |-- SensorPairRegistry, ConnectorPairRegistry, RoomPairRegistry,
  |           |-- SensorDataChannel.Registry, Simulator.Registry,
  |           |-- LensRegistry, MediaPlayer.Registry, CallServer.Registry,
  |           |-- WhiteboardServer.Registry, Object3DPlayerServer.Registry
  |
  |-- L3: Storage.Supervisor           (:rest_for_one, 3/5s)
  |     |-- Iroh.RoomStore
  |     |-- HydrationManager
  |     |-- RoomStore
  |     |-- Iroh.RoomSync
  |     |-- Iroh.RoomStateCRDT
  |     |-- RoomPresenceServer
  |
  |-- L4: Bio.Supervisor               (:one_for_one)
  |     |-- NoveltyDetector
  |     |-- PredictiveLoadBalancer
  |     |-- HomeostaticTuner
  |     |-- ResourceArbiter
  |     |-- CircadianScheduler
  |     |-- SyncComputer
  |
  |-- L5: Domain.Supervisor            (:one_for_one, 5/10s)  ** SEE CONCERNS **
  |     |-- SyncWorker, LobbyModeStore, ModeRoomServer (legacy)
  |     |-- AttentionTracker
  |     |-- SystemLoadMonitor
  |     |-- Lenses.Supervisor (:one_for_one, 5/10s)
  |     |     |-- Router, ThrottledLens, PriorityLens
  |     |-- AttributeStoreTiered.TableOwner
  |     |-- SensorsDynamicSupervisor (local DynamicSupervisor)
  |     |-- Discovery (SensoctoWeb.Discovery)
  |     |-- ConnectorManager
  |     |-- RoomsDynamicSupervisor (Horde.DynamicSupervisor)
  |     |-- CallSupervisor
  |     |-- MediaPlayerSupervisor
  |     |-- WhiteboardSupervisor
  |     |-- Object3DPlayerSupervisor
  |     |-- ChatSupervisor
  |
  |-- L6: SensoctoWeb.Endpoint         (Phoenix web server)
  |
  |-- L7: AshAuthentication.Supervisor  (auth)
  |
  |-- [Conditional] Simulator.Supervisor (:one_for_one)
        |-- Simulator.Registry
        |-- DbTaskSupervisor (max_children: 3)
        |-- BatteryState, TrackPlayer, 5x DataServers
        |-- ConnectorSupervisor (DynamicSupervisor)
        |-- Manager
```

### 1.2 Restart Budget Analysis

| Supervisor | Strategy | Budget | Time Window | Assessment |
|-----------|----------|--------|-------------|------------|
| Root | :rest_for_one | 5 | 10s | Appropriate -- 5 cascading failures before total stop |
| Infrastructure | :one_for_one | 3 | 5s | Tight -- PubSub or Repo flapping 3x in 5s kills Infra |
| Registry | :one_for_one | 3 | 5s | Appropriate -- registries rarely crash |
| Storage | :rest_for_one | 3 | 5s | Correct -- storage has ordering dependencies |
| Bio | :one_for_one | default | default | Missing explicit limits -- should have max_restarts |
| Domain | :one_for_one | 5 | 10s | **Concern: wrong strategy** (see Section 8) |
| Lenses | :one_for_one | 5 | 10s | Appropriate |

### 1.3 Observations

**Strengths:**
- The 7-layer `:rest_for_one` root is excellent. Infrastructure crashes correctly cascade.
- Storage.Supervisor uses `:rest_for_one` for its internal chain (Iroh -> HydrationManager -> RoomStore), which is correct since RoomStore depends on HydrationManager.
- Restart budgets are generally reasonable. Not too loose (would mask flapping), not too tight (would escalate too quickly).

**Concerns:**
- **Bio.Supervisor has no explicit restart limits.** Defaults to `max_restarts: 3, max_seconds: 5`, but this should be explicitly stated. If NoveltyDetector starts crashing in a loop (e.g., due to bad sensor data), it will take down the entire Bio supervisor after 3 crashes, killing SyncComputer, HomeostaticTuner, and all other bio components -- collateral damage.
- **Domain.Supervisor uses `:one_for_one` but has ordering dependencies** (see Section 8.1).
- **SensoctoWeb.Telemetry lives in Infrastructure.Supervisor** -- a web module in a core supervisor creates a coupling that complicates any future separation.

---

## 2. Data Pipeline Analysis

### 2.1 Primary Data Flow

```
External Device
  |
  v
SensorDataChannel (WebSocket)
  |
  v
SimpleSensor (GenServer via Horde.Registry)
  |-- writes to AttributeStoreTiered (ETS: hot + warm tiers)
  |-- broadcasts to "data:{sensor_id}" (always, bypasses attention)
  |-- if attention_level != :none:
  |     broadcasts to "data:global"
  |
  v
Lenses.Router (subscribed to "data:global")
  |
  v
PriorityLens (per-socket ETS buffering)
  |-- buffers measurements in ETS keyed by {socket_id, sensor_id}
  |-- flush timer: 32ms (high), 50ms (medium), 100ms (low), 200ms (minimal)
  |-- broadcasts to "lens:priority:{socket_id}"
  |
  v
LobbyLive / RoomShowLive (handle_info({:lens_batch, ...}))
  |-- process_lens_batch_for_composite
  |-- push_event("composite_measurement")
  |
  v
CompositeMeasurementHandler (JS Hook)
  |-- window.dispatchEvent("composite-measurement-event")
  |
  v
Svelte Component (CompositeECG, CompositeBreathing, etc.)
```

### 2.2 Parallel Data Paths

The `data:{sensor_id}` topic always broadcasts (bypassing attention gating), enabling:
- **SyncComputer** -- subscribes per-sensor for Kuramoto phase sync computation
- **NoveltyDetector** -- monitors sensor data for anomalies via z-score
- **Bio layer** -- various components observing raw sensor data

The `data:global` topic is attention-gated (only broadcasts when `attention_level != :none`), creating an elegant two-tier system:
- Infrastructure consumers (sync, novelty) always get data
- UI consumers only get data for sensors someone is watching

### 2.3 Seed Data Path (Historical Data on View Entry)

```
LobbyLive.handle_params
  |-- seed_composite_historical_data/2
  |-- AttributeStoreTiered.get_attribute (ETS read from :attribute_store_hot/:attribute_store_warm)
  |-- push_event("composite_seed_data")
  |
  v
CompositeMeasurementHandler (JS Hook)
  |-- buffers seed events
  |-- waits for "composite-component-ready" CustomEvent from Svelte
  |-- replays buffer on ready
```

This event-driven handshake is well designed -- it avoids the common race condition of pushing data before the frontend component is mounted.

### 2.4 Pipeline Assessment

**Strengths:**
- Clean separation between always-on (per-sensor) and attention-gated (global) data paths
- ETS-backed buffering in PriorityLens avoids GenServer mailbox buildup
- Timer-based flush with quality tiers provides graceful degradation
- Historical seed data uses proper handshake, not timing hacks

**Concerns:**
- **Single Router GenServer** is a potential bottleneck. All `data:global` messages flow through one process. If the Router's mailbox grows (e.g., lens registration is slow), it becomes a chokepoint. The Router does simple `send/2` forwarding, so throughput should be high, but it is still a single point of serialization.
- **No dead letter handling.** If a PubSub subscriber dies between subscription and message delivery, messages are silently dropped. This is acceptable for real-time data but worth noting.

---

## 3. Backpressure and Flow Control

Sensocto implements five layers of backpressure, which is genuinely impressive for a system of this scale.

### Layer 1: Attention-Aware Routing (SimpleSensor)

SimpleSensor gates `data:global` broadcast based on `attention_level`:
```elixir
# simple_sensor.ex line ~388
if state.attention_level != :none do
  Phoenix.PubSub.broadcast(Sensocto.PubSub, "data:global", {:measurement, measurement})
end
```

Sensors with no viewers produce zero PubSub traffic on the global topic. This is the single most impactful backpressure mechanism in the system. With 100 sensors and 5 viewers watching 10 sensors each, only 10 sensors broadcast globally instead of 100.

### Layer 2: System Load Monitoring (SystemLoadMonitor)

Samples 4 signals with configurable weights:
- CPU (scheduler utilization): 45%
- PubSub pressure: 30%
- Message queue pressure: 15%
- Memory pressure: 10%

Four load levels: `:normal`, `:elevated`, `:high`, `:critical`

Memory protection triggers at 70% usage. The load level feeds into HomeostaticTuner and AttributeStoreTiered to reduce storage limits under pressure.

### Layer 3: Adaptive Storage Limits (AttributeStoreTiered)

Storage limits scale with system load:
- Normal: 1.0x base limits
- Elevated: 0.5x
- High: 0.2x
- Critical: 0.05x warm tier (effectively disabling warm storage)

Type-specific limits are well-considered:
- Skeleton/pose data: 1 hot entry, 0 warm (high-frequency, large payloads)
- ECG/HRV: 150 hot, 500 warm (needs history for composite views)
- Default: 50 hot, 100 warm

Amortized split optimization: hot tier only splits to warm when it reaches 2x the limit, avoiding per-write overhead.

### Layer 4: PriorityLens Quality Tiers

Four quality levels with different flush intervals:
- High: 32ms (31.25 Hz -- near real-time)
- Medium: 50ms (20 Hz)
- Low: 100ms (10 Hz)
- Minimal: 200ms (5 Hz)
- Paused: no flush

Quality is adjusted based on system load and LiveView mailbox depth (the LiveView can call back to request lower quality).

### Layer 5: Biomimetic Adaptation

The Bio layer provides additional adaptive capacity:
- **HomeostaticTuner**: adjusts sampling rates based on system load trends
- **ResourceArbiter**: lateral inhibition -- suppresses low-priority sensors when resources are scarce
- **PredictiveLoadBalancer**: anticipates load changes from sensor behavior patterns
- **CircadianScheduler**: time-based resource allocation adjustments

### Assessment

This is a remarkably sophisticated backpressure system. The key insight is that backpressure is applied at different granularities:

| Layer | Granularity | Speed | Effect |
|-------|------------|-------|--------|
| Attention | Per-sensor | Immediate | Eliminates unnecessary work |
| System Load | System-wide | Seconds | Reduces storage, adjusts limits |
| Storage | Per-attribute-type | Per-write | Bounds memory |
| PriorityLens | Per-socket | Per-flush | Reduces UI update rate |
| Biomimetic | System-wide | Minutes | Long-term adaptation |

**One concern:** These five layers are loosely coupled through shared state (ETS, GenServer calls). There is no centralized view of what all layers are doing simultaneously. Under extreme load, it is possible for multiple layers to react independently, causing over-correction (e.g., both attention and load monitoring reduce throughput, resulting in no data flowing at all). This is the classic "thundering herd of circuit breakers" problem.

---

## 4. Process State and Lifecycle

### 4.1 GenServer Inventory

| GenServer | Instances | State Type | State Size Risk | Hibernates? |
|-----------|-----------|-----------|-----------------|-------------|
| SimpleSensor | N (per sensor) | Map | Medium (~12 keys + attributes) | Yes (5 min idle) |
| RoomServer | N (per room) | Struct (14 fields) | Low | No |
| AttentionTracker | 1 | Struct (5 fields) + 3 ETS | Medium (ETS grows with sensors) | No |
| SystemLoadMonitor | 1 | Struct (11 fields) | Low | No |
| PriorityLens | 1 | Minimal (4 ETS tables) | ETS grows with sockets | No |
| LensRouter | 1 | Struct (1 field: MapSet) | Low | No |
| ConnectorManager | 1 | ETS-backed | Low process state | No |
| NoveltyDetector | 1 | Map (sensor_stats) | Grows with sensors | No |
| HomeostaticTuner | 1 | Map | Low | No |
| ResourceArbiter | 1 | Map | Low | No |
| SyncComputer | 1 | Struct (4 fields + buffers) | Grows with sensors | No |
| CallServer | N (per call) | Struct (13 fields) | Medium (participant maps) | No |
| RoomStore | 1 | Struct (4 fields) | Low | No |

### 4.2 code_change/3 Status

**Critical finding: Zero implementations across the entire codebase.**

No GenServer in Sensocto implements `code_change/3`. This means:
- Hot code upgrades (via FlyDeploy) cannot safely change any GenServer's state structure
- Adding a field to SimpleSensor's state map requires a full restart of all sensor processes
- The default `code_change/3` in GenServer returns `{:ok, state}` unchanged

This is the single biggest gap for operational resilience. Any state structure change forces a rolling restart or full deployment, losing all in-memory state.

### 4.3 Process.flag(:trap_exit, true) Usage

Only 2 files trap exits:
- `Sensocto.Simulator.ConnectorServer` -- correctly traps exits for parallel shutdown
- `Sensocto.Simulator.SensorServer` -- traps exits for cleanup

Notably absent:
- **SimpleSensor does not trap exits.** If its supervisor terminates it (e.g., during shutdown), `terminate/2` may not run, potentially leaving stale entries in Horde.Registry and ETS tables.
- **AttentionTracker does not trap exits.** It owns 3 ETS tables. If the process crashes, the ETS tables are destroyed (owned by the process). The supervisor restarts it, but all cached attention levels are lost.

### 4.4 Process Monitoring

Process monitoring (via `Process.monitor/1`) is used in 5 locations:
- **PriorityLens**: monitors caller_pid for auto-cleanup of socket registrations
- **LensRouter**: monitors lens pids for auto-deregistration
- **AttributeServer**: monitors for cleanup
- **ConnectorManager**: monitors connector pids
- **GossipTopic**: monitors for membership

This is good practice. The PriorityLens monitoring is particularly important -- it ensures dead LiveView processes don't leave stale ETS entries.

### 4.5 Hibernation

Only SimpleSensor hibernates (after 5 minutes idle via `:hibernate` return from `handle_info`). Given that idle sensors are the common case (most sensors are not being watched), this is an excellent memory optimization.

**Recommendation:** Consider hibernation for RoomServer (rooms can be idle for extended periods) and CallServer (between active calls).

---

## 5. Distribution and Clustering

### 5.1 Horde Usage

5 Horde.Registry instances and 1 Horde.DynamicSupervisor:

| Component | Type | sync_interval | Purpose |
|-----------|------|---------------|---------|
| DistributedSensorRegistry | Horde.Registry | 100ms | Sensor name -> pid lookup |
| DistributedRoomRegistry | Horde.Registry | default | Room -> pid lookup |
| DistributedJoinCodeRegistry | Horde.Registry | default | Join code -> room lookup |
| DistributedConnectorRegistry | Horde.Registry | default | Connector -> pid lookup |
| DistributedChatRegistry | Horde.Registry | default | Chat -> pid lookup |
| RoomsDynamicSupervisor | Horde.DynamicSupervisor | N/A | Room process lifecycle |

### 5.2 The Sensor Supervision Mismatch (Critical)

**This is the most significant architectural concern in the system.**

Sensors are registered in `DistributedSensorRegistry` (Horde.Registry -- distributed across all nodes) but supervised by `SensorsDynamicSupervisor` (a local `DynamicSupervisor` -- not Horde).

What this means:
1. Node A starts sensor "sensor_1", registered in Horde with Node A's pid
2. Node A crashes
3. Horde.Registry eventually detects the dead pid and removes the entry
4. But no supervisor on Node B or C will restart sensor_1 -- it was locally supervised

Compare with rooms: RoomServer uses both `Horde.Registry` (distributed lookup) AND `Horde.DynamicSupervisor` (distributed supervision). If the node hosting a room crashes, Horde's DynamicSupervisor starts it on another node.

For sensors, this mismatch creates a window where:
- The sensor's Horde.Registry entry is stale (pointing to a dead pid on a crashed node)
- Functions calling `SimpleSensor.get_state(sensor_id)` will get `:noreply` timeouts or `{:error, :not_found}`
- The sensor will not be automatically restarted anywhere

The `DistributedSensorRegistry` has `sync_interval: 100ms`, meaning stale entries persist for at most 100ms after the node crash is detected. But during that window, and until the external device reconnects, the sensor is gone.

**Mitigation in current code:** `get_device_names()` uses `Horde.Registry.select` with error handling, and many call sites wrap `SimpleSensor` calls in `try/catch :exit`. This is defensive but not a substitute for proper distributed supervision.

### 5.3 PubSub Distribution

Phoenix.PubSub is configured with `pool_size: 16` and uses the `:pg` adapter (default for Phoenix.PubSub). This means:
- PubSub topics work across all cluster nodes automatically
- The pool size of 16 provides good concurrency for pub/sub operations
- No manual cluster formation is needed for PubSub (`:pg` handles it via distributed Erlang)

### 5.4 ConnectorManager Cluster Coordination

ConnectorManager uses `:pg` (process groups) for cluster-wide connector discovery and `:net_kernel.monitor_nodes(true)` for node-down detection. This is a solid pattern -- `:pg` is the modern replacement for `:pg2` and integrates well with Horde.

### 5.5 Distribution Assessment

| Aspect | Status | Notes |
|--------|--------|-------|
| PubSub | Distributed | Via :pg, pool_size: 16 |
| Sensor registry | Distributed | Horde.Registry |
| Sensor supervision | **Local only** | DynamicSupervisor (mismatch) |
| Room registry | Distributed | Horde.Registry |
| Room supervision | Distributed | Horde.DynamicSupervisor |
| Connector coordination | Distributed | :pg + node monitoring |
| State replication | Partial | Iroh CRDT for rooms, nothing for sensors |

---

## 6. ETS Usage and Safety

### 6.1 ETS Table Inventory

| Table | Owner | Access | read_concurrency | write_concurrency | Risk |
|-------|-------|--------|-----------------|-------------------|------|
| `:attribute_store_hot` | TableOwner | :public | Yes | Yes | Low -- bounded by type limits |
| `:attribute_store_warm` | TableOwner | :public | Yes | Yes | Low -- bounded, load-adaptive |
| `:priority_lens_buffers` | PriorityLens | :public | Yes | Yes | Medium -- grows with sockets |
| `:priority_lens_sockets` | PriorityLens | :public | Yes | No | Low |
| `:priority_lens_digests` | PriorityLens | :public | Yes | Yes | Low |
| `:priority_lens_sensor_subscriptions` | PriorityLens | :public | Yes | Yes | Low |
| `:system_load_cache` | SystemLoadMonitor | :public | Yes | No | Very Low -- fixed size |
| `:attention_levels_cache` | AttentionTracker | :public | Yes | No | Low |
| `:sensor_attention_cache` | AttentionTracker | :public | Yes | No | Low |
| `:attention_sensor_views` | AttentionTracker | :public | Yes | No | Medium -- grows with views |
| `:circuit_breakers` | TableOwner | :public | Yes | No | Very Low |
| `:bio_novelty_scores` | NoveltyDetector | :public | Yes | No | Low -- cleanup every 5min |
| `:discovery_sensors` | DiscoveryCache | :public | Yes | No | Low |

### 6.2 ETS Ownership and Crash Impact

**Critical concern: AttentionTracker owns 3 ETS tables directly.**

If AttentionTracker crashes:
1. All 3 ETS tables are destroyed (ETS tables die with their owner)
2. The supervisor restarts AttentionTracker
3. New empty ETS tables are created
4. All cached attention levels are lost
5. All sensors revert to `attention_level: :none`
6. All `data:global` broadcasts stop (attention gate is closed)
7. LiveViews get no new data until they re-register views

The system would self-heal (LiveViews would re-register on next interaction), but there would be a period of silence.

**Better pattern (already used by CircuitBreaker and AttributeStoreTiered):** Use a separate `TableOwner` process that does nothing except own the ETS tables. The GenServer that uses the tables reads/writes but does not own them. If the GenServer crashes, tables survive. The `TableOwner` is a simple process unlikely to crash.

### 6.3 ETS Safety Assessment

All tables use `:public` access, which is correct for the BEAM (ETS `:public` means "any process on this node can read/write" -- it is not a security concern, just a concurrency model). The `read_concurrency: true` flag is appropriately set on tables that are read-heavy.

The `write_concurrency: true` flag on AttributeStoreTiered tables enables concurrent writes from multiple SimpleSensor processes, which is correct since each sensor writes to different keys.

**No ETS memory limits are configured.** ETS tables grow unbounded by default. The application-level bounds (AttributeStoreTiered limits, cleanup timers) provide the actual memory safety. If those bounds have bugs, ETS will consume all available memory.

---

## 7. Resilience Patterns Inventory

### 7.1 Patterns Present

| Pattern | Implementation | Quality |
|---------|---------------|---------|
| Supervision trees | 7-layer hierarchy | Excellent |
| Circuit breaker | `Sensocto.Resilience.CircuitBreaker` | Good (see caveats) |
| Backpressure | 5 layers (attention, load, storage, lens, bio) | Excellent |
| Process monitoring | PriorityLens, Router, ConnectorManager | Good |
| Adaptive load shedding | SystemLoadMonitor + HomeostaticTuner | Good |
| Graceful degradation | PriorityLens quality tiers | Excellent |
| Timeouts | Explicit 5s timeouts on RoomServer calls | Good |
| Hibernation | SimpleSensor after 5min idle | Good |
| Bounded buffers | Phase buffers in SyncComputer (50/20) | Good |
| Parallel shutdown | ConnectorServer Task.yield_many(4000) | Good |
| Stale cleanup | SyncComputer (5min), AttentionTracker (60s) | Good |
| Error isolation | try/rescue/catch on cross-process calls | Adequate |
| Dead socket GC | PriorityLens (1 minute cycle) | Good |
| Amortized operations | AttributeStoreTiered split at 2x limit | Good |
| Defensive reads | `:whereis` checks before ETS access | Good |
| Type-specific limits | AttributeStoreTiered per-type bounds | Good |
| Telemetry | 8 files with `:telemetry.execute` calls | Adequate |
| Safe atom conversion | ConnectorServer whitelist | Good |

### 7.2 Patterns Missing or Incomplete

| Pattern | Status | Impact |
|---------|--------|--------|
| `code_change/3` | Completely absent | Blocks safe hot code upgrades |
| Distributed sensor supervision | Local only | Sensors lost on node crash |
| Circuit breaker failure decay | No decay -- counter only resets on success | Permanent half-open state possible |
| ETS table ownership separation | Missing for AttentionTracker | Tables lost on crash |
| Health check endpoint | Unknown (not found in analysis) | Operational blind spot |
| Bulkhead pattern | Absent | No isolation between sensor types |
| Rate limiting | Absent at PubSub level | Fast producer can flood topics |
| Structured logging | Mix of Logger and IO.puts | Inconsistent observability |

---

## 8. Anti-Patterns and Risks

### 8.1 Domain.Supervisor Strategy Mismatch (High Risk)

`Domain.Supervisor` uses `:one_for_one` but has children with implicit ordering dependencies:

```
AttentionTracker          <-- required by SimpleSensor (via attention levels)
SystemLoadMonitor         <-- required by AttributeStoreTiered (via load levels)
Lenses.Supervisor         <-- required by LiveViews (PriorityLens)
AttributeStoreTiered.TableOwner  <-- required by SimpleSensor (ETS tables)
SensorsDynamicSupervisor  <-- requires all of the above
```

With `:one_for_one`, if `AttentionTracker` crashes and restarts, `SensorsDynamicSupervisor` and its sensors are NOT restarted. The sensors continue running with stale attention level references. When they next call `AttentionTracker.get_sensor_attention_level/1`, the newly restarted AttentionTracker has empty state, so all sensors get `:none` attention -- data flow stops.

**Recommended fix:** Either:
1. Change to `:rest_for_one` (simpler, but causes more restarts), or
2. Have sensors subscribe to an "attention_tracker:ready" PubSub topic and refresh their state when the tracker restarts (more resilient, no cascading restart)

### 8.2 Sensor Registry/Supervision Mismatch (Critical Risk)

Described in Section 5.2. Sensors use distributed Horde.Registry but local DynamicSupervisor. On node crash, sensors are not redistributed.

**Recommended fix:** Migrate to `Horde.DynamicSupervisor` for sensors (matching the Room pattern), or accept the limitation and document that sensor processes are ephemeral and will be recreated when devices reconnect.

### 8.3 Legacy Processes in Domain.Supervisor (Low Risk)

Three processes appear to be legacy:
- `SyncWorker` -- unclear purpose, minimal state
- `LobbyModeStore` -- may be replaced by newer mode system
- `ModeRoomServer` -- may be replaced

These add restart budget consumption without clear purpose. If they crash, they consume one of the 5 allowed restarts in 10 seconds.

### 8.4 Circuit Breaker Lacks Failure Decay (Medium Risk)

The circuit breaker tracks failure count but only resets it on success:

```elixir
# On success:
%{state | failure_count: 0, state: :closed}

# On failure:
%{state | failure_count: state.failure_count + 1}
```

There is no time-based decay. If a service has 4 failures (threshold: 5), then works correctly for a week, then has 1 more failure -- it opens. The historical failures from a week ago should not count against the current health.

**Recommended fix:** Add exponential decay to the failure counter, or use a sliding window of recent failures.

### 8.5 PubSub Lifecycle Gaps (Medium Risk)

SyncComputer subscribes to `data:{sensor_id}` topics for tracked sensors and unsubscribes when sensors are unregistered. However:

- If SyncComputer crashes and restarts, all subscriptions are lost
- The `init/1` schedules `:discover_existing_sensors` after 500ms to re-subscribe
- But during the 500ms gap + attribute discovery delay (2000ms), sync computation stops
- Sensors registered during this 2500ms window might be missed

The cleanup timer (every 5 minutes) catches stale sensors but does not re-discover missed ones.

### 8.6 CallServer Uses IO.puts in Production (Low Risk, Easy Fix)

`call_server.ex` contains `IO.puts` calls at lines ~466, 470, 474, 490. These bypass the Logger, cannot be filtered by log level, and do not include metadata (timestamps, pids, etc.).

**Fix:** Replace with `Logger.debug/1` or `Logger.info/1`.

---

## 9. Biomimetic Layer Assessment

### 9.1 Architecture

The Bio.Supervisor manages 6 components that form an adaptive layer inspired by biological neural systems:

| Component | Biological Analog | Purpose |
|-----------|------------------|---------|
| NoveltyDetector | Locus Coeruleus | Detects anomalous sensor data (Welford's z-score) |
| PredictiveLoadBalancer | Cerebellum | Anticipates load from sensor patterns |
| HomeostaticTuner | Synaptic Plasticity | Adjusts system parameters to maintain stability |
| ResourceArbiter | Lateral Inhibition | Suppresses low-priority sensors under resource pressure |
| CircadianScheduler | Suprachiasmatic Nucleus | Time-based resource allocation |
| SyncComputer | Phase Synchronization | Kuramoto order parameter for group coherence |

### 9.2 SyncComputer Analysis (New Addition)

The SyncComputer implements Kuramoto phase synchronization to measure how synchronized breathing and HRV signals are across a group of sensors. This is mathematically sound:

1. **Phase estimation:** Uses normalized value + derivative direction to map sensor readings to [0, 2*pi]. This is a reasonable approximation for quasi-periodic signals like breathing.

2. **Kuramoto order parameter:** R = |mean(e^(i*theta))| where theta_i are per-sensor phases. R ranges from 0 (no sync) to 1 (perfect sync). Standard formulation.

3. **Exponential smoothing:** `0.85 * prev + 0.15 * R` provides temporal stability. The alpha of 0.15 means ~7 measurements to converge to a new steady state.

**Strengths:**
- Bounded buffers (50 breathing, 20 HRV) prevent memory growth
- Minimum buffer thresholds (15, 8) prevent noisy estimates from short histories
- Task.async_stream for parallel attribute discovery with `max_concurrency: 10` and `timeout: 5000`
- Periodic stale sensor cleanup (5 minutes)
- Catch-all `handle_info` prevents mailbox pollution from unexpected messages

**Concerns:**
- **Phase estimation assumes quasi-periodicity.** If a breathing sensor sends noisy data (not periodic), the phase estimate will be meaningless, and the Kuramoto R will be artificially low. Consider filtering or quality checks before phase estimation.
- **`estimate_phase` returns `nil` for flat signals (range < 2).** The threshold of 2 is a magic number -- its appropriateness depends on sensor value ranges. If HRV values are typically in the 0-1 range, this threshold would filter out all data.
- **No telemetry emissions.** The SyncComputer computes valuable metrics but does not emit telemetry events. Adding `:telemetry.execute` for sync values would enable dashboards and alerting.
- **Stores to a synthetic sensor `"__composite_sync"`.** This is a reasonable hack for fitting sync metrics into the existing storage model, but it means the sync values share namespace with real sensors.

### 9.3 Bio Layer Integration

The bio components communicate through a mix of:
- Direct GenServer calls (e.g., `HomeostaticTuner` reads `SystemLoadMonitor`)
- ETS tables (e.g., `NoveltyDetector` writes to `:bio_novelty_scores`, `AttentionTracker` reads it)
- PubSub (e.g., `bio:novelty:{sensor_id}` topic)

This is well-designed. ETS for hot-path reads, PubSub for event notification, GenServer calls for configuration. The try/rescue/catch wrappers around bio factor reads (in AttentionTracker) ensure that a crashing bio component does not cascade into the attention system -- the factor simply defaults to 1.0.

---

## 10. Recommendations

### Critical Priority

**10.1 Implement `code_change/3` on Key GenServers**

Start with the most frequently changed and most impactful:
1. `SimpleSensor` -- many instances, most likely to have state changes
2. `AttentionTracker` -- singleton, complex state, system-wide impact
3. `RoomServer` -- distributed, state changes affect rooms
4. `SystemLoadMonitor` -- singleton, config fields may evolve
5. `SyncComputer` -- new, state structure likely to change

Pattern:
```elixir
def code_change(_old_vsn, state, _extra) do
  state = Map.put_new(state, :new_field, default_value)
  {:ok, state}
end
```

**10.2 Resolve Sensor Supervision Mismatch**

Either:
- Migrate `SensorsDynamicSupervisor` to `Horde.DynamicSupervisor` (full distributed supervision)
- Or explicitly document that sensors are ephemeral and implement reconnection logic in `SensorDataChannel` to handle the gap

### High Priority

**10.3 Separate AttentionTracker ETS Ownership**

Create `Sensocto.AttentionTracker.TableOwner` (following the pattern already established by `CircuitBreaker.TableOwner` and `AttributeStoreTiered.TableOwner`). Start it before `AttentionTracker` in the supervision tree. This ensures attention caches survive tracker crashes.

**10.4 Fix Domain.Supervisor Strategy**

Change from `:one_for_one` to `:rest_for_one`, or introduce PubSub-based recovery notifications so downstream processes can refresh state when upstream dependencies restart.

**10.5 Add Failure Decay to Circuit Breaker**

Implement time-based decay on the failure counter. A simple approach:
```elixir
# Decay failure count by half every decay_period
effective_failures = failure_count * :math.pow(0.5, elapsed / decay_period)
```

**10.6 Add Explicit Restart Limits to Bio.Supervisor**

```elixir
Supervisor.init(children, strategy: :one_for_one, max_restarts: 10, max_seconds: 60)
```

A more generous budget (10/60s vs the default 3/5s) is appropriate here because bio components are non-critical -- the system functions without them, just less efficiently.

### Medium Priority

**10.7 Replace IO.puts with Logger in CallServer**

Search for `IO.puts` in `call_server.ex` and replace with appropriate `Logger` calls.

**10.8 Add Telemetry to SyncComputer**

```elixir
:telemetry.execute(
  [:sensocto, :bio, :sync],
  %{value: smoothed, raw: r, sensor_count: n},
  %{group: group}
)
```

**10.9 Consider Hibernation for RoomServer and CallServer**

Both can be idle for extended periods. Adding `{:noreply, state, :hibernate}` on idle timeouts would reduce memory footprint of inactive rooms and calls.

**10.10 Add Bulkhead Isolation for Sensor Types**

Consider separate TaskSupervisors or DynamicSupervisors for different sensor categories (e.g., bio sensors vs GPS vs environmental). A misbehaving GPS sensor generating excessive data should not affect bio sensor processing.

### Low Priority

**10.11 Remove or Document Legacy Processes**

Evaluate `SyncWorker`, `LobbyModeStore`, and `ModeRoomServer`. If they are unused, remove them. If they serve a purpose, document it.

**10.12 Add Health Check Endpoint**

Create a `/health` endpoint that checks:
- Database connectivity (Repo ping)
- PubSub responsiveness (self-broadcast roundtrip)
- Key GenServer liveness (AttentionTracker, SystemLoadMonitor)
- ETS table existence
- Horde cluster membership

**10.13 Consider SyncComputer Phase Quality Filter**

Add a check in `estimate_phase/1` that rejects phases from sensors with high variance-to-mean ratios, which would indicate non-periodic signals that pollute the Kuramoto computation.

**10.14 Add PubSub Re-subscription Recovery to SyncComputer**

When SyncComputer restarts, it correctly schedules sensor discovery after 500ms. Consider also having it listen for `discovery:sensors` events that arrive during the discovery delay to avoid the 2500ms blind spot.

---

## Appendix A: Failure Scenario Analysis

### Scenario 1: AttentionTracker Crash

**What happens:**
1. AttentionTracker process crashes
2. 3 ETS tables (`:attention_levels_cache`, `:sensor_attention_cache`, `:attention_sensor_views`) are destroyed
3. Domain.Supervisor restarts AttentionTracker (`:one_for_one`)
4. New empty ETS tables are created
5. All sensors now have `attention_level: :none` (default)
6. All `data:global` broadcasts stop
7. PriorityLens stops receiving data
8. LiveViews stop receiving updates

**Recovery:**
- LiveViews must call `register_view/3` again (happens on next user interaction or periodic refresh)
- Until then, data flow is paused
- SyncComputer and NoveltyDetector are unaffected (they use `data:{sensor_id}`, not `data:global`)

**Blast radius:** All LiveViews lose real-time data until they re-register.

### Scenario 2: PriorityLens Crash

**What happens:**
1. PriorityLens process crashes
2. 4 ETS tables destroyed (buffers, sockets, digests, sensor_subscriptions)
3. Lenses.Supervisor restarts PriorityLens (`:one_for_one`)
4. LensRouter still has PriorityLens registered (monitors detect crash, deregisters)
5. PriorityLens re-registers with Router on restart
6. All socket registrations are lost
7. LiveViews detect missing lens data and re-register on next mount cycle

**Recovery:**
- LiveViews re-register their sockets (typically happens on next `handle_info` or mount)
- Brief gap in data flow (< 1 second typically)
- Historical seed data is preserved in AttributeStoreTiered (unaffected)

**Blast radius:** All LiveViews lose real-time data momentarily.

### Scenario 3: Node Crash in 2-Node Cluster

**What happens (sensors):**
1. All SimpleSensor processes on crashed node die
2. Horde.Registry entries for those sensors become stale
3. After sync_interval (100ms), stale entries are cleaned
4. No automatic restart on surviving node (local DynamicSupervisor)
5. External devices reconnect via WebSocket to surviving node
6. New sensor processes are created

**What happens (rooms):**
1. RoomServer processes on crashed node die
2. Horde.DynamicSupervisor detects loss
3. Rooms are restarted on surviving node (within Horde's sync window)
4. Room state may be partially recovered via Iroh CRDT
5. RoomPresenceServer detects disconnects, updates presence

**Recovery time:**
- Rooms: seconds (Horde redistribution)
- Sensors: until device reconnects (could be seconds to minutes)

### Scenario 4: Database Connection Loss

**What happens:**
1. Ecto.Repo queries start timing out
2. Ash resource operations fail
3. Sensor data pipeline is largely unaffected (ETS-based, not DB-dependent)
4. Room creation/lookup fails if not cached
5. Authentication fails for new sessions
6. Existing LiveView sessions continue (already authenticated, data in ETS/memory)

**Blast radius:** New operations requiring DB access fail. Existing real-time sessions continue.

### Scenario 5: Memory Pressure (>70%)

**What happens:**
1. SystemLoadMonitor detects memory pressure at 70%
2. Load level escalates to `:high` or `:critical`
3. AttributeStoreTiered warm tier limits drop to 5-20% of normal
4. Warm tier data is aggressively evicted
5. PriorityLens quality may be reduced
6. HomeostaticTuner adjusts sampling parameters
7. ResourceArbiter suppresses low-priority sensors

**Recovery:** Automatic as memory pressure subsides. The 5-layer backpressure system works together to reduce memory consumption.

---

## Appendix B: Key File References

| File | Lines | Purpose |
|------|-------|---------|
| `lib/sensocto/application.ex` | ~90 | Root supervision tree |
| `lib/sensocto/infrastructure/supervisor.ex` | ~35 | Infrastructure layer |
| `lib/sensocto/registry/supervisor.ex` | ~60 | 15 registries |
| `lib/sensocto/storage/supervisor.ex` | ~30 | Storage chain |
| `lib/sensocto/bio/supervisor.ex` | ~33 | Biomimetic layer |
| `lib/sensocto/domain/supervisor.ex` | ~70 | Domain processes |
| `lib/sensocto/lenses/supervisor.ex` | ~25 | Lens pipeline |
| `lib/sensocto/otp/simple_sensor.ex` | ~683 | Core sensor process |
| `lib/sensocto/lenses/priority_lens.ex` | ~751 | Per-socket adaptive streaming |
| `lib/sensocto/otp/attention_tracker.ex` | ~1042 | Attention tracking with ETS |
| `lib/sensocto/otp/system_load_monitor.ex` | ~576 | System load sampling |
| `lib/sensocto/resilience/circuit_breaker.ex` | ~155 | Circuit breaker |
| `lib/sensocto/calls/call_server.ex` | ~788 | Video/voice call management |
| `lib/sensocto/otp/attribute_store_tiered.ex` | ~468 | ETS tiered storage |
| `lib/sensocto/lenses/router.ex` | ~127 | Data routing to lenses |
| `lib/sensocto/bio/sync_computer.ex` | ~410 | Kuramoto phase synchronization |
| `lib/sensocto/bio/novelty_detector.ex` | ~300 | Anomaly detection (Welford) |
| `lib/sensocto/otp/sensors_dynamic_supervisor.ex` | ~200 | Sensor lifecycle |
| `lib/sensocto/sensors/connector_manager.ex` | ~250 | Distributed connectors |
| `lib/sensocto/otp/room_server.ex` | ~400 | Distributed room state |
| `lib/sensocto/simulator/connector_server.ex` | ~180 | Simulated connectors |
| `lib/sensocto/simulator/supervisor.ex` | ~45 | Simulator infrastructure |
| `lib/sensocto/telemetry.ex` | ~100 | Telemetry metrics |

---

## Appendix C: Module Statistics

- **Core modules (`lib/sensocto/`):** 152 files
- **Web modules (`lib/sensocto_web/`):** 95 files
- **Total:** 247 files
- **Named ETS tables:** 13+
- **Horde registries:** 5
- **Local registries:** 10
- **GenServer processes (singletons):** ~15
- **GenServer processes (dynamic):** N sensors + N rooms + N calls
- **PubSub topics (patterns):** 15+ distinct patterns
- **Telemetry instrumentation points:** 8 files

---

## 11. Planned Work: Resilience Implications

This section assesses the resilience implications of 10 planned changes across the codebase. Each plan is evaluated for its impact on supervision trees, fault tolerance, distribution, backpressure, and failure modes.

### 11.1 Room Iroh Migration (PLAN-room-iroh-migration.md)

**Plan summary:** Migrate room persistence from PostgreSQL to an in-memory GenServer (RoomStore) with Iroh document storage for distributed state synchronization. Removes Ash/Ecto dependency for rooms.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Supervision tree** | Adds Iroh.RoomSync and restructured RoomStore to Storage.Supervisor. The plan correctly notes that RoomSync must start before RoomStore (hydration dependency). Storage.Supervisor already uses `:rest_for_one`, so this ordering is naturally enforced -- good. |
| **Durability** | Moving from PostgreSQL (ACID, disk-backed) to in-memory + Iroh docs trades durability for speed. If both RoomStore and Iroh.RoomSync crash simultaneously, and Iroh docs are corrupted or unavailable, rooms are lost until the next Iroh doc sync or manual recovery. PostgreSQL was the safety net -- removing it means Iroh IS the safety net. |
| **Distribution** | Iroh provides P2P CRDT synchronization, which could replace or complement the current Horde-based room distribution. However, the plan does not address how this interacts with existing `Horde.DynamicSupervisor` for rooms. Running both Horde room supervision and Iroh room sync creates dual state authority -- which is the source of truth during a conflict? |
| **Recovery** | The hydration-on-startup pattern (load from Iroh docs on init) creates a startup dependency on Iroh. If Iroh is slow or unavailable at boot, RoomStore starts with empty state. The plan includes a "hydrate_from_iroh()" call but does not specify a timeout or fallback. |
| **Recommendation** | Ensure RoomStore has a "degraded" mode where it operates with in-memory-only state if Iroh hydration fails, rather than blocking startup. Add explicit hydration timeout (e.g., 10s) with fallback to empty state + retry timer. Define which is authoritative: Horde or Iroh. |

### 11.2 Adaptive Video Quality (PLAN-adaptive-video-quality.md)

**Plan summary:** Enable 100+ participant video calls by dynamically switching between full video, reduced video, JPEG snapshots, and static avatars based on participant attention and speaking activity. Status: implemented.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Supervision tree** | Adds SnapshotManager (GenServer with ETS) as a singleton. CallServer already exists under CallSupervisor (DynamicSupervisor). SnapshotManager has no TableOwner -- its ETS table dies with the process. |
| **State growth** | SnapshotManager stores JPEG snapshots in ETS keyed by user_id. With 100 participants, each storing a ~20KB JPEG, that is ~2MB per room. With 10 concurrent rooms, ~20MB. The 60s TTL cleanup prevents unbounded growth. Acceptable. |
| **Failure modes** | If SnapshotManager crashes: ETS table dies, all cached snapshots are lost. Viewers in snapshot mode see stale/no images until the next capture cycle. Self-healing within 1-2 seconds. Low blast radius -- video-mode participants are unaffected. |
| **CallServer complexity** | CallServer grows from 13 to 16+ struct fields (participant_attention, active_speaker, quality_tier_counts). The 5-second tier update timer adds periodic work. Combined with the existing `IO.puts` calls (Section 8.6) and the lack of `code_change/3`, this state growth makes hot upgrades harder. |
| **Backpressure** | The tier system IS backpressure for video. Active/recent/viewer/idle is directly analogous to the sensor attention levels. This is well-aligned with the system's philosophy. Snapshots sent via data channel avoid the Membrane RTC Engine media pipeline, which is correct. |
| **Recommendation** | Create `SnapshotManager.TableOwner` to separate ETS ownership from the GenServer logic. Replace `IO.puts` in CallServer as part of this work. Implement `code_change/3` on CallServer before further state additions. |

### 11.3 Sensor Component Migration (PLAN-sensor-component-migration.md)

**Plan summary:** Migrate StatefulSensorLive (separate LiveView processes per sensor tile) to StatefulSensorComponent (LiveComponent running in parent's process). Reduces 73 processes + 288 PubSub subscriptions to 1 process + ~5 subscriptions.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Process count** | Dramatic reduction: 73 processes -> 1. This is unambiguously good for memory and scheduler overhead. However, it concentrates all sensor tile state into a single process (LobbyLive). |
| **Blast radius** | **This is the key trade-off.** Currently, if one StatefulSensorLive crashes, only that sensor tile is affected. After migration, if the LobbyLive process crashes, ALL sensor tiles die simultaneously. The plan correctly identifies this but does not mitigate it. |
| **PubSub pressure** | The parent (LobbyLive) must subscribe to ALL sensor topics and route via `send_update/3`. This concentrates all sensor PubSub traffic into one process's mailbox. With 100 sensors at 10Hz, that is 1000 messages/second into LobbyLive. The existing PriorityLens already batches this, but the migration adds `send_update` overhead per component per flush. |
| **Fault tolerance** | LiveComponents cannot receive messages directly -- they rely on the parent forwarding via `send_update/3`. If the parent's mailbox is saturated, component updates stall. There is no backpressure mechanism between parent and components. |
| **Attention integration** | AttentionTracker register/unregister calls move from per-sensor processes to the parent. A single process managing attention for all sensors means a single point of serialization for attention state. |
| **Recommendation** | Implement mailbox depth monitoring on LobbyLive after migration. If `Process.info(self(), :message_queue_len)` exceeds a threshold (e.g., 500), signal PriorityLens to reduce quality. This closes the backpressure loop between the concentrated process and the lens system. Consider keeping PriorityLens as the primary data path (it already batches and flushes efficiently) rather than adding direct PubSub subscriptions in the parent. |

### 11.4 Startup Optimization (PLAN-startup-optimization.md)

**Plan summary:** Defer simulator database hydration from 100-200ms to 5000-6000ms post-boot. Convert blocking `Ash.read!()` calls to async patterns. Status: implemented.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Startup sequence** | The changes are straightforward and well-executed. Moving from synchronous `Ash.read!()` to async `Task.Supervisor` patterns means GenServer `init/1` completes immediately, allowing the supervision tree to finish starting. HTTP server becomes responsive within 1-2 seconds instead of potentially 30+ seconds. |
| **Degraded startup** | During the 5-6 second hydration window, the simulator has no historical state. Requests for running scenarios return empty results. This is acceptable for the simulator use case. |
| **Error handling** | The conversion from `Ash.read!()` to `Ash.read()` with pattern matching is a resilience improvement -- the bang version crashes the process on any DB error, while the non-bang version allows graceful handling. |
| **Assessment** | This plan is already implemented and poses no new resilience risks. It is a net positive -- the system is more resilient at startup because individual hydration failures do not cascade into supervision tree failures. |

### 11.5 Delta Encoding for ECG Data (plans/delta-encoding-ecg.md)

**Plan summary:** Implement delta encoding for high-frequency ECG waveform data, reducing WebSocket bandwidth by ~84% (1000 bytes -> 162 bytes per 50-sample batch). Feature-flagged.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **PriorityLens modification** | The plan modifies `flush_batch/3` in PriorityLens to conditionally encode ECG data. PriorityLens is a singleton GenServer that processes all socket flushes. Adding encoding work (CPU-bound) to the flush path could increase flush latency under load. |
| **Error propagation** | The plan includes a fallback: if encoding fails, data passes through unencoded. This is correct. The decoder returns `null` on failure, and data is dropped. For real-time ECG, a brief gap is acceptable. |
| **Feature flag** | The `Application.get_env` call in the hot path (every flush) adds a function call per batch. This is cheap but could be cached via `:persistent_term` for zero-overhead reads. |
| **Binary format versioning** | The encoding header includes a version byte (0x01). This is forward-compatible -- old decoders reject unknown versions gracefully. |
| **Concern** | The plan creates a tight coupling between Elixir encoder and JavaScript decoder. If one is updated without the other (e.g., hot code upgrade of the Elixir encoder without reloading JS), the decoder will fail. The version byte mitigates this somewhat, but a mixed-version deployment window is a real risk. |
| **Recommendation** | Cache the feature flag in `:persistent_term` (checked once at startup or on config change). Ensure the JS decoder is loaded from cache-busted assets when the encoder version changes. Consider adding a `:telemetry.execute` event for encoding failures so they are observable. |

### 11.6 Cluster Sensor Visibility (plans/PLAN-cluster-sensor-visibility.md)

**Plan summary:** Make sensors visible across all cluster nodes by migrating local Registry and DynamicSupervisor to Horde equivalents. This directly addresses the sensor supervision mismatch identified in Section 5.2 and 8.2 of this report.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Directly fixes Critical Issue 8.2** | This plan resolves the most significant architectural concern in the current system. Migrating SensorsDynamicSupervisor to Horde.DynamicSupervisor means sensors will be redistributed on node crash. |
| **Horde CRDT overhead** | The plan acknowledges CRDT sync overhead. `DistributedSensorRegistry` already has `sync_interval: 100ms`. With 1000 sensors, the CRDT state becomes non-trivial. Every sensor registration/deregistration triggers a delta sync to all nodes. This is the same concern raised in the Sensor Scaling plan (11.8). |
| **Process.alive? limitation** | The plan correctly notes that `Process.alive?/1` only works for local PIDs. For remote PIDs, Horde's internal monitoring handles liveness. However, code that calls `Process.alive?` directly (e.g., orphan cleanup logic in ConnectorServer) will silently return `false` for live remote processes. |
| **Split-brain** | The plan lists split-brain as a medium-likelihood, high-impact risk. On Fly.io with DNS-based clustering, network partitions between regions are possible. Horde uses CRDTs which are partition-tolerant, but conflicting registrations (same sensor ID on two nodes) resolve by keeping one and killing the other -- which could disrupt a live sensor connection. |
| **Recommendation** | This plan should be implemented -- it directly fixes the most critical issue in the current architecture. However, pair it with the Sensor Scaling plan's `:pg`-based alternative (Section 11.8) for discovery, keeping Horde for supervision only. This avoids overloading Horde's CRDT with both registry and supervision duties at scale. |

### 11.7 Distributed Discovery (plans/PLAN-distributed-discovery.md)

**Plan summary:** Build a 4-layer distributed discovery system: entity registries (Horde), per-node discovery cache (ETS + CRDT sync), public discovery API, and background sync mechanism with debounced updates.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Supervision tree** | Adds 3 new processes to Domain.Supervisor: NodeHealth, DiscoveryCache, SyncWorker. Given Domain.Supervisor's existing concerns (Section 8.1 -- wrong strategy, too many children), adding more children increases the restart budget pressure. |
| **Stale-data-preferred design** | The cache returns stale data rather than blocking on cross-node calls. This is exactly right for a real-time system. A 5-second staleness threshold means the UI shows slightly outdated sensor lists rather than hanging. |
| **NodeHealth circuit breaker** | A per-node circuit breaker with 3-failure threshold is a good pattern. However, it creates a second circuit breaker system alongside `Sensocto.Resilience.CircuitBreaker`. These should either be unified or clearly scoped (NodeHealth for cross-node calls, CircuitBreaker for external services). |
| **SyncWorker debouncing** | The 100ms debounce window and priority queue (deletes > creates > updates) is well-designed. The 1000-message queue limit with oldest-non-delete dropping is a good bounded-buffer pattern. |
| **Full sync safety net** | Every 30 seconds, SyncWorker does a full sync using `Task.async_stream` with max_concurrency: 20 and timeout: 5000ms. With 1000 sensors across 3 nodes, this means up to 1000 GenServer.call operations every 30 seconds. Under load, this could create a periodic spike. |
| **Recommendation** | Consider placing NodeHealth, DiscoveryCache, and SyncWorker in their own supervisor (a Discovery.Supervisor) nested under Domain.Supervisor. This isolates their restart budget from the 20+ other Domain children. Reduce full sync frequency to 60s or make it adaptive (more frequent when stale entries detected, less when cache is fresh). |

### 11.8 Sensor Scaling Refactor (plans/PLAN-sensor-scaling-refactor.md)

**Plan summary:** Multi-phase refactor for 1000+ sensor scale: replace Horde with `:pg` + local Registry for sensor lookup, shard PubSub topics by attention level, use per-socket ETS tables, add ring buffers in SimpleSensor.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Horde removal** | This plan contradicts the Cluster Sensor Visibility plan (11.6), which adds Horde for sensors. The scaling plan argues Horde's CRDT overhead becomes prohibitive at 1000+ sensors, and proposes `:pg` + local Registry as a lighter alternative. Both plans cannot be implemented as written. |
| **:pg vs Horde trade-offs** | `:pg` is built into OTP, has lower overhead, and uses membership-based groups rather than CRDTs. However, `:pg` does not provide named registration (sensor_id -> pid lookup) -- it provides group membership (which nodes have sensors). A two-tier approach (`:pg` for discovery, local Registry for lookup) requires the caller to know which node a sensor is on, then make a remote call. This is more complex but more scalable. |
| **Sharded PubSub topics** | Splitting `data:global` into `data:attention:high/medium/low` reduces fanout significantly. Instead of all data going to all subscribers, each subscriber only receives data at its attention level. This is a natural evolution of the existing attention-aware routing. |
| **Per-socket ETS tables** | Creating one ETS table per socket (`:lens_buffer_{socket_id}`) means ETS tables scale linearly with viewers. With 100 viewers, that is 100 named ETS tables. Named ETS tables are an atom-based resource -- each name consumes an atom. With short-lived LiveView sessions, this could create atom exhaustion over time. |
| **Ring buffer in SimpleSensor** | Adding a ring buffer to SimpleSensor state increases per-process memory but eliminates the need for AttributeStoreTiered for recent data. This is a sound trade-off -- the data is already in the process, why copy it to ETS? However, it makes `code_change/3` even more critical, since the ring buffer format would need migration on hot upgrades. |
| **Recommendation** | The `:pg` approach is the right long-term direction for sensors at scale, but implement the Cluster Visibility plan (11.6 -- Horde) first as it solves the immediate mismatch problem. Migrate to `:pg` later if Horde CRDT overhead becomes measurable. For per-socket ETS, use reference-based table names (not atom-based) to avoid atom exhaustion. |

### 11.9 Research-Grade Synchronization (plans/PLAN-research-grade-synchronization.md)

**Plan summary:** Extend the current Kuramoto sync computation with research-grade metrics: PLV, TLCC, wavelet coherence, cross-recurrence analysis, DTW, and interpersonal recurrence networks. Includes both real-time (Svelte) and post-hoc (Pythonx) components.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **Pythonx integration** | Post-hoc analysis via Pythonx (Elixir -> Python NIF bridge) introduces a new failure domain. Python processes can crash with segfaults, hang on GIL contention, or consume unbounded memory. These failures would propagate into the BEAM as NIF crashes, potentially taking down the calling process. |
| **New modules** | 8 new Elixir analysis modules and 8 new Svelte components. The analysis modules should be supervised independently -- a crash in SurrogateTest should not affect PLV computation. A dedicated `Analysis.Supervisor` with `:one_for_one` strategy is appropriate. |
| **Computational load** | CRQA has O(T^2) space complexity. For a 30-minute session at 1Hz, T=1800, giving a 1800x1800 matrix per pair. With N=10 participants, that is 45 pairs, each producing a ~13MB matrix. Total: ~580MB for one session analysis. This must run in a bounded-concurrency worker pool, not in the hot path. |
| **Database growth** | `sync_reports` table with JSONB results per pair per metric per session. A 10-person session with 6 metrics produces 45 pairs x 6 = 270 report rows plus group metrics. This is manageable but should have a retention policy. |
| **Real-time impact** | PLV and TLCC computed client-side in Svelte are CPU-intensive for N>10 participants. 190 pairs with 30s windows at 5s steps means continuous matrix computation. This could cause frame drops and UI jank on lower-end devices. There is no server-side backpressure on client-side computation. |
| **Recommendation** | Run all Pythonx analysis through `Task.Supervisor` with explicit `max_concurrency` (e.g., 2 concurrent analyses) and memory monitoring. Implement a `Sensocto.Analysis.Supervisor` under Domain.Supervisor. For real-time PLV/TLCC, add a participant count threshold (e.g., N<=12) above which the matrix view is disabled and only the existing Kuramoto R is shown. |

### 11.10 TURN/Cloudflare Integration (plans/PLAN-turn-cloudflare.md)

**Plan summary:** Add Cloudflare TURN relay for WebRTC calls to support mobile devices behind symmetric NAT. Credentials cached in `:persistent_term` with 24h TTL. Status: implemented.

**Resilience implications:**

| Dimension | Assessment |
|-----------|------------|
| **No new processes** | Uses `:persistent_term` instead of a GenServer for credential caching. This is the lightest possible pattern -- no process to crash, no supervision needed, lock-free reads. Excellent choice. |
| **Failure mode** | If Cloudflare API is unreachable, TURN credentials are not generated. Calls fall back to STUN-only. Desktop users are unaffected; mobile users on CGNAT cannot connect. This is a graceful degradation -- the system does not crash, it just reduces capability. |
| **Credential refresh race** | Multiple concurrent call joins could trigger simultaneous Cloudflare API requests if the cache expires during a burst. The current implementation does not lock during refresh -- two processes could both see expired cache, both call the API, and both write to `:persistent_term`. This is harmless (last-writer-wins, both get valid credentials) but wastes API calls. |
| **:persistent_term update cost** | Writing to `:persistent_term` triggers a global GC on all processes. With credentials refreshing every 23 hours, this happens at most once per day -- negligible. But if the refresh logic had a bug causing rapid updates, it could trigger GC storms. |
| **Assessment** | This is a well-implemented, low-risk change. The failure mode is graceful, the caching is appropriate, and there are no supervision tree impacts. |

### 11.11 Cross-Plan Conflicts and Dependencies

Several plans have interactions that must be resolved before implementation:

**Conflict: Cluster Sensor Visibility (11.6) vs Sensor Scaling Refactor (11.8)**

Both address the sensor supervision mismatch but propose incompatible solutions:
- 11.6 adds Horde.DynamicSupervisor for sensors (distributed supervision)
- 11.8 removes Horde for sensors and uses `:pg` + local Registry

**Resolution path:** Implement 11.6 first (Horde) to fix the immediate mismatch. Monitor CRDT overhead as sensor count grows. If overhead becomes problematic above 500 sensors, migrate to the `:pg` hybrid approach from 11.8. The `:pg` approach is architecturally superior at scale but requires more work.

**Dependency chain:**

```
11.4 (Startup Optimization) -- already implemented, no dependencies
11.10 (TURN/Cloudflare) -- already implemented, no dependencies
11.6 (Cluster Visibility) -- foundation for 11.7
11.7 (Distributed Discovery) -- depends on 11.6
11.8 (Sensor Scaling) -- conflicts with 11.6, alternative path at scale
11.3 (Sensor Component Migration) -- independent, but affects PubSub pressure from 11.8
11.5 (Delta Encoding) -- independent, modifies PriorityLens flush path
11.2 (Adaptive Video) -- already implemented, independent
11.1 (Room Iroh Migration) -- independent, modifies Storage.Supervisor
11.9 (Research Sync) -- depends on stable sensor data pipeline (all of above)
```

**Recommended implementation order for resilience:**

1. Fix Domain.Supervisor strategy (from Section 10.4 -- prerequisite for adding more children)
2. Implement 11.6 (Cluster Visibility) -- fixes the most critical architectural gap
3. Implement 11.7 (Distributed Discovery) -- builds on 11.6
4. Implement 11.3 (Sensor Component Migration) -- reduces process count
5. Implement 11.5 (Delta Encoding) -- reduces bandwidth
6. Implement 11.1 (Room Iroh Migration) -- restructures storage
7. Implement 11.9 (Research Sync) -- last, depends on stable pipeline
8. Evaluate 11.8 (Sensor Scaling) -- only if Horde overhead becomes measurable

### 11.12 Cumulative Supervision Tree Impact

If all plans are implemented, the supervision tree changes as follows:

**New processes added:**
- `SnapshotManager` (from 11.2 -- already present)
- `NodeHealth` (from 11.7)
- `DiscoveryCache` (from 11.7)
- `SyncWorker` (from 11.7)
- `Analysis.Supervisor` + children (from 11.9)
- Restructured `RoomStore` + `Iroh.RoomSync` (from 11.1)

**Processes removed:**
- StatefulSensorLive instances (from 11.3 -- replaced by LiveComponents in parent)
- Potentially legacy processes (SyncWorker, LobbyModeStore, ModeRoomServer) if cleaned up

**Net effect on Domain.Supervisor:** 3-4 additional children (NodeHealth, DiscoveryCache, SyncWorker, Analysis.Supervisor). This makes the Domain.Supervisor strategy fix (`:one_for_one` -> `:rest_for_one` or a nested sub-supervisor) even more urgent. Without it, 24+ children under `:one_for_one` creates a fragile topology where any dependency failure silently degrades the system.

**Strong recommendation:** Before implementing any of these plans, refactor Domain.Supervisor into sub-supervisors:

```
Domain.Supervisor (:rest_for_one)
  |-- Core.Supervisor (:one_for_one)
  |     |-- AttentionTracker.TableOwner
  |     |-- AttentionTracker
  |     |-- SystemLoadMonitor
  |     |-- Lenses.Supervisor
  |     |-- AttributeStoreTiered.TableOwner
  |
  |-- Sensors.Supervisor (:one_for_one)
  |     |-- SensorsDynamicSupervisor
  |     |-- ConnectorManager
  |
  |-- Rooms.Supervisor (:one_for_one)
  |     |-- RoomsDynamicSupervisor
  |     |-- CallSupervisor
  |     |-- MediaPlayerSupervisor
  |     |-- WhiteboardSupervisor
  |     |-- Object3DPlayerSupervisor
  |     |-- ChatSupervisor
  |
  |-- Discovery.Supervisor (:one_for_one)
  |     |-- NodeHealth
  |     |-- DiscoveryCache
  |     |-- SyncWorker
  |
  |-- Analysis.Supervisor (:one_for_one)
        |-- (from 11.9)
```

This gives each domain its own restart budget, isolates failure domains, and makes the system comprehensible as it grows.


---

## Conclusion

Sensocto's architecture demonstrates a deep understanding of OTP principles. The attention-aware routing system is an elegant innovation that most BEAM applications lack -- the insight that "the best way to handle load is to not create it in the first place" is exactly right. The five-layer backpressure system, while complex, provides genuine resilience against varying load conditions.

The primary risks are structural rather than algorithmic:
1. The sensor supervision mismatch (local supervisor, distributed registry) is the most significant gap for multi-node deployments
2. The absence of `code_change/3` blocks safe hot code upgrades
3. The Domain.Supervisor strategy mismatch creates silent failure modes

These are addressable without major refactoring. The system's foundations are sound. The supervision tree hierarchy is well-layered, the data pipeline is well-instrumented, and the biomimetic layer adds genuine adaptive capacity rather than just complexity.

As Joe Armstrong would say: the processes are right, the isolation is right, the message passing is right. Now make the supervision match the failure modes, and this system will run for years.

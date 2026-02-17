# Sensocto OTP Architecture and Resilience Assessment

**Generated:** 2026-02-08, **Updated:** 2026-02-17 (scalability revision with live measurement data)
**Author:** Resilient Systems Architect Agent
**Codebase Version:** Based on commit 853f702 (main branch)
**Previous Report:** 2026-02-15

---

## Executive Summary

Sensocto is a real-time sensor platform built on Phoenix/LiveView with a sophisticated biomimetic adaptive layer. The system demonstrates strong architectural instincts -- layered supervision, attention-aware data routing, multi-layer backpressure, and ETS-backed concurrent state. It is clear the developers understand OTP patterns and have applied them thoughtfully.

Several structural issues have been identified and progressively addressed. Recent work (Feb 2026) resolved the sensor registry mismatch (migrating from Horde to `:pg` + local Registry), sharded PubSub topics by attention level, optimized the data pipeline with ETS direct-writes bypassing GenServer mailboxes, and added connector "honey badger" resilience (hydration gates, health checks, room deletion detection). The Distributed Discovery system (DiscoveryCache + SyncWorker) has been implemented and integrated into Domain.Supervisor. A ChatStore (ETS-backed, in-memory) has been added for lobby/room chat and AI agent conversations. The AttentionTracker gained bulk registration/unregistration APIs to prevent thundering herd on graph views.

**Overall Resilience Grade: A-** (maintained from prior assessment)

The system is well above average for Elixir applications. The attention-aware routing, five-layer backpressure system, and ETS direct-write optimization are genuinely innovative. Live measurements with 152 sensors revealed that the SimpleSensor GC fix reduced per-sensor process memory from 2.1 MB to 175 KB (12x improvement), but ETS warm store is now the dominant memory consumer at 3.6 MB/sensor. A single node can support ~1,400 sensors with current caps, or ~4,000 with the recommended warm store cap reduction. Remaining gaps: ETS warm store scaling, Domain.Supervisor strategy mismatch, absence of `code_change/3`, and database retention policy.

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
12. [Changes Applied (Feb 2026)](#12-changes-applied-feb-2026)
13. [Scalability Analysis](#13-scalability-analysis)

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
  |-- L2: Registry.Supervisor          (:one_for_one, 5/5s)
  |     |-- :pg scope (:sensocto_sensors) -- cluster-wide sensor discovery
  |     |-- 3x Horde.Registry (distributed)
  |     |     |-- DistributedRoomRegistry
  |     |     |-- DistributedJoinCodeRegistry
  |     |     |-- DistributedConnectorRegistry
  |     |-- 12x Registry (local)
  |           |-- SimpleSensorRegistry (sensor process lookup)
  |           |-- SensorPairRegistry, SensorsRegistry, SensorRegistry,
  |           |-- SimpleAttributeRegistry, RoomRegistry, RoomJoinCodeRegistry,
  |           |-- CallRegistry, MediaRegistry, Object3DRegistry,
  |           |-- WhiteboardRegistry, TestRegistry
  |
  |-- L3: Storage.Supervisor           (:rest_for_one, 3/5s)
  |     |-- Iroh.ConnectionManager (shared iroh node -- MUST start first)
  |     |-- Iroh.RoomStore
  |     |-- HydrationManager
  |     |-- RoomStore
  |     |-- Iroh.RoomSync
  |     |-- Iroh.RoomStateCRDT
  |     |-- RoomPresenceServer
  |
  |-- L4: Bio.Supervisor               (:one_for_one, 10/60s)
  |     |-- NoveltyDetector
  |     |-- PredictiveLoadBalancer
  |     |-- HomeostaticTuner
  |     |-- ResourceArbiter
  |     |-- CircadianScheduler
  |     |-- SyncComputer
  |
  |-- L5: Domain.Supervisor            (:one_for_one, 5/10s)  ** SEE CONCERNS **
  |     |-- BleConnectorGenServer, SensorsStateAgent, Connector (legacy)
  |     |-- AttentionTracker.TableOwner
  |     |-- AttentionTracker
  |     |-- SystemLoadMonitor
  |     |-- Lenses.Supervisor (:one_for_one, 5/10s)
  |     |     |-- Router, ThrottledLens, PriorityLens
  |     |-- AttributeStoreTiered.TableOwner
  |     |-- SensorsDynamicSupervisor (local DynamicSupervisor)
  |     |-- DiscoveryCache (NEW -- ETS-backed distributed entity cache)
  |     |-- SyncWorker (NEW -- event-driven cluster sync)
  |     |-- ConnectorManager
  |     |-- RoomsDynamicSupervisor (Horde.DynamicSupervisor)
  |     |-- CallSupervisor
  |     |-- MediaPlayerSupervisor
  |     |-- Object3DPlayerSupervisor
  |     |-- WhiteboardSupervisor
  |     |-- RepoReplicatorPool (8 workers)
  |     |-- SearchIndex
  |     |-- GuestUserStore (NEW -- 2h TTL guest sessions)
  |     |-- ChatStore (NEW -- ETS-backed chat messages, 24h TTL)
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
| Registry | :one_for_one | 5 | 5s | Appropriate -- registries rarely crash |
| Storage | :rest_for_one | 3 | 5s | Correct -- storage has ordering dependencies |
| Bio | :one_for_one | 10 | 60s | Good -- generous budget appropriate for non-critical bio components |
| Domain | :one_for_one | 5 | 10s | **Concern: wrong strategy** (see Section 8) |
| Lenses | :one_for_one | 5 | 10s | Appropriate |

### 1.3 Observations

**Strengths:**
- The 7-layer `:rest_for_one` root is excellent. Infrastructure crashes correctly cascade.
- Storage.Supervisor uses `:rest_for_one` with Iroh.ConnectionManager first, ensuring all downstream iroh-dependent processes restart on connection loss. Textbook usage.
- Restart budgets are generally reasonable. Not too loose (would mask flapping), not too tight (would escalate too quickly).
- Bio.Supervisor has explicit `max_restarts: 10, max_seconds: 60` -- generous and appropriate for non-critical observers.

**Concerns:**
- **Domain.Supervisor uses `:one_for_one` but has ordering dependencies** (see Section 8.1). Now has 22 children -- this is growing unwieldy.
- **SensoctoWeb.Telemetry lives in Infrastructure.Supervisor** -- a web module in a core supervisor creates a coupling that complicates any future separation.
- **Domain.Supervisor child count is increasing**: DiscoveryCache, SyncWorker, GuestUserStore, and ChatStore have been added since initial design. 22 children under one supervisor is approaching the point where sub-supervisors become necessary for comprehensibility and failure isolation.

---

## 2. Data Pipeline Analysis

### 2.1 Primary Data Flow

PubSub sharded by attention level; Router writes directly to PriorityLens ETS.

```
External Device
  |
  v
SensorDataChannel (WebSocket)
  |
  v
SimpleSensor (GenServer via local SimpleSensorRegistry + :pg)
  |-- writes to AttributeStoreTiered (ETS: hot + warm tiers)
  |-- broadcasts to "data:{sensor_id}" (always, bypasses attention)
  |-- if attention_level != :none:
  |     broadcasts to "data:attention:{high|medium|low}" (sharded by attention level)
  |
  v
Lenses.Router (subscribed to 3 attention topics, demand-driven)
  |-- Direct ETS write: PriorityLens.buffer_for_sensor/2 (bypasses GenServer)
  |
  v
PriorityLens ETS tables (per-socket buffering, :public access)
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

The `data:attention:{high|medium|low}` topics are attention-gated and sharded (only broadcasts when `attention_level != :none`), creating an elegant two-tier system:
- Infrastructure consumers (sync, novelty) always get data via per-sensor topics
- UI consumers only get data for sensors someone is watching, further sharded by attention priority

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

### 2.4 Discovery Data Path (NEW)

```
SimpleSensor init/terminate
  |-- broadcasts {:sensor_registered, ...} / {:sensor_unregistered, ...}
  |-- on "discovery:sensors" PubSub topic
  |
  v
SyncWorker (event-driven, subscribed to "discovery:sensors")
  |-- Debounces updates (100ms window)
  |-- Deletes processed immediately (high priority)
  |-- Monitors :nodeup/:nodedown for cluster membership
  |
  v
DiscoveryCache (ETS-backed, :discovery_sensors)
  |-- Fast local reads (no GenServer for reads)
  |-- Staleness tracking (5s threshold)
  |-- Serialized writes via GenServer
```

This is a clean implementation of the Distributed Discovery plan (11.7). The event-driven design eliminates the periodic 30s full-sync overhead that was a concern in the original plan. Full sync only runs on startup or manual trigger (`force_sync/0`).

### 2.5 Pipeline Assessment

**Strengths:**
- Clean separation between always-on (per-sensor) and attention-gated (global) data paths
- ETS-backed buffering in PriorityLens avoids GenServer mailbox buildup
- Timer-based flush with quality tiers provides graceful degradation
- Historical seed data uses proper handshake, not timing hacks
- Discovery system is event-driven with proper debouncing and node-down cleanup

**Concerns:**
- ~~**Single Router GenServer bottleneck**~~ **Mitigated.** Router writes directly to public ETS tables. PubSub fan-out reduced via attention-level sharding.
- **No dead letter handling.** If a PubSub subscriber dies between subscription and message delivery, messages are silently dropped. Acceptable for real-time data but worth noting.

---

## 3. Backpressure and Flow Control

Sensocto implements five layers of backpressure, which is genuinely impressive for a system of this scale.

### Layer 1: Attention-Aware Routing (SimpleSensor)

SimpleSensor gates broadcast based on `attention_level` and shards by level:
```elixir
# simple_sensor.ex -- broadcasts to attention-sharded topic
if state.attention_level != :none do
  Phoenix.PubSub.broadcast(Sensocto.PubSub, "data:attention:#{state.attention_level}", {:measurement, measurement})
end
```

Sensors with no viewers produce zero PubSub traffic. With 100 sensors and 5 viewers watching 10 sensors each, only 10 sensors broadcast. Additionally, the traffic is sharded across 3 topics by attention priority (high/medium/low), reducing per-topic fan-out further.

**NEW: Bulk Registration.** The AttentionTracker now supports `register_views_bulk/3` and `unregister_views_bulk/3`. This prevents the thundering herd problem when a graph view subscribes to all sensors at once -- a single cast instead of N individual casts. IndexLive uses this for the lobby graph.

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

**NEW: Philosophy shift.** The PriorityLens now defaults to maximum throughput. Preemptive sensor-count-based throttling has been removed. Degradation only occurs based on actual backpressure (mailbox depth), not predicted load. This is the correct approach -- measure, then react, rather than guess.

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
| SimpleSensor | N (per sensor) | Map | Low (~175 KB with fullsweep_after: 10) | Yes (5 min idle) |
| RoomServer | N (per room) | Struct (14 fields) | Low | No |
| AttentionTracker | 1 | Struct (7 fields) + 3 ETS | Medium (ETS grows with sensors) | No |
| SystemLoadMonitor | 1 | Struct (11 fields) | Low | No |
| PriorityLens | 1 | Minimal (4 ETS tables) | ETS grows with sockets | No |
| LensRouter | 1 | Struct (2 fields: MapSet + bool) | Low | No |
| ConnectorManager | 1 | ETS-backed | Low process state | No |
| NoveltyDetector | 1 | Map (sensor_stats) | Grows with sensors | No |
| HomeostaticTuner | 1 | Map | Low | No |
| ResourceArbiter | 1 | Map | Low | No |
| SyncComputer | 1 | Struct (4 fields + buffers) | Grows with sensors | No |
| CallServer | N (per call) | Struct (13 fields) | Medium (participant maps) | No |
| RoomStore | 1 | Struct (4 fields) | Low | No |
| DiscoveryCache | 1 | Minimal (1 ETS table) | ETS grows with sensors | No |
| SyncWorker | 1 | Map (pending_updates + timer) | Low | No |
| ChatStore | 1 | Minimal (1 ETS table) | Bounded (100 msgs/room, 24h TTL) | No |
| GuestUserStore | 1 | Minimal (1 ETS table) | Bounded (2h TTL) | No |
| Iroh.ConnectionManager | 1 | Struct (4 fields) | Very Low | No |

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
- **SimpleSensor does not trap exits.** If its supervisor terminates it (e.g., during shutdown), `terminate/2` may not run, potentially leaving stale entries in `:pg` groups and ETS tables.
- **AttentionTracker does not trap exits.** It has a TableOwner, so ETS tables survive, but the GenServer state is lost.

### 4.4 Process Monitoring

Process monitoring (via `Process.monitor/1`) is used in key locations:
- **PriorityLens**: monitors caller_pid for auto-cleanup of socket registrations
- **LensRouter**: monitors lens pids for auto-deregistration
- **AttributeServer**: monitors for cleanup
- **ConnectorManager**: monitors connector pids
- **GossipTopic**: monitors for membership

This is good practice. The PriorityLens monitoring is particularly important -- it ensures dead LiveView processes don't leave stale ETS entries.

### 4.5 Hibernation

Only SimpleSensor hibernates (after 5 minutes idle via `:hibernate` return from `handle_info`). Given that idle sensors are the common case (most sensors are not being watched), this is an excellent memory optimization. Combined with the `fullsweep_after: 10` GC tuning, active sensors stay at ~175 KB and idle sensors hibernate to near-zero heap.

**Recommendation:** Consider hibernation for RoomServer (rooms can be idle for extended periods) and CallServer (between active calls).

---

## 5. Distribution and Clustering

### 5.1 Horde and :pg Usage

3 Horde.Registry instances, 1 Horde.DynamicSupervisor, and 1 `:pg` scope:

| Component | Type | Purpose |
|-----------|------|---------|
| :sensocto_sensors | :pg scope | Cluster-wide sensor discovery (replaces Horde for sensors) |
| SimpleSensorRegistry | local Registry | Local sensor pid lookup (via_tuple) |
| DistributedRoomRegistry | Horde.Registry | Room -> pid lookup |
| DistributedJoinCodeRegistry | Horde.Registry | Join code -> room lookup |
| DistributedConnectorRegistry | Horde.Registry | Connector -> pid lookup |
| RoomsDynamicSupervisor | Horde.DynamicSupervisor | Room process lifecycle |

### 5.2 Sensor Registry Architecture (Resolved)

**RESOLVED Feb 2026.** The original Horde-based sensor registry created a mismatch between distributed registry and local supervision. This has been resolved by migrating to a two-tier approach:

1. **Local Registry** (`SimpleSensorRegistry`): Used by `via_tuple` for same-node process lookup. Fast, no CRDT overhead.
2. **:pg process groups** (`:sensocto_sensors` scope): Used for cluster-wide discovery. Sensors join on init, leave on terminate. `:pg` uses OTP's built-in membership protocol -- lighter than Horde CRDT.

**How it works now:**
- `SimpleSensor.alive?/1` checks local Registry first (fast path), falls back to `:pg.get_members/2` + `:rpc.call` for remote nodes
- `get_device_names/0` calls `:pg.which_groups(:sensocto_sensors)` -- returns all sensor IDs across cluster
- Sensors still locally supervised (DynamicSupervisor) -- this is intentional since sensors are ephemeral and reconnect when devices reconnect

**Remaining consideration:** Sensors are still not distributed-supervised (no Horde.DynamicSupervisor). This is accepted because sensor processes are driven by external device connections -- if a node crashes, devices reconnect to another node and new sensor processes are created. The `:pg` approach correctly reflects this ephemeral nature without the overhead of Horde CRDT state sync.

### 5.3 Discovery System (NEW)

The DiscoveryCache + SyncWorker combination provides a clean distributed entity discovery layer:

- **DiscoveryCache**: ETS-backed local cache with staleness tracking (5s threshold). Reads bypass GenServer entirely. Writes serialized through GenServer to prevent races.
- **SyncWorker**: Event-driven (not polling). Subscribes to `"discovery:sensors"` PubSub topic. Debounces updates (100ms). Monitors `:nodeup`/`:nodedown` for cluster membership. Deletes processed immediately (high priority), updates debounced. Full sync only on startup or manual trigger.

**Assessment:** This is a well-designed implementation. The event-driven approach eliminates the periodic full-sync overhead that was a concern in the original plan. The staleness-preferred design (return stale data rather than block) is exactly right for a real-time system.

### 5.4 PubSub Distribution

Phoenix.PubSub is configured with `pool_size: 16` and uses the `:pg` adapter (default for Phoenix.PubSub). This means:
- PubSub topics work across all cluster nodes automatically
- The pool size of 16 provides good concurrency for pub/sub operations
- No manual cluster formation is needed for PubSub (`:pg` handles it via distributed Erlang)

### 5.5 ConnectorManager Cluster Coordination

ConnectorManager uses `:pg` (process groups) for cluster-wide connector discovery and `:net_kernel.monitor_nodes(true)` for node-down detection.

### 5.6 Distribution Assessment

| Aspect | Status | Notes |
|--------|--------|-------|
| PubSub | Distributed | Via :pg, pool_size: 16, attention-sharded topics |
| Sensor discovery | Distributed | :pg process groups (`:sensocto_sensors`) + DiscoveryCache |
| Sensor lookup | Local + remote | Local Registry + :pg fallback with :rpc.call |
| Sensor supervision | Local (intentional) | DynamicSupervisor -- sensors are ephemeral |
| Room registry | Distributed | Horde.Registry |
| Room supervision | Distributed | Horde.DynamicSupervisor |
| Connector coordination | Distributed | :pg + node monitoring |
| State replication | Partial | Iroh CRDT for rooms, DiscoveryCache for sensor metadata |

---

## 6. ETS Usage and Safety

### 6.1 ETS Table Inventory

The system now uses approximately 25 named ETS tables. Key tables:

| Table | Owner | Access | read_concurrency | write_concurrency | Risk |
|-------|-------|--------|-----------------|-------------------|------|
| `:attribute_store_hot` | TableOwner | :public | Yes | Yes | Low -- bounded by type limits |
| `:attribute_store_warm` | TableOwner | :public | Yes | Yes | Low -- bounded, load-adaptive |
| `:attribute_store_metadata` | TableOwner | :public | Yes | Yes | Low |
| `:priority_lens_buffers` | PriorityLens | :public | Yes | Yes | Medium -- grows with sockets |
| `:priority_lens_sockets` | PriorityLens | :public | Yes | No | Low |
| `:priority_lens_digests` | PriorityLens | :public | Yes | Yes | Low |
| `:priority_lens_sensor_subscriptions` | PriorityLens | :public | Yes | Yes | Low |
| `:system_load_cache` | SystemLoadMonitor | :public | Yes | No | Very Low -- fixed size |
| `:attention_levels_cache` | TableOwner | :public | Yes | No | Low |
| `:sensor_attention_cache` | TableOwner | :public | Yes | No | Low |
| `:attention_sensor_views` | TableOwner | :public | Yes | No | Medium -- grows with views |
| `:circuit_breakers` | TableOwner | :public | Yes | No | Very Low |
| `:bio_novelty_scores` | NoveltyDetector | :public | Yes | No | Low -- cleanup every 5min |
| `:bio_homeostatic_data` | HomeostaticTuner | :public | Yes | Yes | Low |
| `:bio_circadian_data` | CircadianScheduler | :public | Yes | Yes | Low |
| `:bio_predictive_data` | PredictiveLoadBalancer | :public | Yes | Yes | Low |
| `:bio_attention_history` | PredictiveLoadBalancer | :public | bag | Yes | Medium |
| `:bio_resource_data` | ResourceArbiter | :public | Yes | Yes | Low |
| `:discovery_sensors` | DiscoveryCache | :public | Yes | Yes | Low |
| `:sensocto_chat_messages` | ChatStore | :public | Yes (ordered_set) | No | Bounded (100/room, 24h TTL) |
| `:throttled_lens_buffer` | ThrottledLens | :public | Yes | No | Low |
| `:guest_users` | GuestUserStore | :public | Yes | No | Bounded (2h TTL) |
| `:snapshot_manager` | SnapshotManager | :public | Yes | Yes | Low (60s TTL) |

### 6.2 ETS Ownership and Crash Impact

**AttentionTracker ETS (RESOLVED Feb 15, 2026):** Full "honey badger" crash resilience.

1. **ETS TableOwner** (`Sensocto.AttentionTracker.TableOwner`): Separate process owns all 3 ETS tables. Started before AttentionTracker in Domain.Supervisor. Tables survive tracker crashes.
2. **Crash-resilient restart**: On restart, `init/1` preserves ETS data instead of clearing it. Sensors continue broadcasting at their last-known attention levels while GenServer state rebuilds.
3. **Re-registration broadcast**: After crash-restart, broadcasts `:attention_tracker_restarted` on `"attention:lobby"` PubSub topic. LobbyLive and IndexLive re-register all their composite attention views, rebuilding GenServer state from actual active viewers.
4. **Recovery grace period**: 60s post-crash window where cleanup is suspended, giving LiveViews time to re-register.
5. **Restart counting**: Uses `persistent_term` to track crash count across restarts for observability.

**ChatStore ETS**: Owned by the ChatStore GenServer. If ChatStore crashes, the ETS table is destroyed and all chat messages are lost. This is acceptable -- chat messages are ephemeral with a 24h TTL, and the bounded size (100 messages per room) means data loss is minimal.

**DiscoveryCache ETS**: Owned by the DiscoveryCache GenServer. If it crashes, the cache is rebuilt on restart via SyncWorker's initial sync. Brief staleness during recovery is acceptable.

### 6.3 ETS Safety Assessment

All tables use `:public` access, which is correct for the BEAM (ETS `:public` means "any process on this node can read/write" -- it is not a security concern, just a concurrency model). The `read_concurrency: true` flag is appropriately set on tables that are read-heavy.

The `write_concurrency: true` flag on AttributeStoreTiered tables enables concurrent writes from multiple SimpleSensor processes, which is correct since each sensor writes to different keys.

**No ETS memory limits are configured.** ETS tables grow unbounded by default. The application-level bounds (AttributeStoreTiered limits, cleanup timers, ChatStore 100-message cap, GuestUserStore 2h TTL) provide the actual memory safety. If those bounds have bugs, ETS will consume all available memory.

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
| Timeouts | Explicit timeouts on GenServer calls | Excellent |
| Hibernation | SimpleSensor after 5min idle | Good |
| Bounded buffers | Phase buffers in SyncComputer (50/20), ChatStore (100/room) | Good |
| Parallel shutdown | ConnectorServer Task.yield_many(4000) | Good |
| Stale cleanup | SyncComputer (5min), AttentionTracker (60s), ChatStore (30min) | Good |
| Error isolation | try/rescue/catch on cross-process calls | Adequate |
| Dead socket GC | PriorityLens (1 minute cycle) | Good |
| Amortized operations | AttributeStoreTiered split at 2x limit | Good |
| Defensive reads | `:whereis` checks before ETS access | Good |
| Type-specific limits | AttributeStoreTiered per-type bounds | Good |
| Telemetry | 7 files with `:telemetry.execute` calls | Adequate |
| Safe atom conversion | ConnectorServer whitelist | Good |
| Bulk operations | AttentionTracker register_views_bulk/unregister_views_bulk | Good |
| Event-driven sync | SyncWorker with debouncing and priority queues | Good |
| Staleness-preferred reads | DiscoveryCache returns stale data rather than blocking | Good |
| Node failure handling | SyncWorker monitors :nodeup/:nodedown | Good |
| Iroh connection sharing | ConnectionManager single shared node | Good |

### 7.2 Patterns Missing or Incomplete

| Pattern | Status | Impact |
|---------|--------|--------|
| `code_change/3` | Completely absent | Blocks safe hot code upgrades |
| Distributed sensor supervision | Local only | Sensors lost on node crash (by design) |
| Circuit breaker failure decay | No decay -- counter only resets on success | Permanent half-open state possible |
| Health check endpoint | Not found in analysis | Operational blind spot |
| Bulkhead pattern | Absent | No isolation between sensor types |
| Rate limiting | Absent at PubSub level | Fast producer can flood topics |

---

## 8. Anti-Patterns and Risks

### 8.1 Domain.Supervisor Strategy Mismatch (High Risk)

`Domain.Supervisor` uses `:one_for_one` but has children with implicit ordering dependencies:

```
AttentionTracker.TableOwner  <-- required by AttentionTracker (owns ETS tables)
AttentionTracker             <-- required by SimpleSensor (via attention levels)
SystemLoadMonitor            <-- required by AttributeStoreTiered (via load levels)
Lenses.Supervisor            <-- required by LiveViews (PriorityLens)
AttributeStoreTiered.TableOwner  <-- required by SimpleSensor (ETS tables)
SensorsDynamicSupervisor     <-- requires all of the above
DiscoveryCache               <-- requires SensorsDynamicSupervisor
SyncWorker                   <-- requires DiscoveryCache
```

With `:one_for_one`, if `AttentionTracker` crashes and restarts, `SensorsDynamicSupervisor` and its sensors are NOT restarted. However, the honey badger resilience pattern mitigates this: ETS tables survive via TableOwner, and the recovery broadcast causes LiveViews to re-register. The net effect is a brief pause in attention-aware routing rather than data loss.

**The concern is now reduced from "High Risk" to "Medium Risk"** due to the honey badger pattern, but the architectural mismatch remains. With 22 children, the need for sub-supervisors is becoming acute.

**Recommended fix:**
1. Introduce sub-supervisors to group related children (see Section 10.4)
2. This also improves comprehensibility and restart budget isolation

### 8.2 Domain.Supervisor Growing Unwieldy (Medium Risk)

Domain.Supervisor now has 22 children:
- 3 legacy (BleConnectorGenServer, SensorsStateAgent, Connector)
- 2 ETS table owners
- 3 singletons (AttentionTracker, SystemLoadMonitor, Lenses.Supervisor)
- 1 attribute storage
- 2 discovery (DiscoveryCache, SyncWorker)
- 1 connector (ConnectorManager)
- 6 dynamic supervisors (Sensors, Rooms, Call, Media, Object3D, Whiteboard)
- 1 replication pool
- 1 search index
- 2 stores (GuestUserStore, ChatStore)

22 children sharing a restart budget of 5/10s means a flapping ChatStore could exhaust the budget and take down all sensors and rooms. These are completely unrelated failure domains.

### 8.3 Legacy Processes in Domain.Supervisor (Low Risk)

Three processes appear to be legacy:
- `BleConnectorGenServer` -- appears to be legacy BLE connector code
- `SensorsStateAgent` -- unclear purpose with SimpleSensor handling state
- `Connector` -- may be replaced by ConnectorManager

These add restart budget consumption without clear purpose. If they crash, they consume one of the 5 allowed restarts in 10 seconds.

### 8.4 Circuit Breaker Lacks Failure Decay (Medium Risk)

The circuit breaker tracks failure count but only resets it on success. There is no time-based decay. If a service has 4 failures (threshold: 5), then works correctly for a week, then has 1 more failure -- it opens. The historical failures from a week ago should not count against the current health.

### 8.5 IO.puts Remnants (Low Risk)

IO.puts/IO.inspect has been mostly cleaned up but remnants exist in:
- `lib/sensocto/utils/otp_dsl_genserver.ex` (2 instances) -- legacy macro DSL
- `lib/sensocto/utils/otp_dsl_genfsm.ex` (1 instance) -- legacy macro DSL
- `lib/sensocto/release.ex` (4 instances) -- appropriate for pre-boot context

The DSL macros are legacy code that appears rarely used. If they are invoked in production, the IO.puts output goes to stdout (captured by container runtime) rather than Logger (captured by observability stack).

### 8.6 ChatStore Uses GenServer.call for Writes (Low Risk)

ChatStore uses `GenServer.call` for `add_message/2`, which means the caller blocks until the write completes. For chat messages, this is fine -- the write is fast (ETS insert), and blocking provides backpressure if chat becomes hot. However, if ChatStore's mailbox grows (e.g., AI agent generating rapid messages), callers will experience latency.

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

### 9.2 SyncComputer Analysis

The SyncComputer implements Kuramoto phase synchronization to measure how synchronized breathing and HRV signals are across a group of sensors. This is mathematically sound:

1. **Phase estimation:** Uses normalized value + derivative direction to map sensor readings to [0, 2*pi]. This is a reasonable approximation for quasi-periodic signals like breathing.
2. **Kuramoto order parameter:** R = |mean(e^(i*theta))| where theta_i are per-sensor phases. R ranges from 0 (no sync) to 1 (perfect sync).
3. **Exponential smoothing:** `0.85 * prev + 0.15 * R` provides temporal stability.

**Strengths:**
- Bounded buffers (50 breathing, 20 HRV) prevent memory growth
- Minimum buffer thresholds (15, 8) prevent noisy estimates from short histories
- Task.async_stream for parallel attribute discovery with `max_concurrency: 10` and `timeout: 5000`
- Periodic stale sensor cleanup (5 minutes)
- Catch-all `handle_info` prevents mailbox pollution

**Concerns:**
- **Phase estimation assumes quasi-periodicity.** Noisy data yields meaningless phases.
- **`estimate_phase` returns `nil` for flat signals (range < 2).** Magic number -- appropriateness depends on sensor value ranges.
- **No telemetry emissions.** Valuable metrics not observable via `:telemetry`.
- **Stores to a synthetic sensor `"__composite_sync"`.** Reasonable but shares namespace with real sensors.

### 9.3 Bio Layer ETS Usage

All 6 bio components now have their own ETS tables with `write_concurrency: true` (applied in the Feb 15 optimization round). This eliminates GenServer bottlenecks for bio data reads. The tables are owned by their respective GenServers (no separate TableOwners), which means they are destroyed on crash. This is acceptable because bio data is ephemeral and non-critical -- the system functions without it, just less efficiently.

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

### High Priority

**10.2 Fix Domain.Supervisor Strategy**

Change from `:one_for_one` to `:rest_for_one`, or (preferred) introduce sub-supervisors. The honey badger pattern mitigates the worst effects, but the underlying architectural mismatch remains. With 22 children, sub-supervisors are now necessary for comprehensibility and failure isolation.

**10.3 Add Failure Decay to Circuit Breaker**

Implement time-based decay on the failure counter:
```elixir
effective_failures = failure_count * :math.pow(0.5, elapsed / decay_period)
```

**10.4 Refactor Domain.Supervisor into Sub-Supervisors**

The current 22-child flat structure needs to be decomposed:

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
  |     |-- DiscoveryCache
  |     |-- SyncWorker
  |     |-- ConnectorManager
  |
  |-- Rooms.Supervisor (:one_for_one)
  |     |-- RoomsDynamicSupervisor
  |     |-- CallSupervisor
  |     |-- MediaPlayerSupervisor
  |     |-- WhiteboardSupervisor
  |     |-- Object3DPlayerSupervisor
  |     |-- ChatStore
  |
  |-- Services.Supervisor (:one_for_one)
  |     |-- RepoReplicatorPool
  |     |-- SearchIndex
  |     |-- GuestUserStore
  |
  |-- Legacy.Supervisor (:one_for_one)
        |-- BleConnectorGenServer
        |-- SensorsStateAgent
        |-- Connector
```

This gives each domain its own restart budget, isolates failure domains, and makes the system comprehensible as it grows. A flapping ChatStore no longer affects sensor processing.

### Medium Priority

**10.5 Add Telemetry to SyncComputer**

```elixir
:telemetry.execute(
  [:sensocto, :bio, :sync],
  %{value: smoothed, raw: r, sensor_count: n},
  %{group: group}
)
```

**10.6 Consider Hibernation for RoomServer and CallServer**

Both can be idle for extended periods. Adding `{:noreply, state, :hibernate}` on idle timeouts would reduce memory footprint of inactive rooms and calls.

**10.7 Add Bulkhead Isolation for Sensor Types**

Consider separate TaskSupervisors or DynamicSupervisors for different sensor categories (e.g., bio sensors vs GPS vs environmental). A misbehaving GPS sensor generating excessive data should not affect bio sensor processing.

### Low Priority

**10.8 Remove or Document Legacy Processes**

Evaluate `BleConnectorGenServer`, `SensorsStateAgent`, and `Connector`. If they are unused, remove them. If they serve a purpose, document it.

**10.9 Add Health Check Endpoint**

Create a `/health` endpoint that checks:
- Database connectivity (Repo ping)
- PubSub responsiveness (self-broadcast roundtrip)
- Key GenServer liveness (AttentionTracker, SystemLoadMonitor)
- ETS table existence
- Horde cluster membership

**10.10 Consider SyncComputer Phase Quality Filter**

Add a check in `estimate_phase/1` that rejects phases from sensors with high variance-to-mean ratios, which would indicate non-periodic signals that pollute the Kuramoto computation.

**10.11 Clean Up DSL IO.puts**

Replace IO.puts in `otp_dsl_genserver.ex` and `otp_dsl_genfsm.ex` with Logger calls, or remove the DSL macros entirely if they are unused.

---

## 12. Changes Applied (Feb 2026)

This section documents the resilience and scaling improvements implemented in February 2026.

### 12.1 Sensor Registry Migration (Horde -> :pg + local Registry)

**Files modified:** `simple_sensor.ex`, `registry/supervisor.ex`, `sensors_dynamic_supervisor.ex`, `discovery/sync_worker.ex`

- Replaced `DistributedSensorRegistry` (Horde) with `SimpleSensorRegistry` (local Registry) + `:pg` process groups
- `via_tuple` uses local Registry for fast same-node lookup
- `:pg.join/leave` in sensor init/terminate for cluster-wide discovery
- `alive?/1` two-tier check: local Registry -> `:pg` + `:rpc.call`
- `get_device_names/0` uses `:pg.which_groups(:sensocto_sensors)`

### 12.2 PubSub Attention Sharding

**Files modified:** `simple_sensor.ex`, `router.ex`

- Replaced monolithic `"data:global"` with 3 attention-sharded topics
- Router subscribes/unsubscribes from all 3 topics (demand-driven)
- Reduces per-topic fan-out by ~3x

### 12.3 ETS Direct-Write Pipeline Optimization

**Files modified:** `priority_lens.ex`, `router.ex`

- Made PriorityLens buffer functions public
- Router calls these directly instead of `send/2` to PriorityLens GenServer
- Hot data path is entirely GenServer-free

### 12.4 RoomStore Hydration Gate

**File modified:** `room_store.ex`

- Added `hydrated: false` field, `ready?/0` public API
- Manager gates connector restoration on `RoomStore.ready?()`

### 12.5 Manager Periodic Health Check

**File modified:** `manager.ex`

- 30s periodic `:health_check` prunes orphaned connectors

### 12.6 SensorServer Room Deletion Detection

**File modified:** `sensor_server.ex`

- After 6 consecutive failures, checks DB via Ash. Sets `:permanently_lost` if room deleted.

### 12.7 BEAM VM Tuning

**Files modified:** `rel/vm.args.eex`, `run.sh`

- Production: `+Q 65536`, `+K true`, `+A 64`, `+SDio 64`, `+sbwt none`

### 12.8 Low-Hanging Fruit Optimization Rounds (Feb 15, 2026)

Three rounds of targeted improvements:

**Round 1: ETS and Pipeline** -- write_concurrency on hot-path tables, PubSub pool alignment, database indexes
**Round 2: Dead Code and ETS** -- removed unused code paths, additional ETS write_concurrency for Bio modules
**Round 3: Safety and Observability** -- SafeKeys atom exhaustion fix, GenServer call timeouts, IO.puts cleanup, Bio.Supervisor restart limits, email sender centralization

### 12.9 Distributed Discovery (Feb 2026)

**New files:** `discovery/discovery_cache.ex`, `discovery/sync_worker.ex`
**Modified:** `domain/supervisor.ex`

- DiscoveryCache: ETS-backed sensor metadata cache with staleness tracking
- SyncWorker: Event-driven cluster sync (no periodic polling)
- Debounced updates, immediate deletes, node-down cleanup
- Added to Domain.Supervisor after SensorsDynamicSupervisor

### 12.10 AttentionTracker Bulk Registration (Feb 2026)

**File modified:** `attention_tracker.ex`

- Added `register_views_bulk/3` and `unregister_views_bulk/3`
- Prevents thundering herd when graph views subscribe to all sensors
- IndexLive uses bulk registration for lobby graph

### 12.11 ChatStore (Feb 2026)

**New file:** `chat/chat_store.ex`
**Modified:** `domain/supervisor.ex`

- ETS-backed chat message storage (`:sensocto_chat_messages`)
- Bounded: 100 messages per room, 24h TTL, 30-minute cleanup cycle
- PubSub integration for real-time message delivery
- Added to Domain.Supervisor

### 12.12 Iroh Connection Manager (Feb 2026)

**New file:** `iroh/connection_manager.ex`
**Modified:** `storage/supervisor.ex`

- Single shared iroh node connection (previously each component created its own)
- Placed first in Storage.Supervisor (`:rest_for_one` ensures downstream restart)
- Graceful degradation when IrohEx NIF unavailable

### 12.13 Shared LiveView Helper (Feb 2026)

**New file:** `sensocto_web/live/helpers/sensor_data.ex`

- Extracted `group_sensors_by_user/1` and `enrich_sensors_with_attention/1` from LobbyLive
- Shared between LobbyLive and IndexLive
- Reduces code duplication for sensor data transformation

### 12.14 SyncComputer Buffer Optimization (Feb 17, 2026)

**File modified:** `lib/sensocto/bio/sync_computer.ex` (`append_to_buffer/5`)

Changed the hot-path buffer append from:
```elixir
Enum.take(buffer ++ values, -buffer_size)
```
to:
```elixir
combined = :lists.append(buffer, values)
excess = length(combined) - buffer_size
if excess > 0, do: Enum.drop(combined, excess), else: combined
```

The original approach was O(n) in both the concatenation (allocating a full intermediate list) and the `Enum.take` scan from the head to find the tail. The new approach uses `:lists.append/2` (a native BIF), then `Enum.drop/2` only when there is actual overflow -- O(excess) rather than O(n). For breathing buffers (max 50) with typical batch sizes of 1-5, the working set stays small, and GC pressure on the hot computation loop is meaningfully reduced. This matters because `append_to_buffer/5` is called on every incoming sensor measurement for all sensors registered with SyncComputer.

**Resilience implication:** Lower GC pressure on the SyncComputer process reduces the risk of that GenServer becoming a mailbox bottleneck during high-sensor-count events. The Bio.Supervisor's generous budget (10/60s) absorbs crashes, but a slow SyncComputer causes measurement staleness that degrades synchronization accuracy before any crash occurs.

### 12.15 SyncComputer Throttled Broadcasting (Feb 17, 2026)

**File modified:** `lib/sensocto/bio/sync_computer.ex` (`maybe_broadcast_sync/4`)

Added a 200ms per-sync-type throttle on PubSub broadcasts. State tracks `last_broadcast` timestamps per sync type. The broadcast only fires if `System.monotonic_time(:millisecond) - last_broadcast >= 200`. If not, the new value replaces the pending value but no PubSub message is sent until the throttle window lapses.

**Before:** With N active sensor pairs and a flush interval of ~16ms, SyncComputer was emitting 300+ PubSub events per second on the `"sync:updates"` topic. Downstream consumers (LobbyLive, LiveView graph hooks) were receiving more updates than the UI could render at 60fps.

**After:** Capped at ~5 broadcasts per second per sync type (~22/sec total for 4-5 sync types). The most recent computed value is always the one broadcast when the window opens -- no stale values are delivered, since each throttle window selects the latest computation. This is a correct rate-limiting strategy: compute eagerly, transmit lazily.

**Resilience implication:** Eliminates a class of thundering-herd failure where a spike in synchronized sensors (e.g., 50 participants entering a breathing exercise simultaneously) would previously flood PubSub and cause LobbyLive processes to fall behind their message queues. Rate limiting is now a property of the producer, not dependent on consumer-side back-pressure.

### 12.16 Demand-Driven SyncComputer Activation (Feb 17, 2026)

**Files modified:** `lib/sensocto/bio/sync_computer.ex`, `lib/sensocto_web/live/lobby_live.ex`, `assets/js/hooks.js`

SyncComputer viewer registration is now demand-driven from the MIDI hook. Previously, SyncComputer was active whenever the graph view was open, regardless of whether any consumer needed sync data. Now:

1. The JS MIDI hook emits `pushEvent("midi_toggled", %{enabled: bool})` when the user enables or disables MIDI output.
2. `LobbyLive.handle_event("midi_toggled", ...)` registers or unregisters a viewer with SyncComputer via `SyncComputer.register_viewer/1` / `unregister_viewer/1`.
3. LobbyLive subscribes/unsubscribes to the `"sync:updates"` PubSub topic accordingly.
4. When `viewer_count` drops to zero, SyncComputer stops broadcasting (no active consumers, no wasted PubSub traffic).

**Resilience implication:** This closes the loop on the attention-aware routing philosophy applied throughout the pipeline -- "the best way to handle load is to not create it." SyncComputer computation continues regardless (it is lightweight), but PubSub emissions now respect the consumer-presence contract. This also eliminates a class of LobbyLive state bloat where sync data was accumulating in assigns even when MIDI output was not active.

### 12.17 Remember Me Token Strategy (Feb 17, 2026)

**Files modified:** Auth configuration, AshAuthentication strategy config

Added AshAuthentication's `remember_me` strategy for persistent sessions:

- 30-day session tokens (standard session lifetime)
- 365-day `remember_me` cookie (long-lived persistent token)
- The `sign_in_with_remember_me` plug silently re-authenticates when session expires using the persistent cookie, issuing a fresh session token

**Resilience implication:** Re-authentication failures (e.g., token signing key rotation during deployments) are surfaced silently to the plug layer rather than forcing LiveView connections to terminate. The 365-day cookie has a separate rotation cycle from session tokens, reducing the blast radius of signing key changes. From an availability perspective, users survive rolling deployments without manual re-login.

**Security note:** Long-lived tokens require the associated AshAuthentication token table to be pruned of expired entries. Ensure the token cleanup job (if any) does not aggressively prune tokens younger than 365 days.

### 12.18 Bio Factor Error Logging (Feb 17, 2026)

**File modified:** `lib/sensocto/otp/attention_tracker.ex`

The four AttentionTracker bio factor functions previously swallowed errors silently, returning fallback values (e.g., `1.0` for a failed novelty factor computation) with no indication that the biomimetic layer was degraded. Added `Logger.warning/2` calls in all four error branches with:

- Module name (for log aggregation routing)
- Error details (exception or reason)
- The fallback value being used

**Resilience implication:** Silent fallbacks are the enemy of observable systems. When the NoveltyDetector, HomeostaticTuner, ResourceArbiter, or CircadianScheduler produces bad data (e.g., GenServer call timeout, ETS table missing), the attention computation silently used neutral weights. Operators had no visibility into bio layer degradation. Logging warnings surfaces these events to the observability stack (Logger -> log aggregator) without crashing the AttentionTracker process. The fallback behavior is preserved -- the system degrades gracefully -- but the degradation is no longer invisible.

This is the minimal step before the proper fix: adding `:telemetry.execute` calls to emit bio factor computation failures as metrics, enabling alert-on-threshold rather than log-grep-after-incident.

---

## 13. Scalability Analysis

**Based on live measurements with 152 simulated sensors (Feb 2026).**

### 13.1 Per-Sensor Memory Budget (Revised)

The SimpleSensor GC fix (`spawn_opt: [fullsweep_after: 10]`) reduced per-sensor process memory by 12x:

| Component | Before GC Fix | After GC Fix | Notes |
|-----------|--------------|-------------|-------|
| SimpleSensor process | ~2.1 MB | ~175 KB | fullsweep_after: 10 vs default 65535 |
| 4x AttributeServer processes | ~200 KB est. | ~80 KB est. | 4 per sensor, lightweight |
| 1x SensorStub process | ~50 KB est. | ~20 KB est. | Minimal state |
| **Per-sensor process memory** | **~2.35 MB** | **~275 KB** | **6 processes per sensor** |

**Root cause of the old bloat:** BEAM's default `fullsweep_after: 65535` means a process must survive 65,535 minor GCs before old-generation heap is reclaimed. Sensors processing at 100 Hz generate many short-lived binaries (measurement maps, PubSub messages) that get promoted to old-gen but never swept. At 100 Hz, a sensor would need ~11 minutes of continuous operation to trigger a single fullsweep. In practice, the old-gen heap grew monotonically during a session. Setting `fullsweep_after: 10` means old-gen is swept every 10 minor GCs -- roughly every 100ms at 100 Hz -- keeping heap size bounded.

**ETS memory is now the dominant consumer.** The `:attribute_store_warm` table alone consumed 546 MB for 152 sensors (~3.6 MB per sensor), dwarfing the process memory by 13x. Total per-sensor memory budget:

| Resource | Per Sensor | 152 Sensors | Notes |
|----------|-----------|-------------|-------|
| Process memory (6 procs) | ~275 KB | ~41 MB | After GC fix |
| ETS warm store | ~3.6 MB | ~546 MB | 10,000 entries/attribute, multiple attributes |
| ETS hot store + metadata | ~480 KB | ~73 MB | Smaller caps, higher churn |
| **Total per sensor** | **~4.3 MB** | **~660 MB** | **ETS is 95% of memory** |

### 13.2 Single-Node Capacity Projections

**Available resources (assumed production node: 8 GB RAM, 4 vCPU):**

| Limit | Value | Constraint |
|-------|-------|-----------|
| Usable RAM (after OS + BEAM overhead) | ~6 GB | Assuming 2 GB for OS, BEAM VM, Repo, Phoenix, etc. |
| Process limit | 1,048,576 (default) | BEAM default, configurable via `+P` |
| Scheduler count | 4 | Matches vCPU |

**Sensor scaling by bottleneck:**

| Bottleneck | Limit | Sensors Supported | Binding? |
|-----------|-------|-------------------|----------|
| **RAM (6 GB usable)** | 4.3 MB/sensor | **~1,400 sensors** | **YES -- primary bottleneck** |
| Process count | 6 procs/sensor + ~1,800 base | ~174,000 sensors | No |
| CPU (100 Hz processing) | 4 schedulers | ~800-1,200 sensors | Possible co-bottleneck |
| PubSub throughput | 3 attention topics | ~2,000+ sensors (with attention gating) | No |

**Memory is the binding constraint, and ETS warm store is the reason.**

At 4.3 MB per sensor, a 6 GB node hits the wall at ~1,400 sensors. However, this assumes every sensor has multiple attributes each capped at 10,000 warm entries. The actual number depends on attribute diversity.

**If we reduce the warm store cap from 10,000 to 2,000 entries per attribute:**

| Resource | Per Sensor (revised) | Sensors in 6 GB |
|----------|---------------------|-----------------|
| Process memory | ~275 KB | -- |
| ETS warm store (2K cap) | ~720 KB | -- |
| ETS hot + metadata | ~480 KB | -- |
| **Total** | **~1.5 MB** | **~4,000 sensors** |

**If warm store is disabled entirely (hot-only mode under pressure):**

| Resource | Per Sensor | Sensors in 6 GB |
|----------|-----------|-----------------|
| Process memory | ~275 KB | -- |
| ETS hot + metadata | ~480 KB | -- |
| **Total** | **~755 KB** | **~8,000 sensors** |

The existing `SystemLoadMonitor` already reduces warm tier to 5% of base limits under `:critical` load. This provides automatic degradation from ~4,000 to ~8,000 sensor capacity as memory pressure increases -- a genuine self-healing capacity curve.

### 13.3 ETS Warm Store Scaling Analysis

The `:attribute_store_warm` table is the single largest memory consumer:

- **152 sensors, 546 MB** = ~3.6 MB per sensor
- **4.26 million entries across 540 keys** = ~7,889 entries per key average
- Each key is `{sensor_id, attribute_type}` -- with ~3.5 attributes per sensor on average

**Is the 10,000 entry cap appropriate?**

At 100 Hz, 10,000 entries represents 100 seconds of history. For composite views (ECG, breathing, gaze), historical data is used for:
1. Seed data on view entry (typically last 5-30 seconds)
2. Phase estimation in SyncComputer (50 breathing / 20 HRV entries)
3. Novelty detection (z-score over recent window)

None of these consumers need 100 seconds of warm history. A cap of 2,000-3,000 entries (20-30 seconds at 100 Hz) would serve all current use cases while reducing per-sensor ETS memory by 65-80%.

**Recommendation:** Reduce the default warm store cap from 10,000 to 2,500. Type-specific overrides can keep ECG/HRV higher if needed. This single change moves the scaling ceiling from ~1,400 to ~3,500 sensors per node.

### 13.4 Process Count Scaling

At 6 processes per sensor plus ~1,800 base processes:

| Sensors | Total Processes | % of Default Limit |
|---------|----------------|-------------------|
| 152 (current) | ~2,712 | 0.26% |
| 500 | ~4,800 | 0.46% |
| 1,400 | ~10,200 | 0.97% |
| 5,000 | ~31,800 | 3.03% |
| 10,000 | ~61,800 | 5.89% |

Process count is not a concern. The BEAM comfortably handles hundreds of thousands of processes. Even at 10,000 sensors, process count is well within limits. Scheduler utilization and memory will bind long before process count does.

### 13.5 CPU and PubSub Throughput

**CPU at 100 Hz per sensor:**

Each sensor at 100 Hz generates: 1 ETS write to hot store, 1 conditional PubSub broadcast (attention-gated), occasional warm tier splits.

With 4 schedulers and attention-aware routing (only watched sensors broadcast), CPU scales well:
- 152 sensors, ~10 watched: 10 broadcasts/tick = 1,000 PubSub msgs/sec -- trivial
- 1,000 sensors, ~50 watched: 5,000 PubSub msgs/sec -- comfortable
- 5,000 sensors, ~100 watched: 10,000 PubSub msgs/sec -- requires monitoring

The attention-gating system means PubSub throughput scales with **viewers**, not sensors. This is the key architectural insight that makes high sensor counts viable.

**SyncComputer at scale:**

SyncComputer subscribes per-sensor for phase computation. At 1,000+ sensors, the per-sensor subscription model becomes expensive. The demand-driven activation (only active when MIDI enabled) limits this, but if many sensors participate in sync computation, SyncComputer becomes a CPU bottleneck. Consider sharding SyncComputer by sensor group at 500+ active sync participants.

### 13.6 Database Scaling

Current state:
- `sensors` table: 712 rows (cleaned from 37K duplicates)
- `sensors_attribute_data`: 50,710 rows (no retention policy, oldest 10 months)

**Concern: `sensors_attribute_data` has no retention policy.** At current insertion rates, this table will grow indefinitely. If sensors persist attribute data at even 1 write/minute per sensor:
- 1,000 sensors x 1 write/min x 60 min x 24 hr x 30 days = 43.2M rows/month

A retention policy (e.g., 30-day TTL via `pg_partman` or periodic `DELETE WHERE inserted_at < now() - interval '30 days'`) is essential before scaling beyond current levels.

The redundant index cleanup (`sensors_unique_index` dropped) is good hygiene. Ensure remaining indexes support the actual query patterns.

### 13.7 Multi-Node Cluster Scaling

With `:pg` for discovery and local Registry for lookup, the cluster architecture is clean:

| Aspect | Single Node | 2 Nodes | N Nodes |
|--------|------------|---------|---------|
| Sensor capacity | ~1,400 (current caps) | ~2,800 | ~1,400 x N |
| Discovery overhead | None | `:pg` membership sync | O(total sensors) on :pg |
| PubSub cross-node | None | All attention topics replicated | All attention topics replicated |
| Room distribution | Local | Horde CRDT sync | Horde CRDT sync |

**Cluster bottlenecks:**

1. **PubSub replication.** Every message on `data:attention:{level}` is replicated to all nodes. With 50 watched sensors at 100 Hz, this is 5,000 cross-node messages/sec per node pair. At 4+ nodes, this becomes significant. **Mitigation:** PubSub pool_size: 16 provides concurrency, but the underlying `:pg` adapter sends one Erlang message per subscriber per node. Consider `Phoenix.PubSub.PG2` partitioning or topic-level node affinity for attention topics.

2. **`:pg` membership churn.** Sensors joining/leaving `:pg` groups generates cluster-wide membership updates. At 1,000 sensors with 10% churn per minute, this is ~100 membership updates/minute across all nodes. `:pg` handles this efficiently (delta-based), but monitor at scale.

3. **Horde CRDT convergence.** Room registries use Horde CRDT, which has O(n) state size where n is total registered entries. At 1,000+ rooms across 4+ nodes, Horde sync overhead becomes measurable. Monitor Horde sync latency.

**Recommended cluster topology for 5,000+ sensors:**

```
Load Balancer (sticky sessions for WebSocket)
  |
  +-- Node A (sensors 1-1250, rooms 1-50)
  +-- Node B (sensors 1251-2500, rooms 51-100)
  +-- Node C (sensors 2501-3750, rooms 101-150)
  +-- Node D (sensors 3751-5000, rooms 151-200)
```

Sensors naturally distribute by device connection point. Rooms distribute via Horde. The attention-aware routing ensures cross-node PubSub traffic scales with viewers (tens) not sensors (thousands).

### 13.8 The Next Bottleneck

With the GC fix in place, the scaling bottlenecks in priority order:

1. **ETS warm store memory (NOW).** At 3.6 MB/sensor, this is 95% of per-sensor cost. Reducing the 10,000 entry cap to 2,500 is the single highest-leverage change. Estimated impact: 3x increase in single-node sensor capacity.

2. **Database retention (SOON).** `sensors_attribute_data` grows without bound. At scale, this table becomes a query performance problem and a storage cost problem. Implement time-based partitioning or a retention policy.

3. **PubSub cross-node replication (AT CLUSTER SCALE).** When scaling beyond 2 nodes, attention-topic messages replicate to all nodes. Topic-level affinity or partitioned PubSub adapters would address this.

4. **SyncComputer per-sensor subscriptions (AT HIGH SYNC PARTICIPATION).** If 500+ sensors participate in sync computation simultaneously, SyncComputer becomes CPU-bound. Sharding by group would solve this.

5. **Horde CRDT sync overhead (AT 1000+ ROOMS).** Horde's delta-CRDT protocol has overhead proportional to total registered entries. Monitor and consider migration to `:pg` for rooms (as was done for sensors) if convergence latency becomes problematic.

### 13.9 Capacity Planning Summary

| Scenario | Sensors | Memory (per node) | Nodes | Key Requirement |
|----------|---------|-------------------|-------|-----------------|
| Current | 152 | ~660 MB | 1 | None -- works today |
| Near-term growth | 500 | ~2.2 GB | 1 | Reduce warm cap to 2,500 |
| Medium deployment | 1,500 | ~2.3 GB | 1 | Warm cap 2,500 + DB retention |
| Large deployment | 5,000 | ~2.3 GB/node | 4 | Cluster + PubSub affinity |
| Research event | 10,000 | ~2.3 GB/node | 8 | All of the above + SyncComputer sharding |

These projections assume the warm store cap is reduced to 2,500 (~1.5 MB/sensor total). Without that change, divide sensor counts by ~3.

---

## Appendix A: Failure Scenario Analysis

### Scenario 1: AttentionTracker Crash

**What happens (with honey badger resilience):**
1. AttentionTracker process crashes
2. 3 ETS tables survive (owned by TableOwner)
3. Domain.Supervisor restarts AttentionTracker (`:one_for_one`)
4. New AttentionTracker reads existing ETS data, enters recovery mode (60s grace)
5. Broadcasts `:attention_tracker_restarted` on `"attention:lobby"`
6. LiveViews re-register attention views within seconds
7. GenServer state rebuilt from actual active viewers
8. After 60s, orphaned ETS entries reconciled

**Blast radius:** Minimal. Brief pause in attention updates (~seconds). No data loss.

### Scenario 2: PriorityLens Crash

**What happens:**
1. PriorityLens process crashes
2. 4 ETS tables destroyed (buffers, sockets, digests, sensor_subscriptions)
3. Lenses.Supervisor restarts PriorityLens (`:one_for_one`)
4. LensRouter detects crash via monitor, deregisters dead lens
5. PriorityLens re-registers with Router on restart
6. LiveViews re-register their sockets on next mount cycle

**Blast radius:** All LiveViews lose real-time data momentarily (< 1 second).

### Scenario 3: Node Crash in 2-Node Cluster

**What happens (sensors):**
1. All SimpleSensor processes on crashed node die
2. SyncWorker on surviving node receives `:nodedown` event
3. SyncWorker cleans up crashed node's sensors from DiscoveryCache
4. `:pg` membership automatically cleaned up by OTP
5. External devices reconnect to surviving node via WebSocket
6. New sensor processes created, SyncWorker receives registration events

**What happens (rooms):**
1. RoomServer processes on crashed node die
2. Horde.DynamicSupervisor detects loss and redistributes
3. Room state recovered via Iroh CRDT

**Recovery time:**
- Rooms: seconds (Horde redistribution)
- Sensors: until device reconnects (seconds to minutes)
- Discovery cache: immediate (SyncWorker handles cleanup on :nodedown)

### Scenario 4: Database Connection Loss

**What happens:**
1. Ecto.Repo queries start timing out
2. Sensor data pipeline largely unaffected (ETS-based, not DB-dependent)
3. Room creation/lookup fails if not cached in RoomStore
4. Authentication fails for new sessions
5. Existing LiveView sessions continue

**Blast radius:** New operations requiring DB access fail. Existing real-time sessions continue.

### Scenario 5: Memory Pressure (>70%)

**What happens:**
1. SystemLoadMonitor detects memory pressure at 70%
2. Load level escalates to `:high` or `:critical`
3. AttributeStoreTiered warm tier limits drop to 5-20% of normal
4. PriorityLens quality may be reduced (based on actual backpressure)
5. HomeostaticTuner adjusts sampling parameters
6. ResourceArbiter suppresses low-priority sensors

**Recovery:** Automatic as memory pressure subsides.

### Scenario 6: Iroh.ConnectionManager Crash (NEW)

**What happens:**
1. ConnectionManager crashes
2. Storage.Supervisor (`:rest_for_one`) restarts ConnectionManager AND all downstream: Iroh.RoomStore, HydrationManager, RoomStore, Iroh.RoomSync, Iroh.RoomStateCRDT, RoomPresenceServer
3. New iroh node created by ConnectionManager
4. Downstream processes re-fetch node_ref on their restart
5. RoomStore rehydrates from HydrationManager

**Blast radius:** Room operations temporarily unavailable (seconds). Sensor data pipeline unaffected (different supervisor tree).

---

## Appendix B: Key File References

| File | Lines | Purpose |
|------|-------|---------|
| `lib/sensocto/application.ex` | ~127 | Root supervision tree |
| `lib/sensocto/infrastructure/supervisor.ex` | ~77 | Infrastructure layer |
| `lib/sensocto/registry/supervisor.ex` | ~97 | 16 registries |
| `lib/sensocto/storage/supervisor.ex` | ~75 | Storage chain with ConnectionManager |
| `lib/sensocto/bio/supervisor.ex` | ~33 | Biomimetic layer |
| `lib/sensocto/domain/supervisor.ex` | ~125 | Domain processes (22 children) |
| `lib/sensocto/lenses/supervisor.ex` | ~25 | Lens pipeline |
| `lib/sensocto/otp/simple_sensor.ex` | ~685 | Core sensor process |
| `lib/sensocto/lenses/priority_lens.ex` | ~831 | Per-socket adaptive streaming |
| `lib/sensocto/otp/attention_tracker.ex` | ~1255 | Attention tracking with ETS + bulk ops |
| `lib/sensocto/otp/system_load_monitor.ex` | ~576 | System load sampling |
| `lib/sensocto/resilience/circuit_breaker.ex` | ~155 | Circuit breaker |
| `lib/sensocto/calls/call_server.ex` | ~788 | Video/voice call management |
| `lib/sensocto/otp/attribute_store_tiered.ex` | ~468 | ETS tiered storage |
| `lib/sensocto/lenses/router.ex` | ~161 | Data routing to lenses |
| `lib/sensocto/bio/sync_computer.ex` | ~604 | Kuramoto phase synchronization |
| `lib/sensocto/bio/novelty_detector.ex` | ~300 | Anomaly detection (Welford) |
| `lib/sensocto/otp/sensors_dynamic_supervisor.ex` | ~200 | Sensor lifecycle |
| `lib/sensocto/sensors/connector_manager.ex` | ~250 | Distributed connectors |
| `lib/sensocto/otp/room_server.ex` | ~400 | Distributed room state |
| `lib/sensocto/otp/room_store.ex` | ~1049 | In-memory room state cache |
| `lib/sensocto/iroh/connection_manager.ex` | ~60+ | Shared iroh node connection |
| `lib/sensocto/discovery/discovery_cache.ex` | ~120 | ETS-backed sensor discovery cache |
| `lib/sensocto/discovery/sync_worker.ex` | ~205 | Event-driven cluster sync |
| `lib/sensocto/chat/chat_store.ex` | ~165 | ETS-backed chat messages |
| `lib/sensocto/simulator/connector_server.ex` | ~180 | Simulated connectors |
| `lib/sensocto/simulator/supervisor.ex` | ~45 | Simulator infrastructure |

---

## Appendix C: Module Statistics

- **Core modules (`lib/sensocto/`):** 152 files
- **Web modules (`lib/sensocto_web/`):** 96 files
- **Total:** 248 files
- **Named ETS tables:** ~25
- **Horde registries:** 3 (rooms, join codes, connectors)
- **Local registries:** 12
- **:pg scopes:** 1 (`:sensocto_sensors`)
- **GenServer processes (singletons):** ~20
- **GenServer processes (dynamic):** 6 per sensor (1 SimpleSensor + 4 AttributeServer + 1 SensorStub) + N rooms + N calls
- **Measured process count:** ~2,669 total with 152 sensors (~1,800 base + 912 sensor processes)
- **PubSub topics (patterns):** 20+ distinct patterns
- **Telemetry instrumentation points:** 7 files

---

## 11. Planned Work: Resilience Implications

This section assesses the resilience implications of planned changes across the codebase. Plans that have been implemented are marked accordingly.

### 11.1 Room Iroh Migration (PLAN-room-iroh-migration.md)

**Status: Partially implemented** -- Iroh.ConnectionManager and Storage.Supervisor restructuring are done. RoomStore hydration gate is implemented.

**Remaining resilience considerations:**
- Iroh IS now the safety net for room state. If both RoomStore and Iroh crash simultaneously, rooms are lost until Iroh doc sync or manual recovery.
- ConnectionManager graceful degradation (when NIF unavailable) handles the case where iroh binaries are not available for the platform.

### 11.2 Adaptive Video Quality (PLAN-adaptive-video-quality.md)

**Status: Implemented.**

SnapshotManager ETS table is owned by the GenServer (no TableOwner). If it crashes, cached snapshots are lost. Self-healing within 1-2 seconds. Low blast radius.

### 11.3 Sensor Component Migration (PLAN-sensor-component-migration.md)

**Status: Implemented.** `@use_sensor_components true` flag in LobbyLive.

LiveComponents run in the parent LobbyLive process. The blast radius trade-off (single sensor crash vs entire lobby crash) is accepted. The `@component_flush_interval_ms 100` provides batched updates to components.

### 11.4 Startup Optimization (PLAN-startup-optimization.md)

**Status: Implemented.** No new resilience risks.

### 11.5 Delta Encoding for ECG Data (plans/delta-encoding-ecg.md)

**Status: Not yet implemented.**

Key resilience considerations unchanged: cache feature flag in `:persistent_term`, ensure JS decoder version matches Elixir encoder version during deployments.

### 11.6 Cluster Sensor Visibility (plans/PLAN-cluster-sensor-visibility.md)

**Status: Partially superseded.** The `:pg` + local Registry approach (from 11.8) was implemented instead of adding Horde for sensors. Discovery visibility is now handled by DiscoveryCache + SyncWorker.

### 11.7 Distributed Discovery (plans/PLAN-distributed-discovery.md)

**Status: Implemented.** DiscoveryCache and SyncWorker are in Domain.Supervisor.

The implementation is cleaner than the original plan:
- Event-driven (no periodic full sync except on startup)
- No NodeHealth circuit breaker needed (SyncWorker handles node down directly)
- No 1000-message queue limit needed (debouncing prevents buildup)

### 11.8 Sensor Scaling Refactor (plans/PLAN-sensor-scaling-refactor.md)

**Status: Partially implemented.** `:pg` + local Registry for sensors is done. PubSub sharding by attention level is done. Per-socket ETS tables and ring buffers are NOT implemented.

### 11.9 Research-Grade Synchronization (plans/PLAN-research-grade-synchronization.md)

**Status: Not yet implemented.** SyncComputer (Kuramoto) is the foundation. Full research-grade metrics require dedicated Analysis.Supervisor.

### 11.10 TURN/Cloudflare Integration (plans/PLAN-turn-cloudflare.md)

**Status: Implemented.** No supervision tree impacts. `:persistent_term` caching is the lightest possible pattern.

### 11.11 Cross-Plan Resolution

The original conflict between Cluster Sensor Visibility (11.6) and Sensor Scaling Refactor (11.8) has been resolved in favor of the `:pg` approach. This was the correct long-term decision -- `:pg` is lighter than Horde for ephemeral sensor processes.

The Discovery system (11.7) was implemented with a simpler architecture than planned, avoiding unnecessary complexity (no NodeHealth, no SyncWorker queue limits). This is a good example of implementing the minimum viable version and adding complexity only when needed.

---

## Conclusion

Sensocto's architecture demonstrates a deep understanding of OTP principles. The attention-aware routing system is an elegant innovation that most BEAM applications lack -- the insight that "the best way to handle load is to not create it in the first place" is exactly right. The five-layer backpressure system, while complex, provides genuine resilience against varying load conditions.

**Status after Feb 2026 resilience work:**

Resolved:
- Sensor supervision mismatch -- migrated to `:pg` + local Registry
- Single Router GenServer bottleneck -- ETS direct-write hot path
- Monolithic PubSub topic -- sharded by attention level
- Manager/RoomStore hydration race -- gated with `RoomStore.ready?/0`
- Orphaned connectors -- 30s health check
- Infinite SensorServer reconnect on deleted rooms -- detects permanent loss
- Bio.Supervisor missing restart limits -- now 10/60s
- Structured logging -- IO.puts cleaned up (except legacy DSL macros)
- GenServer default timeouts -- explicit timeouts everywhere
- Atom exhaustion -- SafeKeys whitelist
- AttentionTracker ETS crash resilience -- TableOwner + honey badger
- Distributed discovery -- DiscoveryCache + SyncWorker (event-driven)
- Iroh connection sharing -- ConnectionManager in Storage.Supervisor
- AttentionTracker thundering herd -- bulk registration/unregistration APIs
- SyncComputer GC pressure on hot path -- O(excess) buffer append replacing O(n)
- SyncComputer PubSub flooding -- 200ms per-type throttle on broadcast (~22/sec cap)
- SyncComputer always-on waste -- demand-driven activation via MIDI hook event
- Silent bio factor degradation -- Logger.warning added to all four error branches
- Session continuity across deployments -- remember_me 365-day persistent token strategy

Remaining risks (ordered by impact):
1. **ETS warm store is the scaling ceiling.** At 3.6 MB/sensor (10,000 entry cap), ETS consumes 95% of per-sensor memory. Reducing the cap to 2,500 would triple single-node capacity from ~1,400 to ~4,000 sensors.
2. The absence of `code_change/3` blocks safe hot code upgrades
3. Domain.Supervisor has 22 children under `:one_for_one` -- needs sub-supervisors
4. `sensors_attribute_data` has no retention policy -- unbounded database growth
5. Circuit breaker lacks failure decay -- permanent half-open state possible
6. No health check endpoint for operational monitoring

**Scalability headline (revised with live data):** The SimpleSensor GC fix (`fullsweep_after: 10`) reclaimed 296 MB from 152 sensors -- a 12x per-process memory reduction (2.1 MB to 175 KB). This moved the per-sensor bottleneck from process heap to ETS warm store. A single 8 GB node can support ~1,400 sensors with current ETS caps, or ~4,000 sensors with the recommended warm store cap reduction to 2,500 entries. Multi-node clusters scale linearly thanks to the `:pg` + local Registry architecture and attention-aware PubSub gating.

The system's foundations are sound and continue to strengthen. The supervision tree hierarchy is well-layered, the data pipeline is highly optimized (ETS direct-write bypasses GenServer serialization), and the biomimetic layer adds genuine adaptive capacity. The honey badger resilience pattern -- processes that self-heal, detect permanent failures, and carry on -- makes this system increasingly suitable for autonomous agent-driven maintenance.

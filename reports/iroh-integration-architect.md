# Iroh Integration -- Team Report
*Last updated: 2026-03-05*

## Goals

1. **Complete the half-built room state CRDT sync** so media playback, 3D viewer, and presence state synchronize between multiple server instances and (eventually) directly to clients.
2. **Consolidate the 4 separate iroh nodes into 1** via the `IrohConnectionManager` pattern. **DONE.**
3. **Bridge sensor data to iroh gossip** for native clients (mobile, edge), while keeping the Phoenix PubSub path for web LiveView.
4. **Use iroh-blobs for historical sensor data distribution** so seed data for composite lenses does not always hit PostgreSQL.
5. **Achieve production readiness** by resolving the Linux x86_64 NIF build blocker for Fly.io.

---

## Current Status (2026-03-05)

### What Has Changed Since 2026-03-01

**iroh modules**: No changes. The iroh code in `lib/sensocto/iroh/` has been stable since the ConnectionManager consolidation (commit `4d12618`, 2026-02-08). All 5 modules (`connection_manager.ex`, `room_store.ex`, `room_sync.ex`, `room_state_crdt.ex`, `room_state_bridge.ex`) are unchanged.

**iroh_ex dependency**: Remains at `~> 0.0.15` (Hex). NIF binary is `aarch64-apple-darwin` only (38.6 MB). No version bump.

**Significant surrounding changes (Mar 1 - Mar 5):**

- **Fullscreen 3D object viewer** (commit `076abf7`): Improvements to the Object3D viewer and graph visualizations. The 3D viewer is one of the state types synchronized via `RoomStateBridge` -> `RoomStateCRDT`. No change to the iroh integration pattern.

- **PriorityLens: respiration added to high-frequency attributes** (commit `076abf7`): `@high_frequency_attributes` in `priority_lens.ex` now includes `"respiration"` alongside `"ecg"`, `"button"`, and `"buttons"`. This means respiration waveform data now accumulates in lists (preserving all samples between flushes) rather than keeping only the latest value. This increases per-flush payload size for respiration sensors and is relevant to the delta encoding opportunity (#5) -- respiration data could benefit from the same delta encoding as ECG.

- **Composite lens tuple now 9 elements**: `extract_composite_data/1` in `lobby_live.ex` returns a 9-tuple: `{heartrate, imu, location, ecg, battery, skeleton, respiration, hrv, gaze}`. The HRV and gaze lenses were added in earlier commits but are now stable. These are additional data types flowing through the same `SimpleSensor -> PubSub -> Router -> PriorityLens -> LobbyLive` pipeline.

**Key takeaway:** The platform continues to grow in features (fullscreen 3D, graph improvements) and the data pipeline is handling more data types (respiration as high-frequency, HRV, gaze). All of this is pure server-mediated. iroh remains in its "foundation laid but not actively used" state. The expanding data types make the eventual case for delta encoding (#5) stronger -- more high-frequency attributes means more bandwidth to save.

### Module-by-Module Assessment

| Module | Lines | Status | Verdict |
|--------|-------|--------|---------|
| `Iroh.ConnectionManager` | 216 | **Functional** | Single shared iroh node. Synchronous init. All other modules get `node_ref` from here. |
| `Iroh.RoomStore` | ~508 | Functional, tested indirectly | Uses shared node from ConnectionManager. CRUD works. `list_all_rooms` broken (always empty). New namespaces every restart. |
| `Iroh.RoomSync` | 352 | Functional | Good debouncing and retry logic. Hydration from iroh docs never actually loads anything (because `list_all_rooms` returns empty). |
| `Iroh.RoomStateCRDT` | ~735 | Functional, tested | Full Automerge API (media, 3D, presence). Uses shared node from ConnectionManager. In-memory only (docs lost on restart). |
| `Iroh.RoomStateBridge` | ~425 | **Functional (both directions)** | Local-to-CRDT via PubSub. CRDT-to-local applies media state (play/pause/seek) and object3d state. Echo suppression via sentinel message pattern. |
| `Storage.Backends.IrohBackend` | 289 | Functional | Secondary backend behind PostgreSQL. Properly delegates to `Iroh.RoomStore`. |
| `P2P.RoomTicket` | 322 | Functional | Generates deterministic tickets via HMAC. Caches in ETS. Good deep link / QR code support. |
| `BridgeChannel` | 166 | Functional | WebSocket bridge for sidecar. Topic pub/sub works. |
| `IrohGossipLive` | 319 | Demo/test page | Creates 50 nodes (!), connects them, sends messages. Useful for testing but resource-heavy. |
| `RoomMarkdown.GossipTopic` | ~360 | Functional (unsupervised) | Per-room gossip topics. Uses shared node from ConnectionManager. Not started in any supervisor. |
| `RoomMarkdown.CrdtDocument` | ~470 | Functional (unsupervised) | Full room-as-document Automerge support. Uses shared node from ConnectionManager. Not started in any supervisor. |

### Supervision Tree (Storage Layer)

```
Storage.Supervisor (:rest_for_one, 3/5s)
  |-- Iroh.ConnectionManager     -- shared iroh node (MUST start first)
  |-- Iroh.RoomStore             -- low-level iroh document storage
  |-- HydrationManager           -- multi-backend hydration coordinator
  |-- RoomStore                  -- in-memory room state cache
  |-- Iroh.RoomSync              -- async persistence (writes to Iroh.RoomStore)
  |-- Iroh.RoomStateCRDT         -- Automerge CRDT state for rooms
  |-- RoomPresenceServer         -- room presence tracking
```

### Sensor Data Pipeline (Current Architecture)

The pipeline has zero iroh involvement and is highly optimized:

```
SimpleSensor GenServer
  |-- put_attribute/put_batch_attributes cast
  |-- AttributeStoreTiered: ETS write (hot data)
  |-- PubSub broadcast: "data:{sensor_id}" (per-sensor, always)
  |-- Attention gate: if attention_level != :none
  |     |-- PubSub broadcast: "data:attention:{high|medium|low}"
  |     |-- Source-side batch throttling under elevated+ system load
  |     |     (buffer measurements, flush as batch on interval)
  |
Router GenServer (singleton)
  |-- Subscribes to 3 attention topics (demand-driven: only when lenses registered)
  |-- Writes directly to PriorityLens ETS tables (bypasses GenServer mailbox)
  |
PriorityLens GenServer
  |-- 4 ETS tables: buffers, sockets, digests, sensor_subscriptions (all :public)
  |-- Reverse index: sensor_id -> MapSet<socket_id> (O(1) lookup)
  |-- High-frequency attributes (ecg, respiration, button, buttons): accumulate lists
  |-- Other attributes: keep-latest-only
  |-- Flush timer per socket: broadcasts to "lens:priority:{socket_id}"
  |-- Quality levels: high(64ms), medium(128ms), low(250ms), minimal(500ms), paused
  |-- Delta encoding integration: maybe_delta_encode_batch/1 on flush (feature-flagged OFF)
  |
LobbyLive LiveView (per-browser-tab)
  |-- Subscribes to "lens:priority:{socket_id}" (personalized stream)
  |-- Receives :lens_batch or :lens_digest events
  |-- Push events to Svelte 5 components for rendering
```

Key efficiency features:
- **Attention-aware routing**: Sensors with `attention_level: :none` do not broadcast to the attention-sharded topics at all
- **Demand-driven subscriptions**: Router only subscribes to attention topics when PriorityLens has registered sockets; PriorityLens only registers with Router when browser tabs are connected
- **GenServer-free hot path**: Router writes directly to PriorityLens ETS tables, no mailbox contention
- **Source-side batch throttling**: Under elevated+ system load, SimpleSensor buffers measurements and flushes as batches (configurable intervals by load_level x attention_level)
- **Mailbox self-protection**: SimpleSensor drops measurements when its own mailbox exceeds 500 messages
- **Hibernation**: Sensors with low/no attention hibernate after 5 minutes of inactivity

### Sensor Registry Architecture (Stable)

- **Local lookup**: `SimpleSensorRegistry` (Elixir `Registry`, unique keys) -- used by `via_tuple`
- **Cluster discovery**: `:pg` process groups (scope `:sensocto_sensors`) -- used by `get_device_names/0`
- **Rooms/Connectors**: Use `Horde.Registry` for cluster-wide distributed lookup
- **Discovery module** (`lib/sensocto/discovery/`): ETS-cached read path with background `SyncWorker`

### Architectural Issues

**RESOLVED: 4 separate iroh nodes consolidated into 1.** The `Iroh.ConnectionManager` GenServer owns the single shared iroh node. All 4 consumer modules (`RoomStore`, `RoomStateCRDT`, `GossipTopic`, `CrdtDocument`) use `ConnectionManager.get_node_ref()`.

**RESOLVED: RoomStateBridge now bidirectional.** The CRDT-to-local direction is implemented with echo suppression. Media state (play/pause/seek) and object3d state sync from CRDT to local servers.

**BLOCKED: Node identity persistence.** Each restart still creates a new node identity because `iroh_ex` v0.0.15's `NodeConfig` has no `secret_key` field. The Rust NIF's `create_node` calls `Endpoint::builder().bind()` without a key. Fix needed in iroh_ex: add `secret_key: Option<String>` to the Rust `NodeConfig` struct.

**Zero cross-node synchronization works today.** Despite the Automerge and gossip infrastructure, no data actually synchronizes between separate server instances because:
- Each restart creates a new node identity (blocked, see above)
- Namespace IDs are ephemeral
- `automerge_sync_via_gossip/2` requires connected peers, but no connection is established between instances

**GossipTopic and CrdtDocument are orphaned.** These two modules exist in `lib/sensocto/room_markdown/` and are functional code, but they are not started in any supervisor. They properly use ConnectionManager but are effectively dead code.

### What Actually Works Well

- **Automerge primitives are solid.** The NIF provides map, list, text, counter operations. Tests pass. Document creation, forking, saving, loading, and merging all work.
- **Circuit breaker integration.** All iroh calls go through `Sensocto.Resilience.CircuitBreaker`, preventing cascading failures when the NIF is unavailable.
- **Graceful NIF detection.** Every module checks `function_exported?(Native, :create_node, 2)` and degrades to `nif_unavailable: true` state rather than crashing.
- **Room ticket generation.** Deterministic HMAC-based namespace derivation means the same room always gets the same ticket parameters.
- **NodeConfig has `discovery` field.** The `build_node_config/0` in ConnectionManager sets `discovery: ["n0", "local_network"]`, which is needed for node discovery to work.

---

## Ranked Opportunities (Effort-to-Impact)

### Opportunity 1: IrohConnectionManager -- Single Shared Node -- DONE
**Status: COMPLETE (2026-02-08)**

### Opportunity 2: Complete RoomStateBridge Bidirectional Sync -- DONE
**Status: COMPLETE (2026-02-08)**

### Opportunity 3: Persist Node Identity and Namespace IDs -- BLOCKED
**Impact: HIGH (enables real P2P continuity)**
**Effort: 4-6 hours** (blocked on iroh_ex missing `secret_key` in NodeConfig)
**Needs Linux NIF: No (but matters more in production)**

**What:** Store the iroh node's secret key to disk on first run, restore it on subsequent runs. Also persist the mapping of `room_id -> namespace_id` so documents survive restarts.

**What's already built:** `RoomTicket` already derives deterministic namespace identifiers via HMAC. The architecture doc specifies a `priv/iroh/node_identity` file path.

**What's missing:** The actual persistence code. `iroh_ex` v0.0.15's `NodeConfig` struct does not have a `secret_key` field. The `generate_secretkey/0` NIF function exists but there is no way to use the result when creating a node.

**Proposed fix for iroh_ex:** Add `secret_key: Option<String>` to the Rust `NodeConfig` struct in `native/iroh_ex/src/lib.rs` and use `Endpoint::builder().secret_key(SecretKey::from_bytes(key))` when present.

**Honest assessment:** This is essential for production P2P sync. Without it, every restart creates a new node identity, room tickets become invalid, and cross-node sync can never work. However, for single-server deployments where iroh is only used for local Automerge CRDT operations, identity persistence has no practical impact.

### Opportunity 4: Sensor Data Gossip Bridge (for Native Clients)
**Impact: HIGH for mobile/native clients; ZERO for web LiveView**
**Effort: 2-3 days**
**Needs Linux NIF: Yes (for production), No (for dev demo)**

**What:** A new `SensorGossipPublisher` GenServer that subscribes to the sharded PubSub topics (`"data:attention:high"`, etc.) and republishes measurements to per-room iroh gossip topics. Native clients receive sensor data P2P instead of going through the server.

**Updated context:** The sensor data pipeline is now even more sophisticated than when this opportunity was first documented. Source-side batch throttling (load_level x attention_level intervals), mailbox self-protection, demand-driven routing, and high-frequency attribute accumulation (ECG + respiration now) all work together to manage the data flow. A gossip bridge would tap into the same attention-sharded topics the Router uses, benefiting from all the same backpressure mechanisms.

**Honest assessment:** This is a significant engineering effort with a dependency chain: it needs identity persistence (#3), a Linux NIF, and a native client with iroh support. For web-only users (LiveView), this provides zero benefit. Only matters once native clients consuming sensor data directly exist.

### Opportunity 5: Delta Encoding for ECG and Respiration Data (NOT iroh -- Pure Server) -- PARTIALLY DONE
**Impact: HIGH for interactive experience**
**Effort: 1-2 days remaining** (encoder implemented, JS decoder + integration pending)
**Needs Linux NIF: No (not iroh-related)**

**What:** Implement the delta encoding plan at `plans/delta-encoding-ecg.md`. Reduces ECG WebSocket bandwidth by ~84%.

**Status:** The Elixir encoder module exists at `lib/sensocto/encoding/delta_encoder.ex` (148 lines). Feature-flagged off. Binary protocol with version byte and reset markers. The `maybe_delta_encode_batch/1` function in PriorityLens is already wired in (`flush_batch/2`) but guards on `DeltaEncoder.enabled?()`.

**New since last report:** Respiration data is now accumulated as a high-frequency attribute in PriorityLens (`@high_frequency_attributes ~w(ecg respiration button buttons)`). This means the delta encoding system, once enabled, should also target respiration data -- not just ECG. The `supported_attributes` config in DeltaEncoder currently defaults to `["ecg"]` and should be extended to `["ecg", "respiration"]`.

**Performance note:** `DeltaEncoder.enabled?/0` calls `Application.get_env` on every invocation in the hot path (`flush_batch`). Before enabling, this should migrate to `:persistent_term` for zero-cost reads.

### Opportunity 6: Guided Session P2P Extension
**Impact: MEDIUM (enables cross-server guide-follower sync without Erlang clustering)**
**Effort: 1-2 days**
**Needs Linux NIF: No**

**What:** The Guidance system (`lib/sensocto/guidance/session_server.ex`) synchronizes a guide's navigation state to a follower via PubSub. The state is small (current lens, focused sensor, annotations, lobby settings) and unidirectional (guide writes, follower reads). If guide and follower are on different non-clustered instances or on native clients, iroh-gossip or CRDT sync would be a natural fit.

**Honest assessment:** PubSub handles this fine for the foreseeable future. Erlang clustering (PG2) already distributes PubSub across nodes. Only worth iroh-ifying if we need non-clustered or native client support. Low priority.

### Opportunity 7: Research-Grade Sync Visualizations (Not iroh)
**Impact: HIGH for differentiation**
**Effort: 5-10 days for the P1 tier**
**Needs Linux NIF: No**

**What:** Real-time Svelte visualizations (PLV matrix, phase space orbits, sync topology graph) as defined in `plans/PLAN-research-grade-synchronization.md`.

**Honest assessment:** The visualizations are pure Svelte/client-side work with existing data. iroh adds marginal value. Build these with Phoenix PubSub.

### Opportunity 8: Historical Data as iroh-blobs
**Impact: MEDIUM (reduces PostgreSQL load for seed data)**
**Effort: 3-5 days**
**Needs Linux NIF: Yes for P2P; No for local caching**

### Opportunity 9: Room Markdown CRDT Sync (Closest to Working)
**Impact: MEDIUM for collaborative room editing**
**Effort: 1-2 days to get it working end-to-end**
**Needs Linux NIF: No (dev-only is fine)**

**What:** The `GossipTopic` and `CrdtDocument` modules exist but are not supervised. They need to be added to the supervision tree (either statically or via a DynamicSupervisor) and connected together. The room_markdown directory also contains `TigrisStorage` and `BackupWorker`, suggesting there is already thinking about persisting room documents to object storage.

---

## Summary Matrix

| # | Opportunity | Effort | Impact | Needs Linux NIF | Status |
|---|-----------|--------|--------|----------------|--------|
| 1 | IrohConnectionManager | 1-2 days | CRITICAL | No | **DONE** |
| 2 | Complete Bridge bidirectional sync | 2-4 hours | HIGH | No | **DONE** |
| 3 | Persist node identity/namespaces | 4-6 hours | HIGH | No | **BLOCKED** (iroh_ex needs secret_key) |
| 4 | Sensor data gossip bridge | 2-3 days | HIGH (native only) | Yes (prod) | Planned |
| 5 | Delta encoding for ECG + respiration | 1-2 days remaining | HIGH (all users) | No | Encoder done, JS decoder pending |
| 6 | Guided Session P2P extension | 1-2 days | MEDIUM | No | Planned (PubSub sufficient) |
| 7 | Research-grade sync visualizations | 5-10 days | HIGH (differentiation) | No | Planned (not iroh) |
| 8 | Historical data as blobs | 3-5 days | MEDIUM | Yes (P2P) | Planned |
| 9 | Room markdown CRDT sync | 1-2 days | MEDIUM | No | Planned |

**Recommended execution order:**
1. **#5 Delta encoding** -- highest impact-to-effort ratio, zero dependencies, benefits all users immediately. Now covers both ECG and respiration.
2. **#3 Identity persistence** -- enables real P2P continuity (blocked on iroh_ex change)
3. **#7 Research visualizations** -- product differentiation, independent of iroh
4. **#9 Room markdown sync** -- close to working, just needs supervision + wiring
5. **#6 Guided Session P2P** -- only if non-clustered or native support needed
6. **#4 Sensor gossip bridge** -- only after Linux NIF is available and native clients exist
7. **#8 Historical data blobs** -- only at scale

---

## Impediments and Blockers

### 1. Linux x86_64 NIF Build (HARD BLOCKER for production P2P)

**Status:** The iroh_ex NIF binary is compiled for `aarch64-apple-darwin` only (38.6 MB at `_build/dev/lib/iroh_ex/priv/native/`). Fly.io runs Linux x86_64 containers. Until a Linux build exists, all iroh features are disabled in production.

**Mitigation:** All modules gracefully degrade when the NIF is unavailable. The application runs fine without iroh -- it just does not have P2P capabilities.

**Action needed:** Either compile iroh_ex for `x86_64-unknown-linux-gnu` or request a precompiled binary from the iroh_ex maintainers. The `rustler_precompiled` dependency (v0.8) is already in the project, so this may be a matter of adding the target to the iroh_ex build matrix.

### 2. iroh_ex NodeConfig Missing `secret_key` (BLOCKER for identity persistence)

The `NodeConfig` Rust struct only has `is_whale_node`, `active_view_capacity`, `passive_view_capacity`, `relay_urls`, and `discovery`. To persist node identity across restarts, we need to pass a previously generated secret key to `create_node`.

The `generate_secretkey/0` NIF function exists but there is no way to use the result when creating a node. **Proposed fix**: Add `secret_key: Option<String>` to the Rust `NodeConfig` struct in `native/iroh_ex/src/lib.rs` and use `Endpoint::builder().secret_key(SecretKey::from_bytes(key))` when present.

### 3. `list_all_rooms` Returns Empty (Known Bug)

`Iroh.RoomStore.do_list_all_rooms/1` always returns `{:ok, []}`. This means hydration from iroh docs on startup never loads anything. The in-memory `RoomStore` with PostgreSQL as primary source is not affected, so this is a correctness issue rather than a functional blocker.

### 4. GossipTopic and CrdtDocument Are Unsupervised

These modules exist and are functional but are not started in any supervisor. They sit in `lib/sensocto/room_markdown/` alongside `TigrisStorage`, `BackupWorker`, and `Parser`. Until they are supervised, they cannot be used in production.

---

## Questions for the iroh Team

(Carried forward from previous reports, still unanswered)

### 1. Shared Node API Pattern
Can a single `node_ref` be safely used from multiple BEAM processes concurrently? The NIF resource handle needs to be thread-safe for our shared-node architecture. We are currently doing this and it appears to work, but we have no confirmation this is safe.

### 2. Node Identity Persistence
Does `iroh_ex` expose an API for exporting/importing the node's secret key? We need identity continuity across restarts. The `generate_secretkey/0` function exists but there is no way to pass the result to `create_node`.

### 3. Gossip Scale Characteristics
What are the memory and CPU costs per gossip topic? We may need 100-1000 concurrent topics (one per active room).

### 4. Automerge Gossip Sync Prerequisites
Does `automerge_sync_via_gossip/2` require nodes to be connected via `connect_node/2` first? We have never observed actual cross-node sync.

### 5. iroh_ex Linux x86_64 Build
Is there a precompiled binary for `x86_64-unknown-linux-gnu` or a documented cross-compilation process? This is our production deployment target (Fly.io).

### 6. NodeConfig secret_key Support
The `NodeConfig` Rust struct needs a `secret_key: Option<String>` field to support identity persistence. The `generate_secretkey/0` NIF function exists but there is no way to use the result when creating a node. We can submit a PR if the iroh team agrees with this approach.

---

## Cost/Scale Analysis

### Current Architecture Cost Projections

The sensor data pipeline uses attention-aware sharded PubSub, ETS direct-writes, source-side batch throttling, and mailbox self-protection -- making the server-only path highly efficient. The data flow is demand-driven end-to-end: no subscriptions unless someone is watching, no broadcasts unless attention_level is non-zero.

| Sensor Count | Active (20%) | Viewers | Server I/O | Est. Monthly Cost (Fly.io) |
|-------------|-------------|---------|------------|---------------------------|
| 100 | 20 | 5 | 0.4 MB/s | $7 (shared-cpu-1x) |
| 1,000 | 200 | 20 | 4 MB/s | $14 (shared-cpu-2x) |
| 10,000 | 2,000 | 50 | 40 MB/s | $57 (performance-4x) |
| 100,000 | 20,000 | 200 | 400 MB/s | $500+ (multi-machine) |

Assumptions: 50Hz average, 200 bytes/measurement, attention-aware routing = 20% active.

**New consideration:** With respiration now treated as high-frequency (accumulating all samples between flushes), per-socket payload sizes increase. At 64ms flush interval (high quality), a respiration sensor at 25Hz produces ~1.6 samples per flush -- modest. At lower quality levels, accumulation is larger but flush frequency is lower, so net bandwidth is similar. The real impact is that there are now *more* high-frequency data streams requiring careful buffer management.

### With Delta Encoding (#5) -- Immediate Win

ECG + respiration data (the highest-bandwidth attributes) compressed by ~84%:

| Sensor Count | Active | Without Delta | With Delta | Savings |
|-------------|--------|--------------|-----------|---------|
| 1,000 | 200 | 4 MB/s | 1.5 MB/s | 62% |
| 10,000 | 2,000 | 40 MB/s | 15 MB/s | 62% |

This applies to ALL users (web and native) immediately, no iroh needed.

### With iroh-gossip (#4) -- Native Clients Only

| Sensor Count | Server I/O (orchestration only) | Est. Monthly Cost | Savings vs Current |
|-------------|-------------------------------|-------------------|---------|
| 1,000 | 0.4 MB/s | $7 | 50% |
| 10,000 | 4 MB/s | $14 | 75% |
| 100,000 | 40 MB/s | $57 | 89% |

Key caveat: savings only apply to native clients using iroh. Web LiveView clients always go through server.

### Combined (Delta + Gossip)

At 10,000 sensors: 62% savings from delta encoding + 75% savings from gossip for native = ~92% total server I/O reduction for the sensor data path.

### Server-Only Breakpoint Analysis

The current architecture is well-optimized for single-server deployment:
- **Attention routing** eliminates 80% of potential broadcasts (only 20% of sensors are watched at any time)
- **Source-side batch throttling** reduces PubSub message count under load by 2-8x
- **ETS direct-write** removes GenServer bottleneck from the hot path
- **Demand-driven everything** means zero overhead when no one is watching

**The honest assessment:** At current feature set and expected near-term scale (hundreds of sensors, tens of viewers), the server-only architecture is sufficient and well-optimized. iroh adds value at:
- **1,000+ sensors with 50+ concurrent viewers** -- where server I/O becomes the bottleneck
- **Native mobile clients** -- where server round-trip latency degrades interactive experience
- **Multi-region deployment** -- where Erlang clustering is impractical and P2P data flow reduces cross-region traffic
- **Offline/edge scenarios** -- where clients need to continue collecting and viewing data without server connectivity

None of these scenarios are imminent priorities. The correct path is to complete the non-iroh wins (#5 delta encoding, #7 research visualizations) first and revisit iroh integration when a concrete use case emerges that the server-only architecture cannot handle.

---

## Roadmap

### Phase 0: Non-iroh Wins (NOW)
- [x] Implement delta encoding -- encoder done (`lib/sensocto/encoding/delta_encoder.ex`), JS decoder + integration pending
- [ ] Extend delta encoding to respiration data (config change + JS decoder)
- [ ] Migrate `DeltaEncoder.enabled?/0` from `Application.get_env` to `:persistent_term`
- [ ] Research-grade sync visualizations P1 tier (`plans/PLAN-research-grade-synchronization.md`)
- [ ] Sensor component migration: LiveView to LiveComponent (`plans/PLAN-sensor-component-migration.md`)

### Phase 1: iroh Foundation
- [x] Implement `IrohConnectionManager` -- single shared node (2026-02-08)
- [x] Complete `RoomStateBridge` bidirectional sync (2026-02-08)
- [ ] Persist node identity across restarts (BLOCKED: iroh_ex needs secret_key in NodeConfig)
- [ ] Persist namespace IDs for document continuity (depends on identity persistence)

### Phase 2: Production Readiness
- [ ] Resolve Linux x86_64 NIF build (iroh_ex cross-compilation or precompiled binary)
- [ ] Test cross-node room state sync (two Fly.io instances)
- [ ] Add telemetry events for iroh operations
- [ ] Performance benchmark: gossip at 100+ topics

### Phase 3: Room Markdown CRDT (Low-Hanging Fruit)
- [ ] Add `GossipTopic` and `CrdtDocument` to supervision (DynamicSupervisor per active room)
- [ ] Wire gossip broadcast on `CrdtDocument` change
- [ ] Wire gossip receive to `CrdtDocument` merge
- [ ] Connect room_markdown changes to LiveView via PubSub

### Phase 4: Sensor Data P2P
- [ ] Implement `SensorGossipPublisher` (subscribes to `data:attention:*` topics)
- [ ] Build reverse index `sensor_id -> room_id` in ETS
- [ ] Add iroh dependency to Rust client
- [ ] Binary encoding for gossip measurements

### Phase 5: Advanced Distribution
- [ ] Historical data as iroh-blobs
- [ ] Client-side iroh for mobile apps
- [ ] Guided session P2P extension (if needed beyond PubSub)
- [ ] Adaptive video quality with iroh signaling (`plans/PLAN-adaptive-video-quality.md`)

---

## Key Relationships with Other Architecture Work

### Data Pipeline Optimizations
The sensor data pipeline has evolved significantly since the initial iroh assessment. Key features that affect iroh integration planning:
- **Source-side batch throttling** (SimpleSensor): load_level x attention_level determines whether measurements broadcast immediately or buffer into batches. Under elevated+ load, SimpleSensor batches measurements before broadcasting to PubSub, reducing message count.
- **High-frequency attribute accumulation** (PriorityLens): ECG and respiration data now accumulate as lists between flushes (preserving waveform fidelity) rather than keep-latest-only.
- **Delta encoding integration point** (PriorityLens): `maybe_delta_encode_batch/1` is already wired into `flush_batch/2` but guarded by feature flag.

These optimizations reduce the urgency of iroh for server-side efficiency. The main remaining argument for iroh is native client support and offline scenarios.

### Discovery Module (`lib/sensocto/discovery/`, `plans/PLAN-distributed-discovery.md`)
The Discovery module provides ETS-cached cluster-wide entity listing with background `SyncWorker`. Uses `:pg` for sensor discovery, Horde for rooms/connectors. This is **complementary** to iroh -- Discovery handles Erlang cluster topology, while iroh handles server-to-native-client and peer-to-peer data flows. Both are needed at different scales.

### Guided Sessions (`lib/sensocto/guidance/`)
Guide-follower navigation sync via PubSub. State is small (lens, sensor focus, annotations, lobby settings) and unidirectional. PubSub handles it well.

### TURN/Cloudflare (`plans/PLAN-turn-cloudflare.md`)
Code-complete Cloudflare TURN integration for WebRTC video calls on mobile. Uses ephemeral credentials cached in `persistent_term`. Independent of iroh -- Membrane handles WebRTC, Cloudflare handles relay.

### Clustering Plan (`docs/CLUSTERING_PLAN.md`)
The clustering plan proposes Horde for distributed registries and `libcluster` for node discovery. This is **complementary** to iroh, not competing. The clustering plan handles server-to-server Erlang distribution. iroh handles server-to-native-client and peer-to-peer data flows.

Current state: `libcluster` is commented out in `mix.exs`. Horde is used for rooms and connectors. Sensors use `:pg` + local Registry. PubSub uses the default adapter.

### Membrane WebRTC Integration (`docs/membrane-webrtc-integration.md`)
The CallServer uses Membrane RTC Engine for video/voice calls. iroh could serve as a signaling layer for WebRTC negotiation, but Membrane handles this already. No iroh integration needed here.

### Scalability (`docs/scalability.md`)
The scalability doc focuses on the AttentionTracker bottleneck. The recommended path for 2000+ users is GenServer sharding by sensor. This is independent of iroh. The attention system's ETS-based read path and async writes are the right pattern regardless of transport layer.

---

## Appendix: Key File Locations

| Purpose | File |
|---------|------|
| iroh NIF bindings | `deps/iroh_ex/lib/iroh_ex.ex` |
| Compiled NIF (.so) | `_build/dev/lib/iroh_ex/priv/native/libiroh_ex-v0.0.15-nif-2.15-aarch64-apple-darwin.so` |
| Connection manager | `lib/sensocto/iroh/connection_manager.ex` |
| Low-level docs storage | `lib/sensocto/iroh/room_store.ex` |
| Async sync worker | `lib/sensocto/iroh/room_sync.ex` |
| Automerge CRDT state | `lib/sensocto/iroh/room_state_crdt.ex` |
| PubSub-to-CRDT bridge | `lib/sensocto/iroh/room_state_bridge.ex` |
| Iroh storage backend | `lib/sensocto/storage/backends/iroh_backend.ex` |
| Room ticket generation | `lib/sensocto/p2p/room_ticket.ex` |
| Bridge socket | `lib/sensocto_web/channels/bridge_socket.ex` |
| Bridge channel | `lib/sensocto_web/channels/bridge_channel.ex` |
| Ticket API controller | `lib/sensocto_web/controllers/api/room_ticket_controller.ex` |
| Gossip test page | `lib/sensocto_web/live/iroh_gossip_live.ex` |
| Per-room gossip topics | `lib/sensocto/room_markdown/gossip_topic.ex` |
| CRDT document wrapper | `lib/sensocto/room_markdown/crdt_document.ex` |
| Room markdown format | `lib/sensocto/room_markdown/room_document.ex` |
| Tigris object storage | `lib/sensocto/room_markdown/tigris_storage.ex` |
| Backup worker | `lib/sensocto/room_markdown/backup_worker.ex` |
| Storage supervisor | `lib/sensocto/storage/supervisor.ex` |
| Application entry | `lib/sensocto/application.ex` |
| Discovery module | `lib/sensocto/discovery/discovery.ex` |
| Discovery cache (ETS) | `lib/sensocto/discovery/discovery_cache.ex` |
| Discovery sync worker | `lib/sensocto/discovery/sync_worker.ex` |
| Guidance session server | `lib/sensocto/guidance/session_server.ex` |
| Guidance session supervisor | `lib/sensocto/guidance/session_supervisor.ex` |
| Sensor data router | `lib/sensocto/lenses/router.ex` |
| Priority lens (buffer) | `lib/sensocto/lenses/priority_lens.ex` |
| SimpleSensor (broadcast) | `lib/sensocto/otp/simple_sensor.ex` |
| Delta encoder | `lib/sensocto/encoding/delta_encoder.ex` |
| Architecture design doc | `docs/iroh-room-storage-architecture.md` |
| Migration plan | `plans/PLAN-room-iroh-migration.md` |
| Distributed discovery plan | `plans/PLAN-distributed-discovery.md` |
| Clustering plan | `docs/CLUSTERING_PLAN.md` |
| Scalability guide | `docs/scalability.md` |
| Delta encoding plan | `plans/delta-encoding-ecg.md` |
| Research sync plan | `plans/PLAN-research-grade-synchronization.md` |
| Sensor scaling plan | `plans/PLAN-sensor-scaling-refactor.md` |
| Adaptive video plan | `plans/PLAN-adaptive-video-quality.md` |
| Sensor component plan | `plans/PLAN-sensor-component-migration.md` |
| TURN/Cloudflare plan | `plans/PLAN-turn-cloudflare.md` |
| Automerge tests | `test/sensocto/iroh/iroh_automerge_test.exs` |
| RoomStateCRDT tests | `test/sensocto/iroh/room_state_crdt_test.exs` |

---

## Changelog

### 2026-03-05: Report Refresh
- No iroh code changes since 2026-02-08; all 5 iroh modules remain unchanged
- iroh_ex remains at v0.0.15, NIF binary aarch64-apple-darwin only (38.6 MB)
- Significant pipeline change: respiration added to `@high_frequency_attributes` in PriorityLens, now accumulates as list (like ECG)
- Updated Opportunity #5: delta encoding should now target respiration data alongside ECG
- Added detailed sensor data pipeline documentation with ASCII diagram showing full data flow
- Added source-side batch throttling details to pipeline documentation
- Added "Server-Only Breakpoint Analysis" section to Cost/Scale Analysis -- honest assessment of when iroh becomes necessary
- Updated composite lens context: now 9-tuple (heartrate, imu, location, ecg, battery, skeleton, respiration, hrv, gaze)
- Added Phase 0 task: migrate DeltaEncoder.enabled?/0 from Application.get_env to :persistent_term
- Added "Data Pipeline Optimizations" section under Key Relationships
- All blockers remain unchanged: no secret_key in NodeConfig, no Linux NIF, list_all_rooms still broken
- All 6 questions for iroh team remain unanswered

### 2026-03-01: Report Refresh
- No iroh code changes since 2026-02-08; all 5 iroh modules remain unchanged
- iroh_ex remains at v0.0.15, NIF binary aarch64-apple-darwin only
- New platform features since last update: Guided Sessions, Discovery module, TURN/Cloudflare integration, graph views, audio/MIDI, breathing lens
- Added Opportunity #6: Guided Session P2P Extension (low priority, PubSub sufficient)
- Renumbered opportunities: Research visualizations is now #7, Historical blobs #8, Room markdown #9
- Updated all plan file paths: moved from root to `plans/` directory
- Added Discovery module, Guidance module, TURN plan to file locations appendix
- Added sensor registry architecture section (confirmed stable at :pg + local Registry)
- Added "Key Relationships" entries for Discovery module and Guided Sessions
- All blockers remain unchanged
- All 6 questions for iroh team remain unanswered

### 2026-02-20: Report Refresh
- No iroh code changes since 2026-02-08; all iroh modules remain unchanged
- Recent commits (12841b8-9207440): audio/MIDI, polls, user profiles, delta encoding -- none touch iroh
- Delta encoding encoder module now exists, upgraded Opportunity #5 to "partially done"
- Updated cost model: delta encoding + attention routing push iroh breakpoint from ~1,000 to ~10,000 sensors

### 2026-02-16: Report Refresh and Context Update
- No iroh code changes since 2026-02-08; all iroh modules remain unchanged
- Updated data pipeline documentation: PubSub now uses sharded attention topics
- Updated sensor registry context: sensors use :pg + local Registry (not Horde)
- Added ETS direct-write optimization to pipeline description
- Noted GossipTopic and CrdtDocument are unsupervised
- Added relationships with clustering plan, Membrane WebRTC, scalability guide

### 2026-02-08: Implementation Progress
- Implemented `Iroh.ConnectionManager` -- consolidated 4 separate iroh nodes into 1 shared GenServer
- Completed `RoomStateBridge` bidirectional sync -- CRDT-to-local direction with echo suppression
- Updated all 4 consumer modules to use ConnectionManager
- Updated `Storage.Supervisor` to start ConnectionManager first
- Discovered blocker: iroh_ex v0.0.15 NodeConfig has no `secret_key` field
- All tests pass (324 tests, 0 failures)

### 2026-02-08: Initial Report
- Inventoried all iroh modules, tests, plans, and architecture documents
- Identified critical architectural issues (4 nodes, no persistence, unidirectional bridge)
- Built cost model showing P2P savings become significant at 1,000+ sensors
- Documented 5 open questions for iroh team

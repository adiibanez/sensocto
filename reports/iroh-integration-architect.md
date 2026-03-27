# Iroh Integration -- Team Report
*Last updated: 2026-03-25*

## Goals

1. **Complete the half-built room state CRDT sync** so media playback, 3D viewer, and presence state synchronize between multiple server instances and (eventually) directly to clients.
2. **Consolidate the 4 separate iroh nodes into 1** via the `IrohConnectionManager` pattern. **DONE.**
3. **Bridge sensor data to iroh gossip** for native clients (mobile, edge), while keeping the Phoenix PubSub path for web LiveView.
4. **Use iroh-blobs for historical sensor data distribution** so seed data for composite lenses does not always hit PostgreSQL.
5. **Achieve production readiness** by resolving the Linux x86_64 NIF build blocker for Fly.io.

---

## Current Status (2026-03-25)

### What Has Changed Since 2026-03-08

**iroh modules**: No changes. The iroh code in `lib/sensocto/iroh/` has been stable since the ConnectionManager consolidation (commit `4d12618`, 2026-02-08). All 5 modules (`connection_manager.ex`, `room_store.ex`, `room_sync.ex`, `room_state_crdt.ex`, `room_state_bridge.ex`) are unchanged.

**iroh_ex dependency**: Unchanged at `~> 0.0.16`.

**Significant surrounding changes (Mar 8 - Mar 25):**

- **New: Rust SDK with lobby and room session management** -- A full Rust client SDK now exists at `clients/rust/`. It uses Phoenix Channels over WebSocket (not iroh) and includes:
  - `LobbySession` (lobby.rs): joins `lobby:{user_id}`, receives `lobby_state`, `room_added`, `room_removed`, `room_updated`, `membership_changed` events
  - `RoomSession` (room_session.rs): joins `room:{room_id}`, receives `room_state`, `sensor_added`, `sensor_removed`, `member_joined`, `member_left`, `room_closed` events
  - Full backpressure model (`BackpressureConfig`, `AttentionLevel`, `SystemLoadLevel`) mirroring the server-side system
  - Auto-reconnect with exponential backoff and jitter
  - Call session (WebRTC signaling via channel)

  **Impact on iroh planning**: This Rust SDK is the **primary integration target for iroh**. It already speaks WebSocket/Channel to the server. Adding iroh as a secondary transport for sensor data would mean: Rust SDK uses WebSocket for control plane (lobby, room join/leave, calls) and optionally iroh-gossip for data plane (sensor measurements). The SDK's existing `BackpressureConfig` model maps cleanly to gossip topic subscription -- a paused sensor would not subscribe to the gossip topic.

- **New: LobbyChannel** (`lib/sensocto_web/channels/lobby_channel.ex`): Read-only Phoenix Channel for the room list. Subscribes to `rooms:lobby` and `lobby:{user_id}` PubSub topics. Pushes `lobby_state`, `room_added`, `room_removed`, `room_updated`, `membership_changed` events. This is the server-side counterpart to the Rust `LobbySession`.

- **New: RoomChannel** (`lib/sensocto_web/channels/room_channel.ex`): Phoenix Channel for live room updates (sensor add/remove, member changes). Joins `room:{room_id}`, subscribes to `room:#{room_id}` PubSub. Validates room access via `authorized_for_room?/2` (public rooms or membership check). This is the server-side counterpart to the Rust `RoomSession`.

- **RoomStore: lobby broadcast hooks** -- `room_store.ex` now broadcasts to lobby-specific PubSub topics on room CRUD and membership changes: `broadcast_lobby_room_created/1`, `broadcast_lobby_room_deleted/1`, `broadcast_lobby_room_updated/1`, `broadcast_lobby_membership_changed/3`. These feed the LobbyChannel. Also added a non-blocking `handle_cast({:remove_sensor, ...})` for use in `terminate/2` callbacks to avoid cascade timeouts during bulk sensor shutdown.

- **Router: early exit guard** -- `handle_info({:measurement, ...})` and `handle_info({:measurements_batch, ...})` now check `MapSet.size(state.registered_lenses) > 0` before calling `PriorityLens.buffer_for_sensor/2`. Avoids unnecessary ETS writes when no lenses are registered. Small but important optimization for idle servers.

- **PriorityLens: crash resilience** -- Multiple public functions (`get_socket_state/1`, `buffer_for_sensor/2`, `buffer_batch_for_sensor/2`, `subscriptions_for_sensor/1`) now rescue `ArgumentError` to handle the window between PriorityLens restart and ETS table recreation. `terminate/2` no longer calls `Router.unregister_lens/1` synchronously (which could timeout under load); it relies on Router's `:DOWN` monitor for cleanup.

- **ViewerDataChannel: visible sensor filtering** -- Now supports `set_visible_sensors` incoming event from the browser. In sensors grid mode, only pushes data for visible sensor IDs (MapSet filter). Composite/graph modes push all sensors. This reduces per-push payload size significantly for large sensor grids.

- **SystemLoadMonitor: container-aware memory** -- `calculate_memory_pressure/0` now reads cgroup v2 (`/sys/fs/cgroup/memory.max`, `/sys/fs/cgroup/memory.current`) and cgroup v1 (`/sys/fs/cgroup/memory/memory.limit_in_bytes`) before falling back to `:memsup`. Memsup fallback now counts cached+buffered memory as available. This makes memory protection thresholds accurate on Fly.io (container environment). Also includes `code_change/3` for hot upgrades.

- **SimpleSensor: auto-register attributes in batch path** -- `handle_cast(:put_batch_attributes, ...)` now auto-registers unknown attributes (infers type from attribute_id and payload), matching the existing single-measurement path. Broadcasts `:new_state` on attribute discovery. Also includes `code_change/3`.

- **SensorDataChannel: backpressure and memory protection** -- Channel now handles `{:memory_protection_changed, %{active: active}}` messages, immediately pushing updated backpressure config to connectors when memory pressure changes. The `get_backpressure_config/1` function incorporates memory protection state with 5x throttling multiplier for surviving sensors.

- **UserSocket: expanded channel routing** -- Now routes `room:*`, `call:*`, `hydration:room:*`, `viewer:*`, `lobby:*` channels alongside the existing `sensocto:*`.

**Key takeaway:** The platform has gained a proper **control plane for native clients** (LobbyChannel + RoomChannel + Rust SDK). The data pipeline is more resilient (crash-safe ETS access, non-blocking terminate, container-aware memory pressure). The Rust SDK provides a clean integration surface for adding iroh as an optional data transport layer. The control plane (room management, membership, calls) will stay on WebSocket/Channels; the data plane (sensor measurements) is where iroh-gossip adds value.

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

### Channel Architecture (Updated)

```
UserSocket
  |-- sensocto:connector:{id}   -> SensorDataChannel  (sensor registration + data ingestion)
  |-- sensocto:sensor:{id}      -> SensorDataChannel  (per-sensor measurement channel)
  |-- room:{room_id}            -> RoomChannel         (NEW: live room updates for native clients)
  |-- call:{room_id}            -> CallChannel         (WebRTC signaling)
  |-- hydration:room:{room_id}  -> HydrationChannel    (historical data seeding)
  |-- viewer:{token}            -> ViewerDataChannel   (high-freq sensor data to browser)
  |-- lobby:{user_id}           -> LobbyChannel        (NEW: room list updates for native clients)
```

### Sensor Data Pipeline (Current Architecture)

The pipeline has zero iroh involvement and is highly optimized:

```
SimpleSensor GenServer
  |-- put_attribute/put_batch_attributes cast
  |-- Auto-registers unknown attributes (infers type from id + payload)
  |-- AttributeStoreTiered: ETS write (hot data)
  |-- PubSub broadcast: "data:{sensor_id}" (per-sensor, always)
  |-- Attention gate: if attention_level != :none
  |     |-- PubSub broadcast: "data:attention:{high|medium|low}"
  |     |-- Source-side batch throttling under elevated+ system load
  |     |     (buffer measurements, flush as batch on interval)
  |
Router GenServer (singleton)
  |-- Subscribes to 3 attention topics (demand-driven: only when lenses registered)
  |-- Early exit: skips ETS write if no lenses registered
  |-- Writes directly to PriorityLens ETS tables (bypasses GenServer mailbox)
  |
PriorityLens GenServer
  |-- 4 ETS tables: buffers, sockets, digests, sensor_subscriptions (all :public)
  |-- Crash-resilient: rescues ArgumentError on ETS access during restart window
  |-- Reverse index: sensor_id -> MapSet<socket_id> (O(1) lookup)
  |-- High-frequency attributes (ecg, respiration, button, buttons): accumulate lists
  |-- Other attributes: keep-latest-only
  |-- Flush timer per socket: broadcasts to "lens:priority:{socket_id}"
  |-- Quality levels: high(64ms), medium(128ms), low(250ms), minimal(500ms), paused
  |-- Delta encoding integration: maybe_delta_encode_batch/1 on flush (feature-flagged OFF)
  |-- Terminate: relies on Router :DOWN monitor (no sync call)
  |
ViewerDataChannel (per-browser-tab)
  |-- Subscribes to "lens:priority:{lv_socket_id}" via signed token
  |-- Sensors grid: filters to visible_sensor_ids MapSet (set_visible_sensors event)
  |-- Composite/graph: pushes all sensors
  |-- Pushes "sensor_batch" and "sensor_digest" to browser
```

Key efficiency features:
- **Attention-aware routing**: Sensors with `attention_level: :none` do not broadcast to the attention-sharded topics at all
- **Demand-driven subscriptions**: Router only subscribes to attention topics when PriorityLens has registered sockets; Router skips ETS writes when no lenses registered
- **GenServer-free hot path**: Router writes directly to PriorityLens ETS tables, no mailbox contention
- **Visible sensor filtering**: ViewerDataChannel only pushes data for sensors visible in the browser viewport (sensors grid mode)
- **Source-side batch throttling**: Under elevated+ system load, SimpleSensor buffers measurements and flushes as batches (configurable intervals by load_level x attention_level)
- **Mailbox self-protection**: SimpleSensor drops measurements when its own mailbox exceeds 500 messages
- **Hibernation**: Sensors with low/no attention hibernate after 5 minutes of inactivity
- **Container-aware memory protection**: SystemLoadMonitor reads cgroup v2/v1 for accurate memory pressure on Fly.io; triggers 5x backpressure multiplier on surviving sensors
- **Crash resilience**: PriorityLens ETS access wrapped in rescue, non-blocking terminate avoids cascade timeouts

### Sensor Registry Architecture (Stable)

- **Local lookup**: `SimpleSensorRegistry` (Elixir `Registry`, unique keys) -- used by `via_tuple`
- **Cluster discovery**: `:pg` process groups (scope `:sensocto_sensors`) -- used by `get_device_names/0`
- **Rooms/Connectors**: Use `Horde.Registry` for cluster-wide distributed lookup
- **Discovery module** (`lib/sensocto/discovery/`): ETS-cached read path with background `SyncWorker`

### Architectural Issues

**RESOLVED: 4 separate iroh nodes consolidated into 1.** The `Iroh.ConnectionManager` GenServer owns the single shared iroh node. All 4 consumer modules (`RoomStore`, `RoomStateCRDT`, `GossipTopic`, `CrdtDocument`) use `ConnectionManager.get_node_ref()`.

**RESOLVED: RoomStateBridge now bidirectional.** The CRDT-to-local direction is implemented with echo suppression. Media state (play/pause/seek) and object3d state sync from CRDT to local servers.

**POSSIBLY UNBLOCKED: Node identity persistence.** Previously blocked because `iroh_ex` v0.0.15's `NodeConfig` had no `secret_key` field. The v0.0.16 `NodeConfig` struct now includes `secret_key` as an enforced key. **Needs validation**: test that passing a `secret_key` to `NodeConfig.build/1` actually results in the same node identity across restarts. The `ConnectionManager.build_node_config/0` must be updated to persist and restore the key.

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

### Opportunity 3: Persist Node Identity and Namespace IDs -- POSSIBLY UNBLOCKED
**Impact: HIGH (enables real P2P continuity)**
**Effort: 2-4 hours** (iroh_ex v0.0.16 now has `secret_key` in NodeConfig -- needs validation)
**Needs Linux NIF: No (but matters more in production)**

**What:** Store the iroh node's secret key to disk on first run, restore it on subsequent runs. Also persist the mapping of `room_id -> namespace_id` so documents survive restarts.

**What's already built:** `RoomTicket` already derives deterministic namespace identifiers via HMAC. The architecture doc specifies a `priv/iroh/node_identity` file path.

**What's changed since last report:** iroh_ex v0.0.16's `NodeConfig` struct now includes `secret_key` as an enforced key. `NodeConfig.build/0` defaults it to `""`. The `generate_secretkey/0` NIF function exists and can presumably be passed to `NodeConfig.build(secret_key: key)`.

**What's needed:** (1) Validate that non-empty `secret_key` in NodeConfig produces deterministic node identity. (2) Add persistence code to `ConnectionManager`: generate key on first start, store to `priv/iroh/node_secret.key`, restore on subsequent starts.

**Honest assessment:** This is likely a half-day task now, down from "blocked." The iroh_ex v0.0.16 upgrade appears to have resolved the API gap. This is the prerequisite for Phase 1 of the P2P sensor data routing plan.

### Opportunity 4: Sensor Data Gossip Bridge (for Native Clients) -- UPDATED
**Impact: HIGH for mobile/native clients; ZERO for web LiveView**
**Effort: 2-3 days**
**Needs Linux NIF: Yes (for production), No (for dev demo)**

**What:** A new `SensorGossipPublisher` GenServer that subscribes to the sharded PubSub topics (`"data:attention:high"`, etc.) and republishes measurements to per-room iroh gossip topics. Native clients receive sensor data P2P instead of going through the server.

**Updated context (2026-03-25):** The Rust SDK now exists at `clients/rust/` and already implements the full WebSocket/Channel protocol with `SensorStream`, `BackpressureConfig`, `LobbySession`, and `RoomSession`. This SDK is the **primary integration target for iroh-gossip**. The architecture would be:
- **Control plane**: WebSocket/Channels (lobby, room management, calls, backpressure) -- unchanged
- **Data plane**: iroh-gossip for sensor measurements -- new, optional, additive

The Rust SDK's `BackpressureConfig` model (paused, attention_level, recommended_batch_window) maps directly to gossip subscription behavior: a paused sensor does not join the gossip topic. The `RoomSession` already knows which room it belongs to, providing the room-to-gossip-topic mapping.

**New efficiency features to leverage:** Router's early-exit guard (no ETS writes when no lenses registered) and ViewerDataChannel's visible-sensor filtering both reduce server-side work. These make the "server as gossip participant" strategy (Strategy A) even cheaper -- the server only processes gossip data when someone is actually viewing it.

**Honest assessment:** The Rust SDK makes this opportunity more concrete. The control plane is already built over Channels. Adding gossip as the data plane for the Rust client is a well-defined, isolated change. But it still needs identity persistence (#3), a Linux NIF, and the Rust SDK to be embedded in a real native app.

### Opportunity 5: Delta Encoding for ECG and Respiration Data (NOT iroh -- Pure Server) -- PARTIALLY DONE
**Impact: HIGH for interactive experience**
**Effort: 1-2 days remaining** (encoder implemented, JS decoder + integration pending)
**Needs Linux NIF: No (not iroh-related)**

**What:** Implement the delta encoding plan at `plans/delta-encoding-ecg.md`. Reduces ECG WebSocket bandwidth by ~84%.

**Status:** The Elixir encoder module exists at `lib/sensocto/encoding/delta_encoder.ex` (148 lines). Feature-flagged off. Binary protocol with version byte and reset markers. The `maybe_delta_encode_batch/1` function in PriorityLens is already wired in (`flush_batch/2`) but guards on `DeltaEncoder.enabled?()`.

**New since last report:** ViewerDataChannel now handles the sensor_batch delivery, so the delta-encoded payloads would flow through `push(socket, "sensor_batch", ...)` in the channel rather than through LiveView push_event. This is actually better for delta encoding -- channel pushes are raw binary-friendly.

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

### Opportunity 10: Rust SDK iroh-gossip Data Transport (NEW)
**Impact: HIGH for native mobile experience**
**Effort: 3-5 days (Rust side) + 2-3 days (server side)**
**Needs Linux NIF: Yes (for production server)**
**Depends on: #3 (identity persistence), #4 (server-side gossip bridge)**

**What:** Extend the Rust SDK (`clients/rust/`) to optionally receive sensor data via iroh-gossip alongside or instead of WebSocket. The SDK already has the room context (via `RoomSession`) and backpressure model. Adding iroh would mean:

1. Rust SDK embeds `iroh-gossip` crate (Rust-native, no NIF needed on client side)
2. On `join_room`, SDK requests a gossip ticket from the server (via the room channel or REST API -- `RoomTicket` already generates these)
3. SDK subscribes to the room's gossip topic
4. Sensor measurements arrive via gossip (binary encoded, ~50-80 bytes vs ~200+ JSON via WebSocket)
5. Backpressure config continues to arrive via WebSocket channel (control plane)

**Architecture:**
```
Control plane (always WebSocket):   lobby, room join/leave, backpressure, calls
Data plane (WebSocket OR gossip):   sensor measurements
Gossip advantage:                   P2P between native clients on same LAN (~1ms)
Gossip fallback:                    relay through server's iroh node (~50ms)
WebSocket fallback:                 existing ViewerDataChannel path (always works)
```

**Honest assessment:** This is the logical evolution of the existing Rust SDK. The control plane is built. The server-side gossip bridge (#4) is designed. The missing piece is the Rust client's iroh integration and the identity persistence (#3). This becomes the highest-impact iroh opportunity once a real native app is being built with the Rust SDK.

---

## Summary Matrix

| # | Opportunity | Effort | Impact | Needs Linux NIF | Status |
|---|-----------|--------|--------|----------------|--------|
| 1 | IrohConnectionManager | 1-2 days | CRITICAL | No | **DONE** |
| 2 | Complete Bridge bidirectional sync | 2-4 hours | HIGH | No | **DONE** |
| 3 | Persist node identity/namespaces | 2-4 hours | HIGH | No | **POSSIBLY UNBLOCKED** (iroh_ex v0.0.16 has secret_key) |
| 4 | Sensor data gossip bridge (server) | 3-5 days | HIGH (native only) | Yes (prod) | **DESIGNED** (see P2P plan) |
| 5 | Delta encoding for ECG + respiration | 1-2 days remaining | HIGH (all users) | No | Encoder done, JS decoder pending |
| 6 | Guided Session P2P extension | 1-2 days | MEDIUM | No | Planned (PubSub sufficient) |
| 7 | Research-grade sync visualizations | 5-10 days | HIGH (differentiation) | No | Planned (not iroh) |
| 8 | Historical data as blobs | 3-5 days | MEDIUM | Yes (P2P) | Planned |
| 9 | Room markdown CRDT sync | 1-2 days | MEDIUM | No | Planned |
| 10 | Rust SDK iroh-gossip transport | 5-8 days | HIGH (native) | Yes (server) | **NEW** -- depends on #3, #4 |

**Recommended execution order:**
1. **#5 Delta encoding** -- highest impact-to-effort ratio, zero dependencies, benefits all users immediately. Now covers both ECG and respiration.
2. **#3 Identity persistence** -- enables real P2P continuity (blocked on iroh_ex change)
3. **#7 Research visualizations** -- product differentiation, independent of iroh
4. **#9 Room markdown sync** -- close to working, just needs supervision + wiring
5. **#4 + #10 Sensor gossip bridge + Rust SDK gossip** -- execute together when native app development begins
6. **#6 Guided Session P2P** -- only if non-clustered or native support needed
7. **#8 Historical data blobs** -- only at scale

---

## Impediments and Blockers

### 1. Linux x86_64 NIF Build (POSSIBLY RESOLVED in v0.0.16)

**Status:** iroh_ex v0.0.16's `RustlerPrecompiled` config at `deps/iroh_ex/lib/native.ex` now lists `"x86_64-unknown-linux-gnu"` and `"aarch64-unknown-linux-gnu"` as compilation targets. This suggests precompiled binaries for Linux should be available via the GitHub releases.

**Needs validation:** Confirm that `_build/dev/lib/iroh_ex/priv/native/` contains or can download the Linux x86_64 binary on a Fly.io deployment. The `rustler_precompiled` dependency (v0.8) handles download at compile time.

**Mitigation:** All modules gracefully degrade when the NIF is unavailable. The application runs fine without iroh -- it just does not have P2P capabilities.

### 2. iroh_ex NodeConfig `secret_key` (POSSIBLY RESOLVED in v0.0.16)

The `NodeConfig` struct in iroh_ex v0.0.16 now includes `secret_key` as an enforced key (defaults to `""` when built via `NodeConfig.build/0`). The `generate_secretkey/0` NIF function also exists. **Needs validation**: does passing a non-empty `secret_key` to `create_node` actually produce a deterministic node identity? The `ConnectionManager.build_node_config/0` must be updated to persist and restore the key. This is a 30-minute validation task.

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

### 7. Rust SDK iroh-gossip Integration (NEW)
We are building a Rust native SDK (`clients/rust/`) that currently uses Phoenix Channels over WebSocket. We want to add iroh-gossip as an optional data transport for sensor measurements. Is there a recommended pattern for embedding iroh-gossip in a Rust application alongside an existing WebSocket connection? Specifically: can we create an iroh node in the same tokio runtime as the WebSocket client, or do they need separate runtimes?

---

## Cost/Scale Analysis

### Current Architecture Cost Projections

The sensor data pipeline uses attention-aware sharded PubSub, ETS direct-writes, source-side batch throttling, mailbox self-protection, container-aware memory pressure, and visible-sensor filtering -- making the server-only path highly efficient. The data flow is demand-driven end-to-end: no subscriptions unless someone is watching, no broadcasts unless attention_level is non-zero, no ETS writes unless lenses are registered, no sensor_batch pushes unless sensors are visible in viewport.

| Sensor Count | Active (20%) | Viewers | Server I/O | Est. Monthly Cost (Fly.io) |
|-------------|-------------|---------|------------|---------------------------|
| 100 | 20 | 5 | 0.4 MB/s | $7 (shared-cpu-1x) |
| 1,000 | 200 | 20 | 4 MB/s | $14 (shared-cpu-2x) |
| 10,000 | 2,000 | 50 | 40 MB/s | $57 (performance-4x) |
| 100,000 | 20,000 | 200 | 400 MB/s | $500+ (multi-machine) |

Assumptions: 50Hz average, 200 bytes/measurement, attention-aware routing = 20% active.

**New efficiency gains since last report:**
- Router early-exit guard: eliminates ETS writes when server is idle (0 lenses). Reduces CPU on servers not actively rendering.
- ViewerDataChannel visible-sensor filtering: for a grid showing 20 of 200 sensors, 90% of batch data is not pushed to the browser. Significant bandwidth savings for large deployments.
- Container-aware memory protection: accurate thresholds on Fly.io prevent OOM kills, keeping the server alive under extreme load instead of crashing.

### With Delta Encoding (#5) -- Immediate Win

ECG + respiration data (the highest-bandwidth attributes) compressed by ~84%:

| Sensor Count | Active | Without Delta | With Delta | Savings |
|-------------|--------|--------------|-----------|---------|
| 1,000 | 200 | 4 MB/s | 1.5 MB/s | 62% |
| 10,000 | 2,000 | 40 MB/s | 15 MB/s | 62% |

This applies to ALL users (web and native) immediately, no iroh needed.

### With iroh-gossip (#4 + #10) -- Native Clients Only

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
- **Router early-exit** eliminates ETS writes when no viewer is connected
- **Visible-sensor filtering** reduces per-push payload by 80-90% for large sensor grids
- **Demand-driven everything** means zero overhead when no one is watching
- **Container-aware memory protection** prevents crash-restart cycles on Fly.io

**The honest assessment:** At current feature set and expected near-term scale (hundreds of sensors, tens of viewers), the server-only architecture is sufficient and well-optimized. The recent efficiency improvements (Router early-exit, visible-sensor filtering, container-aware memory) push the "iroh becomes worth it" threshold even higher. iroh adds value at:
- **1,000+ sensors with 50+ concurrent viewers** -- where server I/O becomes the bottleneck
- **Native mobile clients (Rust SDK)** -- where server round-trip latency degrades interactive experience and P2P on same LAN gives sub-millisecond latency
- **Multi-region deployment** -- where Erlang clustering is impractical and P2P data flow reduces cross-region traffic
- **Offline/edge scenarios** -- where clients need to continue collecting and viewing data without server connectivity

None of these scenarios are imminent priorities. The correct path is to complete the non-iroh wins (#5 delta encoding, #7 research visualizations) first and revisit iroh integration when a concrete use case emerges that the server-only architecture cannot handle. The Rust SDK provides the natural integration surface when that time comes.

---

## Roadmap

### Phase 0: Non-iroh Wins (NOW)
- [x] Implement delta encoding -- encoder done (`lib/sensocto/encoding/delta_encoder.ex`), JS decoder + integration pending
- [ ] Extend delta encoding to respiration data (config change + JS decoder)
- [ ] Migrate `DeltaEncoder.enabled?/0` from `Application.get_env` to `:persistent_term`
- [ ] Research-grade sync visualizations P1 tier (`plans/PLAN-research-grade-synchronization.md`)
- [x] LobbyChannel + RoomChannel for native client control plane
- [x] Rust SDK: lobby, room session, backpressure, auto-reconnect
- [x] ViewerDataChannel visible-sensor filtering
- [x] Container-aware memory protection in SystemLoadMonitor
- [x] Router early-exit guard (no ETS writes when idle)
- [x] PriorityLens crash resilience (ArgumentError rescue, non-blocking terminate)

### Phase 1: iroh Foundation
- [x] Implement `IrohConnectionManager` -- single shared node (2026-02-08)
- [x] Complete `RoomStateBridge` bidirectional sync (2026-02-08)
- [ ] Persist node identity across restarts (BLOCKED: iroh_ex needs secret_key validation)
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

### Phase 4: Sensor Data P2P (Server + Rust SDK)
- [ ] Implement `SensorGossipBridge` (subscribes to `data:attention:*` topics)
- [ ] Build reverse index `sensor_id -> room_id` in ETS
- [ ] Extend `RoomTicket` to include sensor gossip topic
- [ ] Add `iroh-gossip` crate to Rust SDK (`clients/rust/Cargo.toml`)
- [ ] Implement `GossipTransport` in Rust SDK (optional data plane alongside WebSocket)
- [ ] Binary encoding for gossip measurements (~50-80 bytes vs ~200+ JSON)
- [ ] Backpressure-aware gossip subscription (paused sensors do not join gossip)

### Phase 5: Advanced Distribution
- [ ] Historical data as iroh-blobs
- [ ] Client-side iroh for mobile apps (iOS/Android via Rust FFI)
- [ ] Guided session P2P extension (if needed beyond PubSub)
- [ ] Adaptive video quality with iroh signaling (`plans/PLAN-adaptive-video-quality.md`)

---

## Key Relationships with Other Architecture Work

### Data Pipeline Optimizations
The sensor data pipeline has evolved significantly since the initial iroh assessment. Key features that affect iroh integration planning:
- **Source-side batch throttling** (SimpleSensor): load_level x attention_level determines whether measurements broadcast immediately or buffer into batches. Under elevated+ load, SimpleSensor batches measurements before broadcasting to PubSub, reducing message count.
- **High-frequency attribute accumulation** (PriorityLens): ECG and respiration data now accumulate as lists between flushes (preserving waveform fidelity) rather than keep-latest-only.
- **Delta encoding integration point** (PriorityLens): `maybe_delta_encode_batch/1` is already wired into `flush_batch/2` but guarded by feature flag.
- **Router early-exit**: No ETS writes when no lenses registered. This means the gossip bridge (#4) would be the only consumer of attention-sharded PubSub data when no web viewers are connected -- clean separation.
- **ViewerDataChannel visible-sensor filtering**: Reduces bandwidth for web clients. The gossip bridge would not need this filtering since native clients manage their own rendering.

These optimizations reduce the urgency of iroh for server-side efficiency. The main remaining argument for iroh is native client support and offline scenarios.

### Rust SDK (`clients/rust/`)
The Rust SDK is the primary native client implementation. It currently handles:
- **Control plane**: lobby (room discovery), room sessions (sensor/member updates), calls (WebRTC signaling), backpressure (attention + load config)
- **Data plane**: sensor measurement ingestion via `SensorStream` over Phoenix Channels

The iroh integration target is clear: add gossip as an alternative data plane transport. The control plane stays on Channels. The SDK's architecture (tokio-based async, mpsc event channels, Arc-wrapped shared state) is well-suited for embedding an iroh node.

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
| Compiled NIF (.so) | `_build/dev/lib/iroh_ex/priv/native/libiroh_ex-v0.0.16-nif-2.15-{arch}.so` |
| Connection manager | `lib/sensocto/iroh/connection_manager.ex` |
| Low-level docs storage | `lib/sensocto/iroh/room_store.ex` |
| Async sync worker | `lib/sensocto/iroh/room_sync.ex` |
| Automerge CRDT state | `lib/sensocto/iroh/room_state_crdt.ex` |
| PubSub-to-CRDT bridge | `lib/sensocto/iroh/room_state_bridge.ex` |
| Iroh storage backend | `lib/sensocto/storage/backends/iroh_backend.ex` |
| Room ticket generation | `lib/sensocto/p2p/room_ticket.ex` |
| Bridge socket | `lib/sensocto_web/channels/bridge_socket.ex` |
| Bridge channel | `lib/sensocto_web/channels/bridge_channel.ex` |
| Lobby channel | `lib/sensocto_web/channels/lobby_channel.ex` |
| Room channel | `lib/sensocto_web/channels/room_channel.ex` |
| Sensor data channel | `lib/sensocto_web/channels/sensor_data_channel.ex` |
| Viewer data channel | `lib/sensocto_web/channels/viewer_data_channel.ex` |
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
| RoomStore (in-memory) | `lib/sensocto/otp/room_store.ex` |
| SystemLoadMonitor | `lib/sensocto/otp/system_load_monitor.ex` |
| Delta encoder | `lib/sensocto/encoding/delta_encoder.ex` |
| **Rust SDK** | `clients/rust/src/` |
| Rust SDK: client | `clients/rust/src/client.rs` |
| Rust SDK: lobby session | `clients/rust/src/lobby.rs` |
| Rust SDK: room session | `clients/rust/src/room_session.rs` |
| Rust SDK: models | `clients/rust/src/models.rs` |
| Rust SDK: channel/stream | `clients/rust/src/channel.rs` |
| Rust SDK: socket | `clients/rust/src/socket.rs` |
| Rust SDK: config | `clients/rust/src/config.rs` |
| Architecture design doc | `docs/iroh-room-storage-architecture.md` |
| Migration plan | `plans/PLAN-room-iroh-migration.md` |
| Distributed discovery plan | `plans/PLAN-distributed-discovery.md` |
| Clustering plan | `docs/CLUSTERING_PLAN.md` |
| Scalability guide | `docs/scalability.md` |
| Delta encoding plan | `plans/delta-encoding-ecg.md` |
| Research sync plan | `plans/PLAN-research-grade-synchronization.md` |
| Sensor scaling plan | `plans/PLAN-sensor-scaling-refactor.md` |
| Adaptive video plan | `plans/PLAN-adaptive-video-quality.md` |
| TURN/Cloudflare plan | `plans/PLAN-turn-cloudflare.md` |
| Automerge tests | `test/sensocto/iroh/iroh_automerge_test.exs` |
| RoomStateCRDT tests | `test/sensocto/iroh/room_state_crdt_test.exs` |

---

## P2P Sensor Data Routing -- Architectural Plan (2026-03-08, updated 2026-03-25)

### Problem Statement

Mobile devices in the same Sensocto room currently route all sensor data through the server:

```
Mobile A (sensor) --WebSocket--> Server --WebSocket--> Mobile B (viewer)
Mobile A (sensor) --WebSocket--> Server --WebSocket--> Mobile C (viewer)
```

Each sensor measurement travels to the server and is fanned out to every viewer. For N mobile devices in a room, each producing sensor data at 10-50Hz with ~200 bytes/measurement, the server handles N * M * freq * 200 bytes/second of I/O (where M = number of viewers). With 10 devices at 25Hz average, that is 10 * 9 * 25 * 200 = 450KB/s through the server -- modest, but growing quadratically with room size.

The goal is to enable same-room mobile devices to exchange sensor data peer-to-peer, reducing server I/O and latency. Two sub-goals:

1. **Full P2P**: All devices exchange sensor data directly, server only orchestrates room membership
2. **Hybrid**: One device streams to server (for persistence/audit), others receive locally via P2P

### Design Question Answers

#### 1. What iroh primitives are available?

From the `IrohEx.Native` NIF bindings at `deps/iroh_ex/lib/native.ex`:

| Primitive | Available | Relevant Functions |
|-----------|-----------|-------------------|
| **iroh-net** (QUIC connectivity) | Yes | `create_node/2`, `connect_node/2`, `gen_node_addr/1`, `list_peers/1` |
| **iroh-gossip** (pub/sub) | Yes | `subscribe_to_topic/3`, `broadcast_message/3`, `unsubscribe_from_topic/2`, `list_topics/1` |
| **iroh-blobs** (content-addressed transfer) | Yes | `blob_add/2`, `blob_get/2`, `blob_list/1` |
| **iroh-docs** (CRDT key-value) | Yes | `docs_create/1`, `docs_set_entry/5`, `docs_get_entry_value/4` |
| **Automerge CRDT** | Yes | Full map/list/text/counter ops, merge, sync via gossip |

**Best primitive for sensor data: iroh-gossip.** Sensor data is ephemeral (no need to persist in a CRDT), high-frequency, fan-out to all room members, and tolerant of message loss. iroh-gossip is built on HyParView/PlumTree epidemic broadcast trees -- exactly the right tool for real-time sensor dissemination.

iroh-docs/Automerge are wrong for sensor data: they are designed for persistent, conflict-free state (like room configuration), not for ephemeral streams.

#### 2. Best topology: full mesh P2P, or one device as relay?

**Recommended: Star topology with server node as bootstrap, converging to partial mesh via gossip.**

iroh-gossip handles topology automatically. It does not require full mesh -- it builds a spanning tree (PlumTree) with lazy repair paths. Devices join a gossip topic and iroh manages the overlay network.

However, the critical architecture choice is where the iroh node lives:

| Option | Pros | Cons |
|--------|------|------|
| **A. Server-side iroh node only** (mobiles connect via WebSocket/Channel, server publishes to gossip) | Simplest to implement, web clients unchanged | Server still handles all data, just adds gossip as secondary transport |
| **B. Native mobile iroh + server iroh node** | True P2P between native apps, server participates as one gossip peer for persistence | Requires iroh SDK on each mobile platform (iOS/Android), web browsers cannot participate in P2P |
| **C. Server-mediated relay: one mobile streams to server, server gossips to room** | Reduces upstream bandwidth (1 device to server instead of N), other devices receive from server via gossip or WebSocket | Still server-mediated for first hop |

**Recommendation: Option A (Phase 1), then Option B (Phase 2).**

Phase 1 (server-side gossip publisher) is achievable with the current stack. Phase 2 (native mobile iroh) is now more concrete thanks to the Rust SDK -- the Rust client already has the async runtime and connection management needed to embed an iroh node.

#### 3. How does a mobile browser/native app connect to iroh?

**Native mobile apps (iOS/Android) -- via Rust SDK:**
- The Rust SDK at `clients/rust/` already runs on tokio and manages Phoenix Channel connections
- Adding `iroh-gossip` as a Cargo dependency gives native gossip support in the same process
- On same LAN: iroh uses local network discovery (mDNS) for direct connections (~1ms latency)
- Different networks: iroh holepunches (success rate ~90%) or falls back to relay (~50-100ms added latency)
- The `RoomTicket` at `lib/sensocto/p2p/room_ticket.ex` already generates bootstrap data: docs namespace, gossip topic, bootstrap peers, relay URL

**Browser (web) clients:**
- iroh compiles to WASM but ALL connections must flow through a relay (browsers cannot send UDP)
- For web clients, the existing ViewerDataChannel path will remain the lowest-latency option since the Phoenix server is already a single hop
- No change needed for web clients

**Practical implication:** P2P sensor data routing primarily benefits native mobile apps using the Rust SDK. Web browsers gain little because they already communicate through the server via WebSocket. The plan should not break the existing web path.

#### 4. What happens when devices are NOT on the same LAN?

iroh handles this transparently with a fallback chain:

```
Same LAN  -->  mDNS discovery  -->  direct QUIC  (~1ms)
                    |
                    v (if mDNS fails)
Public IP  -->  holepunching via relay-assisted NAT traversal  (~10-30ms)
                    |
                    v (if holepunching fails, ~10% of cases)
Relay      -->  encrypted relay through euw1-1.relay.iroh.network  (~50-100ms)
```

All connections are end-to-end encrypted. The relay cannot read the data.

For the Sensocto use case, the "same room" scenario splits into two:

- **Physical same room**: Devices on same WiFi network. mDNS discovery gives direct QUIC connections. This is the best case -- sub-millisecond latency between devices.
- **Virtual same room**: Devices in different locations joined to the same Sensocto room. Holepunching or relay. Still better than server round-trip if the server is geographically distant.

**Server fallback**: If iroh connectivity fails entirely (rare, but possible behind very restrictive corporate NATs), the existing WebSocket/Channel path remains available. The Rust SDK already implements auto-reconnect with exponential backoff for the WebSocket path.

#### 5. How does the server learn about sensor data if P2P bypasses it?

Three strategies, not mutually exclusive:

**Strategy A: Server participates in gossip (recommended)**
The server's iroh node (managed by `ConnectionManager`) joins the same gossip topic as the mobile devices. It receives all sensor data via gossip and feeds it into the existing pipeline (PriorityLens ETS) for web clients and persistence.

```
Mobile A --gossip--> Mobile B (direct, P2P)
Mobile A --gossip--> Server iroh node (via gossip, same topic)
                         |
                         v
                    PubSub "data:attention:{level}" (existing pipeline)
```

This means the server sees 100% of the data with no additional mobile upload cost -- gossip distributes the data, and the server is just another subscriber. The Router's early-exit guard ensures no ETS writes happen unless a web viewer is actually connected.

**Strategy B: Elected uploader**
One mobile device is elected (by the server) to upload sensor data via the existing WebSocket path. Other devices receive P2P. If the elected device goes offline, another is elected. This reduces upstream bandwidth by (N-1)/N.

**Strategy C: Digest-only to server**
Mobile devices only send periodic digests (1Hz summaries instead of 25Hz raw data) to the server. Full-rate data flows P2P. The server stores digests for audit. Works well when the server does not need to render real-time visualizations.

**Recommendation: Strategy A for Phase 1.** The server iroh node subscribing to gossip is the simplest and gives the server complete visibility. Strategies B and C are optimizations for Phase 2 when server bandwidth becomes a concern.

#### 6. What is the minimal server-side change needed?

**Phase 1 requires one new module and one small change:**

1. **New module: `Sensocto.Iroh.SensorGossipBridge`** (~200 lines)
   - A GenServer that subscribes to PubSub `"data:attention:high"`, `"data:attention:medium"`, `"data:attention:low"`
   - On each measurement batch, publishes to per-room gossip topics via `IrohEx.Native.broadcast_message/3`
   - Also subscribes to incoming gossip (from mobile devices publishing sensor data P2P)
   - Incoming gossip data is re-published to the existing PubSub topics so PriorityLens picks it up

2. **Small change: extend `RoomTicket.generate/2`** to include sensor gossip topic alongside the existing docs namespace and CRDT gossip topic

No changes needed to: SimpleSensor, Router, PriorityLens, LobbyLive, ViewerDataChannel, LobbyChannel, RoomChannel, or any Svelte components. The existing pipeline is completely preserved.

**Phase 2: Rust SDK gossip integration** (~300-400 lines Rust)
1. Add `iroh-gossip` crate dependency
2. New `GossipTransport` struct that creates an iroh node, joins room gossip topics
3. `SensorStream` gains ability to publish via gossip instead of (or in addition to) WebSocket
4. `RoomSession` gains ability to receive sensor data via gossip subscription
5. Fallback: if gossip connection fails, sensor data flows over WebSocket (existing path)

### Architecture Diagram

```mermaid
graph TB
    subgraph "Mobile Device A (sensor source)"
        SA[Sensor Hardware<br/>BLE/Internal]
        IA[iroh node<br/>native Rust]
        SA -->|raw data| IA
    end

    subgraph "Mobile Device B (viewer)"
        IB[iroh node<br/>native Rust]
        VB[Sensor Visualization<br/>native UI]
        IB -->|sensor data| VB
    end

    subgraph "Server (Phoenix)"
        SGB[SensorGossipBridge<br/>new GenServer]
        CM[ConnectionManager<br/>shared iroh node]
        PS[PubSub<br/>data:attention:*]
        R[Router]
        PL[PriorityLens<br/>ETS]
        VDC[ViewerDataChannel<br/>WebSocket]
        LC[LobbyChannel<br/>room list]
        RC[RoomChannel<br/>room updates]

        SGB <-->|gossip subscribe/<br/>publish| CM
        SGB -->|incoming gossip<br/>measurements| PS
        PS -->|existing pipeline| R
        R -->|ETS write<br/>(if lenses registered)| PL
        PL -->|flush| VDC
    end

    subgraph "Web Browser (viewer)"
        WS[WebSocket]
        LV[LiveView / Svelte]
        WS --> LV
    end

    subgraph "Rust SDK (native client)"
        RS[SensoctoClient]
        WS2[WebSocket<br/>control plane]
        GT[GossipTransport<br/>data plane]
        RS --> WS2
        RS --> GT
    end

    IA <-->|iroh gossip<br/>P2P or relay| IB
    IA <-->|iroh gossip| CM
    IB <-->|iroh gossip| CM
    VDC <-->|WebSocket| WS
    WS2 <-->|Channels| LC
    WS2 <-->|Channels| RC
    GT <-->|iroh gossip| CM

    style SGB fill:#f9f,stroke:#333,stroke-width:2px
    style GT fill:#f9f,stroke:#333,stroke-width:2px
    style IA fill:#bbf,stroke:#333
    style IB fill:#bbf,stroke:#333
    style CM fill:#bbf,stroke:#333
```

---

## Changelog

### 2026-03-25
- Added analysis of new Rust SDK (`clients/rust/`), LobbyChannel, RoomChannel
- Added Opportunity #10: Rust SDK iroh-gossip data transport
- Updated channel architecture diagram (new channels)
- Updated data pipeline documentation (Router early-exit, PriorityLens crash resilience, ViewerDataChannel visible-sensor filtering)
- Updated cost analysis with new efficiency gains
- Updated RoomStore analysis (lobby broadcasts, non-blocking remove_sensor)
- Updated SystemLoadMonitor analysis (container-aware memory, code_change)
- Added Question #7 for iroh team (Rust SDK integration pattern)
- Updated Phase 4 roadmap to include Rust SDK gossip integration
- Updated architecture diagram to include Rust SDK and new channels

### 2026-03-08
- Added P2P Sensor Data Routing architectural plan
- Research on iroh browser/mobile capabilities
- Identified iroh-gossip (not iroh-docs) as the correct primitive for sensor data
- Designed server-as-gossip-participant strategy
- Added architecture diagram

### 2026-03-05
- Updated for iroh_ex v0.0.16 (secret_key, Linux targets)
- Added respiration as high-frequency attribute
- Updated composite lens tuple to 9 elements

### 2026-03-01
- Initial comprehensive report
- Consolidated from previous partial assessments
- Module-by-module assessment
- Cost/scale analysis

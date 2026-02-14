# Iroh Integration -- Team Report
*Last updated: 2026-02-08 (Implementation Progress)*

## Goals

1. **Complete the half-built room state CRDT sync** so media playback, 3D viewer, and presence state synchronize between multiple server instances and (eventually) directly to clients.
2. **Consolidate the 4 separate iroh nodes into 1** via the `IrohConnectionManager` pattern, which is a prerequisite for everything else.
3. **Bridge sensor data to iroh gossip** for native clients (mobile, edge), while keeping the Phoenix PubSub path for web LiveView.
4. **Use iroh-blobs for historical sensor data distribution** so seed data for composite lenses does not always hit PostgreSQL.
5. **Achieve production readiness** by resolving the Linux x86_64 NIF build blocker for Fly.io.

---

## Current Status -- Deep Audit (2026-02-08)

### Module-by-Module Assessment

| Module | Lines | Status | Verdict |
|--------|-------|--------|---------|
| `Iroh.ConnectionManager` | 216 | **NEW -- Functional** | Single shared iroh node. Synchronous init. All other modules get `node_ref` from here. |
| `Iroh.RoomStore` | ~530 | Functional, tested indirectly | Uses shared node from ConnectionManager. CRUD works. `list_all_rooms` broken (always empty). New namespaces every restart. |
| `Iroh.RoomSync` | 352 | Functional | Good debouncing and retry logic. Hydration from iroh docs never actually loads anything (because `list_all_rooms` returns empty). |
| `Iroh.RoomStateCRDT` | ~740 | Functional, tested | Full Automerge API (media, 3D, presence). Uses shared node from ConnectionManager. In-memory only (docs lost on restart). |
| `Iroh.RoomStateBridge` | ~400 | **Functional (both directions)** | Local-to-CRDT via PubSub. CRDT-to-local now applies media state (play/pause/seek) and object3d state. Echo suppression via sentinel message pattern. |
| `Storage.Backends.IrohBackend` | 289 | Functional | Secondary backend behind PostgreSQL. Properly delegates to `Iroh.RoomStore`. |
| `P2P.RoomTicket` | 322 | Functional | Generates deterministic tickets via HMAC. Caches in ETS. Good deep link / QR code support. |
| `BridgeChannel` | 166 | Functional | WebSocket bridge for sidecar. Topic pub/sub works. |
| `IrohGossipLive` | 319 | Demo/test page | Creates 50 nodes (!), connects them, sends messages. Useful for testing but resource-heavy. |
| `RoomMarkdown.GossipTopic` | ~360 | Functional (unsupervised) | Per-room gossip topics. Uses shared node from ConnectionManager. Not started in any supervisor. |
| `RoomMarkdown.CrdtDocument` | ~470 | Functional (unsupervised) | Full room-as-document Automerge support. Uses shared node from ConnectionManager. Not started in any supervisor. |

### Architectural Issues (Updated 2026-02-08)

**RESOLVED: 4 separate iroh nodes consolidated into 1.** The new `Iroh.ConnectionManager` GenServer owns the single shared iroh node. All 4 consumer modules (`RoomStore`, `RoomStateCRDT`, `GossipTopic`, `CrdtDocument`) now request `node_ref` from ConnectionManager. This eliminates 3 redundant relay connections and enables cross-module coordination.

**RESOLVED: RoomStateBridge now bidirectional.** The CRDT-to-local direction is implemented with echo suppression. Media state (play/pause/seek) and object3d state sync from CRDT to local servers.

**BLOCKED: Node identity persistence.** Each restart still creates a new node identity because `iroh_ex` v0.0.15's `NodeConfig` has no `secret_key` field. The Rust NIF's `create_node` calls `Endpoint::builder().bind()` without a key. Fix needed in iroh_ex: add `secret_key: Option<String>` to the Rust `NodeConfig` struct.

**Zero cross-node synchronization works today.** Despite the Automerge and gossip infrastructure, no data actually synchronizes between separate server instances because:
- Each restart creates a new node identity (blocked, see above)
- Namespace IDs are ephemeral
- `automerge_sync_via_gossip/2` requires connected peers, but no connection is established between instances

**Sensor data pipeline has zero iroh involvement.** The entire `SimpleSensor -> data:global -> Router -> PriorityLens -> LiveView` path is pure Phoenix PubSub. This is by design — Phoenix PubSub is the right tool for web LiveView clients.

### What Actually Works Well

- **Automerge primitives are solid.** The NIF provides map, list, text, counter operations. Tests pass. Document creation, forking, saving, loading, and merging all work.
- **Circuit breaker integration.** All iroh calls go through `Sensocto.Resilience.CircuitBreaker`, preventing cascading failures when the NIF is unavailable.
- **Graceful NIF detection.** Every module checks `function_exported?(Native, :create_node, 2)` and degrades to `nif_unavailable: true` state rather than crashing.
- **Room ticket generation.** Deterministic HMAC-based namespace derivation means the same room always gets the same ticket parameters.

---

## Ranked Opportunities (Effort-to-Impact)

### Opportunity 1: IrohConnectionManager -- Single Shared Node -- DONE
**Impact: CRITICAL (prerequisite for everything else)**
**Effort: 1-2 days** (completed 2026-02-08)
**Needs Linux NIF: No (dev-only is fine)**

**What:** Create a single GenServer that owns the iroh node reference. All 4 modules request the `node_ref` from it instead of creating their own nodes.

**What's already built:** The full design exists at `docs/iroh-room-storage-architecture.md` (lines 77-194). The struct, client API, health monitoring, and identity persistence are all specified.

**What's missing:** The actual implementation. Currently each module has its own `initialize_node/0` function creating independent nodes.

**Why it matters:** Without this, every other iroh feature is degraded. 4 nodes means 4x relay connections, 4 different network identities, and no shared state between room storage and room CRDT operations.

**Honest assessment:** This is a clear win regardless of whether iroh is "the right tool." If you have iroh in the project at all, you should not be running 4 nodes. Pure engineering hygiene.

---

### Opportunity 2: Complete RoomStateBridge Bidirectional Sync -- DONE
**Impact: HIGH for interactive room experience**
**Effort: 2-4 hours** (completed 2026-02-08)
**Needs Linux NIF: No**

**What:** The `RoomStateBridge.do_sync_crdt_to_local/1` function (line 360-371) currently only logs remote state instead of applying it:

```elixir
defp do_sync_crdt_to_local(state) do
  case RoomStateCRDT.get_media_state(state.room_id) do
    {:ok, media} ->
      # NOTE: only logs, does NOT apply
      Logger.debug("[RoomStateBridge] Remote media state: #{inspect(media)}")
    {:error, _} -> :ok
  end
end
```

**What's already built:** The local-to-CRDT direction works perfectly. PubSub events from `MediaPlayerServer` and `Object3DPlayerServer` are captured and written to Automerge documents. The CRDT document structure supports all needed fields.

**What's missing:** Applying remote CRDT state back to local servers. This requires calling `MediaPlayerServer.seek/2`, `MediaPlayerServer.play/1`, etc. based on remote changes. Need to add loop prevention (don't re-broadcast changes that came from remote).

**Why it matters:** This is the "last mile" for room state sync. Once this works, two users in the same room on different server instances will see synchronized media playback, 3D viewer state, and presence.

**Honest assessment:** This is genuinely valuable for the interactive experience. Two people watching synchronized video or exploring a 3D object together is a real use case. However, Phoenix PubSub already handles same-node sync perfectly. The iroh path only matters for multi-node deployments. If you are running a single Fly.io instance, server-side PubSub is simpler and sufficient.

---

### Opportunity 3: Persist Node Identity and Namespace IDs -- BLOCKED
**Impact: HIGH (enables real P2P continuity)**
**Effort: 4-6 hours** (blocked on iroh_ex missing `secret_key` in NodeConfig)
**Needs Linux NIF: No (but matters more in production)**

**What:** Store the iroh node's secret key to disk on first run, restore it on subsequent runs. Also persist the mapping of `room_id -> namespace_id` so documents survive restarts.

**What's already built:** `RoomTicket` already derives deterministic namespace identifiers via HMAC. The architecture doc specifies a `priv/iroh/node_identity` file path.

**What's missing:** The actual persistence code. `iroh_ex` may or may not expose a secret key export API (this is Question #2 for the iroh team). If it does not, we may need to request this feature.

**Why it matters:** Without identity persistence, every restart creates a new node. Room tickets generated before the restart become invalid. Cross-node sync can never work because the node cannot be found by peers after restarting.

**Honest assessment:** This is essential for production P2P sync. For dev-only use where you restart frequently, it matters less. But it is a prerequisite for the "offline-capable" and "distributed sync" goals.

---

### Opportunity 4: Sensor Data Gossip Bridge (for Native Clients)
**Impact: HIGH for mobile/native clients; ZERO for web LiveView**
**Effort: 2-3 days**
**Needs Linux NIF: Yes (for production), No (for dev demo)**

**What:** A new `SensorGossipPublisher` GenServer that subscribes to `"data:global"` PubSub and republishes measurements to per-room iroh gossip topics. Native clients (mobile apps, Rust CLI) receive sensor data P2P instead of going through the server.

**What's already built:**
- `GossipTopic` already manages per-room gossip topics with join/leave/broadcast
- `BridgeChannel` already bridges Phoenix PubSub to external consumers
- The attention-aware routing in `SimpleSensor` already gates broadcasts

**What's missing:**
- The publisher module itself
- A reverse index from `sensor_id -> room_id` for fast routing
- Binary encoding of measurements for gossip (JSON is too wasteful for 50Hz data)
- A native client that consumes gossip topics (the Rust client at `clients/rust/` has no iroh dependency)

**Why it matters:** This is the core cost-reduction opportunity. At 10,000 sensors, moving native client data paths to P2P saves ~75% on server I/O costs (see Cost Analysis section below).

**Honest assessment:** This is a significant engineering effort with a dependency chain: it needs the `IrohConnectionManager` (Opportunity #1), identity persistence (#3), and a native client with iroh support. The payoff is real but distant. For web-only users (LiveView), this provides zero benefit -- Phoenix PubSub is the right tool for browser clients. This only matters if you have native clients consuming sensor data directly.

**Recommendation:** Build this incrementally. Start with the publisher module in dev, verify gossip delivery with the test page (`IrohGossipLive`), then add it to the Rust client when the Linux NIF is available.

---

### Opportunity 5: Delta Encoding for ECG Data (NOT iroh -- Pure Server)
**Impact: HIGH for interactive experience**
**Effort: 2-3 days**
**Needs Linux NIF: No (not iroh-related)**

**What:** Implement the delta encoding plan already designed at `plans/delta-encoding-ecg.md`. This reduces ECG WebSocket bandwidth by ~84% (from ~1000 bytes to ~162 bytes per 50-sample batch).

**Why this is listed here:** The existing plan is fully designed with Elixir encoder, JS decoder, PriorityLens integration, and rollout strategy. It requires zero iroh involvement. It improves the interactive experience for ALL users (web and native) immediately.

**Honest assessment:** This is better done with server-side encoding + client-side decoding via the existing Phoenix pipeline. iroh adds no value here. The plan is excellent and should be implemented as-is. I include it because it directly addresses the "big impact on interactive experience" goal and is lower risk than any iroh-dependent change.

---

### Opportunity 6: Research-Grade Sync Visualizations (Partially iroh-adjacent)
**Impact: HIGH for differentiation and interactive experience**
**Effort: 5-10 days for the P1 tier**
**Needs Linux NIF: No**

**What:** The plan at `plans/PLAN-research-grade-synchronization.md` defines 6 real-time Svelte visualizations and 3 post-hoc analysis types. The P1 tier (PLV matrix, phase space orbits, sync topology graph) would transform the product from "heart rate dashboard" to "interpersonal synchronization research tool."

**Where iroh fits:** The pairwise sync data (PLV matrix, TLCC) could be computed server-side and distributed via iroh-gossip to multiple viewers, reducing duplicate computation. But honestly, Phoenix PubSub handles this fine for the current scale.

**Honest assessment:** The visualizations themselves are pure Svelte/client-side work with existing data. iroh adds marginal value here. The impact comes from the visualizations themselves, not from the data transport mechanism. Build these with Phoenix PubSub.

---

### Opportunity 7: Historical Data as iroh-blobs
**Impact: MEDIUM (reduces PostgreSQL load for seed data)**
**Effort: 3-5 days**
**Needs Linux NIF: Yes for P2P; No for local caching**

**What:** When a user opens a composite lens and `seed_composite_historical_data/2` fetches from `AttributeStoreTiered`, store the result as an iroh blob with a content-addressed ticket. Subsequent viewers of the same time window fetch the blob instead of querying PostgreSQL.

**What's already built:** The `BlobStorageWorker` is fully designed in the architecture doc. `AttributeStoreTiered` already has the query infrastructure.

**What's missing:** The blob storage implementation, ticket generation for historical data, and a cleanup mechanism for expired time windows.

**Honest assessment:** This is a nice optimization at scale (50+ viewers repeatedly opening the same lens), but for small deployments, PostgreSQL with ETS caching (which `AttributeStoreTiered` already does) is sufficient. The iroh-blob approach shines in multi-node deployments where viewers on different nodes need the same historical data. Consider implementing this after the foundation (Opportunities #1-3) is solid.

---

### Opportunity 8: Room Markdown CRDT Sync (Closest to Working)
**Impact: MEDIUM for collaborative room editing**
**Effort: 1-2 days to get it working end-to-end**
**Needs Linux NIF: No (dev-only is fine)**

**What:** The `CrdtDocument` and `GossipTopic` modules together provide the infrastructure for room configuration documents (name, features, admins, body text) to sync via Automerge. This is the "room as a markdown document" concept.

**What's already built:** `CrdtDocument` can create, update, export, merge, and delete documents. `GossipTopic` manages per-room gossip topics with subscriber notification. `RoomDocument` defines the structured document format.

**What's missing:** Connecting the two -- when a `CrdtDocument` changes, broadcast via `GossipTopic`; when a gossip message arrives, merge into `CrdtDocument`. Also needs the `IrohConnectionManager` (#1) to avoid creating 2 additional nodes.

**Honest assessment:** Room configuration changes happen infrequently (minutes/hours, not seconds). Phoenix PubSub + PostgreSQL handles this perfectly for server-mediated sync. The iroh/CRDT approach adds value only if you want offline-capable room editing or true multi-writer conflict resolution for room configuration. For most use cases, server authority is simpler.

---

## Summary Matrix

| # | Opportunity | Effort | Impact | Needs Linux NIF | Status |
|---|-----------|--------|--------|----------------|--------|
| 1 | IrohConnectionManager | 1-2 days | CRITICAL | No | **DONE** |
| 2 | Complete Bridge bidirectional sync | 2-4 hours | HIGH | No | **DONE** |
| 3 | Persist node identity/namespaces | 4-6 hours | HIGH | No | **BLOCKED** (iroh_ex needs secret_key) |
| 4 | Sensor data gossip bridge | 2-3 days | HIGH (native only) | Yes (prod) | Planned |
| 5 | Delta encoding for ECG | 2-3 days | HIGH (all users) | No | Planned (not iroh) |
| 6 | Research-grade sync visualizations | 5-10 days | HIGH (differentiation) | No | Planned (not iroh) |
| 7 | Historical data as blobs | 3-5 days | MEDIUM | Yes (P2P) | Planned |
| 8 | Room markdown CRDT sync | 1-2 days | MEDIUM | No | Planned |

**Recommended execution order:**
1. **#5 Delta encoding** -- highest impact-to-effort ratio, zero dependencies, benefits all users immediately
2. **#1 IrohConnectionManager** -- prerequisite for all iroh work, pure code hygiene
3. **#2 Complete bridge sync** -- small effort, unlocks multi-node room experience
4. **#3 Identity persistence** -- enables real P2P continuity
5. **#6 Research visualizations** -- product differentiation, independent of iroh
6. **#4 Sensor gossip bridge** -- only after Linux NIF is available and native clients exist
7. **#8 Room markdown sync** -- nice to have
8. **#7 Historical data blobs** -- only at scale

---

## Impediments and Blockers

### 1. Linux x86_64 NIF Build (HARD BLOCKER for production P2P)

**Status:** The iroh_ex NIF binary is compiled for `aarch64-apple-darwin` only. Fly.io runs Linux x86_64 containers. Until a Linux build exists, all iroh features are disabled in production.

**Mitigation:** All modules gracefully degrade when the NIF is unavailable. The application runs fine without iroh -- it just does not have P2P capabilities.

**Action needed:** Either compile iroh_ex for `x86_64-unknown-linux-gnu` or request a precompiled binary from the iroh_ex maintainers.

### 2. ~~Four Separate Iroh Nodes~~ RESOLVED

Consolidated into single `Iroh.ConnectionManager` on 2026-02-08. All 4 consumer modules now share one node.

### 3. `list_all_rooms` Returns Empty (Known Bug)

`Iroh.RoomStore.do_list_all_rooms/1` always returns `{:ok, []}`. This means hydration from iroh docs on startup never loads anything. The in-memory `RoomStore` with PostgreSQL as primary source is not affected.

### 4. iroh_ex API Questions

Open questions from the previous report remain unanswered:
- Is `node_ref` safe to share across BEAM processes?
- Can node secret key be exported/imported for identity persistence?
- What are gossip performance characteristics at 100+ concurrent topics?
- Does `automerge_sync_via_gossip/2` require prior `connect_node/2`?

---

## Questions for the iroh Team

(Carried forward from previous report, still unanswered)

### 1. Shared Node API Pattern
Can a single `node_ref` be safely used from multiple BEAM processes concurrently? The NIF resource handle needs to be thread-safe for our shared-node architecture.

### 2. Node Identity Persistence
Does `iroh_ex` expose an API for exporting/importing the node's secret key? We need identity continuity across restarts.

### 3. Gossip Scale Characteristics
What are the memory and CPU costs per gossip topic? We may need 100-1000 concurrent topics.

### 4. Automerge Gossip Sync Prerequisites
Does `automerge_sync_via_gossip/2` require nodes to be connected via `connect_node/2` first? We have never observed actual cross-node sync.

### 5. iroh_ex Linux x86_64 Build
Is there a precompiled binary for `x86_64-unknown-linux-gnu` or a documented cross-compilation process? This is our production deployment target (Fly.io).

### 6. (NEW) NodeConfig secret_key Support
The `NodeConfig` Rust struct only has `is_whale_node`, `active_view_capacity`, `passive_view_capacity`, `relay_urls`. To persist node identity across restarts, we need to pass a previously generated secret key to `create_node`. The `generate_secretkey/0` NIF function exists but there's no way to use the result when creating a node. **Proposed fix**: Add `secret_key: Option<String>` to the Rust `NodeConfig` struct in `native/iroh_ex/src/lib.rs` and use `Endpoint::builder().secret_key(SecretKey::from_bytes(key))` when present.

---

## Cost/Scale Analysis

### Current Architecture Cost Projections

| Sensor Count | Active (20%) | Viewers | Server I/O | Est. Monthly Cost (Fly.io) |
|-------------|-------------|---------|------------|---------------------------|
| 100 | 20 | 5 | 0.4 MB/s | $7 (shared-cpu-1x) |
| 1,000 | 200 | 20 | 4 MB/s | $14 (shared-cpu-2x) |
| 10,000 | 2,000 | 50 | 40 MB/s | $57 (performance-4x) |
| 100,000 | 20,000 | 200 | 400 MB/s | $500+ (multi-machine) |

Assumptions: 50Hz average, 200 bytes/measurement, attention-aware routing = 20% active.

### With Delta Encoding (#5) -- Immediate Win

ECG data (the highest-bandwidth attribute) compressed by ~84%:

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

---

## Roadmap

### Phase 0: Non-iroh Wins (NOW)
- [ ] Implement delta encoding (plans/delta-encoding-ecg.md)
- [ ] Research-grade sync visualizations P1 tier (plans/PLAN-research-grade-synchronization.md)

### Phase 1: iroh Foundation
- [x] Implement `IrohConnectionManager` -- single shared node (2026-02-08)
- [x] Complete `RoomStateBridge` bidirectional sync (2026-02-08)
- [ ] Persist node identity across restarts (BLOCKED: iroh_ex needs secret_key in NodeConfig)
- [ ] Persist namespace IDs for document continuity (depends on identity persistence)

### Phase 2: Production Readiness
- [ ] Resolve Linux x86_64 NIF build
- [ ] Test cross-node room state sync (two Fly.io instances)
- [ ] Add telemetry events for iroh operations
- [ ] Performance benchmark: gossip at 100+ topics

### Phase 3: Sensor Data P2P
- [ ] Implement `SensorGossipPublisher`
- [ ] Build reverse index `sensor_id -> room_id` in ETS
- [ ] Add iroh dependency to Rust client
- [ ] Binary encoding for gossip measurements

### Phase 4: Advanced Distribution
- [ ] Historical data as iroh-blobs
- [ ] Room markdown CRDT end-to-end sync
- [ ] Client-side iroh for mobile apps

---

## Appendix: Key File Locations

| Purpose | File |
|---------|------|
| iroh NIF bindings | `deps/iroh_ex/lib/iroh_ex.ex` |
| Compiled NIF (.so) | `_build/dev/lib/iroh_ex/priv/native/libiroh_ex-v0.0.15-nif-2.15-aarch64-apple-darwin.so` |
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
| Storage supervisor | `lib/sensocto/storage/supervisor.ex` |
| Architecture design doc | `docs/iroh-room-storage-architecture.md` |
| Migration plan | `PLAN-room-iroh-migration.md` |
| Delta encoding plan | `plans/delta-encoding-ecg.md` |
| Research sync plan | `plans/PLAN-research-grade-synchronization.md` |
| Sensor scaling plan | `plans/PLAN-sensor-scaling-refactor.md` |
| Distributed discovery plan | `plans/PLAN-distributed-discovery.md` |
| Cluster visibility plan | `plans/PLAN-cluster-sensor-visibility.md` |
| Automerge tests | `test/sensocto/iroh/iroh_automerge_test.exs` |
| Sensor data router | `lib/sensocto/lenses/router.ex` |
| Priority lens (buffer) | `lib/sensocto/lenses/priority_lens.ex` |
| SimpleSensor (broadcast) | `lib/sensocto/otp/simple_sensor.ex` |
| Application supervision | `lib/sensocto/application.ex` |

---

## Changelog

### 2026-02-08: Implementation Progress
- Implemented `Iroh.ConnectionManager` -- consolidated 4 separate iroh nodes into 1 shared GenServer
- Completed `RoomStateBridge` bidirectional sync -- CRDT-to-local direction with echo suppression
- Updated all 4 consumer modules (RoomStore, RoomStateCRDT, GossipTopic, CrdtDocument) to use ConnectionManager
- Updated `Storage.Supervisor` to start ConnectionManager first (rest_for_one ordering)
- Discovered blocker: iroh_ex v0.0.15 NodeConfig has no `secret_key` field, blocking identity persistence
- Added Question #6 for iroh team about NodeConfig secret_key support
- All tests pass (324 tests, 0 failures)

### 2026-02-08: Opportunity Audit
- Deep audit of all 10+ iroh modules with line-level analysis
- Identified 8 concrete opportunities ranked by effort-to-impact
- Key finding: non-iroh wins (#5 delta encoding, #6 research visualizations) have higher immediate impact than iroh-specific work
- Key finding: `RoomStateBridge` bidirectional sync is 2-4 hours from working
- Key finding: 4 separate iroh nodes at startup is the most urgent architectural debt
- Recommended execution order prioritizes immediate user impact over iroh purity

### 2026-02-08: Initial Report
- Inventoried all iroh modules, tests, plans, and architecture documents
- Identified critical architectural issues (4 nodes, no persistence, unidirectional bridge)
- Built cost model showing P2P savings become significant at 1,000+ sensors
- Documented 5 open questions for iroh team

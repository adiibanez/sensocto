# Client-Side Offload Strategy

## Overview

Analysis of Sensocto server-side functionality that can be moved to the client (JavaScript/Svelte) to reduce server resource usage, improve scalability, and enable lower-cost deployments.

**Current bottleneck**: LobbyLive `handle_info` processes every PriorityLens flush (20-30/sec per socket), performing filtering, format conversion, sorting, and list computation that the client could handle.

**Estimated capacity**: 50 sensors x 10 users = ~10,000 PubSub messages/sec, 200 batch flushes/sec total.

---

## Strategy A: Thin Server Batches (Low Risk, High Impact)

### Concept
Stop filtering/transforming data in LobbyLive's `handle_info`. Instead, forward raw PriorityLens batches to the client and let JavaScript/Svelte filter by composite type, decode formats, and route to the correct component.

### What Changes

**Server (lobby_live.ex)**:
- `process_lens_batch_for_composite` (lines 3069-3131): Replace per-attribute-type filtering with a single `push_event("lens_batch", raw_batch)`.
- `process_lens_batch_for_sensors` (lines 2964-3054): Remove virtual scroll visibility filtering server-side. Send full batch, let client filter by visible range.
- `process_lens_digest_for_composite` (lines 3135-3162): Same pattern — send raw digest, client extracts what it needs.

**Client (app.js / Svelte)**:
- `CompositeMeasurementHandler` hook: Add attribute-type filtering. Currently dispatches every measurement as a CustomEvent; add a filter step that checks `attribute.type` against the active composite view.
- Svelte components already buffer updates (e.g., CompositeECG has `pendingUpdates` Map with 100ms batching). They would simply receive more data and discard irrelevant attributes.
- Delta decoding: Already partially client-side (`app.js:408`). Extend to handle all formats.

### Estimated Savings
- **30-40% reduction** in LobbyLive `handle_info` CPU time
- **~50% fewer push_events** (currently one per attribute; batched = one per flush)
- No architectural changes to PubSub or PriorityLens

### Pros
- Lowest risk: PriorityLens and SimpleSensor unchanged
- Incremental: can migrate one composite view at a time
- Client already has most of the infrastructure (buffering, batching, CustomEvents)
- Reduces server mailbox pressure, improving quality recovery during load spikes

### Cons
- Slightly more data over the WebSocket (sending attributes the client will discard)
- Client CPU increase (filtering ~100-300 measurements/sec — negligible for modern browsers)
- Need to maintain attribute type metadata on client side

### Implementation Effort
- **Server**: ~200 lines changed in lobby_live.ex (simplify 3 handler functions)
- **Client**: ~150 lines added to CompositeMeasurementHandler hook
- **Timeline**: 2-3 sessions

---

## Strategy B: Client-Side Sensor State (Medium Risk, High Impact)

### Concept
Move sensor list management (sorting, grouping, composite extraction, available lenses computation) from the server to the client. Server sends incremental sensor diffs; client maintains its own sensor state.

### What Changes

**Server (lobby_live.ex)**:
- Remove `extract_composite_data/1` (lines 642-850) — currently iterates all sensors 9 times per presence change
- Remove `sort_sensors/3` (lines 512-549) — called on every attention change
- Remove `compute_available_lenses/9` — derived from composite sensor lists
- On presence join: push `{:sensor_added, sensor_metadata}` event
- On presence leave: push `{:sensor_removed, sensor_id}` event
- On attention change: push `{:attention_update, sensor_id, level}` event
- On mount: push `{:sensor_list, [all_sensor_metadata]}` once

**Client (new SensorStateManager.js + Svelte stores)**:
- Maintain `Map<sensor_id, SensorMetadata>` client-side
- Derive composite lists: `heartrate_sensors = sensors.filter(s => s.attributes.includes('heartrate'))`
- Derive available lenses: `has_ecg = heartrate_sensors.length > 0`
- Sort by name/type/battery locally; sort by activity using attention levels from server events
- Svelte reactive stores auto-update UI when underlying data changes

### Estimated Savings
- **Eliminates O(N) recomputation** on every presence change and attention update
- Removes ~15-20% of intermittent CPU spikes (presence events trigger wholesale re-processing)
- Reduces server assigns size (9 composite lists + sorted sensor list removed from socket state)

### Pros
- Eliminates repeated server-side list recomputation
- Client-side sorting is instant (Svelte reactivity)
- Reduces socket assign memory (currently stores 9 lists of sensor IDs)
- Makes adding new composite lenses trivial (client filter, no server changes)

### Cons
- Larger initial payload on mount (full sensor metadata list)
- Client must handle edge cases: stale sensors, race conditions between presence diff and data arrival
- Sort-by-activity requires attention level sync (server must push attention changes reliably)
- Testing complexity increases (client state divergence from server)

### Implementation Effort
- **Server**: ~400 lines removed from lobby_live.ex, ~100 lines added (diff events)
- **Client**: New ~300 line SensorStateManager.js + Svelte store integration
- **Timeline**: 3-5 sessions

---

## Strategy C: Client-Side Search (Low Risk, Low-Medium Impact)

### Concept
Replace server-side `SearchIndex.search/1` with a client-side search library. Pre-load a lightweight search index on page mount.

### What Changes

**Server (search_live.ex)**:
- Remove `handle_event("search", ...)` handler (lines 38-55)
- Add `on_mount` hook that pushes `{:search_index, index_data}` with sensor names, room names, user names
- Push index updates when sensors/rooms change (infrequent)

**Client**:
- Use lightweight search library (e.g., Fuse.js ~6KB gzipped, or custom prefix matcher)
- Filter results locally on each keystroke
- Update UI directly without server round-trip

### Estimated Savings
- Eliminates ~10 server round-trips/sec during active typing
- Removes `SearchIndex` GenServer pressure
- Search results appear instantly (no WebSocket latency)

### Pros
- Very low risk: search is isolated, no data pipeline impact
- Instant results improve UX significantly
- Dataset is tiny (50-100 entries) — no performance concerns
- Reduces perceived latency from ~50-100ms to <5ms

### Cons
- Requires maintaining index freshness (push updates on sensor/room changes)
- Slight increase in initial page payload (~2-5KB for index data)
- Duplicates index logic (server still needs it for API/other consumers)

### Implementation Effort
- **Server**: ~50 lines changed in search_live.ex
- **Client**: ~100 lines for search integration
- **Timeline**: 1 session

---

## Strategy D: WebSocket Channel Direct (High Risk, Highest Impact)

### Concept
Bypass LiveView's `push_event` entirely for high-frequency sensor data. Use a dedicated Phoenix Channel that streams raw sensor batches directly to the client. LiveView handles only UI state (lens selection, modals, navigation).

### What Changes

**Server**:
- New `SensorDataChannel` joins a topic per user session
- PriorityLens flushes directly to Channel (bypasses LobbyLive mailbox entirely)
- LobbyLive no longer handles `{:lens_batch, ...}` or `{:lens_digest, ...}`
- LobbyLive only handles: lens selection, presence, UI events

**Client**:
- Separate Channel connection for data stream
- All data processing (filtering, format conversion, routing to components) client-side
- Svelte components receive data directly from Channel, not from LiveView hooks

### Estimated Savings
- **60-70% reduction** in LobbyLive process mailbox load
- LiveView process only handles low-frequency UI events (~1-10/sec instead of 20-30/sec)
- Channel can use binary serialization (MessagePack) for lower bandwidth
- Data path completely decoupled from DOM diffing

### Pros
- Maximum server resource savings
- Clean separation: LiveView = UI state, Channel = data stream
- Can scale data channel independently (different process pool)
- Opens door to WebRTC DataChannel for peer-to-peer sensor data (future iroh integration)
- Binary encoding reduces bandwidth 40-60% vs JSON push_events

### Cons
- Highest implementation complexity
- Two concurrent connections per client (LiveView socket + data channel)
- State synchronization between channel and LiveView (e.g., which lens is active)
- Harder to debug (data doesn't flow through LiveView DevTools)
- Requires significant client-side architecture (data routing, component wiring)
- Risk of data/UI desync if channel and LiveView get out of step

### Implementation Effort
- **Server**: New Channel module (~200 lines), PriorityLens modifications (~100 lines), LobbyLive simplification (~500 lines removed)
- **Client**: New DataChannelManager (~400 lines), Svelte store rewiring (~200 lines)
- **Timeline**: 5-8 sessions

---

## Strategy E: Hybrid Attention (Medium Risk, Medium Impact)

### Concept
Move attention aggregation partially to the client. Instead of each user's viewport/focus events going to the server for global aggregation, the client computes its own attention levels locally. Server only receives aggregated "I care about these sensors" updates at lower frequency.

### What Changes

**Server (attention_tracker.ex)**:
- Reduce incoming event frequency: client sends batch updates every 2-5 seconds instead of per-element
- Simplify aggregation: fewer messages to process
- Still maintains authoritative attention levels for PubSub routing

**Client (attention_tracker.js)**:
- Compute local attention levels from IntersectionObserver + focus + hover
- Batch changes: accumulate for 2-5 seconds, then send single update with all changed sensors
- Optimistic local state: immediately apply attention levels for sorting/filtering

### Estimated Savings
- **80-90% reduction** in attention-related server messages (batching)
- Reduces `{:attention_changed, ...}` broadcast storms during scrolling
- Smoother client-side sorting (no round-trip wait)

### Pros
- Dramatic reduction in attention-related server traffic
- Client-side attention feels more responsive (no round-trip)
- Server attention aggregation becomes simpler (fewer, larger updates)
- Compatible with all other strategies

### Cons
- Slightly stale server-side attention levels (2-5 second delay)
- May affect PubSub routing accuracy (sensor broadcasts to wrong attention tier temporarily)
- Client must handle attention computation (currently trivial but adds complexity)

### Implementation Effort
- **Server**: ~100 lines changed in attention_tracker.ex (batch handling)
- **Client**: ~150 lines changed in attention_tracker.js (local computation + batching)
- **Timeline**: 2 sessions

---

## Recommended Rollout Order

```
Phase 1 (Quick Wins):
  Strategy C (Client Search)     — 1 session, isolated, immediate UX win
  Strategy E (Hybrid Attention)  — 2 sessions, reduces message storm

Phase 2 (Core Offload):
  Strategy A (Thin Server Batches) — 2-3 sessions, biggest server CPU reduction
  Strategy B (Client Sensor State) — 3-5 sessions, eliminates recomputation spikes

Phase 3 (Architecture):
  Strategy D (WebSocket Channel)   — 5-8 sessions, maximum decoupling
  (Only if Phase 1+2 insufficient for target scale)
```

### Combined Impact Estimate

| Phase | Server CPU Reduction | WebSocket Bandwidth | Client CPU Increase | Risk |
|-------|---------------------|--------------------|--------------------|------|
| Phase 1 (C+E) | ~15-20% | -5% (fewer round-trips) | Negligible | Low |
| Phase 2 (A+B) | ~40-50% cumulative | +10% (raw batches) | Low (~5ms/batch) | Medium |
| Phase 3 (D) | ~60-70% cumulative | -20% (binary encoding) | Medium | High |

### Decision Criteria for Phase 3

Proceed to Strategy D only if:
- Target deployment exceeds 100 concurrent sensors / 20 users
- Server CPU remains above 60% after Phase 1+2
- Binary encoding bandwidth savings justify the complexity
- Iroh/P2P integration is on the roadmap (Strategy D is a stepping stone)

---

## Compatibility Matrix

| Strategy | Requires Other Strategies | Conflicts With |
|----------|--------------------------|----------------|
| A (Thin Batches) | None | D partially supersedes A |
| B (Client Sensor State) | None | None |
| C (Client Search) | None | None |
| D (Channel Direct) | Supersedes A | None (but A work is wasted) |
| E (Hybrid Attention) | None | None |

**Recommendation**: If Strategy D is on the horizon, skip A and go directly to D after Phase 1. If staying with LiveView long-term, do A+B for the best cost/benefit ratio.

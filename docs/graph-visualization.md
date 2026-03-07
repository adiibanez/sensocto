# Graph Visualization

The lobby graph (`/lobby/graph`, `/lobby/graph3d`) renders live sensor data as an interactive network. The primary implementation is `assets/svelte/LobbyGraph.svelte` (~4600 lines), built on [Sigma.js](https://www.sigmajs.org/) + [Graphology](https://graphology.github.io/).

## Graph Structure

The graph is a three-level hierarchy:

```
User (connector) ──── Sensor ──── Attribute
   user:abc              sensor:xyz         attr:xyz:heartrate
```

| Node type | Key format | Typical count |
|-----------|-----------|---------------|
| `user` | `user:{connector_id}` | 1–10 |
| `sensor` | `sensor:{sensor_id}` | 10–200 |
| `attribute` | `attr:{sensor_id}:{attr_id}` | 3–10 per sensor |

Edges carry a `tgtNodeType` field (`"sensor"` or `"attribute"`) cached at insertion time, used by the edge reducer without runtime graph lookups.

## Data Pipeline

```
ViewerDataChannel (Phoenix Channel)
    ↓  sensor_batch push
CompositeMeasurementHandler (JS hook in app.js)
    ↓  dispatches CustomEvents per attribute
    ├─ "composite-measurement-event"  → handleCompositeMeasurement()
    ├─ "graph-activity-event"         → handleGraphActivity()
    └─ "attention-changed-event"      → handleAttentionChanged()
```

The graph subscribes on `onMount` and cleans up on `onDestroy`. The three handlers update Graphology attributes and trigger visual effects — they do **not** directly call `sigma.refresh()`; that is batched via `scheduleRefresh()` (at most one RAF per frame).

## Layout Modes

Nine layout algorithms are available, selectable from the sidebar or via auto-cycle:

| Mode | Algorithm | Description |
|------|-----------|-------------|
| `topology` | ForceAtlas2 (Web Worker) | Organic force-directed clustering. Default. |
| `per-user` | Circular sub-clusters | Each user's sensors arranged in a ring around the user node. |
| `per-type` | Column lanes | One vertical column per attribute type; sensors positioned within their type columns. |
| `radial` | Concentric rings | Users → sensors → attributes in expanding rings from center. |
| `flower` | Rose-curve petals | Each sensor type forms a petal; nodes distributed along petal curves. |
| `octopus` | Central head + tentacles | 8 typed tentacles curving outward from a central cluster. |
| `mushroom` | Dome cap + stem | Users in a dome, sensors/attributes in a tapered stem below. |
| `jellyfish` | Bell + trailing tentacles | Parabolic bell with undulating tentacle strands. |
| `dna` | Double helix spiral | Nodes arranged on a 3D-projected helix. |

### ForceAtlas2 details

- **< 50 nodes**: synchronous layout (blocking, instant)
- **50–200 nodes**: async Web Worker, 1500ms wall-clock budget
- **200–500 nodes**: async Worker, 2000ms budget
- **> 500 nodes**: async Worker, 3000ms budget; Barnes-Hut O(N log N) enabled
- Settings: `gravity: 0.3`, `scalingRatio: 12` (small) / `20` (large), `linLogMode: true`, `barnesHutTheta: 0.6`

Layout switches use a morph animation (500ms) → quick sync pre-pass → async refinement phase.

### per-type layout notes

After positioning nodes by type group, any node not covered (sensor hub nodes without attributes in view, or type-mismatched keys) is pulled to center `(50, 50)` to avoid outliers from stale coordinates of a previous layout.

## Visual Modes

Six overlays that change how nodes/edges are colored and animated:

| Mode | Description | Key data structure |
|------|-------------|-------------------|
| `pulse` | Nodes briefly enlarge + lighten on each data event. Default. | `activePulsations: Map<nodeId, {timeout, baseSize, originalColor}>` |
| `heatmap` | Node color/size scales with event frequency over a 10s sliding window. | `activityCounts: Map<nodeId, number>`, `activityDecayTimers: Map<nodeId, timer>` |
| `freshness` | Nodes fade toward gray as time since last data event increases. Resets on new data. | `nodeFreshness: Map<nodeId, timestamp>` |
| `heartbeat` | Canvas overlay draws ECG-style pulse waves along edges, synchronized to BPM. | `heartbeatBPMs: Map<nodeId, bpm>`, `heartbeatHopDistances: Map<nodeId, hops>` |
| `river` | Animated particles travel along edges from sensor to attribute nodes. Max 300 particles. | `riverParticles: Particle[]` |
| `attention` | Nodes colored by PriorityLens attention level (high/medium/low/none). | `sensorAttentionLevels: Map<sensor_id, level>` |

Switching visual modes calls `cleanupVisual(oldMode)` then `applyViewMode(newMode)`. Each mode has a corresponding `stop*()` function that clears its data structures and cancels timers/animation frames.

## Seasonal Themes

Five color themes control node, edge, glow, and heatmap colors:

| Season | Palette character |
|--------|-------------------|
| `spring` | Greens, soft teal |
| `summer` | Bright yellows, warm orange |
| `autumn` | Deep amber, rust, burgundy |
| `winter` | Cold blue-gray, icy whites |
| `rainbow` | Vibrant multi-hue |

Season is auto-detected from the current CET month on first load, then persisted to `localStorage`. Attribute node colors additionally vary by attribute type (`heartrate`, `battery`, `location`, `imu`, or default).

## Level-of-Detail (LOD)

When the graph has **≥ 300 nodes** and the camera ratio exceeds `2.5` (zoomed far out), attribute nodes and their edges are hidden. This is controlled by the reactive `lodAttributesVisible` boolean, evaluated in the Sigma node/edge reducers on every refresh.

The edge reducer uses the cached `tgtNodeType` field on edge data — no graph lookups in the hot path.

## Performance Architecture

### Pulsation coalescing

`handleGraphActivity` calls `schedulePulsation(nodeId)` instead of `pulsateNode()` directly. A `Set<string>` collects all pending node IDs; a single `requestAnimationFrame` callback flushes them all in one batch. Many events arriving in the same frame (e.g. 10 sensors × 5 attributes) produce at most one `pulsateNode()` call per node.

```
handleGraphActivity (many per frame)
    ↓  schedulePulsation(nodeId)
pendingPulsations: Set<string>  (deduplicates)
    ↓  requestAnimationFrame (one per frame)
pulsateNode(nodeId) × unique nodes only
```

### Sigma refresh throttling

`scheduleRefresh()` gates all `sigma.refresh()` calls to one per animation frame via a `refreshScheduled` boolean + `requestAnimationFrame`. All visual mode updates, pulsations, and glow loops call `scheduleRefresh()` rather than refreshing directly.

### Sensor→attribute index

`sensorAttrIndex: Map<sensor_id, string[]>` maps each sensor to its attribute node IDs. Maintained on node addition and deletion. Used by `handleAttentionChanged()` to update attribute appearances in O(k) (k = attr count) instead of O(N) `forEachNode`.

### Heatmap decay timers

`activityDecayTimers: Map<nodeId, timer>` holds one timer per node. New activity for the same node cancels the old timer and starts a fresh one. This bounds the total timer count to the number of active nodes rather than the number of events received.

### Glow loop

A single shared RAF loop (`startGlowLoop` / `stopGlowLoop`) drives all active glow halos on the canvas overlay. It stops automatically when `activeGlows` is empty, so there is no idle rendering cost when no glows are active.

## Canvas Overlays

Sigma renders nodes and edges via WebGL. A separate `glowCanvas` (2D Canvas) sits on top for effects that need per-pixel blending:

- **Glow halos** — radial gradient circles around nodes on connect/disconnect/data events
- **Heartbeat pass 1** — batched halo for all edges (single `stroke()` call, organic artery feel)
- **Heartbeat pass 2** — per-edge core stroke + traveling bolus gradient
- **Heartbeat pass 3** — node glow rings synchronized to ECG phase

The canvas is cleared each frame with `clearRect` (no alpha-blend fade accumulation).

## Internals: Key State Variables

| Variable | Type | Purpose |
|----------|------|---------|
| `graph` | `Graphology.Graph` | The graph data model |
| `sigma` | `Sigma` | The WebGL renderer |
| `fa2Worker` | `FA2Layout \| null` | Async layout worker (topology mode) |
| `layoutMode` | `LayoutMode` | Current layout algorithm |
| `visualMode` | `VisualMode` | Current visual overlay |
| `currentSeason` | `Season` | Active color theme |
| `lodAttributesVisible` | `boolean` | Whether attribute nodes are rendered |
| `highlightedNodes` | `Set<string>` | Nodes hovered/selected (dims others) |
| `activeGlows` | `Map<nodeId, GlowEntry>` | Ongoing glow animations |
| `activePulsations` | `Map<nodeId, PulsationEntry>` | Ongoing node pulsations |
| `sensorAttrIndex` | `Map<sensor_id, string[]>` | sensor→attribute node lookup |
| `pendingPulsations` | `Set<string>` | Nodes awaiting next-frame pulsation |

## Adding a New Layout Mode

1. Add the new string literal to the `LayoutMode` type union (top of script)
2. Add it to the `layoutModes` array (controls sidebar order and auto-cycle)
3. Create a `layout<Name>()` function following the pattern of existing layouts:
   - Collect nodes by type with a single `graph.forEachNode()` pass
   - Set `x`/`y` attributes directly on each node
   - At the end, pull unpositioned nodes to center to avoid outliers
4. Add a `case "<name>": layout<Name>(); break;` inside `applyLayout()`
5. Add a button in the sidebar section (search for `mode-btn` in the template)

## Adding a New Visual Mode

1. Add to the `VisualMode` type union
2. Add to `visualModes` array
3. Create `start<Name>()` and `stop<Name>()` functions
4. Add `stop<Name>()` call in `cleanupVisual()`
5. Add `start<Name>()` call in `applyViewMode()`
6. Handle `handleGraphActivity` / `handleCompositeMeasurement` events in the new mode
7. Add a sidebar button

## 3D Graph

`assets/svelte/Composite3DGraph.svelte` provides a Three.js / WebGL alternative at `/lobby/graph3d`. It shares the same data pipeline (same CustomEvents from `CompositeMeasurementHandler`) but uses `THREE.js` force-directed 3D layout with spherical node placement.

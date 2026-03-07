# Sensocto LiveView Architecture

> Document for the Phoenix LiveView team. Overview of what we're building, how we use LiveView, and where we encounter friction.

## What is Sensocto?

Sensocto is a **real-time biometric sensor platform**. It connects wearable sensors (heart rate, ECG, IMU, eye tracking, breathing, etc.) to a web dashboard where multiple users can collaboratively view, analyze, and annotate live sensor data.

**Key characteristics:**
- **High-frequency data**: Sensors stream at 10-200Hz (ECG at 125-250Hz)
- **Many concurrent sensors**: 10-200+ sensors per session, each with multiple attributes
- **Collaborative**: Multiple users view the same data simultaneously (guided sessions, presence, shared media/whiteboard)
- **Multi-modal visualization**: Composite views (ECG waveforms, heart rate grids, 3D skeleton, gaze tracking, IMU orientation), force-directed graphs, 3D topology, maps, plus media players, whiteboards
- **Adaptive quality**: System degrades gracefully under load (quality levels, backpressure)
- **Audio/MIDI output**: Sensor data drives real-time MIDI output and audio synthesis (biometric sonification)
- **Bio-inspired backend**: Server-side modules for cross-sensor sync computation (breathing synchrony, HRV coherence), novelty detection, and homeostatic resource tuning
- **Multi-platform**: Web, mobile API, native iOS (LiveView Native / SwiftUI), Web Bluetooth for direct sensor connections
- **i18n**: Multi-language support via Gettext (English, German, more planned)

## Codebase Scale

| Metric | Count |
|--------|-------|
| LiveView modules | 54 files |
| LiveView code | ~28,000 lines |
| Svelte components | 44 files (~24,000 lines) |
| JS hooks | ~30 hooks |
| Largest LiveView (room_show_live.ex) | 3,973 lines |
| Second largest (lobby_live.ex) | 3,769 lines |
| Largest template (lobby_live.html.heex) | 2,446 lines |
| PubSub topics | ~20 distinct topic patterns |
| Bio-inspired backend modules | 8 (sync, novelty, homeostatic, etc.) |

## Architecture Overview

```mermaid
%% title: Sensor Data Flow
graph LR
    S[SimpleSensor GenServer] -->|PubSub: data:attention:high/med/low| R[Lenses.Router GenServer]
    R -->|ETS direct write| P[PriorityLens ETS tables]
    P -->|flush timer 64-500ms| PB[PubSub: lens:priority:socket_id]
    PB -->|handle_info| LV[LobbyLive LiveView]
    LV -->|push_event| H[JS Hook: CompositeMeasurementHandler]
    H -->|window CustomEvent| SV[Svelte Component]
```

### The Lens System

We built a custom "lens" routing layer between sensors and LiveViews to avoid O(N*M) PubSub subscriptions:

1. **Router** (`Lenses.Router`): Single GenServer subscribes to 3 attention-sharded PubSub topics, forwards to registered lenses
2. **PriorityLens** (`Lenses.PriorityLens`): Per-socket ETS buffers. Flushes batched data at adaptive intervals (64ms at `:high` quality, 500ms at `:minimal`). The hot data path bypasses the GenServer entirely (ETS tables are `:public`, writes happen in the Router's process).
3. **Attention Tracker**: Backend process that classifies sensors into attention levels (high/medium/low/none) based on which LiveViews are watching which sensors. Only sensors with viewers broadcast at all.

### Bio-Inspired Backend Modules

Server-side computation that runs alongside the data pipeline and publishes results back via PubSub:

- **SyncComputer**: Computes real-time breathing synchrony and HRV coherence across sensor pairs. Subscribes to individual sensor topics, publishes `{:sync_update, attr_id, value, timestamp}`.
- **NoveltyDetector**: Detects unusual sensor patterns (sudden HR spikes, movement anomalies). Publishes novelty events that the attention system uses for auto-focusing.
- **HomeostaticTuner**: Adjusts system parameters (flush intervals, attention thresholds) based on overall load — inspired by biological homeostasis.
- **CircadianScheduler**: Time-of-day-aware resource allocation.
- **CorrelationTracker**: Tracks cross-sensor correlations in real time.
- **PredictiveLoadBalancer**: Predicts load spikes based on sensor registration patterns.

These modules all communicate with LiveViews via PubSub, adding more `handle_info` clauses to already-large LiveView modules.

### Quality Adaptation / Backpressure

LobbyLive monitors its own mailbox depth and degrades quality when overwhelmed. System load monitoring (CPU, memory, scheduler utilization) feeds proactive thresholds — e.g., when system load is `:elevated`, backpressure thresholds are halved:

```
:high (64ms) → :medium (128ms) → :low (250ms) → :minimal (500ms) → :paused (stop)
```

Recovery is hysteresis-based: multiple consecutive healthy checks required before upgrading. Client-side health reports (JS hook) can trigger immediate downgrades but not upgrades.

## How We Use LiveView

### Session Structure

**Single `live_session`** for the entire app. All routes share one `ash_authentication_live_session` with `on_mount` hooks for auth, path tracking, and locale:

```elixir
ash_authentication_live_session :main_app,
  on_mount: [
    {LiveUserAuth, :live_user_optional},
    {SensoctoWeb.Live.Hooks.TrackVisitedPath, :default},
    {SensoctoWeb.Live.Hooks.SetLocale, :default}
  ] do
    live "/lobby", LobbyLive, :sensors
    live "/lobby/heartrate", LobbyLive, :heartrate
    live "/lobby/ecg", LobbyLive, :ecg
    # ... 18 more lobby sub-routes as live_actions
    live "/rooms/:id", RoomShowLive, :show
    # ... 30+ routes total
  end
```

### Layout-Level Persistent LiveViews

The app layout (`app.html.heex`) embeds several `live_render` calls with `sticky: true`:

```heex
{live_render(@socket, SensoctoWeb.SearchLive, id: "global-search", sticky: true)}
{live_render(@socket, SensoctoWeb.ChatSidebarLive, id: "chat-sidebar-live", sticky: true)}
{live_render(@socket, SensoctoWeb.TabbedFooterLive, id: "tabbed-footer-live", sticky: true)}
{live_render(@socket, SensoctoWeb.SenseLive, id: "bluetooth", sticky: true)}
```

These persist across navigation within the `live_session`. The Bluetooth `SenseLive` manages Web Bluetooth connections (sensors connect via the browser). The chat sidebar and footer persist UI state.

### Component vs Process Tradeoff

We went through two approaches for rendering sensor tiles in the lobby grid:

1. **`live_render` per sensor** (`StatefulSensorLive`): Each sensor tile is its own LiveView process. Pro: isolated state/crash. Con: 200 sensors = 200 processes with separate WebSocket frames. Virtual scrolling becomes expensive (mount/unmount processes).

2. **`live_component` per sensor** (`StatefulSensorComponent`): Single parent process, components are just function calls with state. Pro: way less overhead for virtual scrolling. Con: parent LiveView becomes a bottleneck, all data flows through one process.

We currently use **approach 2** (`@use_sensor_components true` flag) with a `send_update` pattern: the parent LobbyLive receives data from PriorityLens and fans out via `send_update(StatefulSensorComponent, id: "sensor_#{id}", flush: true)`.

### Svelte Integration via LiveSvelte

We use [`live_svelte`](https://github.com/woutdp/live_svelte) to render Svelte 5 components inside LiveView templates. Svelte handles the high-frequency visualization (ECG waveforms, sparklines, 3D graphs, maps) while LiveView handles state management and data delivery.

**How it works:**
- `esbuild-svelte` compiles `.svelte` files
- `live_svelte` generates hooks that mount/update Svelte components
- LiveView pushes data via `push_event` to JS hooks
- Hooks dispatch `window.CustomEvent`s that Svelte components listen to

**Seed data handshake** (race condition solution):
1. LiveView sends `push_event("composite_seed_data", ...)` with historical data
2. JS hook buffers events in `window.__compositeSeedBuffer`
3. Svelte component dispatches `composite-component-ready` CustomEvent when mounted
4. Hook replays buffer to component

### JS Hooks We Maintain

We have ~30 hooks. The most complex ones:

| Hook | What it does | Why it's complex |
|------|-------------|------------------|
| `CompositeMeasurementHandler` | Bridges LiveView push_events to Svelte components | Seed buffering, delta decoding (ECG), multi-component dispatch |
| `VirtualScrollHook` | Infinite scroll for sensor grid | Reports visible range to LiveView, triggers `send_update` for visible components |
| `ClientHealthHook` | Reports frame timing, event processing latency | Feeds backpressure system |
| `MediaPlayerHook` | YouTube playback sync across users | Full state machine (INIT→LOADING→READY→SYNCING→PLAYING), autoplay handling, drift correction |
| `Object3DPlayerHook` | 3D Gaussian splat viewer with camera sync | Camera position polling, user control detection |
| `CallHook` | WebRTC calls via Membrane | Audio/video tracks, speaking detection, quality tiers |
| `MidiOutputHook` | Maps sensor data to MIDI CC/note messages | Real-time biometric sonification, Web MIDI API, configurable mappings |
| `WhiteboardHook` | Collaborative drawing canvas | HTML5 Canvas, stroke sync via PubSub, color picker, undo/redo |
| `LobbyPreferences` | localStorage ↔ LiveView sync | Persists layout, sort, mode preferences |
| `DraggableBallsHook` | Animated presence visualization on sign-in | Physics simulation, presence-synced across users |
| `GaussianSplatViewer` | 3D Gaussian splat rendering | `@mkkellogg/gaussian-splats-3d`, camera sync between users |

### PubSub Usage

Major topic patterns:

| Topic | Publisher | Subscriber | Frequency |
|-------|----------|------------|-----------|
| `data:attention:{level}` | SimpleSensor | Lenses.Router | 10-250Hz per sensor |
| `lens:priority:{socket_id}` | PriorityLens | LobbyLive | 2-16 flushes/sec |
| `presence:all` | Presence | LobbyLive | On join/leave |
| `attention:lobby` | AttentionTracker | LobbyLive | On level changes |
| `room:{id}` | RoomServer | RoomShowLive | On room updates |
| `room:{id}:mode_presence` | Presence | LobbyLive/RoomShowLive | On mode changes |
| `media:{room_id}` | MediaPlayerServer | LiveViews | Playback sync |
| `guidance:{session_id}` | SessionServer | LobbyLive | Guide commands |
| `whiteboard:{room_id}` | WhiteboardServer | LiveViews | Drawing strokes |
| `sync:updates` | SyncComputer | LobbyLive | Breathing/HRV sync values |
| `poll:{poll_id}` | Vote module | PollComponent | Vote updates |
| `call:{room_id}` | CallServer | LiveViews | WebRTC call events |
| `object3d:{room_id}` | Object3DServer | LiveViews | 3D camera sync |
| `system:load` | SystemLoadMonitor | SimpleSensor, LiveViews | Load level changes |

### Delta Encoding for High-Frequency Data

ECG data at 125-250Hz produces massive payloads. We delta-encode ECG samples server-side and decode client-side:

```elixir
# Server: push delta-encoded ECG batch
push_event(socket, "composite_measurement_encoded", %{
  sensor_id: sensor_id,
  attribute_id: "ecg",
  encoded: %{type: :delta, data: delta_encoded_samples}
})
```

```javascript
// Client: CompositeMeasurementHandler decodes
this.handleEvent("composite_measurement_encoded", (event) => {
  if (isDeltaEncoded(event.encoded)) {
    const samples = decodeDelta(event.encoded.data);
    // dispatch individual samples to Svelte ECG waveform
  }
});
```

This is a workaround for `push_event` only supporting JSON. Binary transfer would eliminate the encoding overhead.

### Graph and Topology Views

The lobby includes force-directed graph (`/lobby/graph`) and 3D graph (`/lobby/graph3d`) views that visualize sensor relationships as a network. These use the `graphology` and `3d-force-graph` JS libraries, driven by LiveView assigns for node/edge data and `push_event` for real-time activity pulses:

- Nodes represent sensors, edges represent correlations (from `CorrelationTracker`)
- Node pulsation reflects real-time data activity (heartbeat frequency, movement intensity)
- Graph layout runs entirely client-side; LiveView only pushes data changes
- User interactions (hover, click, zoom) push events back to LiveView for attention tracking

### Guided Sessions

A "guide" user can lead followers through the lobby in real time — changing lenses, focusing sensors, adjusting quality. This uses a `SessionServer` GenServer that coordinates via PubSub:

- Guide actions broadcast to `"guidance:{session_id}"` topic
- Followers' LobbyLive receives and applies changes (lens navigation via `push_patch`, quality changes, sensor focus)
- Followers can "break away" (stop following) and "drift back" (re-sync with guide)
- Session invite codes shared via chat or QR code

This adds ~15 `handle_info` and ~10 `handle_event` clauses to LobbyLive — a good example of why the module is so large.

### Polls

Live polls (`/polls`) allow real-time voting during sessions. `PollComponent` subscribes to `"poll:{poll_id}"` for instant vote count updates. Polls are embedded as a panel in the lobby footer.

## Friction Points, Feedback & Next Steps

> After sharing this document with the LiveView team, we received feedback that resolves several friction points. This section documents both the original problems and the solutions.

### 1. LiveView Process as Bottleneck for High-Frequency Data

**The core tension**: LiveView's process model is great for most UI, but our lobby handles 100+ sensors streaming at 10-250Hz. All data must flow through one LiveView process's mailbox.

**What we built to work around it:**
- Custom ETS-based buffering layer (PriorityLens) that batches data before hitting the LiveView
- Mailbox depth monitoring with automatic quality degradation
- Drain-all pattern: when backpressure hits, we drain ALL pending `{:lens_batch, _}` messages from the mailbox in one `handle_info`
- Client-side health reporting for adaptive quality

**Resolution: Phoenix Channels on the same WebSocket** (see [Phoenix.LiveView.Socket docs](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.Socket.html))

Phoenix Channels and LiveViews can share the same WebSocket connection. By moving the high-frequency sensor data to a dedicated Channel:
- Data bypasses the LiveView process entirely — no mailbox bottleneck
- We can batch events arbitrarily on the Channel side
- Binary payloads are supported natively (no JSON serialization overhead)
- LiveView's diffing is not involved at all — it skips diffing when assigns haven't changed

**TODO**: Migrate the hot data path from `push_event` to a dedicated `SensorDataChannel` that shares the LiveView WebSocket. The PriorityLens can push directly to the channel process.

### 2. `push_event` as Main Data Path — Solved by Channels

Same solution as #1. With a dedicated Channel for sensor data:
- Events can be batched into single WebSocket frames
- Binary payloads eliminate JSON serialization overhead for numeric arrays (ECG samples)
- The LiveView process only handles UI state changes (lens switches, settings, presence)

### 3. Virtual Scrolling with LiveComponents

We show 100-200 sensor tiles in a scrollable grid. Only ~20-40 are visible at once. We implement virtual scrolling via a JS hook that reports the visible range, and the parent only `send_update`s visible components.

**Friction:**
- LiveComponents don't have a "sleep/wake" concept. Invisible components still exist in memory with full state.
- When scrolling fast, there's a visible blank flash because `send_update` for newly-visible components takes a round trip.

**Resolution: Channel-based visibility filtering**

With a dedicated Channel for sensor data, the JS client tells the Channel which sensor tiles are currently visible. The Channel then only pushes data for visible sensors, completely skipping invisible ones. This eliminates the need for LiveView to manage visibility at all.

### 4. Giant LiveView Modules — Solved by `attach_hook`

`room_show_live.ex` is 3,973 lines. `lobby_live.ex` is 3,769 lines. These handle: sensor data routing, media player sync, 3D viewer sync, whiteboard sync, WebRTC calls, guided sessions, presence, polls, MIDI output, graph views, virtual scrolling, quality adaptation, bio-sync updates, and more.

**Resolution: [`attach_hook/4`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#attach_hook/4)**

LiveView's `attach_hook/4` allows composing `handle_info`, `handle_event`, and `handle_params` handlers from separate modules. This is exactly what we need:

```elixir
# In LobbyLive.mount:
socket
|> attach_hook(:media_player, :handle_event, &MediaPlayerHandlers.handle_event/3)
|> attach_hook(:media_player, :handle_info, &MediaPlayerHandlers.handle_info/3)
|> attach_hook(:whiteboard, :handle_event, &WhiteboardHandlers.handle_event/3)
|> attach_hook(:whiteboard, :handle_info, &WhiteboardHandlers.handle_info/3)
|> attach_hook(:guided_session, :handle_event, &GuidedSessionHandlers.handle_event/3)
|> attach_hook(:guided_session, :handle_info, &GuidedSessionHandlers.handle_info/3)
```

Each handler module has a catch-all `def handle_event(_event, _params, socket), do: {:cont, socket}` to pass unhandled events through. This lets us split 3700-line modules into focused, testable modules.

**TODO**: Refactor LobbyLive and RoomShowLive to use `attach_hook` for media player, whiteboard, guided session, call, and object3D handlers.

### 5. Seed Data / Historical Data on Navigation — Solved by `start_async`

When a user navigates to a composite view (e.g., `/lobby/ecg`), we need to send historical data (last 30 seconds of ECG samples) so the chart isn't empty.

**Previous approach:** Synchronous fetch in `handle_params`, blocking the response.

**Resolution: [`start_async/4`](https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#start_async/4)**

```elixir
def handle_params(_params, _uri, socket) do
  # Don't block — start async fetch
  socket = start_async(socket, :seed_data, fn ->
    fetch_historical_data(socket.assigns.live_action)
  end)
  {:noreply, socket}
end

def handle_async(:seed_data, {:ok, data}, socket) do
  # Push seed data to client when ready
  socket = push_seed_events(socket, data)
  {:noreply, socket}
end
```

This also pairs well with the Channel approach: seed data could be pushed through the Channel, and the Svelte buffering handshake might become unnecessary if data arrives after the component mounts.

### 6. send_update for High-Frequency Component Updates

We use `send_update(StatefulSensorComponent, id: "sensor_#{id}", flush: true)` to trigger measurement flushes in components. With 40 visible sensors, that's 40 `send_update` calls every 100ms.

**Friction:**
- `send_update` is not cheap — it involves message passing and component re-render
- No way to batch `send_update` calls ("update these 40 components, then diff once")
- Components receiving `send_update` with only a `:flush` flag still go through the full update lifecycle

**Partially resolved by Channel approach**: If sensor data flows through a Channel directly to JS, components don't need `send_update` for measurements at all — only for UI state changes (favorites, attention level, etc.).

### 7. Svelte ↔ LiveView Boundary — Solved by Channels

**Previous friction**: LiveView → JS Hook → `window.CustomEvent` → Svelte component (3 hops), JSON-only payloads.

**Resolution**: With a Channel for sensor data:
- Channel → JS callback → Svelte component (2 hops, no LiveView process involved)
- Binary payloads supported (Channel can send raw binary frames)
- No `window.dispatchEvent` / global buffer hacks needed
- The Svelte component can subscribe directly to Channel events

### 8. Process Lifecycle Mismatch with Browser State

The LiveView process can restart (deploy, crash, reconnect) but the browser holds state (Bluetooth connections, IndexedDB data, media playback position, WebRTC calls). On reconnect:

- Svelte components are destroyed and recreated (losing internal state like chart zoom, scroll position)
- JS hooks' `mounted()` fires again, but the old state in closures is gone
- We need to re-seed historical data, re-sync media playback, re-establish WebRTC

**Partially resolved by Channels**: Channel connections can be managed independently of LiveView lifecycle. A Channel can persist across LiveView reconnects if managed separately on the JS side. This means sensor data flow doesn't interrupt on LiveView reconnect.

**Current mitigation for remaining issues:** Extensive `localStorage` persistence and the `LobbyPreferences` hook that restores state on mount.

### 9. No Streams for Our Use Case — Resolved by Channel approach

**Previous friction**: Streams are designed for append/prepend lists, not grids of independently-updating components.

**Resolution**: With sensor data flowing through a Channel, this is no longer a LiveView concern. The Channel pushes data directly to JS, which updates Svelte components. LiveView Streams aren't needed because the data path bypasses LiveView entirely.

### 10. Template Size & Conditional Rendering — Solved by Function Components

`lobby_live.html.heex` is 2,446 lines with large `:if` blocks for each lens view.

**Resolution: Function components and LiveComponents for subtree isolation**

LiveView already optimizes conditional rendering: when a template is split into function components, subtrees whose assigns haven't changed are skipped during diffing. For even stronger isolation, LiveComponents do their own independent diff tracking.

**Done**: Split `lobby_live.html.heex` into function components in `LensComponents`:
- Generic `composite_lens/1` covers all 9 composite views (heartrate, IMU, location, ECG, battery, skeleton, respiration, HRV, gaze)
- `midi_panel/1` extracts the ~860-line MIDI/GrooveEngine panel (pure static HTML)
- Template reduced from 2,415 → 1,513 lines (−37%)
- LiveView now skips diffing inactive lens subtrees when assigns haven't changed

## Tech Stack Summary

- **Phoenix**: 1.8.3
- **LiveView**: 1.1.19
- **Elixir**: 1.19.4, OTP 27
- **Frontend**: Svelte 5 via `live_svelte`, esbuild, Tailwind + DaisyUI
- **Key JS deps**: chart.js, three.js, maplibre-gl, membrane-webrtc-js, gaussian-splats-3d, graphology, 3d-force-graph, Web MIDI API, Tone.js (audio synthesis)
- **Auth**: `ash_authentication` (email/password, magic link, guest tokens)
- **Data**: Ash Framework + PostgreSQL
- **Real-time**: Phoenix PubSub, Presence, custom ETS-based lens system
- **WebRTC**: Membrane Framework for video/audio calls
- **Sensor connectivity**: Web Bluetooth (browser-side), simulator connectors (server-side), mobile API
- **Bio computation**: Custom sync/novelty/homeostatic modules (~8 GenServers)

## Migration Plan: Channel-Based Data Path

Based on the feedback, the biggest architectural improvement is moving the high-frequency sensor data path from LiveView `push_event` to a dedicated Phoenix Channel sharing the same WebSocket. This resolves friction points 1, 2, 3, 7, and 9.

### Phase 1: Channel Setup
- Create `SensorDataChannel` that joins with the user's socket
- Share the WebSocket via `use Phoenix.LiveView.Socket` in a custom UserSocket
- Channel receives sensor IDs to subscribe to on join

### Phase 2: Data Path Migration
- PriorityLens pushes batched data to the Channel process instead of PubSub → LiveView
- Channel sends binary-encoded sensor data frames to JS
- JS dispatches to Svelte components directly (no `window.dispatchEvent` hacks)

### Phase 3: LiveView Cleanup
- Remove mailbox backpressure monitoring from LobbyLive (Channel handles its own)
- Remove `push_event`-based measurement delivery
- LiveView only handles: UI state, navigation, presence, settings
- Use `attach_hook` to split remaining handlers into focused modules
- Split templates into function components per lens view

### Phase 4: Async Historical Data
- Use `start_async` for historical data fetching on lens navigation
- Push seed data through Channel (or `handle_async` → `push_event` for small payloads)

## Summary

We've built a complex real-time biometric platform on LiveView. After discussing our friction points with the LiveView team, we learned that most of our issues have existing solutions:

1. **High-frequency data bottleneck** → Phoenix Channels on the same WebSocket bypass the LiveView process entirely
2. **Module composition** → `attach_hook/4` lets us split 3700-line modules into focused handler modules
3. **Async data loading** → `start_async/4` prevents blocking on historical data fetches
4. **Template optimization** → Function components and LiveComponents already provide subtree diff isolation

The key insight is that **LiveView and Channels are complementary**: LiveView handles UI state and DOM management, while Channels handle high-frequency data streaming. Both share the same WebSocket connection, giving us the best of both worlds.

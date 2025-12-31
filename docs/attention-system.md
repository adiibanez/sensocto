# Attention Ecosystem

The Sensocto attention system provides intelligent back-pressure control for sensor data streams, reducing resource usage when data isn't being actively viewed.

## Overview

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│   Browser/App   │────▶│  AttentionTracker │────▶│   Connectors    │
│  (JS Hooks)     │     │   (GenServer)     │     │  (Channels)     │
└─────────────────┘     └──────────────────┘     └─────────────────┘
        │                        │                        │
   viewport/focus          ETS cache              backpressure_config
   battery state          PubSub broadcast        batch_window/size
```

## Attention Levels

| Level | Trigger | Batch Window | Batch Size | Use Case |
|-------|---------|--------------|------------|----------|
| `:high` | Focus/click OR hover on attribute | 100-500ms | 1 | User actively interacting |
| `:medium` | Attribute in viewport | 500-2000ms | 5 | User viewing sensor |
| `:low` | Sensor connected, not viewed | 2000-10000ms | 10 | Background monitoring |
| `:none` | No active connections | 5000-30000ms | 20 | Idle/disconnected |

## Components

### 1. AttentionTracker (`lib/sensocto/otp/attention_tracker.ex`)

Central GenServer that tracks attention state across all users and sensors.

**Features:**
- **Triple ETS caching** for fast concurrent reads (no GenServer bottleneck):
  - `:attention_levels_cache` - Per-attribute attention levels
  - `:sensor_attention_cache` - Sensor-level attention (highest across attributes)
  - `:attention_config_cache` - Static configuration
- PubSub broadcasts on attention changes
- Hover tracking with 2-second boost duration (prevents flicker)
- Sensor pinning for guaranteed high-frequency updates
- Battery/energy state tracking with source metadata
- Automatic cleanup of stale records (60s threshold)

**Client API:**

```elixir
# View tracking
AttentionTracker.register_view(sensor_id, attribute_id, user_id)
AttentionTracker.unregister_view(sensor_id, attribute_id, user_id)

# Hover tracking (triggers :high attention)
AttentionTracker.register_hover(sensor_id, attribute_id, user_id)
AttentionTracker.unregister_hover(sensor_id, attribute_id, user_id)

# Focus tracking (click/focus, highest priority)
AttentionTracker.register_focus(sensor_id, attribute_id, user_id)
AttentionTracker.unregister_focus(sensor_id, attribute_id, user_id)

# Sensor pinning (guarantees :high attention)
AttentionTracker.pin_sensor(sensor_id, user_id)
AttentionTracker.unpin_sensor(sensor_id, user_id)

# Battery/energy state
AttentionTracker.report_battery_state(user_id, :low,
  source: :web_api,
  level: 25,
  charging: false
)

# Query functions (ETS-backed, O(1) lookups)
AttentionTracker.get_attention_level(sensor_id, attribute_id)
AttentionTracker.get_sensor_attention_level(sensor_id)
AttentionTracker.calculate_batch_window(base_window, sensor_id, attribute_id)
```

### 2. UI Tracking Hook (`assets/js/hooks/attention_tracker.js`)

Client-side attention detection for web browsers.

**Features:**
- `IntersectionObserver` for viewport visibility (10% threshold, 50px margin)
- **Instant hover detection** - hover triggers immediately on mouse enter
- **Hover boost duration** (2 seconds) - prevents flicker when moving between elements
- Click/focus tracking for high attention
- Page visibility API integration (hidden/visible tabs)
- Battery Status API integration
- **Adaptive debouncing** (50-500ms) based on system responsiveness
- Latency tracking to adjust debounce dynamically

**Debounce Settings:**

| Constant | Value | Purpose |
|----------|-------|---------|
| `HOVER_DEBOUNCE_MIN_MS` | 50ms | Fast response on responsive systems |
| `HOVER_DEBOUNCE_MAX_MS` | 500ms | Throttle on slow/loaded systems |
| `HOVER_BOOST_DURATION_MS` | 2000ms | Keep `:high` attention after mouse leaves |
| `BATTERY_LOW_THRESHOLD` | 30% | Trigger `:low` battery state |
| `BATTERY_CRITICAL_THRESHOLD` | 15% | Trigger `:critical` battery state |

**Usage in templates:**

```heex
<div id="sensor-container" phx-hook="AttentionTracker">
  <div data-sensor_id={@sensor_id} data-attribute_id="temperature">
    <!-- attribute content -->
  </div>
</div>
```

### 3. Connector Backpressure (`lib/sensocto_web/channels/sensor_data_channel.ex`)

Pushes backpressure configuration to external connectors via Phoenix Channels.

**Protocol:**

```javascript
// Connector receives backpressure_config message
channel.on("backpressure_config", (config) => {
  // config = {
  //   attention_level: "medium",
  //   recommended_batch_window: 500,
  //   recommended_batch_size: 5,
  //   timestamp: 1703856000000
  // }
  this.batchWindow = config.recommended_batch_window;
  this.batchSize = config.recommended_batch_size;
});
```

### 4. Dynamic Batch Window (`lib/sensocto/simulator/attribute_server.ex`)

Simulator attributes automatically adjust their batch windows based on attention.

```elixir
# Subscribes to attention changes
Phoenix.PubSub.subscribe(Sensocto.PubSub, "attention:#{sensor_id}:#{attribute_id}")

# Recalculates batch window on attention change
handle_info({:attention_changed, %{level: new_level}}, state) ->
  new_batch_window = AttentionTracker.calculate_batch_window(
    state.base_batch_window,
    sensor_id,
    attribute_id
  )
```

## Battery/Energy Awareness

The system supports battery state from multiple sources to reduce updates on low-power devices.

### Battery States

| State | Trigger | Effect |
|-------|---------|--------|
| `:normal` | Charging OR battery >= 30% | No restrictions |
| `:low` | Battery 15-30%, not charging | Cap attention at `:medium` |
| `:critical` | Battery < 15%, not charging | Cap attention at `:low` |

### Supported Sources

| Source | Use Case |
|--------|----------|
| `:web_api` | Browser Battery Status API |
| `:native_ios` | iOS app via LiveView Native |
| `:native_android` | Android app via LiveView Native |
| `:external_api` | Third-party APIs (carbon intensity, solar forecast) |

### API Examples

```elixir
# Web browser
AttentionTracker.report_battery_state(user_id, :low,
  source: :web_api,
  level: 25,
  charging: false
)

# Native iOS app
AttentionTracker.report_battery_state(user_id, :critical,
  source: :native_ios,
  level: 8,
  power_source: :battery
)

# External energy API (e.g., high carbon grid)
AttentionTracker.report_battery_state(user_id, :low,
  source: :external_api,
  reason: :high_carbon_intensity
)

# Query with metadata
{state, metadata} = AttentionTracker.get_battery_state(user_id)
# => {:low, %{source: :web_api, level: 25, charging: false, reported_at: ~U[...]}}

# Dashboard: all battery states
AttentionTracker.get_all_battery_states()
```

## PubSub Topics

| Topic | Message | When |
|-------|---------|------|
| `attention:#{sensor_id}` | `{:attention_changed, %{sensor_id, level}}` | Sensor-level attention changes |
| `attention:#{sensor_id}:#{attr_id}` | `{:attention_changed, %{sensor_id, attribute_id, level}}` | Attribute-level attention changes |

## LiveView Integration

The `StatefulSensorLive` handles all attention events from JS hooks:

```elixir
# Event handlers
handle_event("view_enter", ...)   # Attribute entered viewport
handle_event("view_leave", ...)   # Attribute left viewport
handle_event("hover_enter", ...)  # Mouse entered attribute
handle_event("hover_leave", ...)  # Mouse left attribute
handle_event("focus", ...)        # User clicked/focused attribute
handle_event("unfocus", ...)      # User unfocused
handle_event("pin_sensor", ...)   # Pin for high-frequency
handle_event("unpin_sensor", ...) # Unpin
handle_event("page_hidden", ...)  # Tab hidden
handle_event("page_visible", ...) # Tab visible
handle_event("battery_state_changed", ...) # Battery level changed
```

## Configuration

Batch window multipliers are configured in `AttentionTracker`:

```elixir
@attention_config %{
  high:   %{window_multiplier: 0.2, min_window: 100,  max_window: 500},
  medium: %{window_multiplier: 1.0, min_window: 500,  max_window: 2000},
  low:    %{window_multiplier: 4.0, min_window: 2000, max_window: 10000},
  none:   %{window_multiplier: 10.0, min_window: 5000, max_window: 30000}
}
```

## Architecture

### Data Flow

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                              ATTENTION FLOW                                  │
├──────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌─────────────┐    pushEvent()    ┌─────────────────────┐                  │
│  │   Browser   │ ─────────────────▶│  StatefulSensor     │                  │
│  │  JS Hooks   │                   │  LiveView           │                  │
│  │             │                   │                     │                  │
│  │ • viewport  │                   │ handle_event/3:     │                  │
│  │ • focus     │                   │ • view_enter/leave  │                  │
│  │ • battery   │                   │ • focus/unfocus     │                  │
│  └─────────────┘                   │ • battery_changed   │                  │
│                                    └─────────┬───────────┘                  │
│                                              │                              │
│                                              ▼                              │
│                                    ┌─────────────────────┐                  │
│                                    │  AttentionTracker   │                  │
│                                    │  (GenServer + ETS)  │                  │
│                                    │                     │                  │
│                                    │ • attention_state   │                  │
│                                    │ • pinned_sensors    │                  │
│                                    │ • battery_states    │                  │
│                                    └─────────┬───────────┘                  │
│                                              │                              │
│                          PubSub broadcast    │                              │
│                     ┌────────────────────────┼────────────────────────┐     │
│                     │                        │                        │     │
│                     ▼                        ▼                        ▼     │
│           ┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐ │
│           │ AttributeServer │    │ SensorDataChannel│    │ LiveView UI     │ │
│           │ (Simulator)     │    │ (Connectors)    │    │ (attention_badge│ │
│           │                 │    │                 │    │  display)       │ │
│           │ adjusts batch   │    │ pushes          │    │                 │ │
│           │ window timing   │    │ backpressure_   │    │                 │ │
│           │                 │    │ config          │    │                 │ │
│           └─────────────────┘    └─────────────────┘    └─────────────────┘ │
│                                                                              │
└──────────────────────────────────────────────────────────────────────────────┘
```

### Battery State Modifier

Battery state acts as a modifier that caps the maximum attention level:

```
Raw Attention Level → Battery Modifier → Effective Attention Level

Examples:
  :high   + :normal   = :high     (no cap)
  :high   + :low      = :medium   (capped)
  :high   + :critical = :low      (heavily capped)
  :medium + :critical = :low      (capped)
  :low    + :critical = :low      (already at cap)
```

### Multi-User Aggregation

When multiple users view the same sensor, the **highest** attention level wins:

```
User A: viewing (medium) ─┐
User B: focused (high)   ─┼──▶ Sensor attention = :high
User C: not viewing      ─┘
```

But battery state uses the **worst** (most restrictive) state among viewers:

```
User A: battery normal ─┐
User B: battery low    ─┼──▶ Effective cap = :low (most restrictive)
User C: battery normal ─┘
```

## Roadmap

See `.claude/plans/snazzy-herding-octopus.md` for the full roadmap including:

- **P1**: Priority queue for sensors, metrics dashboard, AI/alarm hooks
- **P2**: Scroll-aware tracking, predictive pre-warming
- **P3**: Distributed attention (gossip protocol), energy scheduler, self-tuning

## Performance Optimizations

### ETS-Based Lookups

All attention queries use ETS tables with `read_concurrency: true`:

```elixir
# O(1) lookups, no GenServer call required
AttentionTracker.get_attention_level(sensor_id, attribute_id)
AttentionTracker.get_sensor_attention_level(sensor_id)
```

This prevents GenServer bottlenecks during LiveView child mount synchronization.

### Async Write Pattern

All state modifications use `GenServer.cast` (fire-and-forget):

```elixir
# Non-blocking - returns immediately
AttentionTracker.register_hover(sensor_id, attribute_id, user_id)
```

Users experience no latency from attention tracking operations.

### LiveView Mount Safety

To prevent child LiveView mount timeouts (5-second sync limit):

1. **Parent LiveView** (`IndexLive`): Defers expensive operations via `send(self(), :refresh_sensors)` instead of blocking in `handle_info`

2. **Child LiveView** (`StatefulSensorLive`): Uses Task with 1-second timeout for sensor state fetch, falling back to session-cached data

3. **Attention queries**: Now use ETS directly instead of GenServer calls

### Adaptive Debouncing (Client-Side)

The JS hook tracks event latencies and adjusts debounce timing:

```javascript
// Scales between 50ms (responsive) and 500ms (loaded)
const avgLatency = eventLatencies.reduce((a, b) => a + b, 0) / eventLatencies.length;
const debounce = Math.min(500, Math.max(50, avgLatency * 2));
```

## Scalability

See `docs/scalability.md` for detailed analysis of multi-user scalability characteristics and recommendations for high-scale deployments.

## Files

| File | Purpose |
|------|---------|
| `lib/sensocto/otp/attention_tracker.ex` | Core GenServer, ETS caching, battery tracking |
| `assets/js/hooks/attention_tracker.js` | Browser attention detection, Battery API |
| `lib/sensocto_web/channels/sensor_data_channel.ex` | Backpressure protocol for connectors |
| `lib/sensocto_web/live/stateful_sensor_live.ex` | LiveView event handlers |
| `lib/sensocto_web/live/index_live.ex` | Parent LiveView with async sensor refresh |
| `lib/sensocto/simulator/attribute_server.ex` | Dynamic batch window adjustment |
| `docs/scalability.md` | Multi-user scalability guide |

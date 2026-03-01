# Migration Plan: StatefulSensorLive → StatefulSensorComponent

**Status: PLANNED** (not yet started)

## Executive Summary

**Problem**: The lobby experiences full page reloads when scrolling, especially on Fly.dev. Root cause: `live_render` creates separate Erlang processes for each sensor tile. Virtual scrolling causes rapid process creation/destruction, overwhelming the server.

**Solution**: Migrate `StatefulSensorLive` (LiveView) to `StatefulSensorComponent` (LiveComponent). LiveComponents run in the parent's process, eliminating inter-process overhead.

---

## Current Architecture vs. Target

```
CURRENT (live_render)                    TARGET (live_component)
┌─────────────────────────┐              ┌─────────────────────────┐
│      LobbyLive          │              │      LobbyLive          │
│   (1 Erlang process)    │              │   (1 Erlang process)    │
└─────────────────────────┘              │                         │
         │                               │  ┌─────────────────┐    │
         │ spawns                        │  │SensorComponent 1│    │
         ▼                               │  └─────────────────┘    │
┌─────────────────────────┐              │  ┌─────────────────┐    │
│  StatefulSensorLive 1   │ ◄── 4 subs   │  │SensorComponent 2│    │
│  (separate process)     │              │  └─────────────────┘    │
└─────────────────────────┘              │  ┌─────────────────┐    │
┌─────────────────────────┐              │  │SensorComponent N│    │
│  StatefulSensorLive 2   │ ◄── 4 subs   │  └─────────────────┘    │
│  (separate process)     │              │                         │
└─────────────────────────┘              └─────────────────────────┘
         ...                                   (all in 1 process)
┌─────────────────────────┐
│  StatefulSensorLive N   │ ◄── 4 subs
│  (separate process)     │
└─────────────────────────┘

With 72 visible sensors:
- CURRENT: 73 processes, 288 PubSub subscriptions
- TARGET: 1 process, ~5 PubSub subscriptions
```

---

## Risk Analysis

### HIGH RISK

| Risk | Impact | Mitigation |
|------|--------|------------|
| **PubSub subscriptions must move to parent** | Data flow architecture changes. Parent must subscribe to all sensor topics and route to components. | Design centralized subscription manager in LobbyLive. Use `send_update/3` to push data to components. |
| **Measurement throttling logic** | Per-sensor throttle buffers (`pending_measurements`) run independently. Must be maintained per-component. | Keep throttle buffer per component. Use `handle_info` callback via parent to trigger flushes. |
| **AttentionTracker integration** | Heavy coupling with hooks, ETS lookups, and OTP calls. Events flow through component. | Keep hook on container div. Events will route through parent to component via `handle_event`. |
| **Process.send_after for flush timer** | LiveViews can self-schedule. Components cannot directly receive messages. | Parent schedules global flush timer. Or use `handle_async` with periodic task. |

### MEDIUM RISK

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Modal state isolation** | Map and detail modals per-sensor must not interfere. | Use component-scoped IDs. Only one modal visible at a time (enforced by parent state). |
| **Favorite toggle broadcast** | Components broadcast to parent via PubSub. | Use callback function passed as assign. Or event bubbling via `phx-target`. |
| **send_update to AttributeComponent** | Child components update grandchild components. | Maintain same pattern - `send_update/3` works from LiveComponents too. |
| **Template complexity** | 200+ line template with conditionals. | Extract sub-components for modals, header, attribute grid. |

### LOW RISK

| Risk | Impact | Mitigation |
|------|--------|------------|
| **Latency ping/pong** | Adaptive ping interval calculation per sensor. | Keep ping logic in hook. Hook already handles intervals. |
| **View mode sync** | Global view mode broadcast from parent. | Pass `view_mode` as assign. Simpler than current PubSub approach. |
| **Battery state tracking** | Hook reports battery, component stores state. | Same event flow, just via parent routing. |

---

## Functionality Preservation Checklist

### Message Handlers (handle_info → update or parent routing)

| Current Handler | Migration Strategy |
|-----------------|-------------------|
| `{:measurement, ...}` | Parent receives, calls `send_update(SensorComponent, id: ..., measurement: ...)` |
| `{:measurements_batch, ...}` | Parent receives, calls `send_update` per sensor_id in batch |
| `{:new_state, sensor_id}` | Parent receives, calls `send_update` to re-fetch state |
| `{:attention_changed, ...}` | Parent receives, calls `send_update` with new level |
| `{:global_view_mode_changed, ...}` | Pass `@view_mode` assign directly - no handler needed |
| `:flush_throttled_measurements` | Component schedules via parent callback or uses `handle_async` |
| `:attributes_loaded` | Set in `mount/1` or `update/2` |

### Event Handlers (handle_event stays mostly same)

| Event | Migration Notes |
|-------|-----------------|
| `toggle_highlight` | Direct component state toggle |
| `toggle_view_mode` | Direct component state toggle |
| `toggle_favorite` | Call parent callback or `send(parent_pid, ...)` |
| `show_map_modal` / `close_map_modal` | Component state, ensure isolation |
| `show_detail_modal` / `close_detail_modal` | Component state |
| Attention events (`view_enter`, etc.) | Route via parent to AttentionTracker |
| `pin_sensor` / `unpin_sensor` | Route via parent to AttentionTracker |
| `latency_ping` / `latency_report` | Keep as-is (hook handles timing) |
| `battery_state_changed` | Route via parent to AttentionTracker |
| `request-seed-data` | Fetch and push_event via parent socket |

### State (assigns → component assigns)

All current assigns transfer to component assigns. Key differences:
- `parent_pid` → not needed (component has access to parent socket)
- `pending_measurements` → component state, flushed via scheduled update

---

## Migration Phases

### Phase 0: Quick Mitigation (1 hour) - OPTIONAL
Increase virtual scroll throttling to reduce pressure while proper fix is developed:

```javascript
// assets/js/hooks/virtual_scroll.js
const MIN_UPDATE_INTERVAL_MS = 500;  // Was 250
const MIN_CHANGE_THRESHOLD = 12;     // Was 6
```

### Phase 1: Scaffold Component (2-3 hours)

1. Create `lib/sensocto_web/live/components/stateful_sensor_component.ex`
2. Copy template to `stateful_sensor_component.html.heex`
3. Implement basic `mount/1` and `update/2`
4. No functionality yet - just renders static sensor data

```elixir
defmodule SensoctoWeb.Live.Components.StatefulSensorComponent do
  use SensoctoWeb, :live_component

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> assign_new(:view_mode, fn -> :summary end)
      |> assign_new(:highlighted, fn -> false end)
      # ... other defaults
    {:ok, socket}
  end
end
```

### Phase 2: Parent Subscription Management (3-4 hours)

1. Add centralized sensor subscription in LobbyLive:
   ```elixir
   def handle_info({:measurement, %{sensor_id: sensor_id} = m}, socket) do
     # Forward to component
     send_update(StatefulSensorComponent,
       id: "sensor_#{sensor_id}",
       measurement: m
     )
     {:noreply, socket}
   end
   ```

2. Subscribe to sensor topics in parent:
   ```elixir
   # In LobbyLive mount, for ALL sensors (not just visible)
   Enum.each(all_sensor_ids, fn id ->
     Phoenix.PubSub.subscribe(Sensocto.PubSub, "data:#{id}")
     Phoenix.PubSub.subscribe(Sensocto.PubSub, "signal:#{id}")
   end)
   ```

3. Handle subscription cleanup when sensors disconnect

### Phase 3: Component Event Handlers (2-3 hours)

1. Implement all `handle_event` callbacks in component
2. For events needing parent action (favorites, attention), use:
   ```elixir
   # Option A: Callback function
   def handle_event("toggle_favorite", _, socket) do
     socket.assigns.on_favorite_toggle.(socket.assigns.sensor_id)
     {:noreply, assign(socket, :is_favorite, !socket.assigns.is_favorite)}
   end

   # Option B: Phoenix.LiveView.send_update to parent (not recommended)
   # Option C: phx-target={@myself} with event bubbling
   ```

### Phase 4: Measurement Throttling (2-3 hours)

1. Implement per-component throttle buffer:
   ```elixir
   def update(%{measurement: m} = assigns, socket) do
     buffer = [m | socket.assigns.pending_measurements]
     {:ok, assign(socket, :pending_measurements, buffer)}
   end

   # Parent schedules flush every 100ms
   def handle_info(:flush_all_sensors, socket) do
     for sensor_id <- socket.assigns.visible_sensor_ids do
       send_update(StatefulSensorComponent, id: "sensor_#{sensor_id}", flush: true)
     end
     Process.send_after(self(), :flush_all_sensors, 100)
     {:noreply, socket}
   end
   ```

2. Component handles flush:
   ```elixir
   def update(%{flush: true}, socket) do
     socket = push_measurements_to_client(socket)
     {:ok, assign(socket, :pending_measurements, [])}
   end
   ```

### Phase 5: Attention Tracking Integration (2-3 hours)

1. Hook events continue to fire on container div
2. Parent routes to AttentionTracker:
   ```elixir
   def handle_event("view_enter", %{"sensor_id" => id, "attribute_id" => attr}, socket) do
     AttentionTracker.register_view(id, attr, get_user_id(socket))
     {:noreply, socket}
   end
   ```

3. Attention changes forwarded to components via `send_update`

### Phase 6: Template Extraction (1-2 hours)

1. Extract modal components:
   - `sensor_map_modal.html.heex`
   - `sensor_detail_modal.html.heex`

2. Ensure component IDs are unique per sensor

### Phase 7: Integration & Switch (1-2 hours)

1. Update `lobby_live.html.heex`:
   ```heex
   <%# OLD %>
   {live_render(@socket, StatefulSensorLive, ...)}

   <%# NEW %>
   <.live_component
     module={StatefulSensorComponent}
     id={"sensor_#{sensor_id}"}
     sensor_id={sensor_id}
     sensor={@sensors[sensor_id]}
     view_mode={@global_view_mode}
     is_favorite={sensor_id in @favorite_sensors}
     on_favorite_toggle={&handle_favorite_toggle/1}
   />
   ```

2. Update IndexLive and RoomShowLive similarly

3. Mark StatefulSensorLive as deprecated

### Phase 8: Cleanup (1 hour)

1. Remove deprecated StatefulSensorLive
2. Update tests
3. Verify all hooks work correctly
4. Load test with 100+ sensors

---

## Total Estimated Effort

| Phase | Hours | Can Parallelize |
|-------|-------|-----------------|
| Phase 0: Quick Mitigation | 1 | Yes (immediate) |
| Phase 1: Scaffold | 2-3 | No |
| Phase 2: Parent Subscriptions | 3-4 | No |
| Phase 3: Event Handlers | 2-3 | Yes (after P1) |
| Phase 4: Throttling | 2-3 | Yes (after P2) |
| Phase 5: Attention | 2-3 | Yes (after P2) |
| Phase 6: Template | 1-2 | Yes (after P1) |
| Phase 7: Integration | 1-2 | No (last) |
| Phase 8: Cleanup | 1 | No (last) |

**Total: 15-22 hours** (can be reduced with parallelization)

---

## Testing Strategy

### Unit Tests
- Component renders with minimal assigns
- Event handlers update state correctly
- Throttle buffer accumulates and flushes

### Integration Tests
- Parent forwards measurements to components
- Virtual scroll creates/destroys components cleanly
- Attention events flow through correctly

### Performance Tests
- Scroll 100+ sensors without page reload
- Compare CPU/memory with current implementation
- Test on Fly.dev with network latency

### Regression Tests
- Favorites toggle persists
- Pin/unpin works
- Modals open/close correctly
- Latency measurement continues working

---

## Rollback Plan

1. Keep StatefulSensorLive alongside new component during migration
2. Feature flag to switch between implementations:
   ```elixir
   if Application.get_env(:sensocto, :use_sensor_component, false) do
     live_component(...)
   else
     live_render(...)
   end
   ```
3. Easy rollback by toggling config

---

## Success Criteria

- [ ] No full page reloads when scrolling lobby
- [ ] All sensor functionality preserved
- [ ] Performance improvement on Fly.dev
- [ ] Tests pass
- [ ] Memory usage reduced (fewer processes)

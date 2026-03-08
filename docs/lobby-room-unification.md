# Lobby / Room Unification Plan

> Status: **Planning** (Mar 2026)
> Goal: Merge `LobbyLive` and `RoomShowLive` into a single `RoomLive` LiveView, where the Lobby becomes a built-in special room.

---

## Motivation

`LobbyLive` (~3,000 lines) and `RoomShowLive` (~3,500 lines) handle largely overlapping concerns: sensor data display, media player, 3D object player, whiteboard, calls, polls, presence, and more. The components already support both contexts via an `is_lobby: true` flag, and all server processes (MediaPlayerServer, Object3DPlayerServer, WhiteboardServer, Calls) already use `:lobby` as the room ID atom. The two LiveViews have drifted apart due to lobby-specific features (guided sessions, virtual scroll, PriorityLens, graph views) and room-specific features (membership management, curated sensor lists, Ash-backed configuration).

Unifying them reduces duplication, enables room configurability, and makes the lobby a first-class citizen of the room system.

---

## Current State

### LobbyLive

- **File:** `lib/sensocto_web/live/lobby_live.ex`
- **Template:** `lib/sensocto_web/live/lobby_live.html.heex`
- **Routes:** 15 live_actions (`/lobby`, `/lobby/ecg`, `/lobby/heartrate`, `/lobby/graph`, etc.) — URL-based lens navigation
- **Sensor source:** All sensors — `SensorsDynamicSupervisor.get_all_sensors_state(:view)`, no filter
- **Data pipeline:** PriorityLens ETS → PubSub → ViewerDataChannel → browser (adaptive, backpressure-aware)
- **Lens system:** Hardcoded 9-element tuple (`extract_composite_data`). All destructuring sites must be updated simultaneously when adding lenses.
- **Hook modules attached:** `MediaHook`, `Object3DHook`, `WhiteboardHook`, `CallHook`, `GuidedSessionHook`

**Lobby-only features:**
- Virtual scroll (visible range window, `VirtualScrollHook`, `SensorGridHook`)
- Guided sessions (guide/follower coordination, 15+ events, `GuidedSessionHook`)
- PriorityLens adaptive streaming + quality management (`quality_override`, `data_mode`, backpressure)
- Graph views (`:graph`, `:graph3d`, `:hierarchy` live_actions)
- Sort modes (`sort_by`: activity/name/type/battery, debounced sort timer)
- Favorites (`:favorites` live_action, `toggle_favorite` event)
- MIDI sync (`midi_toggled`, SyncComputer integration)
- User view (`:users` live_action, `UserVideoCardComponent`)
- Layout toggle (`lobby_layout`: stacked / side-by-side)
- Sensor grouping by user/connector (`sensors_by_user`)
- Performance telemetry (`perf_stats`, `:log_perf_stats` timer)
- Seed data async (`start_async(:seed_composite_data, ...)` for historical data)

### RoomShowLive

- **File:** `lib/sensocto_web/live/rooms/room_show_live.ex`
- **Routes:** `/rooms/:id` (`:show`) and `/rooms/:id/settings` (`:settings`) — mode via query param
- **Sensor source:** Curated — only sensors in `SensorConnection` join table for the room
- **Data pipeline:** Direct PubSub per sensor (`data:#{sensor_id}`), no backpressure
- **Lens system:** Dynamic — `extract_available_lenses/1` discovers lenses from attribute types, builds `%{type, category, label, icon, color, sensor_count, has_composite}` structs. Lens selection is event-based (`select_lens`), no URL change.
- **Hook modules attached:** `MediaHook`, `Object3DHook`, `WhiteboardHook`, `CallHook`

**Room-only features:**
- Persistent Ash-backed configuration (`Room` resource: name, description, is_public, calls_enabled, media_playback_enabled, object_3d_enabled, whiteboard_enabled, join_code, owner_id)
- Membership management (owner/member/admin roles, `promote_to_admin`, `demote_to_member`, `kick_member`)
- Curated sensor list (`add_sensor`, `remove_sensor`, `available_sensors` modal)
- Room CRUD (`save_room`, `delete_room`, `validate_edit`, `edit_form`)
- Join code / share modal (`regenerate_code`, `copy_link`)
- Feature flag toggles persisted to DB (`toggle_calls_enabled`, `toggle_media_playback_enabled`, `toggle_object_3d_enabled`)
- Attention filter (`set_min_attention`, `min_attention`)
- Auto-join of user's own sensors on connect
- Guest restrictions (`@guest_restricted_events` guard)
- Settings live_action (`/rooms/:id/settings`)

### Shared Functionality (Currently Duplicated)

| Category | Notes |
|---|---|
| Call controls UI + handlers | ~25 identical WebRTC hook acknowledgement handlers |
| MediaPlayerComponent | Shared component, `is_lobby` flag already exists |
| Object3DPlayerComponent | Shared component, `is_lobby` flag already exists |
| WhiteboardComponent | Shared component, `is_lobby` flag already exists |
| PollsPanelComponent | Identical in both |
| Mode tab bar | `switch_lobby_mode` vs `switch_room_mode` — same UI, different event name |
| Presence viewer counts | Same pattern, lobby uses `:lobby` as topic key |
| Room mode presence tracking | `room:lobby:mode_presence` vs `room:#{id}:mode_presence` |
| Control request modals | Identical logic in both |
| Media sync | Identical events |
| Hook modules | 4 hook modules duplicated in different namespaces |
| Chat system | Same system, different `chat_room_id` |
| Attention tracker integration | Same register/unregister pattern |

### Lobby's Existing Room Identity

The lobby already behaves like a room with `id: :lobby` at the service layer:
- All server processes accept `:lobby` as the room ID atom (Calls, MediaPlayerServer, Object3DPlayerServer, WhiteboardServer)
- Components already have `is_lobby` guards
- PubSub topics follow the same `room:lobby:*` pattern as regular rooms

This means **no service-layer changes are needed** — only the LiveView layer needs unification.

---

## Proposed Migration

### Phase 1 — Extract Shared Infrastructure

**No UX change. Low risk.**

**1.1 — Shared hook modules**

The four hook modules in `lobby_live/hooks/` and `rooms/hooks/` have nearly identical logic. Create a shared namespace (e.g. `SensoctoWeb.Live.Hooks`) with:
- `CallHook`
- `MediaHook`
- `Object3DHook`
- `WhiteboardHook`

Both LiveViews `attach_hook` from the shared namespace. Lobby keeps `GuidedSessionHook` in its own namespace (lobby-specific).

**1.2 — Shared call event handlers**

Extract the ~25 identical WebRTC acknowledgement handlers (`track_ready`, `track_removed`, `quality_changed`, `participant_audio_changed`, etc.) into a shared module both LiveViews import or delegate to.

**1.3 — Unified mode tab component**

Extract the mode tab bar (Media / 3D Object / Whiteboard / Polls) into a shared function component `RoomModeTabs` with a configurable event-name attribute. Eliminates the `switch_lobby_mode` vs `switch_room_mode` split.

**1.4 — Shared control request modal logic**

The control request and media control request modal logic is identical. Extract to a shared helper.

---

### Phase 2 — Formal Lobby Room Context

**Optional DB migration. Medium risk.**

**Decision required:** Use a well-known DB record or keep the `:lobby` atom.

**Option A — Well-known Room record (recommended for long-term configurability)**

Seed a `Room` record with a config-driven UUID (`config :sensocto, :lobby_room_id, "00000000-0000-0000-0000-000000000001"`):
- `name: "Lobby"`, `is_public: true`
- No `SensorConnection` rows — lobby uses all sensors via a `:all_sensors` policy
- Enables admin configuration of the lobby via the existing room settings UI in the future
- Integrates cleanly with Ash authorization

**Option B — Keep `:lobby` atom (minimal disruption)**

The `:lobby` atom is already the convention at every layer. No migration needed. The unified LiveView checks `room_id == :lobby` for lobby-specific behavior. Less clean, harder to make configurable later.

---

### Phase 3 — Unified `RoomLive` LiveView

**High effort. Core change. Prerequisite: Phase 1 complete.**

Create `lib/sensocto_web/live/room_live.ex` replacing both LiveViews.

**Mount dispatch:**
```elixir
def mount(%{"id" => room_id}, session, socket) do
  mount_room(room_id, session, socket)
end

def mount(_params, session, socket) do
  # Lobby: special built-in room
  mount_room(:lobby, session, socket)
end
```

**Key assign unification:**

| Assign | Source | Notes |
|---|---|---|
| `room_context` | New | `:lobby` or `%Room{}` struct |
| `room_id` | Derived | `:lobby` or `room.id` |
| `is_lobby` | Derived | `room_id == :lobby` |
| `sensors` | Conditional | All sensors (lobby) or room-filtered list |
| `available_lenses` | Room's dynamic system | Replace lobby's hardcoded tuple |
| `current_lens` | Unified | Event-based for both initially |
| `room_mode` | Unified | `:media \| :object3d \| :whiteboard \| :sensors \| :call \| :polls` |
| Lobby extras | Guarded by `is_lobby` | `sort_by`, virtual scroll, guided session, priority lens, quality |
| Room extras | Guarded by `!is_lobby` | `is_owner`, `is_member`, `can_manage`, `edit_form`, `available_sensors` |

**Lens system migration (critical):**

Replace the lobby's hardcoded 9-element tuple with Room's dynamic `extract_available_lenses/1`. This eliminates the "update all destructuring sites simultaneously" footgun.

Lens navigation model for Phase 3:
- Lobby: keep URL-based live_action routes (`/lobby/ecg` → live_action `:ecg`)
- Rooms: keep event-based `select_lens` (no URL change)
- Phase 4 will unify these

**Data pipeline — branch on `is_lobby`:**

```elixir
if socket.assigns.is_lobby do
  setup_priority_lens(socket)   # PriorityLens → ViewerDataChannel
else
  setup_direct_subscriptions(socket, room)   # PubSub per sensor
end
```

Long-term (Phase 5): migrate rooms to PriorityLens too.

**Guided sessions:** Only `attach_hook GuidedSessionHook` when `is_lobby`. All guided session assigns and events guarded by `is_lobby`.

**Template structure:**

```heex
<!-- Context-specific header -->
<%= if @is_lobby, do: lobby_header(), else: room_header() %>

<!-- Shared for both -->
<.call_controls ... />
<.room_mode_tabs room_mode={@room_mode} is_lobby={@is_lobby} ... />

<!-- Sensor views: different implementations -->
<%= if @is_lobby && @room_mode == :sensors do %>
  <!-- Virtual scroll grid + SensorGridHook -->
<% else %>
  <!-- Flat sensor list (room) -->
<% end %>

<!-- Composite lenses: same Svelte components work for both -->
<%= if @current_lens do %>
  <.composite_view lens={@current_lens} ... />
<% end %>
```

**Router:**
```elixir
# Lobby (special built-in room) — existing routes unchanged
live "/lobby", RoomLive, :sensors
live "/lobby/heartrate", RoomLive, :heartrate
# ... all existing lobby routes

# Regular rooms — existing routes unchanged
live "/rooms/:id", RoomLive, :show
live "/rooms/:id/settings", RoomLive, :settings
```

---

### Phase 4 — URL-based Lens Navigation for Rooms (Optional)

After Phase 3 stabilizes, give rooms shareable lens URLs:

```elixir
live "/rooms/:id/lens/:lens_type", RoomLive, :lens
```

This makes room lens navigation identical to lobby lens navigation and enables bookmarking.

---

### Phase 5 — PriorityLens for Rooms (Optional, Performance)

Migrate rooms from direct per-sensor PubSub to PriorityLens adaptive streaming. Only valuable when room sensor counts approach lobby scale. Gives rooms the same quality management and ViewerDataChannel delivery that the lobby uses.

---

## Open Decisions

| Decision | Options | Recommendation |
|---|---|---|
| Lobby room identity | A: DB record with well-known UUID; B: keep `:lobby` atom | A for long-term configurability; B for minimal disruption |
| Lens navigation for rooms | Keep event-based (Phase 3); promote to URL-based (Phase 4) | Event-based first, then URL in Phase 4 |
| Virtual scroll for rooms | Lobby-only or extend to rooms too | Lobby-only until rooms have large sensor counts |
| Guided sessions scope | Lobby-only forever or extend to rooms | Lobby-only for now — guard with `is_lobby` |
| Phase 3 timing | Begin after Phase 1 complete | Phase 1 is safe to start immediately |

---

## Risk / Sequencing

| Phase | Effort | Risk | Rollback |
|---|---|---|---|
| 1 — Shared infrastructure | Medium | Low | Revert shared namespace |
| 2 — Lobby Room record | Medium | Medium | Keep `:lobby` atom fallback |
| 3 — Unified RoomLive | Large | High | Keep both LiveViews until fully tested |
| 4 — URL-based room lenses | Medium | Low | Revert to event-based |
| 5 — PriorityLens for rooms | Large | Medium | Keep direct PubSub |

Phase 1 can begin immediately without breaking anything. Phase 3 should run in a feature branch with both LiveViews coexisting until the new one is validated.

---

## Files Affected (Phase 3)

| File | Action |
|---|---|
| `lib/sensocto_web/live/lobby_live.ex` | Replace with `room_live.ex` |
| `lib/sensocto_web/live/lobby_live.html.heex` | Replace with `room_live.html.heex` |
| `lib/sensocto_web/live/lobby_live/` (hooks, components) | Merge into shared hooks namespace |
| `lib/sensocto_web/live/rooms/room_show_live.ex` | Replace with `room_live.ex` |
| `lib/sensocto_web/router.ex` | Point lobby + room routes at `RoomLive` |
| `lib/sensocto_web/live/rooms/hooks/` | Merge into shared hooks namespace |
| `lib/sensocto/sensors/room.ex` | Possibly add lobby seeding (Phase 2) |

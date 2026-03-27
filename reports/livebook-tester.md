# Sensocto Codebase Analysis: Livebook & Testing Landscape

## Executive Summary

Sensocto is a sophisticated real-time sensor platform built on Phoenix/LiveView with Ash Framework, featuring:
- Multi-sensor data ingestion via WebSocket channels
- Room-based collaboration with distributed state (Horde, Iroh)
- Video/voice calling via Membrane RTC Engine
- Attention-aware back-pressure with sharded PubSub
- GPS track replay simulation
- Nx/numerical computing for quaternion calculations
- Collaborative whiteboard, media player, and 3D object viewer
- Guided session system for guide/follower coordination
- Rust and mobile native clients with lobby/room channel support
- IMU composite visualization for motion sensor data

**Current Testing Status:** Stable at **65 test files**, **971 test definitions**, **~15,600 total test lines** across unit, integration, E2E (Wallaby), and regression guard tests. No new test files since Mar 1.

**Livebook Status:** 16 livebooks totaling 8,713 lines. Livebook count stagnant since Feb 16 (over 5 weeks). No new livebooks created.

**Priority Recommendation:** Create tests for the new LobbyChannel and RoomChannel (0% coverage, client-facing contract), expand GuidedSessionHook tests (212 lines, 16 message handlers, 0% coverage), and add DataGenerator property-based tests. The Rust client's lobby.rs and room_session.rs modules depend on the JSON shapes produced by these channels -- contract drift is the top integration risk.

---

## Update: March 25, 2026

### Key Changes Since Mar 1, 2026

The past three weeks brought several new modules and features, but **no new test files were created**. The test count remains flat at 65 files / 971 definitions. The main additions are new channels for mobile/Rust clients, an IMU composite lens, expanded guided session coordination, whiteboard improvements, and a sensor background animation helper. The Rust client also gained lobby and room_session modules that consume the new channel APIs.

#### 1. New Channel: LobbyChannel (0% Test Coverage)

`lib/sensocto_web/channels/lobby_channel.ex` (159 lines) is a new read-only channel providing mobile and Rust clients with live room list updates. Registered in UserSocket as `"lobby:*"`.

**Key behaviors to test:**
- `join("lobby:<user_id>")` -- authorization check (user_id must match socket assigns)
- `join` with mismatched user_id returns `{:error, %{reason: "unauthorized"}}`
- `:after_join` pushes `"lobby_state"` with `my_rooms` and `public_rooms` lists
- PubSub handlers: `{:lobby_room_created, room}` pushes `"room_added"`, `{:lobby_room_deleted, room_id}` pushes `"room_removed"`, `{:lobby_room_updated, room}` pushes `"room_updated"`, `{:membership_changed, room_id, action, user_id}` pushes `"membership_changed"`
- `room_to_json/1` serialization: handles MapSet and list sensor_ids, includes member_count
- Unknown messages are silently dropped

**Integration risk:** The Rust client (`clients/rust/src/lobby.rs`, 173 lines) deserializes `lobby_state`, `room_added`, `room_removed`, `room_updated`, and `membership_changed` events. Any change to the JSON shape in `room_to_json/1` or `sensor_to_json/1` will break the Rust client silently. A regression guard test for the channel event contracts is strongly recommended.

#### 2. New Channel: RoomChannel (0% Test Coverage)

`lib/sensocto_web/channels/room_channel.ex` (157 lines) provides per-room live sensor/member updates for mobile clients. Registered in UserSocket as `"room:*"`.

**Key behaviors to test:**
- `join("room:<room_id>")` -- validates UUID format via `Ecto.UUID.cast/1`
- Authorization: `authorized_for_room?/2` checks public flag or membership via RoomStore
- `:after_join` pushes `"room_state"` with sensors list and member_count
- PubSub `{:room_update, event}` dispatches: `:sensor_added`, `:sensor_removed`, `:member_joined`, `:member_left`, `:room_closed`
- `:sensor_measurement` events are intentionally ignored (no push)

**Integration risk:** The Rust client (`clients/rust/src/room_session.rs`, 176 lines) consumes `room_state`, `sensor_added`, `sensor_removed`, `member_joined`, `member_left`, and `room_closed` events. Same contract drift risk as LobbyChannel.

#### 3. Rust Client: New Lobby and RoomSession Modules

Two new Rust modules consume the channel APIs above:
- `clients/rust/src/lobby.rs` (173 lines) -- `LobbySession` + `handle_lobby_event_sync` event parser
- `clients/rust/src/room_session.rs` (176 lines) -- `RoomSession` + `handle_room_event_sync` event parser

Both use `serde_json::from_value` deserialization with fallback to empty vecs on parse failure. The `Room` and `RoomSensor` model structs must match the JSON produced by `room_to_json/1` and `sensor_to_json/1` in the Elixir channels.

**Testing recommendation:** Create a regression guard test (`test/sensocto/regression_guards/channel_contract_test.exs`) that verifies the exact JSON shapes returned by `LobbyChannel.room_to_json/1` and `RoomChannel.sensor_to_json/1` against expected Rust-compatible structures. This is the highest-priority testing gap.

#### 4. IMU Composite Lens (New Svelte Component)

`assets/svelte/CompositeIMU.svelte` (359 lines) is a new composite visualization for IMU (Inertial Measurement Unit) sensor data. The lobby routes now include `/lobby/imu` alongside existing composite views (heartrate, ecg, etc.).

In `lobby_live.ex`, IMU sensors are extracted as part of the `extract_composite_data/1` tuple, filtered in `compute_available_lenses`, and dispatched through the standard `process_lens_batch_for_composite` / `process_lens_digest_for_composite` pipeline.

**Testing impact:** The `lobby_graph_regression_test.exs` should be verified to include the `/lobby/imu` route in its mount regression checks. The `extract_composite_data` tuple now includes `imu_sensors` -- all destructuring sites in lobby_live.ex must handle the expanded tuple.

#### 5. Sensor Background Animations

`lib/sensocto_web/live/helpers/sensor_background.ex` (100 lines) is a new shared helper module for sensor-driven background animations. Used by `CustomSignInLive` and `IndexLive` to create ambient visualizations driven by real sensor activity.

**Key functions:** `subscribe/0`, `unsubscribe/0`, `start_bg_tick/0`, `init_activity/0`, `handle_measurement/2`

Subscribes to `["data:attention:high", "data:attention:medium", "sensors:global"]` PubSub topics and accumulates sensor activity with decay for visual effects.

**Testing opportunity:** Pure functions like `handle_measurement/2` and `init_activity/0` are easily unit-testable. The tick/decay logic could benefit from property-based testing.

#### 6. Guided Session Hook Expansion

`lib/sensocto_web/live/lobby_live/hooks/guided_session_hook.ex` grew from 182 to **212 lines** (16% increase). New message handlers added:
- `{:guided_quality_changed, %{quality: quality}}` -- propagates quality settings to PriorityLens
- `{:guided_sort_changed, %{sort_by: sort_by}}` -- sorts sensor list per guide preference
- `{:guided_mode_changed, %{mode: mode}}` -- switches lobby mode (sensors/whiteboard/etc.)
- `{:guided_panel_changed, %{panel, collapsed}}` -- controls panel visibility
- `{:guided_layout_changed, %{layout: layout}}` -- switches grid/list layout
- `{:guidance_available, info}` -- new inline join flow (replaces old invite code page)
- `{:guidance_unavailable, %{session_id: id}}` -- dismisses available session prompt

The hook now has **16 `on_handle_info/2` clauses** plus a catch-all. Every clause follows the `{:halt, socket}` / `{:cont, socket}` pattern and is testable with mock socket assigns.

**Coverage: still 0%.** This is the most complex hook module with multiple conditional branches (checking `guided_session`, `guided_following`, `guiding_session` assigns). Each conditional path is a test case.

#### 7. Whiteboard Hook Improvements

`lib/sensocto_web/live/lobby_live/hooks/whiteboard_hook.ex` grew to **139 lines** with 12 message handlers:
- Stroke operations: `stroke_progress`, `strokes_batch`, `stroke_added`
- Canvas operations: `cleared`, `undo`, `background_changed`
- Control operations: `controller_changed`, `control_requested`, `control_request_denied`, `control_request_cancelled`
- Utility: `clear_whiteboard_bump` timer handler

The "bump" animation pattern (assign true, send_after 300ms, assign false) is repeated in 3 handlers -- a potential extraction candidate.

**Coverage: still 0%.** All handlers delegate to `send_update/2` which is easy to verify in tests.

#### 8. Simulator Manager and DataGenerator Changes

`lib/sensocto/simulator/manager.ex` grew to **1,069 lines** (up from ~950). New additions include:
- Multi-scenario support: `start_scenario/2`, `stop_scenario/1`, `get_running_scenarios/0`
- Scenario isolation: each scenario tracks its own room_id and connector_ids
- `get_current_scenario/0` for backwards compatibility

`lib/sensocto/simulator/data_generator.ex` grew to **1,555 lines** (up from ~1,392). New sensor type generators:
- `fetch_respiration_data` -- breathing rate simulation
- `fetch_hrv_data` -- heart rate variability
- `fetch_eye_gaze_data` -- eye tracking
- `fetch_eye_aperture_data` -- blink detection
- `fetch_hydro_api_data` -- hydrology API simulation

**Existing coverage:** Manager has 19 tests in `manager_test.exs`. DataGenerator has **0% coverage** despite being 1,555 lines of mostly pure math functions -- ideal for property-based testing with StreamData.

#### 9. LensComponents Extraction

`lib/sensocto_web/live/lobby_live/lens_components.ex` grew to **893 lines** (up from ~412). New additions:
- `composite_lens/1` -- generic wrapper for all Svelte composite views
- `midi_panel/1` -- MIDI / GrooveEngine panel for graph views
- Multiple lens-specific layout components

This module contains only function components (no state, no events) making it testable via `Phoenix.LiveViewTest.render_component/2`.

#### 10. Channel Architecture Overview

UserSocket now registers **6 channel modules**:

| Channel | Topic Pattern | Lines | Test Coverage |
|---------|--------------|-------|---------------|
| SensorDataChannel | `sensocto:*` | 717 | 2 tests (ping + broadcast) |
| RoomChannel | `room:*` | 157 | **0%** |
| CallChannel | `call:*` | ~100 | **0%** |
| HydrationChannel | `hydration:room:*` | ~80 | **0%** |
| ViewerDataChannel | `viewer:*` | ~120 | **0%** |
| LobbyChannel | `lobby:*` | 159 | **0%** |

Only SensorDataChannel has any test coverage, and even that is minimal (2 tests for ping and basic broadcast). The other 5 channels are completely untested. With the Rust client now consuming LobbyChannel and RoomChannel, this is a significant gap.

### Updated Metrics

| Metric | Mar 1 | Mar 25 | Change |
|--------|-------|--------|--------|
| Test Files | 65 | **65** | +0 (stagnant) |
| Test Definitions | 974 | **971** | -3 (minor cleanup) |
| Total Test Lines | ~15,592 | **~15,600** | Flat |
| Channels (total/tested) | 5/1 | **6/1** | +1 untested |
| Rust Client Modules | ~4 | **6** | +2 (lobby, room_session) |
| GuidedSessionHook Handlers | ~12 | **16** | +4 new handlers |
| DataGenerator Lines | ~1,392 | **1,555** | +163 lines, 0% coverage |
| Simulator Manager Lines | ~950 | **1,069** | +119 lines |
| LensComponents Lines | ~412 | **893** | +481 lines |
| Lobby Live Lines | ~3,138 | **3,513** | +375 lines |
| Livebook Count | 16 | **16** | Stagnant (5+ weeks) |
| Guidance Test Coverage | 0% | **0%** | Still untested |

---

## Priority Testing Recommendations (Ranked)

### P0: Channel Contract Regression Guards

**Why:** The Rust client directly deserializes JSON from LobbyChannel and RoomChannel. Any drift in field names, types, or structure will cause silent client failures.

**Suggested file:** `test/sensocto_web/channels/lobby_channel_test.exs`

```elixir
# Test join authorization (matching user_id required)
# Test join rejection for mismatched user_id
# Test :after_join pushes lobby_state with my_rooms and public_rooms
# Test room_to_json/1 output shape matches Rust Room struct fields:
#   {id, name, description, owner_id, join_code, is_public, created_at, sensors, member_count}
# Test sensor_to_json/1 output shape matches Rust RoomSensor struct fields:
#   {sensor_id, sensor_name, sensor_type, connector_id, connector_name, activity_status, attributes}
# Test PubSub event forwarding: room_added, room_removed, room_updated, membership_changed
# Test unknown messages are silently dropped
```

**Suggested file:** `test/sensocto_web/channels/room_channel_test.exs`

```elixir
# Test join with valid UUID room_id
# Test join with invalid UUID returns {:error, %{reason: "invalid room id"}}
# Test authorization: public rooms allow any user, private rooms require membership
# Test :after_join pushes room_state with sensors and member_count
# Test room_update events: sensor_added, sensor_removed, member_joined, member_left, room_closed
# Test sensor_measurement events are silently ignored (no push)
```

### P1: GuidedSessionHook Unit Tests

**Why:** 16 message handlers, multiple conditional branches, direct PriorityLens integration. The hook is growing fast and has complex state dependencies.

**Suggested file:** `test/sensocto_web/live/hooks/guided_session_hook_test.exs`

```elixir
# For each of the 16 on_handle_info/2 clauses:
# - Test with guided_session=nil (should pass through or halt with no change)
# - Test with guided_following=true (should apply changes)
# - Test with guided_following=false (should halt without applying)
# Specific edge cases:
# - :guided_quality_changed with :auto vs specific quality level
# - :guidance_available when already in a session (should ignore)
# - :guidance_unavailable for non-matching session_id (should ignore)
# - :guided_drift_back calls apply_guided_settings
# - :guided_ended resets all guided assigns
```

### P2: DataGenerator Property-Based Tests

**Why:** 1,555 lines of pure math functions generating simulated sensor data. Perfect candidate for StreamData property-based testing.

```elixir
# Properties to verify:
# - fetch_sensor_data always returns {:ok, data} or {:error, reason}
# - Generated heartrate values are within physiological range (30-220 bpm)
# - Generated battery levels are 0-100
# - Generated GPS coordinates are valid lat/lng ranges
# - Skeleton keyframe data has expected joint count
# - Respiration rate is within 4-60 breaths/min
# - HRV values are positive
# - Eye gaze coordinates are normalized 0.0-1.0
```

### P3: SensorBackground Helper Tests

**Why:** Small (100 lines), pure functions, used on public-facing pages (sign-in, index).

```elixir
# Test init_activity/0 returns map keyed by sensor_id
# Test handle_measurement/2 increments hit_count for known sensor
# Test handle_measurement/2 creates entry for unknown sensor
# Test decay logic reduces hit_count over time
```

### P4: WhiteboardHook Tests

**Why:** 12 handlers, all following the same delegation pattern. Easy to test in bulk.

```elixir
# Test each PubSub message triggers correct send_update to WhiteboardComponent
# Test whiteboard_bump timer: first event sets true, :clear_whiteboard_bump sets false
# Test stroke_progress filters out current user's own strokes
```

### P5: Remaining Extracted Hooks

All lobby hooks remain at 0% coverage:

| Hook Module | Lines | Handlers | Complexity |
|------------|-------|----------|------------|
| `guided_session_hook.ex` | 212 | 16 | HIGH (conditionals) |
| `whiteboard_hook.ex` | 139 | 12 | LOW (delegation) |
| `media_hook.ex` | ~140 | ~8 | LOW (delegation) |
| `object3d_hook.ex` | ~156 | ~8 | LOW (delegation) |
| `call_hook.ex` | ~70 | ~4 | LOW (delegation) |

---

## Update: March 1, 2026

### Key Changes Since Feb 24, 2026

The past week brought significant architectural refactoring, substantial new test coverage for the backpressure and OTP layers, and continued improvements to the data pipeline. The codebase grew from ~780 to 974 test definitions (+25%) while the lobby was decomposed into a modular hook-based architecture.

#### 1. Lobby Refactoring: Extracted Hooks and Components

The monolithic `lobby_live.ex` was refactored into a modular architecture. Eight modules were extracted into `lib/sensocto_web/live/lobby_live/`:

| Module | Lines | Purpose | Test Coverage |
|--------|-------|---------|---------------|
| `hooks/guided_session_hook.ex` | 182 | Guide/follower PubSub message handling | **0%** |
| `hooks/media_hook.ex` | 140 | Media player event delegation | **0%** |
| `hooks/object3d_hook.ex` | 156 | 3D object viewer event delegation | **0%** |
| `hooks/whiteboard_hook.ex` | 131 | Whiteboard event delegation | **0%** |
| `hooks/call_hook.ex` | 70 | Call/WebRTC event delegation | **0%** |
| `components.ex` | 412 | Extracted function components | **0%** |
| `sensor_detail_live.ex` | 909 | Sensor detail subview | **0%** |
| `sensor_compare_live.ex` | 231 | Sensor comparison subview | **0%** |

Despite the extraction, `lobby_live.ex` remains large at 3,513 lines, indicating the core lens/sensor logic is still inline. The hook modules use Phoenix LiveView's `attach_hook` pattern and follow a consistent `on_handle_info/2` callback structure with `{:halt, socket}` returns.

**Testing opportunity:** Each hook module has a small, well-defined interface. They accept a PubSub message tuple and a socket, returning `{:halt, socket}`. These are highly testable with mock sockets.

#### 2. Backpressure and PriorityLens Improvements

Major improvements to the backpressure pipeline with substantial new test coverage. These files were all created since Feb 24:

| New Test File | Lines | Tests | What It Covers |
|---------------|-------|-------|----------------|
| `priority_lens_buffer_test.exs` | 312 | 15 | ETS hot-path buffer operations, batch routing, flush timer |
| `router_test.exs` | 188 | 13 | Demand-driven PubSub subscription, lens registration/unregistration |
| `lobby_backpressure_test.exs` | 231 | 19 | Load level threshold calculation, quality hysteresis, upgrade delays |
| `mount_optimization_test.exs` | 297 | 20 | SearchLive sticky mount, deferred subscriptions, signal topic deferral |
| `simple_sensor_throttle_test.exs` | 452 | 16 | SimpleSensor throttling behavior under load |
| `system_load_monitor_test.exs` | 266 | 24 | ETS fast reads, load level determination, memory protection, PubSub broadcasts |

The `lobby_backpressure_test.exs` specifically catches a previously missing `:high` load level case that caused a fall-through to `:normal` thresholds. The `mount_optimization_test.exs` validates deferred subscription patterns that reduce mount-time overhead.

**Key insight:** The backpressure system now has strong unit-level coverage but lacks end-to-end tests that verify the full pipeline from SystemLoadMonitor -> PriorityLens quality adjustment -> LobbyLive threshold response.

#### 3. New OTP and Infrastructure Tests

Several new test files were created for previously untested OTP modules:

| New Test File | Lines | Tests | What It Covers |
|---------------|-------|-------|----------------|
| `room_store_test.exs` | 447 | 43 | RoomStore GenServer: hydration gate, room CRUD, member management |
| `sensors_dynamic_supervisor_test.exs` | 321 | 18 | DynamicSupervisor for sensor processes |
| `attribute_store_tiered_extended_test.exs` | 272 | 16 | Extended tiered storage: TTL, compaction, tier promotion |
| `button_signal_reliability_test.exs` | 252 | 8 | Button press/release signal reliability under load |

The `room_store_test.exs` at 447 lines and 43 tests is the most comprehensive new test file, covering the full RoomStore lifecycle including the hydration gate pattern documented in project memory.

#### 4. Simulator Manager Tests

`simulator/manager_test.exs` (202 lines, 19 tests) is the first test coverage for the simulator system. Tests startup phase, state queries, and connector management. Uses a defensive `skip_if_unavailable` pattern since the Manager may not be started in the test environment.

**Remaining simulator gaps:** DataGenerator (1,555 lines, pure math functions -- ideal for property-based testing), AttributeServer (406 lines, recently refactored with ~85 lines of churn), SensorServer (408 lines).

#### 5. Session Server Changes

`SessionServer` grew from ~417 to 516 lines. Changes include expanded guide/follower coordination with quality, sort, mode, and layout synchronization. The module still has **0% test coverage** despite being a complex GenServer with timer-based state management.

#### 6. Additional New Test Files

| New Test File | Lines | Tests | What It Covers |
|---------------|-------|-------|----------------|
| `health_controller_test.exs` | 174 | 15 | API health check endpoint |
| `room_markdown_test.exs` | 438 | 50 | Markdown parsing and rendering |
| `admin_protection_test.exs` | 175 | 16 | Admin-only operation guards |
| `safe_keys_test.exs` | 238 | 32 | Safe key sanitization |
| `correlation_tracker_test.exs` | 109 | 11 | Bio layer co-activation tracking |

#### 7. Search Index Privacy Changes

`search_index.ex` received privacy-related modifications (commit `e53fb41` -- profiles, graph, privacy). The existing `search_index_test.exs` (165 lines, 11 tests) should be reviewed to ensure it covers the new visibility/privacy filtering logic.

#### 8. Other Notable Additions

- `profile_live.ex` and `profile_live.html.heex` -- significantly expanded with privacy settings (commit `e53fb41`)
- `user_settings_live.ex` (63 lines) -- new LiveView, untested
- `magic_sign_in_live.ex` -- received additions, untested
- `docs/liveview-architecture.md` -- new architecture documentation (552 lines)
- `docs/midi-output.md` -- new MIDI output documentation
- Plans moved to `plans/` directory (5 planning documents)
- Migration `20260226195225_default_is_public_to_false.exs` -- `is_public` now defaults to false

---

## Update: February 24, 2026

### New Feature: Guided Session System

A new **Guidance** domain has been added with the following components:

| Component | File | Purpose |
|-----------|------|---------|
| `Sensocto.Guidance` | `lib/sensocto/guidance.ex` | Ash domain with AshAdmin |
| `Sensocto.Guidance.GuidedSession` | `lib/sensocto/guidance/guided_session.ex` | Ash resource (DB-backed, 8 actions, invite code generation) |
| `Sensocto.Guidance.SessionServer` | `lib/sensocto/guidance/session_server.ex` | GenServer: lens sync, drift-back timer, annotations, idle timeout |
| `Sensocto.Guidance.SessionSupervisor` | `lib/sensocto/guidance/session_supervisor.ex` | DynamicSupervisor, one SessionServer per active session |
| `SensoctoWeb.GuidedSessionJoinLive` | `lib/sensocto_web/live/guided_session_join_live.ex` | LiveView for accepting/declining invitations via invite code |

**Ecto Schema Count:** 30 (up from 24). New: GuidedSession, plus UserConnection, UserSkill, Poll, PollOption, Vote added since last schema count.

**Current Guided Session Test Coverage: 0%.** No test files exist for any guidance module.

### Architecture Analysis: Guided Session

The system follows a guide/follower pattern (similar to MediaPlayerServer's take_control/release_control):

1. **Session lifecycle:** pending -> active -> ended/declined (Ash state machine via actions)
2. **Invite code:** 6-char alphanumeric from unambiguous alphabet (no O/0/I/1), unique identity constraint
3. **Drift-back timer:** Configurable 5-120s (default 15s). When follower breaks away, timer fires `:drift_back` message to auto-rejoin guide's view
4. **Idle timeout:** 5-minute timer starts when guide disconnects; ends session on expiry
5. **PubSub broadcasting:** All state changes broadcast to `"guidance:#{session_id}"` topic
6. **Registry:** Uses `Sensocto.GuidanceRegistry` (local Elixir Registry) for process lookup

**Key Design Observations:**

- `is_guide?/2` and `is_follower?/2` compare with `to_string/1`, safely handling both binary and UUID types
- `cancel_idle_timeout/1` in `handle_call({:end_session, ...})` does not return the updated state (the `state` var is not reassigned). This is benign because the process stops immediately after, but is inconsistent with `cancel_drift_back_timer/1` usage
- `annotations` list grows unboundedly via `state.annotations ++ [annotation]` -- potential memory concern for very long sessions
- The `handle_event("accept", ...)` in JoinLive uses `:create` action to set `follower_user_id`, but this is an update on an existing record. This looks like it should be a custom `:accept` action that also accepts `follower_user_id`, or a separate `:assign_follower` action
- No route for the JoinLive is visible in router.ex -- may need to be added

### Recommended Tests for Guided Session

#### 1. Ash Resource Tests (`test/sensocto/guidance/guided_session_test.exs`)

```elixir
# Test all 6 actions: create, accept, decline, end_session, by_invite_code, active_for_user
# Test invite_code uniqueness identity constraint
# Test drift_back_seconds min/max constraints (5..120)
# Test status transitions: pending->active, pending->declined, active->ended
# Test generate_invite_code/1 produces expected length and alphabet
```

#### 2. SessionServer Unit Tests (`test/sensocto/guidance/session_server_test.exs`)

```elixir
# Guide actions: set_lens, set_focused_sensor, add_annotation, suggest_action
# Non-guide rejection: all guide actions return {:error, :not_guide} for follower
# Follower actions: break_away starts drift-back timer, rejoin cancels it
# Non-follower rejection: break_away/rejoin return {:error, :not_follower}
# Drift-back timer: fires after configured seconds, resets following to true
# report_activity resets the drift-back timer
# Idle timeout: guide disconnect starts 5-min timer, reconnect cancels it
# end_session: updates Ash resource, broadcasts :guided_ended, stops process
# PubSub: verify all broadcast messages reach subscribers
# Connect/disconnect presence tracking
```

#### 3. SessionSupervisor Tests (`test/sensocto/guidance/session_supervisor_test.exs`)

```elixir
# start_session creates a process findable via Registry
# start_session with duplicate session_id returns {:ok, existing_pid}
# stop_session terminates the process
# get_or_start_session idempotency
# list_active_sessions returns all running session IDs
# count returns correct active count
```

#### 4. JoinLive Tests (`test/sensocto_web/live/guided_session_join_live_test.exs`)

```elixir
# Mount with valid invite code shows session details and Accept button
# Mount with invalid/expired code shows error message
# Mount without code shows error message
# Accept event with signed-in user activates session and redirects to /lobby
# Accept event without signed-in user shows flash error
```

---

## Update: February 22, 2026

### Changes Since Last Review (Feb 20 -> Feb 22, 2026)

| Change | Impact |
|--------|--------|
| E2E Tests (#35): 3 new Wallaby feature test files -- `auth_flow_feature_test.exs`, `room_feature_test.exs`, `lobby_navigation_feature_test.exs` | **Total 7 feature test files** (up from 4). E2E Pioneer achievement extended. Auth flow coverage is a major addition -- tests login/logout/redirect pipeline end-to-end. |
| OpenAPI Spec (#32): Controller specs added to RoomController, RoomTicketController, ConnectorController | `openapi_test.exs` should be expanded to validate new connector schemas. Currently only 2 tests. |
| Connector REST API (#40): New controller at `/api/connectors` | New API endpoint needs controller tests (index/show/update/delete). No test file yet for ConnectorController. |
| Hierarchy View (#41) + My Devices View (#42): New LiveViews at `/lobby/hierarchy` and `/devices` | Two new LiveView modules need mount + event handler tests. DevicesLive has inline rename and forget-with-confirmation that are good candidates for LiveView event testing. |
| CRDT Sessions (#36): document_worker.ex GenServer | New GenServer needs unit tests for LWW merge semantics, multi-device tracking, and auto-shutdown on idle. |
| Bio-Layer (#34): correlation_tracker.ex, ultradian modulation | CorrelationTracker needs tests for co-activation weight accumulation and decay. Extends bio test suite (currently at 100% for existing 5 modules). |
| Updated test counts: ~54 test files, ~780+ test definitions. E2E feature files: 7. |

---

## Update: February 20, 2026

### Testing Status -- Continued Strong Growth

| Metric | Feb 16 | Feb 20 | Change |
|--------|--------|--------|--------|
| Test Files | 33 | **51** | +18 (+55%) |
| Test Definitions | ~373 | **~732** | +359 (+96%) |
| Implementation Files | 250 | **280** | +30 |
| LiveView Modules | 46 | **52+** | +6 |
| Livebook Count | 16 | **16** | Stagnant |
| Estimated Code Coverage | ~15% | **~22%** | +7% |

### New Test Files (Feb 16 -> Feb 20)

- `lobby_graph_regression_test.exs` (229 lines) -- Verifies all 13 lobby routes mount without crashing
- `midi_output_regression_test.exs` (219 lines) -- MIDI push_event contract verification
- `accounts_test.exs` (316 lines) -- Full Ash coverage: User, UserSkill, UserConnection, GuestSession
- `collaboration_test.exs` (192 lines) -- Poll, PollOption, Vote Ash resource tests
- `delta_encoder_test.exs` (149 lines) -- Round-trip encoding, overflow, precision tests
- `attention_tracker_test.exs` (147 lines), `attribute_store_tiered_test.exs` (133 lines), `room_server_test.exs` (330 lines)
- `circuit_breaker_test.exs`, `sensor_test.exs`, `search_index_test.exs`, `sync_computer_test.exs`, `chat_store_test.exs`, `object3d_player_server_test.exs`
- `search_live_test.exs`, `user_directory_live_test.exs` -- Basic LiveView mount/render
- `sensor_data_channel_test.exs` -- Channel broadcast and ping/reply

---

## Previous Update: February 16, 2026

### Testing Growth Since January

| Metric | Jan 20, 2026 | Feb 16, 2026 | Change |
|--------|-------------|-------------|--------|
| Test Files | 20 | **33** | +65% |
| Test Cases (approximate) | 150+ | **456** | +200% |
| E2E Feature Tests (Wallaby) | 0 | **4 files** | NEW |
| Ash Resource Tests | 0 | **1 file (Room)** | NEW |
| Regression Guard Tests | 0 | **1 file** | NEW |
| Rate Limiter Tests | 0 | **1 file** | NEW |
| OpenAPI Spec Tests | 0 | **1 file** | NEW |
| Accessibility Tests | 0 | **2 files** | NEW |
| Attention Tracker Tests | 0 | **1 file** | NEW |
| PriorityLens Tests | 0 | **1 file** | NEW |
| AttributeStoreTiered Tests | 0 | **1 file** | NEW |
| ButtonState Visualization Tests | 0 | **1 file** | NEW |
| Livebook Count | 11 | **16** | +45% |
| Livebook Total Lines | ~3,500 | **8,713** | +149% |

---

## Complete Test File Inventory (65 files, 971 tests, ~15,600 lines)

**Core OTP / Data Pipeline:**
- `test/sensocto/otp/simple_sensor_test.exs` (23 tests) -- SimpleSensor GenServer
- `test/sensocto/otp/simple_sensor_throttle_test.exs` (16 tests) -- SimpleSensor throttling under load
- `test/sensocto/otp/attribute_store_tiered_test.exs` (13 tests) -- Tiered attribute storage
- `test/sensocto/otp/attribute_store_tiered_extended_test.exs` (16 tests) -- Extended: TTL, compaction, tier promotion
- `test/sensocto/otp/attention_tracker_test.exs` (23 tests) -- Attention level management
- `test/sensocto/otp/button_state_visualization_test.exs` (7 tests) -- Button press/release integration
- `test/sensocto/otp/button_signal_reliability_test.exs` (8 tests) -- Signal reliability under load
- `test/sensocto/otp/room_store_test.exs` (43 tests) -- RoomStore hydration, CRUD, members
- `test/sensocto/otp/room_server_test.exs` (29 tests) -- RoomServer GenServer
- `test/sensocto/otp/sensors_dynamic_supervisor_test.exs` (18 tests) -- Sensor DynamicSupervisor
- `test/sensocto/otp/system_load_monitor_test.exs` (24 tests) -- SystemLoadMonitor ETS reads, load levels
- `test/sensocto/lenses/priority_lens_test.exs` (20 tests) -- Reactive backpressure, quality tiers
- `test/sensocto/lenses/priority_lens_buffer_test.exs` (15 tests) -- ETS hot-path buffer operations
- `test/sensocto/lenses/router_test.exs` (13 tests) -- Demand-driven subscription, lens registration
- `test/sensocto/regression_guards_test.exs` (49 tests) -- Data pipeline contract guards

**Ash Resources:**
- `test/sensocto/sensors/room_test.exs` (18 tests) -- Room resource create/read/update actions
- `test/sensocto/sensors/sensor_test.exs` (9 tests) -- Sensor resource tests
- `test/sensocto/sensors/attribute_store_test.exs` (9 tests) -- Legacy attribute store
- `test/sensocto/accounts/accounts_test.exs` (19 tests) -- User, UserSkill, UserConnection, GuestSession
- `test/sensocto/collaboration/collaboration_test.exs` (11 tests) -- Poll, PollOption, Vote

**Bio Layer (Biomimetic Supervision):**
- `test/sensocto/bio/homeostatic_tuner_test.exs` (6 tests)
- `test/sensocto/bio/resource_arbiter_test.exs` (6 tests)
- `test/sensocto/bio/predictive_load_balancer_test.exs` (7 tests)
- `test/sensocto/bio/circadian_scheduler_test.exs` (9 tests)
- `test/sensocto/bio/novelty_detector_test.exs` (6 tests)
- `test/sensocto/bio/correlation_tracker_test.exs` (11 tests)
- `test/sensocto/bio/sync_computer_test.exs` (8 tests)

**CRDT / Iroh:**
- `test/sensocto/iroh/room_state_crdt_test.exs` (13 tests)
- `test/sensocto/iroh/iroh_automerge_test.exs` (20 tests)

**Media / Object3D:**
- `test/sensocto/media/media_player_server_test.exs` (35 tests)
- `test/sensocto/object3d/object3d_player_server_test.exs` (31 tests)

**Simulator:**
- `test/sensocto/simulator/manager_test.exs` (19 tests) -- Startup phase, state queries, connectors

**Encoding / Types:**
- `test/sensocto/encoding/delta_encoder_test.exs` (11 tests)
- `test/sensocto/types/safe_keys_test.exs` (32 tests)

**Room Markdown:**
- `test/sensocto/room_markdown/room_markdown_test.exs` (50 tests)
- `test/sensocto/room_markdown/admin_protection_test.exs` (16 tests)

**Resilience:**
- `test/sensocto/resilience/circuit_breaker_test.exs` (13 tests)

**Search:**
- `test/sensocto/search/search_index_test.exs` (11 tests)

**Chat:**
- `test/sensocto/chat/chat_store_test.exs` (8 tests)

**Supervision:**
- `test/sensocto/supervision/supervision_tree_test.exs` (31 tests)

**Web Layer:**
- `test/sensocto_web/controllers/error_json_test.exs` (2 tests)
- `test/sensocto_web/controllers/error_html_test.exs` (2 tests)
- `test/sensocto_web/controllers/page_controller_test.exs` (1 test)
- `test/sensocto_web/controllers/health_controller_test.exs` (15 tests)
- `test/sensocto_web/channels/sensor_data_channel_test.exs` (2 tests)
- `test/sensocto_web/openapi_test.exs` (2 tests)
- `test/sensocto_web/plugs/rate_limiter_test.exs` (13 tests)

**LiveView / Component Tests:**
- `test/sensocto_web/live/media_player_component_test.exs` (10 tests)
- `test/sensocto_web/live/object3d_player_component_test.exs` (9 tests)
- `test/sensocto_web/live/stateful_sensor_live_test.exs` (2 tests)
- `test/sensocto_web/live/search_live_test.exs` (4 tests)
- `test/sensocto_web/live/user_directory_live_test.exs` (8 tests)
- `test/sensocto_web/live/lobby_graph_regression_test.exs` (14 tests)
- `test/sensocto_web/live/midi_output_regression_test.exs` (7 tests)
- `test/sensocto_web/live/lobby_backpressure_test.exs` (19 tests)
- `test/sensocto_web/live/mount_optimization_test.exs` (20 tests)
- `test/sensocto_web/components/core_components_test.exs` (10 tests)
- `test/sensocto_web/components/modal_accessibility_test.exs` (14 tests)

**E2E Feature Tests (Wallaby / ChromeDriver):**
- `test/sensocto_web/features/collab_demo_feature_test.exs` (13 tests)
- `test/sensocto_web/features/media_player_feature_test.exs` (20 tests)
- `test/sensocto_web/features/whiteboard_feature_test.exs` (20 tests)
- `test/sensocto_web/features/object3d_player_feature_test.exs` (23 tests)
- `test/sensocto_web/features/auth_flow_feature_test.exs` (5 tests)
- `test/sensocto_web/features/lobby_navigation_feature_test.exs` (7 tests)
- `test/sensocto_web/features/room_feature_test.exs` (3 tests)

---

## E2E Testing Infrastructure

A comprehensive E2E testing framework has been established using Wallaby with ChromeDriver, as documented in `docs/e2e-testing.md`. Key highlights:

- **FeatureCase** with helper module (`SensoctoWeb.FeatureCase.Helpers`) providing navigation, tab switching, control actions, and event simulation
- **Multi-user testing** via multiple Wallaby sessions
- **Device compatibility**: Desktop (1920x1080), Tablet (768x1024), Mobile (390x844)
- **Touch simulation**: `simulate_touch_tap/2`, `simulate_touch_drag/6`
- **Tag-based execution**: `@tag :e2e` (excluded by default), `@tag :multi_user`, `@tag :slow`, `@tag :touch`, `@tag :mobile`
- **CI support**: `CI=true` enables headless Chrome; screenshots saved on failure

Running E2E tests:
```bash
mix test --include e2e                    # All E2E
mix test test/sensocto_web/features/      # Feature tests only
```

---

## Notable Test Patterns

**Regression Guards** (`regression_guards_test.exs`, 49 tests): A "honey badger" approach that tests contracts (message shapes, topic formats, API return values) rather than implementation details. These catch silent breakage during refactoring. This pattern is worth expanding to channel event contracts for the Rust client.

**PriorityLens Buffer Tests** (`priority_lens_buffer_test.exs`): Tests the GenServer-free hot data path via ETS direct writes. Verifies `buffer_for_sensor/2`, `buffer_batch_for_sensor/2`, `get_sockets_for_sensor/1`, and flush timer delivery.

**Backpressure Threshold Tests** (`lobby_backpressure_test.exs`): Pure function tests for load level threshold calculation. Caught the missing `:high` case that was falling through to `:normal`. Uses `async: true` since it tests pure logic.

**Mount Optimization Tests** (`mount_optimization_test.exs`): Integration tests verifying SearchLive sticky mount persistence, LobbyLive deferred subscriptions, and SenseLive deferred signal subscription. Uses `Ash.Seed.seed!` for user setup with JWT authentication.

**Simulator Manager Tests** (`manager_test.exs`): Uses defensive `skip_if_unavailable` pattern since Manager may not be started in test environment. A pragmatic approach for testing supervisor-managed processes.

---

## Complete Livebook Inventory (16 files, 8,713 lines)

| File | Lines | Category | Quality |
|------|-------|----------|---------|
| `test-accessibility-assessment.livemd` | 1,088 | Testing/Accessibility | HIGH |
| `supervisor_mermaid_viz.livemd` | 1,019 | Architecture | HIGH |
| `biomimetic-resilience.livemd` | 1,000 | Architecture/Bio | HIGH |
| `resilience-assessment.livemd` | 811 | Architecture/Ops | HIGH |
| `api-developer-experience.livemd` | 752 | Developer Guide | HIGH |
| `security-assessment.livemd` | 674 | Security | HIGH |
| `object3d_exploration.livemd` | 666 | Feature Exploration | HIGH |
| `livebook-phoenixclient.livemd` | 656 | Client Testing | MEDIUM |
| `ash_neo4j_demo.livemd` | 587 | Integration (outdated*) | LOW |
| `livebook-ash.livemd` | 387 | Domain Documentation | MEDIUM |
| `adaptive_video_quality.livemd` | 358 | Feature Exploration | HIGH |
| `nx_demo_liveview.livemd` | 335 | Tutorial | MEDIUM |
| `livebook.livemd` | 139 | General Exploration | LOW |
| `liveview-processing.livemd` | 120 | Prototype | LOW |
| `map-juggeling.livemd` | 61 | Utility | LOW |
| `supervisors.livemd` | 60 | Sketch (incomplete) | LOW |

*Note: `ash_neo4j_demo.livemd` references Neo4j, which has been removed from the project. This livebook should be archived or deleted.

### Recommended New Livebooks

1. **Channel Contract Explorer** -- Interactive notebook that connects to LobbyChannel and RoomChannel, displays JSON shapes, and validates against Rust struct definitions. Would serve as living documentation for the client API contract.

2. **Guided Session Flow** -- Step-by-step notebook demonstrating guide/follower coordination, drift-back timer behavior, and all 16 GuidedSessionHook message types with mock sockets.

3. **DataGenerator Sandbox** -- Interactive exploration of all sensor type generators (heartrate, IMU, skeleton, HRV, eye gaze, etc.) with VegaLite visualizations of generated waveforms.

4. **Backpressure Pipeline E2E** -- End-to-end notebook tracing a measurement from SimpleSensor through PriorityLens to LobbyLive, visualizing buffer states and quality transitions.

---

## Ecto Schemas (30 Total)

The project has 30 Ecto schemas across domains:
- **Accounts (6):** User, Token, UserPreference, GuestSession, UserConnection, UserSkill
- **Sensors (16):** Sensor, SensorType, SensorAttribute, SensorAttributeData, Room, RoomMembership, RoomSensorType, Connector, ConnectorSensorType, SensorConnection, SensorSensorConnection, SensorManager, SimulatorBatteryState, SimulatorConnector, SimulatorScenario, SimulatorTrackPosition
- **Collaboration (3):** Poll, PollOption, Vote
- **Guidance (1):** GuidedSession
- **Media (2):** Playlist, PlaylistItem
- **Object3D (2):** Object3DPlaylist, Object3DPlaylistItem

---

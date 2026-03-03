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

**Current Testing Status:** Substantial and growing -- **65 test files**, **974 test definitions**, **15,592 total test lines** across unit, integration, E2E (Wallaby), and regression guard tests.

**Livebook Status:** 16 livebooks totaling 8,713 lines. Livebook count stagnant since Feb 16 (over 3 weeks). No new livebooks created.

**Priority Recommendation:** Test the extracted LobbyLive hooks (8 new modules, 2,231 lines, 0% coverage), create tests for the expanded SessionServer (513 lines, 0% coverage), and add simulator DataGenerator/AttributeServer tests. Livebooks for the lobby hook architecture and backpressure pipeline would be high-value additions.

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

Despite the extraction, `lobby_live.ex` remains large at 3,138 lines, indicating the core lens/sensor logic is still inline. The hook modules use Phoenix LiveView's `attach_hook` pattern and follow a consistent `on_handle_info/2` callback structure with `{:halt, socket}` returns.

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

**Remaining simulator gaps:** DataGenerator (1,392 lines, pure math functions -- ideal for property-based testing), AttributeServer (406 lines, recently refactored with ~85 lines of churn), SensorServer (408 lines).

#### 5. Session Server Changes

`SessionServer` grew from ~417 to 513 lines. Changes in commit `2797fa9` include expanded guide/follower coordination. The module still has **0% test coverage** despite being a complex GenServer with timer-based state management.

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

### Updated Metrics

| Metric | Feb 24 | Mar 1 | Change |
|--------|--------|-------|--------|
| Test Files | 65 | **65** | +0 (new files created in the Feb 22-24 batch) |
| Test Definitions | ~780 | **974** | +194 (+25%) |
| Total Test Lines | ~9,500 | **15,592** | +6,092 (+64%) |
| Ecto Schemas | 30 | **30** | No change |
| Ash Domains | 6 | **6** | No change |
| Livebook Count | 16 | **16** | Stagnant (3+ weeks) |
| Docs Count | 20 | **22** | +2 (liveview-architecture.md, midi-output.md) |
| Lobby Extracted Modules | 0 | **8** | NEW architecture |
| Guidance Test Coverage | 0% | **0%** | Still untested |
| Simulator Test Coverage | 0% | **~15%** | Manager only |

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

## Complete Test File Inventory (65 files, 974 tests, 15,592 lines)

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
- `test/sensocto_web/live/midi_output_regression_test.exs` (10 tests)
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

**Regression Guards** (`regression_guards_test.exs`, 49 tests): A "honey badger" approach that tests contracts (message shapes, topic formats, API return values) rather than implementation details. These catch silent breakage during refactoring. This pattern is worth expanding to other subsystems.

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

## Remaining Gaps and Recommendations

### Critical Gaps

#### 1. Extracted Lobby Hooks -- 0% Coverage (HIGH PRIORITY)

The lobby refactoring created 8 new modules (2,231 lines total) with zero test coverage. These hooks are the integration glue for guided sessions, media, object3D, whiteboard, and calls within the lobby.

| Hook Module | Lines | Testing Strategy |
|-------------|-------|-----------------|
| `guided_session_hook.ex` | 182 | Mock socket assigns, verify PubSub message routing and assign updates |
| `media_hook.ex` | 140 | Test event delegation to MediaPlayerServer |
| `object3d_hook.ex` | 156 | Test event delegation to Object3DPlayerServer |
| `whiteboard_hook.ex` | 131 | Test event delegation to WhiteboardComponent |
| `call_hook.ex` | 70 | Test call initiation/termination events |
| `components.ex` | 412 | Render tests for extracted function components |
| `sensor_detail_live.ex` | 909 | Mount and event tests for sensor detail view |
| `sensor_compare_live.ex` | 231 | Mount and comparison logic tests |

#### 2. Guided Session System -- Still 0%

SessionServer (513 lines), GuidedSession Ash resource, SessionSupervisor, and JoinLive all remain untested. The `guided_session_hook.ex` extraction makes this even more urgent since the hook delegates to SessionServer but neither has tests.

#### 3. Calls System -- Still 0%

CallServer, QualityManager, SnapshotManager, CallChannel remain untested.

#### 4. Simulator DataGenerator and AttributeServer -- 0%

DataGenerator (1,392 lines) contains pure mathematical functions for ECG waveforms, GPS interpolation, and battery curves. AttributeServer (406 lines) was recently refactored. Both are prime candidates for unit testing.

#### 5. New LiveViews Without Tests

- `profile_live.ex` -- significantly expanded with privacy settings
- `user_settings_live.ex` -- new module
- `devices_live.ex` -- device management with rename/forget
- `magic_sign_in_live.ex` -- magic link authentication flow
- `sensor_detail_live.ex` -- extracted from lobby, 909 lines
- `sensor_compare_live.ex` -- extracted from lobby, 231 lines

#### 6. Search Index Privacy Filtering

The `search_index.ex` received privacy-related changes. Existing `search_index_test.exs` should be reviewed and extended to cover visibility/privacy filtering logic.

#### 7. Outdated Content

- `ash_neo4j_demo.livemd` references Neo4j, which has been removed from the project

### Priority Recommendations

**Immediate (This Sprint):**

1. **Test extracted lobby hooks** -- Start with `guided_session_hook.ex` (most complex at 182 lines) and `components.ex` (412 lines of function components). These are self-contained modules with clear input/output contracts.
2. **Test SessionServer** -- 513 lines of complex GenServer logic with timers, now the highest-risk untested module.
3. **Test DataGenerator pure functions** -- 1,392 lines of mathematical logic. Property-based testing with StreamData would verify ECG waveform bounds, GPS coordinate validity, and battery curve monotonicity.
4. **Review search_index_test.exs** -- Ensure privacy filtering changes are covered.
5. **Archive or delete `ash_neo4j_demo.livemd`** -- References removed dependency.

**Short-term (2-4 Weeks):**

1. **Create `backpressure-pipeline.livemd`** -- Interactive notebook tracing data flow from SystemLoadMonitor through PriorityLens quality adjustment to LobbyLive threshold response. Visualize with VegaLite charts showing quality transitions under load.
2. **Create `lobby-hooks-architecture.livemd`** -- Document the new hook extraction pattern with Mermaid diagrams showing message flow through each hook.
3. **Test sensor_detail_live.ex and sensor_compare_live.ex** -- Largest extracted modules at 909 and 231 lines.
4. **End-to-end backpressure test** -- Integration test that applies load via SystemLoadMonitor, verifies PriorityLens quality degradation, and confirms LobbyLive responds with appropriate threshold adjustments.

**Medium-term (1-2 Months):**

1. **CallServer integration tests** -- WebRTC participant lifecycle
2. **Full E2E for sensor data flow** -- Connect via channel, send measurement, verify it appears in lobby LiveView
3. **Property-based testing for AttributeServer** -- Test data generation, attribute routing, and cleanup under concurrent load
4. **Create `guided-session-lifecycle.livemd`** -- Interactive exploration of guide/follower coordination with PubSub observation
5. **Create `data-generator-waveforms.livemd`** -- Plot ECG, breathing, HRV waveforms with VegaLite for visual verification

---

## Testing Infrastructure Quality Assessment

### Strengths

- **Well-structured E2E framework**: Wallaby setup with FeatureCase helpers, multi-user support, device viewport simulation, and proper tag-based execution gating
- **Regression guard pattern**: The "honey badger" approach in `regression_guards_test.exs` (49 tests) is excellent -- testing contracts rather than implementations
- **Consistent test isolation**: Most tests use `System.unique_integer([:positive])` for unique IDs, avoiding cross-test interference
- **Accessibility testing**: Two dedicated test files for ARIA attributes, keyboard navigation, and focus management in modals
- **Integration tests**: ButtonState visualization tests create real processes and verify the full PubSub pipeline
- **Backpressure coverage**: New tests for PriorityLens buffer, Router demand-driven subscription, SystemLoadMonitor, and lobby threshold calculation provide strong coverage of the hot data path
- **Defensive test patterns**: The `skip_if_unavailable` pattern in Manager tests handles optional supervisor-managed processes gracefully

### Areas for Improvement

- **No test factories or shared fixture module**: Each test file creates its own helpers (e.g., `create_user/1` in room_test.exs). A shared factory module would reduce duplication
- **No property-based testing**: StreamData is not yet used anywhere. DataGenerator is the ideal first candidate
- **No test coverage tooling**: No excoveralls or similar tool configured
- **Limited channel tests**: `sensor_data_channel_test.exs` is only 2 tests with basic join/broadcast
- **Async test ratio**: Many tests use `async: false` -- reviewing which can safely use `async: true` would improve test suite speed
- **Hook modules untested**: The lobby refactoring created 8 new modules (2,231 lines) with 0% coverage, representing the largest untested surface area in the codebase

### Documentation Ecosystem

The docs/ directory contains 22 markdown files providing comprehensive coverage:

| Category | Files |
|----------|-------|
| Architecture | `architecture.md`, `supervision-tree.md`, `attention-system.md`, `liveview-architecture.md` |
| Operations | `deployment.md`, `beam-vm-tuning.md`, `scalability.md` |
| Development | `getting-started.md`, `e2e-testing.md`, `attributes.md`, `api-attributes-reference.md` |
| Integration | `simulator-integration.md`, `membrane-webrtc-integration.md`, `iroh-room-storage-architecture.md` |
| Planning | `CLUSTERING_PLAN.md`, `VISION.md` + 5 plan docs in `plans/` directory |
| Features | `room-markdown-format.md`, `modal-accessibility-implementation.md`, `letsgobio.md`, `midi-output.md` |
| Infrastructure | `tidewave-production.md`, `github-agents.md` |

Combined with 16 livebooks and 65 test files (974 test definitions), the project has a mature documentation and testing foundation.

---

## Architecture Notes (Updated)

### Key Changes Since Last Report

1. **Lobby refactored into hook architecture** -- 5 hook modules (`guided_session`, `media`, `object3d`, `whiteboard`, `call`) extracted from LobbyLive, following Phoenix LiveView's `attach_hook` pattern. Each hook has a consistent `on_handle_info/2` interface.
2. **Sensor detail and compare views extracted** -- `sensor_detail_live.ex` (909 lines) and `sensor_compare_live.ex` (231 lines) separated from LobbyLive.
3. **Components extracted** -- `lobby_live/components.ex` (412 lines) contains function components previously inline in LobbyLive.
4. **SystemLoadMonitor** tested -- ETS-based load level reads, memory protection, PubSub broadcasts on transitions.
5. **SessionServer expanded** -- 513 lines (up from ~417), with additional guide/follower coordination logic.
6. **Profile and privacy system** -- ProfileLive significantly expanded, `is_public` default changed to false.
7. **Simulator AttributeServer refactored** -- ~85 lines of churn, simplified data generation flow.
8. **New docs** -- `liveview-architecture.md` (552 lines) documents the LiveView module structure. `midi-output.md` documents MIDI integration.

### Data Pipeline (Current)

```
SimpleSensor -> PubSub (data:attention:{level}) -> Router -> PriorityLens ETS -> flush timer -> PubSub (lens:priority:{socket_id}) -> LobbyLive
```

Hot path is GenServer-free (ETS `:public` tables for direct writes).

### Backpressure Feedback Loop (Updated)

```
SystemLoadMonitor (ETS) -> load level broadcast -> LobbyLive adjusts thresholds
                                                -> PriorityLens adjusts quality/flush interval
LobbyLive mailbox size -> backpressure/critical -> quality downgrade request to PriorityLens
Consecutive healthy checks (2) + delay (8s) -> quality upgrade request to PriorityLens
```

Quality levels scale flush intervals: `:high` (32ms) -> `:medium` (50ms) -> `:low` (100ms) -> `:paused` (200ms). All non-paused quality levels use `max_sensors: :unlimited` per project memory.

---

## Gamification -- Test Coverage Progress

### Achievements Earned

| Achievement | Status | Details |
|-------------|--------|---------|
| **First Blood** | EARNED | Many modules now have first tests |
| **OTP Guardian** | EARNED | SimpleSensor, throttle, AttentionTracker, PriorityLens+buffer, Router, RoomStore, RoomServer, SystemLoadMonitor, SensorsDynSup all tested |
| **Room Champion** | PARTIAL | Room Ash resource + RoomStore + RoomServer tested; RoomShowLive not yet |
| **Bio Master** | EARNED | All 7 bio modules have comprehensive tests (including CorrelationTracker, SyncComputer) |
| **Accessibility Advocate** | EARNED | Modal and core component ARIA tests |
| **E2E Pioneer** | EARNED | 7 Wallaby feature test files |
| **Regression Sentinel** | EARNED | Contract-based regression guards (49 tests) |
| **Backpressure Guardian** | EARNED | PriorityLens buffer, Router, SystemLoadMonitor, lobby thresholds, mount optimization all tested |
| **Markdown Master** | EARNED | RoomMarkdown + admin protection: 66 tests |
| **Simulator Scout** | PARTIAL | Manager tested (19 tests), DataGenerator/AttributeServer/SensorServer still at 0% |

### Remaining Challenges

| Achievement | Criteria | Progress |
|-------------|----------|----------|
| **Ash Master** | Test all Ash resource actions | ~5/30 schemas covered |
| **Guidance Guardian** | Full Guided Session lifecycle tests | 0% |
| **Hook Hero** | Test all extracted lobby hooks | 0% (8 modules, 2,231 lines) |
| **Channel Surfer** | Full channel message coverage | ~10% |
| **Call Expert** | WebRTC integration tests | 0% |
| **Simulator Sage** | All data generators tested | ~15% (Manager only) |
| **LiveView Legend** | All LiveViews have tests | ~20% |
| **Property Prover** | StreamData property tests | 0% |

### Current Coverage Estimate

```
Core OTP:        |=========.| ~90%
Backpressure:    |=========.| ~90%
Bio Layer:       |==========| 100%
CRDT/Iroh:       |========..| ~80%
Media/Object3D:  |==========| 100%
Ash Resources:   |==........| ~17%
Channels:        |=.........| ~10%
Call System:     |..........| 0%
Simulator:       |==........| ~15%
LiveViews:       |===.......| ~25%
Lobby Hooks:     |..........| 0%
Web/Plugs:       |====......| ~35%
Guidance:        |..........| 0%
E2E Features:    |=====.....| ~45%
Room Markdown:   |==========| 100%
Types/Encoding:  |==========| 100%
```

Overall estimated module coverage: ~35-40%

---

*Report updated: 2026-03-01*
*Analysis by: Livebook Tester Agent (Claude Opus 4.6)*

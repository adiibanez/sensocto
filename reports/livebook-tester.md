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

**Current Testing Status:** Substantial and growing -- **33 test files** with **456 test cases** across unit, integration, E2E (Wallaby), and regression guard tests.

**Livebook Status:** 16 livebooks totaling 8,713 lines, covering architecture, security, resilience, API developer experience, biomimetic patterns, and accessibility.

**Priority Recommendation:** Expand Ash resource test coverage (only Room tested so far), add property-based testing for sensor payloads, create QualityManager tests, and consolidate the data pipeline / lobby lens testing.

---

## Update: February 16, 2026

### Testing Status -- Significant Growth Since January

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

### Complete Test File Inventory (33 files)

**Core OTP / Data Pipeline:**
- `test/sensocto/otp/simple_sensor_test.exs` -- SimpleSensor GenServer
- `test/sensocto/otp/attribute_store_tiered_test.exs` -- Tiered attribute storage
- `test/sensocto/otp/attention_tracker_test.exs` -- Attention level management
- `test/sensocto/otp/button_state_visualization_test.exs` -- Button press/release integration
- `test/sensocto/lenses/priority_lens_test.exs` -- Reactive backpressure, quality tiers
- `test/sensocto/regression_guards_test.exs` -- Data pipeline contract guards

**Ash Resources:**
- `test/sensocto/sensors/room_test.exs` -- Room resource create/read/update actions
- `test/sensocto/sensors/attribute_store_test.exs` -- Legacy attribute store (may be outdated)

**Bio Layer (Biomimetic Supervision):**
- `test/sensocto/bio/homeostatic_tuner_test.exs`
- `test/sensocto/bio/resource_arbiter_test.exs`
- `test/sensocto/bio/predictive_load_balancer_test.exs`
- `test/sensocto/bio/circadian_scheduler_test.exs`
- `test/sensocto/bio/novelty_detector_test.exs`

**CRDT / Iroh:**
- `test/sensocto/iroh/room_state_crdt_test.exs`
- `test/sensocto/iroh/iroh_automerge_test.exs`

**Media / Object3D:**
- `test/sensocto/media/media_player_server_test.exs` -- Complete GenServer coverage
- `test/sensocto/object3d/object3d_player_server_test.exs` -- Complete GenServer coverage

**Supervision:**
- `test/sensocto/supervision/supervision_tree_test.exs` -- Hierarchy verification

**Web Layer:**
- `test/sensocto_web/controllers/error_json_test.exs`
- `test/sensocto_web/controllers/error_html_test.exs`
- `test/sensocto_web/controllers/page_controller_test.exs`
- `test/sensocto_web/channels/sensor_data_channel_test.exs`
- `test/sensocto_web/openapi_test.exs` -- OpenAPI 3.x spec validation
- `test/sensocto_web/plugs/rate_limiter_test.exs` -- Rate limiting with ETS

**LiveView / Component Tests:**
- `test/sensocto_web/live/media_player_component_test.exs`
- `test/sensocto_web/live/object3d_player_component_test.exs`
- `test/sensocto_web/live/stateful_sensor_live_test.exs`
- `test/sensocto_web/components/core_components_test.exs` -- ARIA/accessibility
- `test/sensocto_web/components/modal_accessibility_test.exs` -- Focus management, keyboard nav

**E2E Feature Tests (Wallaby / ChromeDriver):**
- `test/sensocto_web/features/collab_demo_feature_test.exs` -- Cross-component collaboration
- `test/sensocto_web/features/media_player_feature_test.exs` -- Media player E2E
- `test/sensocto_web/features/whiteboard_feature_test.exs` -- Whiteboard E2E
- `test/sensocto_web/features/object3d_player_feature_test.exs` -- 3D viewer E2E

### E2E Testing Infrastructure

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

### Notable New Test Patterns

**Regression Guards** (`regression_guards_test.exs`): A "honey badger" approach that tests contracts (message shapes, topic formats, API return values) rather than implementation details. These catch silent breakage during refactoring. This pattern is worth expanding to other subsystems.

**PriorityLens Tests**: Verify the removal of preemptive quality throttling -- quality always starts at `:high` regardless of sensor count, validating the reactive backpressure design.

**AttentionTracker Tests**: Cover the attention level lifecycle (`:none` -> `:medium` -> `:high`), multi-user view registration, and hover tracking.

**ButtonState Visualization Tests**: Integration tests that create actual SimpleSensor processes, send button events through PubSub, and verify PriorityLens buffering.

### Complete Livebook Inventory (16 files, 8,713 lines)

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

**New since January 20:**
- `security-assessment.livemd` (674 lines) -- Platform security audit with OWASP framework
- `biomimetic-resilience.livemd` (1,000 lines) -- Bio-inspired patterns (immune memory, synaptic pruning, quorum sensing)
- `api-developer-experience.livemd` (752 lines) -- Interactive API guide with Kino forms for REST and WebSocket
- `test-accessibility-assessment.livemd` (1,088 lines) -- Testing coverage and accessibility audit
- `resilience-assessment.livemd` (811 lines) -- Live supervision tree visualization and resilience metrics

### Ecto Schemas (24 Total)

The project now has 24 Ecto schemas across domains:
- **Accounts (4):** User, Token, UserPreference, GuestSession
- **Sensors (14):** Sensor, SensorType, SensorAttribute, SensorAttributeData, Room, RoomMembership, RoomSensorType, Connector, ConnectorSensorType, SensorConnection, SensorSensorConnection, SensorManager, SimulatorBatteryState, SimulatorConnector, SimulatorScenario, SimulatorTrackPosition
- **Media (2):** Playlist, PlaylistItem
- **Object3D (2):** Object3DPlaylist, Object3DPlaylistItem

### Source Changes in Progress (Git Status)

Active modifications on main branch:
- `lib/sensocto_web/live/lobby_live.ex` -- Lobby LiveView changes
- `lib/sensocto_web/live/index_live.ex` -- Index LiveView changes
- `lib/sensocto_web/live/tabbed_footer_live.ex` -- Tabbed footer
- `lib/sensocto_web/live/helpers/sensor_data.ex` -- NEW shared helper for sensor data transformation (used by both LobbyLive and IndexLive)
- `lib/sensocto_web/live/components/about_content_component.ex` -- About content
- `assets/svelte/LobbyGraph.svelte` -- Lobby graph Svelte component
- `assets/js/hooks.js` -- JS hooks updates

The new `SensoctoWeb.LiveHelpers.SensorData` module is a refactoring that extracts shared logic (`group_sensors_by_user/1`) for both LobbyLive and IndexLive. This is a good candidate for unit testing.

---

## Remaining Gaps and Recommendations

### Critical Gaps

#### 1. Ash Resource Tests -- Only Room Covered

Only `Sensocto.Sensors.Room` has Ash resource tests. The following resources have zero test coverage:

| Resource | Actions | Risk |
|----------|---------|------|
| `Sensocto.Sensors.Sensor` | create, read, update | HIGH -- core entity |
| `Sensocto.Accounts.User` | register, sign_in | HIGH -- authentication |
| `Sensocto.Sensors.SensorAttribute` | create, read | MEDIUM |
| `Sensocto.Sensors.Connector` | create, read | MEDIUM |
| `Sensocto.Media.Playlist` | CRUD | MEDIUM |
| `Sensocto.Object3D.Object3DPlaylist` | CRUD | MEDIUM |

**Recommendation:** Use the pattern established in `room_test.exs` (Ash.Seed.seed! for setup, Ash.Changeset.for_create for actions) and extend to Sensor and User resources first.

#### 2. No Call System Tests

- `CallServer` -- WebRTC coordination via Membrane RTC Engine, untested
- `QualityManager` (`lib/sensocto/calls/quality_manager.ex`) -- Pure functions, straightforward to test
- `SnapshotManager` -- untested

**Recommendation:** Start with QualityManager since it contains pure functions with no process dependencies.

#### 3. No Simulator Tests

DataGenerator, TrackPlayer, BatteryState remain untested. These modules generate ECG waveforms, GPS track interpolation, and battery drain curves -- all with mathematical logic that benefits from property-based testing.

**Recommendation:** Use StreamData for property-based testing of DataGenerator output ranges and waveform characteristics.

#### 4. No LobbyLive / Data Pipeline Integration Tests

The lobby lens system (LobbyLive + PriorityLens + Router + AttentionTracker) is the most complex data path in the application. While individual components (PriorityLens, AttentionTracker) now have tests, there are no integration tests for the full pipeline including composite lenses (heartrate, ECG, breathing).

The new `SensoctoWeb.LiveHelpers.SensorData` module also lacks tests.

#### 5. Outdated Content

- `ash_neo4j_demo.livemd` references Neo4j, which has been removed from the project
- `attribute_store_test.exs` may reference outdated modules (flagged since January)
- The architecture overview in this report still listed Neo4j under "Graph (Ash Domain)" -- now corrected

### Priority Recommendations

**Immediate (This Sprint):**

1. **Test `SensoctoWeb.LiveHelpers.SensorData`** -- New shared helper module, pure functions, easy to test
2. **Create QualityManager tests** -- Pure function module in the call system
3. **Archive or delete `ash_neo4j_demo.livemd`** -- References removed Neo4j dependency
4. **Expand regression guards** -- Add contracts for attention level changes, composite lens data shapes, PubSub topic formats

**Short-term (2-4 Weeks):**

1. **Ash resource tests for Sensor and User** -- Follow the Room test pattern
2. **Simulator DataGenerator tests** -- Property-based testing with StreamData for ECG waveform bounds, GPS coordinate validity
3. **Create `data_pipeline_exploration.livemd`** -- Interactive notebook documenting SimpleSensor -> PubSub -> Router -> PriorityLens -> LobbyLive flow with live tracing
4. **Lobby composite lens integration tests** -- Test `extract_composite_data/1` tuple shapes and all destructuring sites

**Medium-term (1-2 Months):**

1. **CallServer integration tests** -- WebRTC participant lifecycle
2. **Full E2E for sensor data flow** -- Connect via channel, send measurement, verify it appears in lobby LiveView
3. **Performance benchmarking livebook** -- Benchmark PriorityLens ETS write throughput, attention level switching latency
4. **Property-based testing expansion** -- StreamData for all sensor type payloads (ECG, IMU, HTML5, Thingy52)

---

## Testing Infrastructure Quality Assessment

### Strengths

- **Well-structured E2E framework**: Wallaby setup with FeatureCase helpers, multi-user support, device viewport simulation, and proper tag-based execution gating
- **Regression guard pattern**: The "honey badger" approach in `regression_guards_test.exs` is excellent -- testing contracts rather than implementations
- **Consistent test isolation**: Most tests use `System.unique_integer([:positive])` for unique IDs, avoiding cross-test interference
- **Accessibility testing**: Two dedicated test files for ARIA attributes, keyboard navigation, and focus management in modals
- **Integration tests**: ButtonState visualization tests create real processes and verify the full PubSub pipeline

### Areas for Improvement

- **No test factories or shared fixture module**: Each test file creates its own helpers (e.g., `create_user/1` in room_test.exs). A shared factory module would reduce duplication
- **No property-based testing**: StreamData is not yet used anywhere
- **No test coverage tooling**: No excoveralls or similar tool configured
- **Limited channel tests**: `sensor_data_channel_test.exs` is only 28 lines with basic join/broadcast tests
- **Async test ratio**: Many tests use `async: false` -- reviewing which can safely use `async: true` would improve test suite speed

### Documentation Ecosystem

The docs/ directory contains 20 markdown files providing comprehensive coverage:

| Category | Files |
|----------|-------|
| Architecture | `architecture.md`, `supervision-tree.md`, `attention-system.md` |
| Operations | `deployment.md`, `beam-vm-tuning.md`, `scalability.md` |
| Development | `getting-started.md`, `e2e-testing.md`, `attributes.md`, `api-attributes-reference.md` |
| Integration | `simulator-integration.md`, `membrane-webrtc-integration.md`, `iroh-room-storage-architecture.md` |
| Planning | `CLUSTERING_PLAN.md`, `VISION.md` |
| Features | `room-markdown-format.md`, `modal-accessibility-implementation.md`, `letsgobio.md` |
| Infrastructure | `tidewave-production.md`, `github-agents.md` |

Combined with 16 livebooks and 33 test files, the project has a mature documentation and testing foundation that continues to grow.

---

## Architecture Notes (Updated)

### Key Changes Since Last Report

1. **Neo4j removed** -- No more graph database. The Graph Ash domain no longer exists.
2. **Sensor data helper extraction** -- `SensoctoWeb.LiveHelpers.SensorData` centralizes `group_sensors_by_user/1` for LobbyLive and IndexLive.
3. **7-Layer supervision tree** -- The application now uses a layered supervision architecture: Infrastructure, Registry, Storage, Bio, Domain, plus Endpoint and Auth layers.
4. **Attention-aware routing** is fully operational with sharded PubSub topics (`data:attention:high`, `data:attention:medium`, `data:attention:low`).
5. **GuestSession** added to Accounts domain (24th Ecto schema).

### Data Pipeline (Current)

```
SimpleSensor -> PubSub (data:attention:{level}) -> Router -> PriorityLens ETS -> flush timer -> PubSub (lens:priority:{socket_id}) -> LobbyLive
```

Hot path is GenServer-free (ETS `:public` tables for direct writes).

---

## Gamification -- Test Coverage Progress

### Achievements Earned

| Achievement | Status | Details |
|-------------|--------|---------|
| **First Blood** | EARNED | Many modules now have first tests |
| **OTP Guardian** | PARTIAL | SimpleSensor, AttentionTracker, PriorityLens tested; Router, RoomServer still missing |
| **Room Champion** | PARTIAL | Room Ash resource tested; RoomServer, RoomStore not yet |
| **Bio Master** | EARNED | All 5 bio modules have comprehensive tests |
| **Accessibility Advocate** | EARNED | Modal and core component ARIA tests |
| **E2E Pioneer** | EARNED | 4 Wallaby feature test files |
| **Regression Sentinel** | EARNED | Contract-based regression guards |

### Remaining Challenges

| Achievement | Criteria | Progress |
|-------------|----------|----------|
| **Ash Master** | Test all Ash resource actions | 1/24 schemas |
| **Channel Surfer** | Full channel message coverage | ~10% |
| **Call Expert** | WebRTC integration tests | 0% |
| **Simulator Sage** | All data generators tested | 0% |
| **LiveView Legend** | All LiveViews have tests | ~15% |
| **Property Prover** | StreamData property tests | 0% |

### Current Coverage Estimate

```
Core OTP:        ████████░░  ~80% (SimpleSensor, AttentionTracker, PriorityLens, AttributeStoreTiered)
Bio Layer:       ██████████  100% (All 5 modules)
CRDT/Iroh:       ████████░░  ~80% (RoomStateCRDT, Automerge)
Media/Object3D:  ██████████  100% (Both player servers)
Ash Resources:   █░░░░░░░░░  ~4% (Room only)
Channels:        █░░░░░░░░░  ~10% (Basic channel join)
Call System:     ░░░░░░░░░░  0%
Simulator:       ░░░░░░░░░░  0%
LiveViews:       ██░░░░░░░░  ~15% (Components, stateful sensor)
Web/Plugs:       ███░░░░░░░  ~30% (RateLimiter, OpenAPI, Controllers)
E2E Features:    ████░░░░░░  ~40% (Collab demos covered)
```

Overall estimated module coverage: ~30-35%

---

*Report updated: 2026-02-16*
*Analysis by: Livebook Tester Agent (Claude Opus 4.6)*

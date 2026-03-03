# Sensocto API Client Development Report

**Generated:** 2026-01-24
**Last Updated:** 2026-03-01
**Status:** Comprehensive Review with Dependency Updates, New Routes, and Cross-SDK Audit

---

## Executive Summary

The Sensocto platform provides four client SDKs (Unity/C#, Rust, Python, TypeScript/Three.js) for connecting to the sensor streaming platform. All SDKs are functionally complete for core use cases including sensor data streaming, video/voice calls, and backpressure handling. However, a critical cross-SDK model mismatch remains: the server sends `backpressure_config` events with 8 fields, but only Rust and TypeScript SDKs model all key fields. Unity and Python SDKs are missing critical fields (`paused`, `system_load`, `load_multiplier`), and ALL SDKs are missing `memory_protection_active`.

Since the last review (2026-02-24), development focus has been on platform resilience, UI improvements (graphs, whiteboard, profiles, privacy, audio/MIDI), new lobby routes (`/lobby/graph3d`, `/lobby/hierarchy`), poll features, user profiles, and dependency maintenance across all SDKs. A Connector REST API (`GET/PUT/DELETE /api/connectors`) and token refresh (`POST /api/auth/refresh`) endpoint are now documented in the OpenAPI spec. No new WebSocket channel events or REST endpoints were added in this period.

### Key Findings (2026-03-01)

| Area | Status | Priority |
|------|--------|----------|
| BackpressureConfig Model Mismatch | Unity + Python missing critical fields | **Critical** |
| `memory_protection_active` field | Missing from ALL SDKs | **Critical** |
| New Attribute Types (Eye Tracking) | `eye_gaze`, `eye_blink`, `eye_worn`, `eye_aperture` not in any SDK model | High |
| New Attribute Type (Skeleton) | `skeleton` not in any SDK model | High |
| `update_connector` event | Server supports it, NO SDK exposes it | High |
| HydrationChannel | New channel, no SDK support or docs | High |
| SyncComputer (Kuramoto Sync) | Server-side sync data exposed via composite events, no SDK access | Medium |
| Test Coverage | Python SDK tests still empty | Medium |
| Python Reconnection Logic | Config exists but not implemented | Medium |
| `request_quality_tier` event | Undocumented in SDKs | Medium |
| Guided Sessions -- No REST API | Feature exists, LiveView-only, no mobile SDK access | **High** |
| Package Publishing | Not published to registries | Low |

### Changes Since Last Review (2026-02-24 to 2026-03-01)

| Change | Impact |
|--------|--------|
| Rust SDK: `bytes` bumped 1.11.0 to 1.11.1 (PR #63) | Minor dependency maintenance, no API change |
| Rust SDK: `SDK_NAME` constant added as `"sensocto-rust"` (PR #49) | Rust now has identification constant; Unity, Python, TypeScript still lack one |
| Three.js SDK: `rollup` bumped 4.55.1 to 4.59.0 (PR #64) | Build tooling update, no runtime change |
| Three.js SDK: `esbuild`, `@vitest/coverage-v8`, `vitest` bumped (PR #55) | Dev dependency update, no runtime change |
| Python SDK: `aiohttp` bumped 3.10.11 to 3.13.3 (PR #54) | Runtime dependency update; drops Python 3.8 support in aiohttp itself |
| Python SDK: minimum Python version bumped to 3.9 in `pyproject.toml` | `requires-python = ">=3.9"` now; classifiers still list 3.8 (stale) |
| Python SDK: `uv.lock` revision updated from 1 to 3, drops Python <3.9 resolution markers | Lock file simplified, no longer resolves for Python 3.8 |
| New lobby routes: `/lobby/graph3d`, `/lobby/hierarchy` | LiveView-only, no SDK impact |
| Guided session improvements (commit `ce729b2`: "improvements to guide, whiteboard") | Continued iteration on guided sessions; still LiveView-only |
| User profiles, graph views, privacy features (commit `e53fb41`) | LiveView-only, no SDK impact |
| Audio/MIDI system improvements | Client-side JS only, no SDK impact |
| Poll system | Collaboration domain; no REST API endpoints for polls yet |
| Chat component fixes | LiveView-only, no SDK impact |
| `ash_admin` bumped 0.13.24 to 0.13.26 (PR #72) | Admin UI only, no SDK impact |

### Python SDK: Version Mismatch Warning

The `pyproject.toml` now specifies `requires-python = ">=3.9"` and the `uv.lock` no longer resolves dependencies for Python 3.8. However, the classifiers list still includes `"Programming Language :: Python :: 3.8"` and the tool configs (`[tool.black]`, `[tool.ruff]`, `[tool.mypy]`) still target Python 3.8. These should be updated to 3.9 for consistency:

- `classifiers`: Remove `"Programming Language :: Python :: 3.8"`
- `[tool.black] target-version`: Change to `["py39", "py310", "py311", "py312"]`
- `[tool.ruff] target-version`: Change to `"py39"`
- `[tool.mypy] python_version`: Change to `"3.9"`

---

## CRITICAL FINDING: BackpressureConfig Model Mismatch

### Server Payload (sensor_data_channel.ex)

The server's `get_backpressure_config/1` function returns 8 fields:

```elixir
%{
  attention_level: attention_level,
  system_load: system_load,
  memory_protection_active: memory_protection_active,
  paused: paused,
  recommended_batch_window: final_batch_window,
  recommended_batch_size: base_batch_size,
  load_multiplier: final_multiplier,
  timestamp: System.system_time(:millisecond)
}
```

### SDK Field Coverage Matrix

| Field | Server | Rust | TypeScript | Unity | Python |
|-------|--------|------|------------|-------|--------|
| `attention_level` | Yes | Yes | Yes | Yes | Yes |
| `recommended_batch_window` | Yes | Yes | Yes | Yes | Yes |
| `recommended_batch_size` | Yes | Yes | Yes | Yes | Yes |
| `timestamp` | Yes | Yes | Yes | Yes | Yes |
| `paused` | Yes | Yes | Yes | **NO** | **NO** |
| `system_load` | Yes | Yes | Yes | **NO** | **NO** |
| `load_multiplier` | Yes | Yes | Yes | **NO** | **NO** |
| `memory_protection_active` | Yes | **NO** | **NO** | **NO** | **NO** |

### Impact Analysis

**Unity and Python SDKs** will silently ignore the `paused` field. When the server activates memory protection mode (pausing low/none attention sensors), these SDKs will continue sending data, potentially worsening the memory pressure situation they are supposed to help relieve.

**All SDKs** are missing `memory_protection_active`. While `paused` is the actionable field (clients should stop sending when `paused: true`), `memory_protection_active` provides valuable diagnostic information about why backpressure is being applied.

### Pause Conditions (from server code)

The server sets `paused: true` under two conditions:
1. **Memory protection active** AND attention is `low` or `none`
2. **Critical system load** AND attention is `low` or `none`

When memory protection is active, non-paused sensors (high/medium attention) receive a 5x multiplier to their batch window.

### Behavioral Comparison of paused Handling

**Rust SDK** (`clients/rust/src/models.rs`, `channel.rs`):
- `BackpressureConfig` includes `paused`, `system_load` (as `SystemLoadLevel` enum), `load_multiplier`
- `should_pause()` and `effective_batch_window()` helper methods
- Checks `paused` before `send_measurement` (returns error)
- Checks `paused` before auto-flush in `add_to_batch`
- Checks `paused` before `flush_batch` (unless `force`)
- Exposes `is_paused()` async method
- Force-flushes on close even when paused

**TypeScript SDK** (`clients/threejs/src/models.ts`, `sensor.ts`):
- `BackpressureConfig` interface includes `paused`, `systemLoad`, `loadMultiplier`
- `parseBackpressureConfig()` correctly maps all fields from server payload
- `isPaused` getter on SensorStream
- Checks `paused` before `sendMeasurement`, `addToBatch`, `flushBatch`
- Force-flush on close even when paused

**Unity SDK** (`clients/unity/SensoctoSDK/Runtime/Models.cs`): No `paused` field in `BackpressureConfig`, `FromPayload()` only parses 4 fields, no pause checks in `BackpressureManager`

**Python SDK** (`clients/python/sensocto/models.py`): No `paused` field in `BackpressureConfig`, `from_payload()` only parses 4 fields, no pause checks anywhere

---

## FINDING: Attribute Type Expansion (Eye Tracking + Skeleton)

### New Attribute Types

The `AttributeType` module now includes 48 attribute types across 8 categories. The following are the newer types that have no SDK model support:

#### Eye Tracking Category (`:eye_tracking`)

| Type | Payload Fields | Description |
|------|----------------|-------------|
| `eye_gaze` | `x`, `y`, `confidence` | Eye gaze direction with confidence score |
| `eye_blink` | `value` | Blink detection |
| `eye_worn` | `value` | Whether eye tracker is being worn |
| `eye_aperture` | `left`, `right` | Eye aperture (openness) per eye |

#### Pose/Skeleton Category (within `:motion`)

| Type | Payload Fields | Description |
|------|----------------|-------------|
| `skeleton` | `landmarks` | Full body pose tracking landmarks |

### SDK Impact

No SDK currently includes models for these attribute types. While the SDKs can still receive and forward the raw payload data (they do not strictly validate attribute types), adding typed models would improve developer experience through autocomplete, type safety, and documentation.

### Composite View Coverage

The server's `has_composite_view?/1` function recognizes these attribute types for composite (multi-sensor) visualization: `heartrate`, `hr`, `imu`, `geolocation`, `ecg`, `battery`, `spo2`, `skeleton`, `respiration`, `hrv`, `eye_gaze`, `eye_aperture`.

---

## FINDING: Server-Side Synchronization Computing

### SyncComputer (Kuramoto Phase Synchronization)

A `Sensocto.Bio.SyncComputer` GenServer computes real-time interpersonal physiological synchronization using the Kuramoto order parameter. This is a demand-driven system that only activates when viewers are present.

| Aspect | Details |
|--------|---------|
| Location | `lib/sensocto/bio/sync_computer.ex` |
| Algorithm | Kuramoto order parameter with exponential smoothing (alpha=0.15) |
| Data sources | Breathing (`respiration`) and HRV (`hrv`) sensors |
| Output | Stored as attributes under `__composite_sync` sensor in `AttributeStoreTiered` |

**SDK Impact:** Currently internal only, exposed via LiveView composite events. If REST endpoints are added for sync data, SDKs will need new models.

---

## FINDING: Guided Sessions -- API Surface for Mobile Clients

### Overview

The Guided Sessions feature enables a **guide** to lead a **follower** through the sensor lobby in real time. The guide's navigation actions (lens changes, sensor focus, annotations, suggested actions) are broadcast to the follower via PubSub. The follower can temporarily "break away" to explore independently, then either manually rejoin or be automatically drifted back after a configurable timeout (5-120 seconds, default 15).

### Architecture Components

| Component | Location | Role |
|-----------|----------|------|
| `Sensocto.Guidance` | `lib/sensocto/guidance.ex` | Ash domain (with AshAdmin) |
| `GuidedSession` | `lib/sensocto/guidance/guided_session.ex` | Ash resource (PostgreSQL-backed) |
| `SessionServer` | `lib/sensocto/guidance/session_server.ex` | GenServer managing real-time state |
| `SessionSupervisor` | `lib/sensocto/guidance/session_supervisor.ex` | DynamicSupervisor with Registry lookup |
| `GuidedSessionJoinLive` | `lib/sensocto_web/live/guided_session_join_live.ex` | LiveView for accepting invites |

### Ash Resource: GuidedSession

**Table:** `guided_sessions`

| Attribute | Type | Constraints | Notes |
|-----------|------|-------------|-------|
| `id` | UUID | PK | Auto-generated |
| `status` | atom | `:pending`, `:active`, `:ended`, `:declined` | Starts as `:pending` |
| `guide_user_id` | UUID | required | Set via argument on `:create` |
| `follower_user_id` | UUID | nullable, public | Set when follower accepts |
| `room_id` | UUID | nullable, public | Optional room scope |
| `invite_code` | string | required, unique | 6-char alphanumeric (no ambiguous chars: O/0/I/1 excluded) |
| `drift_back_seconds` | integer | 5-120, default 15 | How long before follower auto-rejoins |
| `started_at` | utc_datetime_usec | nullable | Set on `:accept` |
| `ended_at` | utc_datetime_usec | nullable | Set on `:decline` or `:end_session` |

**Actions:**

| Action | Type | Accepts | Effect |
|--------|------|---------|--------|
| `:create` | create | `follower_user_id`, `room_id`, `drift_back_seconds` + arg `guide_user_id` | Creates session with status `:pending`, generates invite code |
| `:accept` | update | (none) | Sets status `:active`, sets `started_at` |
| `:decline` | update | (none) | Sets status `:declined`, sets `ended_at` |
| `:end_session` | update | (none) | Sets status `:ended`, sets `ended_at` |
| `:by_invite_code` | read | arg `invite_code` | Finds pending/active session by code |
| `:active_for_user` | read | arg `user_id` | Lists active sessions where user is guide or follower |

### SessionServer: Real-Time State

The SessionServer GenServer manages the live state of an active session.

**Client API (GenServer calls/casts):**

| Function | Role | Type | Returns |
|----------|------|------|---------|
| `get_state(session_id)` | Any | call | `{:ok, state_map}` or `{:error, :not_found}` |
| `set_lens(session_id, user_id, lens)` | Guide | call | `:ok` or `{:error, :not_guide}` |
| `set_focused_sensor(session_id, user_id, sensor_id)` | Guide | call | `:ok` or `{:error, :not_guide}` |
| `add_annotation(session_id, user_id, annotation)` | Guide | call | `:ok` or `{:error, :not_guide}` |
| `suggest_action(session_id, user_id, action)` | Guide | call | `:ok` or `{:error, :not_guide}` |
| `break_away(session_id, user_id)` | Follower | call | `:ok` or `{:error, :not_follower}` |
| `report_activity(session_id, user_id)` | Follower | cast | (fire-and-forget, resets drift timer) |
| `rejoin(session_id, user_id)` | Follower | call | `{:ok, %{lens, focused_sensor_id}}` or `{:error, :not_follower}` |
| `end_session(session_id, user_id)` | Either | call | `:ok` (stops GenServer) |
| `connect(session_id, user_id)` | Either | cast | (marks user connected, broadcasts presence) |
| `disconnect(session_id, user_id)` | Either | cast | (marks disconnected, starts idle timeout for guide) |

**PubSub Events (broadcast on `guidance:{session_id}`):**

| Event | Payload | Trigger |
|-------|---------|---------|
| `{:guided_lens_changed, %{lens: atom}}` | Lens atom | Guide calls `set_lens` |
| `{:guided_sensor_focused, %{sensor_id: string}}` | Sensor ID | Guide calls `set_focused_sensor` |
| `{:guided_annotation, %{annotation: map}}` | Annotation with auto-generated `:id` | Guide calls `add_annotation` |
| `{:guided_suggestion, %{action: any}}` | Suggested action | Guide calls `suggest_action` |
| `{:guided_break_away, %{follower_user_id: uuid}}` | Follower ID | Follower calls `break_away` |
| `{:guided_drift_back, %{lens: atom, focused_sensor_id: any}}` | Current guide state | Drift-back timer fires |
| `{:guided_rejoin, %{follower_user_id: uuid}}` | Follower ID | Follower calls `rejoin` |
| `{:guided_presence, %{guide_connected: bool, follower_connected: bool, following: bool}}` | Presence state | `connect` or `disconnect` |
| `{:guided_ended, %{ended_by: uuid or :idle_timeout}}` | Who ended it | `end_session` or 5-min idle timeout |

### Current Gap: No REST or WebSocket API for Mobile

There are **no REST endpoints** and **no dedicated WebSocket channel** for guided sessions. The router has no `/api/guidance/*` routes. Mobile SDK support requires:

1. REST endpoints for session lifecycle (create, accept, decline, end, lookup by invite code)
2. A WebSocket channel (`guidance:{session_id}`) for real-time event delivery (lens changes, annotations, drift-back, presence)
3. SDK models for `GuidedSession` and `GuidedSessionState`

### Recommended REST API Endpoints

#### Session Lifecycle (Guide)

| Method | Path | Purpose |
|--------|------|---------|
| POST | `/api/guidance/sessions` | Create a new guided session |
| GET | `/api/guidance/sessions/:id` | Get session details + state |
| GET | `/api/guidance/sessions/active` | List active sessions for current user |
| DELETE | `/api/guidance/sessions/:id` | End a session |

#### Session Lifecycle (Follower)

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/api/guidance/sessions/by-code/:code` | Look up session by invite code |
| POST | `/api/guidance/sessions/:id/accept` | Accept invitation and join |
| POST | `/api/guidance/sessions/:id/decline` | Decline invitation |

#### Real-Time Actions (via WebSocket channel or REST)

| Method | Path | Role | Purpose |
|--------|------|------|---------|
| POST | `/api/guidance/sessions/:id/lens` | Guide | Set current lens |
| POST | `/api/guidance/sessions/:id/focus` | Guide | Focus on a sensor |
| POST | `/api/guidance/sessions/:id/annotate` | Guide | Add annotation |
| POST | `/api/guidance/sessions/:id/suggest` | Guide | Suggest action |
| POST | `/api/guidance/sessions/:id/break-away` | Follower | Stop following temporarily |
| POST | `/api/guidance/sessions/:id/rejoin` | Follower | Resume following |
| POST | `/api/guidance/sessions/:id/activity` | Follower | Report activity (reset drift timer) |

### Recommended WebSocket Channel for Real-Time Events

REST endpoints alone are insufficient for the follower experience. A dedicated Guidance Channel is recommended:

```elixir
# In user_socket.ex
channel "guidance:*", SensoctoWeb.GuidanceChannel
```

Channel events would map directly to existing PubSub events:

| Server-to-Client Event | Payload | Source PubSub Event |
|------------------------|---------|---------------------|
| `lens_changed` | `{lens: string}` | `:guided_lens_changed` |
| `sensor_focused` | `{sensor_id: string}` | `:guided_sensor_focused` |
| `annotation` | `{id, text, ...}` | `:guided_annotation` |
| `suggestion` | `{action: string}` | `:guided_suggestion` |
| `break_away` | `{follower_user_id: string}` | `:guided_break_away` |
| `drift_back` | `{lens: string, focused_sensor_id: string}` | `:guided_drift_back` |
| `rejoin` | `{follower_user_id: string}` | `:guided_rejoin` |
| `presence` | `{guide_connected, follower_connected, following}` | `:guided_presence` |
| `ended` | `{ended_by: string}` | `:guided_ended` |

### Mobile UX Considerations

1. **Invite Code Entry**: The 6-character code uses an unambiguous alphabet (no O/0/I/1). Mobile SDKs should provide a dedicated invite code input with uppercase filtering and validation.
2. **Drift-Back Timer**: When the follower breaks away, they have `drift_back_seconds` (default 15s) before being pulled back. Mobile SDKs should expose this countdown.
3. **Idle Timeout**: If the guide disconnects for 5 minutes, the session auto-ends. Mobile clients should handle this gracefully.
4. **Presence Tracking**: The `connect`/`disconnect` cast calls should be sent on app foreground/background transitions.
5. **Offline Resilience**: If the follower loses connectivity briefly, they should rejoin the guidance channel on reconnect and request current state via `get_state`.

---

## DX Deep Dive Analysis

### New Developer Onboarding Friction Assessment

#### Critical Friction Points

| Issue | Severity | Impact |
|-------|----------|--------|
| **Phoenix Channel Protocol Knowledge Required** | High | Developers must understand Phoenix-specific message formats (`ref`, `join_ref`, heartbeat protocol) |
| **Undocumented Backpressure Response Contract** | High | `backpressure_config` events pushed to clients but no guidance on how clients should respond |
| **Memory Protection Protocol Undocumented** | Medium | System can activate memory protection mode that pauses low-priority sensors |
| **Guest Token Format Secret** | Medium | Guest tokens use `guest:{id}:{token}` format but this is not documented externally |
| **Attribute Type Validation** | Medium | 48 valid attribute types but no client-side validation utilities in SDKs |

#### Positive DX Elements Found

| Element | Implementation | Location |
|---------|---------------|----------|
| **OpenAPI Spec** | Full spec with Swagger UI | `/api/openapi`, `/swaggerui` |
| **Type System** | Comprehensive `AttributeType` module (48 types) | `lib/sensocto/types/attribute_type.ex` |
| **Health Endpoints** | Kubernetes-ready liveness/readiness | `/health/live`, `/health/ready` |
| **Rate Limiting** | ETS-based sliding window with headers | `lib/sensocto_web/plugs/rate_limiter.ex` |
| **Internationalization** | Gettext with 8 languages | `priv/gettext/` |
| **Connector REST API** | Full CRUD with OpenAPI specs | `/api/connectors` |
| **Token Refresh** | HttpOnly cookie auth + refresh endpoint | `/api/auth/refresh` |

### Client-Side Resilience Patterns Required

Based on server analysis, clients MUST implement these patterns:

#### 1. Backpressure Response Handler

```javascript
channel.on("backpressure_config", (config) => {
  if (config.paused) {
    pauseDataTransmission();
    startLocalQueue();
  } else if (config.memory_protection_active) {
    setThrottleMultiplier(5.0);
  } else {
    setBatchWindow(config.recommended_batch_window);
    setBatchSize(config.recommended_batch_size);
  }
});
```

#### 2. Reconnection with Channel Rejoin

On reconnect, clients must:
1. Re-establish WebSocket connection with exponential backoff
2. Re-join ALL previously joined channels with same parameters
3. Re-subscribe to PubSub topics (attention, system load)
4. Request fresh backpressure config via `:send_backpressure_config`

### API Resilience Assessment

| Feature | Status | Notes |
|---------|--------|-------|
| **Rate Limit Headers** | Implemented | `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After` |
| **Request IDs** | Not present | Add `X-Request-ID` for distributed tracing |
| **API Versioning** | None | Implement `/api/v1/` prefix |
| **Idempotency Keys** | Not supported | Add for POST/PUT mutations |
| **Error Codes** | Strings only | Add numeric codes for programmatic handling |

### SDK Testing Infrastructure Audit

| SDK | Unit Tests | Integration Tests | Mock Server |
|-----|------------|-------------------|-------------|
| Rust | Present | Missing | Missing |
| Unity | N/A (manual) | N/A | N/A |
| Python | **Empty** | Missing | Missing |
| TypeScript | Present | Missing | Missing |

**Critical**: Python SDK test directory (`clients/python/sensocto/tests/__init__.py`) contains only a docstring. No actual test implementations exist.

---

## Planned Work: SDK and API Implications

### 1. Room Persistence: PostgreSQL to In-Memory + Iroh Docs

**Plan:** `PLAN-room-iroh-migration.md`
**Status:** Planned

**SDK Impact: MEDIUM** -- Rooms may take 1-3 seconds to appear after a server cold start (Iroh hydration is async). SDKs should handle empty room lists gracefully. No API endpoint changes.

### 2. Adaptive Video Quality for Massive Scale Calls

**Plan:** `PLAN-adaptive-video-quality.md`
**Status:** 100% Complete (implemented 2026-01-16)

**SDK Impact: HIGH -- New channel events already deployed but not documented in SDKs**

| New Channel Event | Direction | SDK Coverage |
|-------------------|-----------|--------------|
| `speaking_state` | Client -> Server | Not in any SDK |
| `attention_state` | Client -> Server | Not in any SDK |
| `video_snapshot` | Client -> Server | Not in any SDK |
| `request_quality_tier` | Client -> Server | Not in any SDK |
| `tier_changed` | Server -> Client | Rust has `QualityChanged` event |
| `quality_tier_request` | Server -> Client | Not in any SDK |
| `participant_speaking` | Server -> Client | Not in any SDK |

**Quality Tiers (already deployed):**

| Tier | Mode | Resolution | Bandwidth |
|------|------|------------|-----------|
| `:active` | Full Video | 720p @ 30fps | ~2.5 Mbps |
| `:recent` | Reduced Video | 480p @ 15fps | ~500 Kbps |
| `:viewer` | Snapshot | 240p @ 1fps JPEG | ~50-100 Kbps |
| `:idle` | Static Avatar | N/A | ~0 |

### 3. Delta Encoding for High-Frequency ECG Data

**Status:** Planned (feature-flagged off)

**SDK Impact: HIGH** -- When enabled, SDKs need delta decoders:
- Read 1-byte header (version in lower nibble)
- Read 8-byte base timestamp (int64 LE)
- Read 4-byte first value (float32 LE)
- Read deltas: int8 value delta (0x80 = reset marker) + uint16 timestamp delta (LE)
- Quantization step: 0.01 mV per int8 unit

### 4. Distributed Discovery System

**Status:** Planned

**SDK Impact: MEDIUM** -- New REST endpoints (`GET /api/sensors`, `GET /api/sensors/:id`) when shipped.

### 5. Sensor Scaling Refactor

**Status:** Partially implemented (attention-based sharded PubSub is live)

**SDK Impact: MEDIUM** -- Sensor-specific topic `data:sensor:{sensor_id}` enables direct subscriptions. Per-socket ETS buffers in PriorityLens are implemented. When exposed via API, SDKs will need `subscribeTo(sensorId)` and `requestHistory(sensorId, from, to)` methods.

### 6. Research-Grade Synchronization Metrics

**Status:** Partially implemented (SyncComputer with Kuramoto order parameter is live)

**SDK Impact: HIGH** -- Major new API surface for analysis. New REST endpoints needed:
- `GET /api/sessions/:id/sync-report` -- Fetch sync analysis results
- `POST /api/sessions/:id/sync-report` -- Trigger sync report generation

### Planned Work Summary: SDK Update Matrix

| Plan | Rust | TypeScript | Unity | Python | Priority |
|------|------|------------|-------|--------|----------|
| Room Iroh Migration | None | None | None | None | - |
| Adaptive Video Quality | Add events | Add events | Add events | Add events | High |
| Sensor Component Migration | None | None | None | None | - |
| Startup Optimization | None | None | None | None | - |
| Delta Encoding ECG | Add decoder | Add decoder | Add decoder | Add decoder | High |
| Cluster Sensor Visibility | None | None | None | None | - |
| Distributed Discovery | Add sensor list API | Add sensor list API | Add sensor list API | Add sensor list API | Medium |
| Sensor Scaling Refactor | Add subscribe/history | Add subscribe/history | Add subscribe/history | Add subscribe/history | Medium |
| Research Sync Metrics | None | Add report viewer | None | Add analysis API | Medium |
| TURN/Cloudflare | Verify ICE config | Verify ICE config | Verify ICE config | Verify ICE config | Low |
| Guided Sessions | Add guide+follower API | Add guide+follower API | Add guide+follower API | Add programmatic guide API | High |

---

## Current API Surface

### WebSocket Channels (Phoenix Channels)

#### User Socket (`/socket/websocket`)

**Endpoint:** `wss://{server}/socket/websocket`

| Channel Topic | Handler | Purpose |
|--------------|---------|---------|
| `sensocto:sensor:{sensor_id}` | SensorDataChannel | Real-time sensor data streaming |
| `sensocto:connector:{connector_id}` | SensorDataChannel | Connector registration |
| `sensocto:lvntest:{connector_id}` | SensorDataChannel | LiveView Native test connector |
| `call:{room_id}` | CallChannel | WebRTC signaling for video/voice calls |
| `hydration:room:{room_id}` | HydrationChannel | Client-side room snapshot storage |
| `guidance:{session_id}` | *(not yet implemented)* | Guided session real-time events (proposed) |

#### Bridge Socket (`/bridge/websocket`)

**Endpoint:** `wss://{server}/bridge/websocket`

| Channel Topic | Handler | Purpose |
|--------------|---------|---------|
| `bridge:control` | BridgeChannel | Iroh bridge control channel |
| `bridge:topic:{topic}` | BridgeChannel | Subscribe to Phoenix PubSub topics |

### REST API Endpoints

#### Authentication
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET/POST | `/api/auth/verify` | MobileAuthController | Verify JWT token |
| GET | `/api/me` | MobileAuthController | Get current user info |
| POST | `/api/auth/refresh` | MobileAuthController | Refresh auth token |
| POST | `/api/auth/debug` | MobileAuthController | Debug token verification (dev only) |

#### Rooms
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/api/rooms` | RoomController | List user's rooms |
| GET | `/api/rooms/public` | RoomController | List public rooms |
| GET | `/api/rooms/:id` | RoomController | Get room details |
| GET | `/api/rooms/:id/ticket` | RoomTicketController | Generate P2P room ticket |
| GET | `/api/rooms/by-code/:code/ticket` | RoomTicketController | Get ticket by join code |
| POST | `/api/rooms/verify-ticket` | RoomTicketController | Verify room ticket |

#### Connectors
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/api/connectors` | ConnectorController | List user's connectors |
| GET | `/api/connectors/:id` | ConnectorController | Get connector with sensors |
| PUT | `/api/connectors/:id` | ConnectorController | Update connector (rename) |
| DELETE | `/api/connectors/:id` | ConnectorController | Forget a connector |

#### Guest Authentication
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/auth/guest/:guest_id/:token` | GuestAuthController | Guest user sign-in |

#### Health Checks
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/health/live` | HealthController | Liveness probe (shallow) |
| GET | `/health/ready` | HealthController | Readiness probe (deep) |

### Phoenix LiveView (Browser-Only)

LiveView routes require browser sessions with CSRF protection:
- `/` - Index page with sigma graph preview and rooms
- `/lobby/*` - Real-time sensor monitoring dashboard (16 sub-routes: sensors, heartrate, imu, location, ecg, battery, skeleton, breathing, hrv, gaze, favorites, users, graph, graph3d, hierarchy, plus sensor detail and compare)
- `/rooms/*` - Room management and viewing
- `/simulator` - Sensor simulation interface
- `/settings` - User settings
- `/profile` - User profile
- `/users` - User directory with graph view
- `/polls` - Collaboration polls
- `/guide/join` - Guided session invite acceptance
- `/devices` - My devices page
- `/ai-chat` - AI chat interface
- `/system-status` - System status dashboard

---

## Client Platforms

### Unity/C# SDK

**Location:** `clients/unity/SensoctoSDK/`
**Status:** Production-ready but missing critical backpressure fields

**Strengths:** Unity-idiomatic ScriptableObject config, async/await, event-driven, thread-safe, auto-reconnection (1s-30s backoff), serial port integration, deep link auth, `ShouldFlushImmediate()` for high attention

**Critical Issues:**
- BackpressureConfig missing `paused`, `system_load`, `load_multiplier`, `memory_protection_active`
- `FromPayload()` (Models.cs) only parses 4 of 8 fields
- `BackpressureManager.cs` has no pause check
- Missing `SDK_NAME` and `VERSION` constants
- No models for new attribute types (eye tracking, skeleton)
- No Connector REST API methods

### Rust SDK

**Location:** `clients/rust/`
**Status:** Most complete SDK alongside TypeScript

**Strengths:** Idiomatic Rust, async tokio, builder pattern, thiserror errors, `SDK_NAME = "sensocto-rust"`, full backpressure with `paused`/`system_load`/`load_multiplier`, `should_pause()` + `effective_batch_window()`, pause checks in all send paths, force-flush on close

**Issues:** Missing `memory_protection_active`, `blocking` feature flag not implemented, examples commented out, no models for new attribute types (eye tracking, skeleton), no Connector REST API methods

**Recent Changes:**
- `bytes` dependency bumped 1.11.0 to 1.11.1 (PR #63, minor maintenance)
- `SDK_NAME` constant added as `"sensocto-rust"` (PR #49)

### Python SDK

**Location:** `clients/python/`
**Status:** Functional but incomplete

**Strengths:** Async context manager, type hints, Pydantic models, good error hierarchy, `__version__` exposed

**Critical Issues:**
- BackpressureConfig missing `paused`, `system_load`, `load_multiplier`, `memory_protection_active`
- Tests directory empty
- Reconnection not implemented (config exists, socket does not use it)
- Missing `SDK_NAME`
- No models for new attribute types (eye tracking, skeleton)
- No Connector REST API methods

**Recent Changes:**
- `aiohttp` bumped 3.10.11 to 3.13.3 (PR #54) -- significant upgrade
- Minimum Python version bumped to 3.9 in `requires-python` but tool configs still target 3.8 (inconsistency)
- `uv.lock` simplified: no longer resolves for Python <3.9

### TypeScript/Three.js SDK

**Location:** `clients/threejs/`
**Status:** Feature-complete with best backpressure handling

**Strengths:** Full TypeScript, `BackpressureConfig` with `paused`/`systemLoad`/`loadMultiplier`, `parseBackpressureConfig()`, `isPaused` getter, pause checks everywhere, force-flush on close, handler unsubscribe pattern, ESM + CJS

**Issues:** Missing `memory_protection_active`, missing `SDK_NAME`, no models for new attribute types (eye tracking, skeleton), no Connector REST API methods

**Recent Changes:**
- `rollup` bumped 4.55.1 to 4.59.0 (PR #64)
- `esbuild`, `@vitest/coverage-v8`, `vitest` bumped (PR #55)

### Livebook/Elixir

**Status:** Interactive `livebooks/api-developer-experience.livemd` available. Additional livebooks added for resilience assessment, security assessment, and biomimetic resilience. Not formally packaged.

---

## WebSocket Protocol

### Connection Flow

```
1. Connect to wss://{server}/socket/websocket
2. Heartbeat every 30s to "phoenix" topic
3. Join channel with topic + params (auth happens here)
4. Exchange messages
5. Leave / disconnect
```

### Sensor Data Channel Protocol

#### Client-to-Server Events

| Event | Payload | Description |
|-------|---------|-------------|
| `measurement` | `{attribute_id, payload, timestamp}` | Single measurement |
| `measurements_batch` | `[{attribute_id, payload, timestamp}, ...]` | Batch of measurements |
| `update_attributes` | `{action, attribute_id, metadata}` | Attribute registry update |
| `update_connector` | `{connector_name}` | Rename connector (1-100 bytes) |
| `ping` | any | Connection test |
| `shout` | any | Broadcast to all subscribers |

#### Backpressure Configuration
```json
{
  "attention_level": "high|medium|low|none",
  "system_load": "normal|elevated|high|critical",
  "memory_protection_active": false,
  "paused": false,
  "recommended_batch_window": 500,
  "recommended_batch_size": 5,
  "load_multiplier": 1.0,
  "timestamp": 1706000000000
}
```

### Call Channel Protocol

#### Client-to-Server Events

| Event | Payload | Description |
|-------|---------|-------------|
| `join_call` | none | Join the call |
| `leave_call` | none | Leave the call |
| `media_event` | `{data: {...}}` | WebRTC signaling |
| `toggle_audio` | `{enabled: bool}` | Toggle audio |
| `toggle_video` | `{enabled: bool}` | Toggle video |
| `set_quality` | `{quality: "high\|medium\|low"}` | Set quality |
| `speaking_state` | `{speaking: bool}` | Voice activity |
| `attention_state` | `{level: "high\|medium\|low"}` | Viewer attention |
| `video_snapshot` | `{data, width, height, timestamp}` | Snapshot for low-tier |
| `get_participants` | none | Request participant list |
| `request_quality_tier` | `{target_user_id, tier}` | Request quality adjustment |

#### Server-to-Client Events

| Event | Payload | Description |
|-------|---------|-------------|
| `participant_joined` | participant object | Someone joined |
| `participant_left` | `{user_id, crashed?}` | Someone left |
| `media_event` | `{data: {...}}` | WebRTC signaling |
| `quality_changed` | `{quality}` | Quality changed |
| `tier_changed` | `{user_id, tier}` | Adaptive tier changed |
| `quality_tier_request` | `{from_user_id, target_user_id, tier}` | Quality request |
| `participant_audio_changed` | `{user_id, enabled}` | Audio state |
| `participant_video_changed` | `{user_id, enabled}` | Video state |
| `participant_speaking` | `{user_id, speaking}` | Speaking state |
| `video_snapshot` | `{user_id, data, ...}` | Snapshot broadcast |
| `call_ended` | none | Call terminated |

### Bridge Channel Protocol

Iroh P2P bridge with envelope format (version 1), `publish`/`subscribe`/`unsubscribe`/`heartbeat` events. Optional token-based auth.

### Hydration Channel Protocol

**Topic:** `hydration:room:{room_id}` (supports `*` wildcard)

Client-to-server: `snapshot:offer`, `snapshot:data`, `snapshot:batch_offer`, `snapshot:stored`
Server-to-client: `snapshot:request`, `snapshot:store`, `snapshot:delete`

---

## Authentication

| Method | Format | Where Used |
|--------|--------|-----------|
| JWT Bearer Token | Standard JWT (AshAuthentication) | REST API + Channel join params |
| Guest Token | `guest:{guest_id}:{token}` | Channel join params |
| Development Token | `"missing"` literal | Channel join (bypass -- TODO disable in prod) |
| Basic Auth | Env vars | Admin routes |
| Magic Link | Email-based authentication | Sign-in flow |

**Socket-Level:** UserSocket accepts ALL connections. Auth deferred to channel join. BridgeSocket has optional token validation.

**Rate Limiting:** ETS sliding window. Auth: 10/60s, Registration: 5/60s, API auth: 20/60s, Guest: 10/60s. POST only. Headers: `X-RateLimit-*`, `Retry-After`.

---

## Complete Attribute Types Reference (48 Types)

### By Category

| Category | Types | Count |
|----------|-------|-------|
| Health/Cardiac | `ecg`, `hrv`, `hr`, `heartrate`, `spo2`, `respiration` | 6 |
| Motion/IMU | `imu`, `accelerometer`, `gyroscope`, `magnetometer`, `quaternion`, `euler`, `heading`, `gravity`, `tap`, `orientation`, `skeleton` | 11 |
| Location | `geolocation`, `altitude`, `speed` | 3 |
| Environment | `temperature`, `humidity`, `pressure`, `light`, `proximity`, `gas`, `air_quality`, `color` | 8 |
| Device | `battery`, `button`, `led`, `speaker`, `microphone`, `body_location`, `rich_presence` | 7 |
| Activity | `steps`, `calories`, `distance` | 3 |
| Specialty | `buttplug` | 1 |
| Eye Tracking | `eye_gaze`, `eye_blink`, `eye_worn`, `eye_aperture` | 4 |

### Eye Tracking Payload Fields

| Type | Fields | Example Payload |
|------|--------|-----------------|
| `eye_gaze` | `x`, `y`, `confidence` | `{"x": 0.5, "y": 0.3, "confidence": 0.95}` |
| `eye_blink` | `value` | `{"value": true}` |
| `eye_worn` | `value` | `{"value": true}` |
| `eye_aperture` | `left`, `right` | `{"left": 0.8, "right": 0.75}` |

### Skeleton Payload Fields

| Type | Fields | Example Payload |
|------|--------|-----------------|
| `skeleton` | `landmarks` | `{"landmarks": [{...}, ...]}` |

---

## Summary Recommendations

### Immediate Actions (Priority: Critical)

1. **Add `paused`, `system_load`, `load_multiplier` to Unity BackpressureConfig**
2. **Add `paused`, `system_load`, `load_multiplier` to Python BackpressureConfig**
3. **Add `memory_protection_active` to ALL SDK BackpressureConfig models**
4. **Add pause checks to Unity BackpressureManager and Python sensor streaming**

### Short-term Actions (Priority: High)

5. **Add Guided Sessions REST API + WebSocket channel** -- Create `/api/guidance/*` endpoints and `guidance:*` channel on UserSocket so mobile clients can participate as guide or follower
6. **Add GuidedSession and GuidedSessionState models** to Unity and TypeScript SDKs (primary mobile platforms)
7. **Add eye tracking attribute models** (`EyeGaze`, `EyeBlink`, `EyeWorn`, `EyeAperture`) to all SDKs
8. **Add skeleton/pose attribute model** (`Skeleton` with `landmarks` field) to all SDKs
9. **Implement Python reconnection logic** -- Config exists but socket has no reconnection code
10. **Add Python SDK tests** -- Currently empty directory
11. **Expose `update_connector` event in SDKs**
12. **Add Connector REST API methods** to all SDKs (`GET/PUT/DELETE /api/connectors`)
13. **Fix Python SDK version config inconsistency** -- Update tool configs from 3.8 to 3.9 targets
14. **Add SDK_NAME and VERSION constants** to Unity, Python, and TypeScript SDKs
15. **Document adaptive video quality events** in SDK call session classes

### Medium-term Actions (Priority: Medium)

16. **Prepare delta decoders** for each SDK ahead of delta encoding rollout
17. **Publish SDKs** to package registries (crates.io, PyPI, npm, OpenUPM)
18. **Add `blocking` API** to Rust SDK
19. **Add sync wrapper** for Python SDK
20. **Create cross-SDK backpressure handling guide**
21. **Add sensor listing API** when Distributed Discovery ships
22. **Document HydrationChannel protocol** in SDK docs
23. **Document marine/coral attribute types** in SDK attribute enums (currently in docs but not in `AttributeType` module)

### Long-term Actions (Priority: Low)

24. **Create Elixir/Livebook SDK** with Kino integration
25. **Add binary protocol option** for high-frequency data
26. **Implement API versioning** strategy
27. **Build developer portal** with interactive docs
28. **Add WebWorker support** to TypeScript SDK
29. **Add sync report API** to Python SDK when research sync metrics ship
30. **Verify ICE server propagation** across all SDKs for TURN support

---

## Appendix A: Channel Join Parameters Reference

### Sensor Channel
```typescript
interface SensorJoinParams {
  connector_id: string;
  connector_name: string;
  sensor_id: string;
  sensor_name: string;
  sensor_type: string;
  attributes: string[];
  sampling_rate: number;
  batch_size: number;
  bearer_token: string;
}
```

### Call Channel
```typescript
interface CallJoinParams {
  user_id: string;
  user_info?: { name?: string; avatar?: string; [key: string]: any; };
}
```

### Connector Channel
```typescript
interface ConnectorJoinParams {
  connector_id: string;
  connector_name: string;
  connector_type: string;
  features: string[];
  bearer_token: string;
}
```

### Hydration Channel
```typescript
interface HydrationJoinParams {
  offers?: Array<{ room_id: string; version: number; checksum?: string; }>;
}
```

---

## Appendix B: Error Codes

| Code | Category | Description | Recoverable |
|------|----------|-------------|-------------|
| `unauthorized` | Auth | Invalid or expired token | Yes (refresh) |
| `invalid_attribute_id` | Validation | Attribute ID format invalid | No |
| `invalid_action` | Validation | Unknown action for update_attributes | No |
| `missing_fields` | Validation | Required fields missing | No |
| `invalid_batch` | Validation | Batch validation failed | No |
| `invalid_connector_name` | Validation | Connector name empty or >100 bytes | No |
| `call_full` | Call | Room at capacity | Yes (wait) |
| `not_room_member` | Auth | User not in room | No |
| `not_in_call` | State | Action requires being in call | Yes (join first) |

---

## Appendix C: File Locations

### SDK Source Files

| SDK | Location |
|-----|----------|
| Unity | `clients/unity/SensoctoSDK/Runtime/` |
| Rust | `clients/rust/src/` |
| Python | `clients/python/sensocto/` |
| TypeScript | `clients/threejs/src/` |

### Server Channel Files

| Channel | Location |
|---------|----------|
| SensorDataChannel | `lib/sensocto_web/channels/sensor_data_channel.ex` |
| CallChannel | `lib/sensocto_web/channels/call_channel.ex` |
| BridgeChannel | `lib/sensocto_web/channels/bridge_channel.ex` |
| HydrationChannel | `lib/sensocto_web/channels/hydration_channel.ex` |
| UserSocket | `lib/sensocto_web/channels/user_socket.ex` |
| BridgeSocket | `lib/sensocto_web/channels/bridge_socket.ex` |

### API Controllers

| Controller | Location |
|-----------|----------|
| MobileAuthController | `lib/sensocto_web/controllers/api/mobile_auth_controller.ex` |
| RoomController | `lib/sensocto_web/controllers/api/room_controller.ex` |
| RoomTicketController | `lib/sensocto_web/controllers/api/room_ticket_controller.ex` |
| ConnectorController | `lib/sensocto_web/controllers/api/connector_controller.ex` |
| HealthController | `lib/sensocto_web/controllers/health_controller.ex` |
| GuestAuthController | `lib/sensocto_web/controllers/guest_auth_controller.ex` |

### Key Server Modules

| Module | Location | Purpose |
|--------|----------|---------|
| AttributeType | `lib/sensocto/types/attribute_type.ex` | 48 attribute type definitions |
| SyncComputer | `lib/sensocto/bio/sync_computer.ex` | Kuramoto phase synchronization |
| CircuitBreaker | `lib/sensocto/resilience/circuit_breaker.ex` | Fault isolation |
| Guidance Domain | `lib/sensocto/guidance.ex` | Ash domain for guided sessions |
| GuidedSession | `lib/sensocto/guidance/guided_session.ex` | Ash resource: session lifecycle + invite codes |
| SessionServer | `lib/sensocto/guidance/session_server.ex` | GenServer: real-time guide/follower state |
| SessionSupervisor | `lib/sensocto/guidance/session_supervisor.ex` | DynamicSupervisor for SessionServer processes |
| GuidedSessionJoinLive | `lib/sensocto_web/live/guided_session_join_live.ex` | LiveView for invite code acceptance |
| SensorData Helper | `lib/sensocto_web/live/helpers/sensor_data.ex` | Shared sensor data helpers |

### Documentation

| Document | Location |
|----------|----------|
| API Attributes Reference | `docs/api-attributes-reference.md` |
| Getting Started | `docs/getting-started.md` |
| Architecture | `docs/architecture.md` |
| Simulator Integration | `docs/simulator-integration.md` |
| Attention System | `docs/attention-system.md` |
| Supervision Tree | `docs/supervision-tree.md` |
| API Developer Experience Livebook | `livebooks/api-developer-experience.livemd` |
| OpenAPI Spec Module | `lib/sensocto_web/api_spec.ex` |
| Rate Limiter | `lib/sensocto_web/plugs/rate_limiter.ex` |

---

*Report generated by api-client-developer agent*
*Last review: 2026-03-01*

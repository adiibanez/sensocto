# Sensocto API Client Development Report

**Generated:** 2026-01-24
**Last Updated:** 2026-02-08
**Status:** Comprehensive Review with DX Deep Dive and Cross-SDK Audit

---

## Executive Summary

The Sensocto platform provides four client SDKs (Unity/C#, Rust, Python, TypeScript/Three.js) for connecting to the sensor streaming platform. All SDKs are functionally complete for core use cases including sensor data streaming, video/voice calls, and backpressure handling. However, a critical cross-SDK model mismatch has been identified: the server sends `backpressure_config` events with 8 fields, but only Rust and TypeScript SDKs model all key fields. Unity and Python SDKs are missing critical fields (`paused`, `system_load`, `load_multiplier`), and ALL SDKs are missing `memory_protection_active`.

### Key Findings (2026-02-08)

| Area | Status | Priority |
|------|--------|----------|
| BackpressureConfig Model Mismatch | Unity + Python missing critical fields | **Critical** |
| `memory_protection_active` field | Missing from ALL SDKs | **Critical** |
| `update_connector` event | Server supports it, NO SDK exposes it | High |
| HydrationChannel | New channel, no SDK support or docs | High |
| SDK Identification Constants | Inconsistent across SDKs | Medium |
| Test Coverage | Python SDK tests still empty | Medium |
| Python Reconnection Logic | Config exists but not implemented | Medium |
| `request_quality_tier` event | Undocumented in SDKs | Medium |
| Package Publishing | Not published to registries | Low |

### Changes Since Last Review (2026-02-06 to 2026-02-08)

| Change | Impact |
|--------|--------|
| Identified BackpressureConfig model mismatch across SDKs | Critical - Unity/Python silently ignore `paused` field |
| Discovered `update_connector` event exists on server (lines 249-265 of sensor_data_channel.ex) | No SDK can rename connectors at runtime |
| Confirmed rate limiting is now fully implemented | Resolves gap flagged in previous review |
| Discovered HydrationChannel (318 lines, client-side room snapshot storage) | New channel not covered by any SDK |
| Identified `request_quality_tier` call channel event (lines 184-198 of call_channel.ex) | Undocumented adaptive video quality feature |
| No breaking server-side changes in recent commits | SDKs remain backward-compatible |

---

## CRITICAL FINDING: BackpressureConfig Model Mismatch

### Server Payload (sensor_data_channel.ex lines 735-744)

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

### Pause Conditions (from server code lines 710-723)

The server sets `paused: true` under two conditions:
1. **Memory protection active** AND attention is `low` or `none`
2. **Critical system load** AND attention is `low` or `none`

When memory protection is active, non-paused sensors (high/medium attention) receive a 5x multiplier to their batch window.

### Behavioral Comparison of paused Handling

**Rust SDK** (`clients/rust/src/models.rs` lines 75-130, `channel.rs`):
- `BackpressureConfig` includes `paused`, `system_load` (as `SystemLoadLevel` enum), `load_multiplier`
- `should_pause()` and `effective_batch_window()` helper methods
- Checks `paused` before `send_measurement` (returns error)
- Checks `paused` before auto-flush in `add_to_batch`
- Checks `paused` before `flush_batch` (unless `force`)
- Exposes `is_paused()` async method
- Force-flushes on close even when paused

**TypeScript SDK** (`clients/threejs/src/models.ts` lines 126-212, `sensor.ts`):
- `BackpressureConfig` interface includes `paused`, `systemLoad`, `loadMultiplier`
- `parseBackpressureConfig()` correctly maps all fields from server payload
- `isPaused` getter on SensorStream
- Checks `paused` before `sendMeasurement`, `addToBatch`, `flushBatch`
- Force-flush on close even when paused

**Unity SDK** (`clients/unity/SensoctoSDK/Runtime/Models.cs` lines 127-186): No `paused` field in `BackpressureConfig`, `FromPayload()` only parses 4 fields, no pause checks in `BackpressureManager`

**Python SDK** (`clients/python/sensocto/models.py` lines 82-104): No `paused` field in `BackpressureConfig`, `from_payload()` only parses 4 fields, no pause checks anywhere

---

## DX Deep Dive Analysis (2026-02-06, updated 2026-02-08)

### New Developer Onboarding Friction Assessment

After a detailed code review of the server-side implementation, the following friction points were identified for new developers trying to integrate with Sensocto:

#### Critical Friction Points

| Issue | Severity | Impact |
|-------|----------|--------|
| **Phoenix Channel Protocol Knowledge Required** | High | Developers must understand Phoenix-specific message formats (`ref`, `join_ref`, heartbeat protocol) |
| **Undocumented Backpressure Response Contract** | High | `backpressure_config` events pushed to clients but no guidance on how clients should respond |
| **Memory Protection Protocol Undocumented** | Medium | System can activate memory protection mode that pauses low-priority sensors - clients need to handle gracefully |
| **Guest Token Format Secret** | Medium | Guest tokens use `guest:{id}:{token}` format but this is not documented externally |
| **Attribute Type Validation** | Medium | 30+ valid attribute types but no client-side validation utilities in SDKs |

#### Positive DX Elements Found

| Element | Implementation | Location |
|---------|---------------|----------|
| **OpenAPI Spec** | Full spec with Swagger UI | `/api/openapi`, `/swaggerui` |
| **Type System** | Comprehensive `AttributeType` module | `lib/sensocto/types/attribute_type.ex` |
| **Safe Key Validation** | Prevents atom exhaustion attacks | `lib/sensocto/types/safe_keys.ex` |
| **BLE UUID Mappings** | 80+ Bluetooth characteristic mappings | `assets/svelte/bluetooth-utils.js` |
| **Health Endpoints** | Kubernetes-ready liveness/readiness | `/health/live`, `/health/ready` |
| **Rate Limiting** | ETS-based sliding window with headers | `lib/sensocto_web/plugs/rate_limiter.ex` |

### Client-Side Resilience Patterns Required

Based on server analysis, clients MUST implement these patterns:

#### 1. Backpressure Response Handler

```javascript
// Required client implementation
channel.on("backpressure_config", (config) => {
  if (config.paused) {
    // MUST stop sending data - queue locally
    pauseDataTransmission();
    startLocalQueue();
  } else if (config.memory_protection_active) {
    // Heavy throttling active - reduce rate 5x
    setThrottleMultiplier(5.0);
  } else {
    // Normal operation - follow recommendations
    setBatchWindow(config.recommended_batch_window);
    setBatchSize(config.recommended_batch_size);
  }
});
```

#### 2. Reconnection with Channel Rejoin

The server uses Phoenix Presence to track connections. On reconnect, clients must:
1. Re-establish WebSocket connection with exponential backoff
2. Re-join ALL previously joined channels with same parameters
3. Re-subscribe to PubSub topics (attention, system load)
4. Request fresh backpressure config via `:send_backpressure_config`

#### 3. Offline-First Data Queue

For sensor data reliability:
```
On disconnect:
  1. Detect disconnect (heartbeat failure or close event)
  2. Start local IndexedDB/SQLite queue
  3. Continue collecting measurements locally
  4. Track queue depth for memory management

On reconnect:
  1. Rejoin channel
  2. Wait for backpressure_config
  3. If not paused: drain queue with rate limiting
  4. Resume real-time streaming
```

### API Resilience Assessment

| Feature | Status | Notes |
|---------|--------|-------|
| **Rate Limit Headers** | Implemented | `X-RateLimit-Limit`, `X-RateLimit-Remaining`, `X-RateLimit-Reset`, `Retry-After` |
| **Request IDs** | Not present | Add `X-Request-ID` for distributed tracing |
| **API Versioning** | None | Implement `/api/v1/` prefix |
| **Idempotency Keys** | Not supported | Add for POST/PUT mutations |
| **Error Codes** | Strings only | Add numeric codes for programmatic handling |
| **Rate Limiting Scope** | POST only | Only rate-limits POST requests; GET requests bypass |

### Recommended Error Code Structure

Current error responses use simple reason strings:
```elixir
{:error, %{reason: "unauthorized"}}
```

Proposed standardized structure:
```json
{
  "error": {
    "code": "AUTH_TOKEN_EXPIRED",
    "message": "Bearer token has expired",
    "category": "auth",
    "retryable": true,
    "retry_after_ms": 0,
    "request_id": "req_abc123def456"
  }
}
```

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

This section analyzes all planned architecture changes and their impact on client SDKs, API surface, and developer experience.

### 1. Room Persistence: PostgreSQL to In-Memory + Iroh Docs

**Plan:** `PLAN-room-iroh-migration.md`
**Status:** Planned

**SDK Impact: MEDIUM**

The room persistence layer is migrating from PostgreSQL (Ash/Ecto) to an in-memory GenServer with Iroh document storage for distributed state synchronization.

| Aspect | Current | After Migration | SDK Change Required |
|--------|---------|-----------------|---------------------|
| Room CRUD API | REST via Ash | REST via RoomStore GenServer | None -- API contract stays the same |
| Room data model | Ash Resource | Plain map with same fields | None -- JSON shape identical |
| Room membership | Join table in PostgreSQL | In-memory map + Iroh sync | None -- REST API same |
| Startup behavior | Rooms available immediately | Rooms available after Iroh hydration | SDKs may see brief period of empty room lists on cold start |

**Developer Experience Implications:**
- Rooms may take 1-3 seconds to appear after a server cold start (Iroh hydration is async)
- SDKs should handle empty room lists gracefully during startup
- No new API endpoints; existing `/api/rooms/*` routes remain unchanged
- HydrationChannel (`hydration:room:*`) is the client-side complement to this -- SDKs that want to participate in room snapshot persistence would need to implement the snapshot offer/data protocol

**Recommendation:** Document in SDK READMEs that room lists may be temporarily empty during server startup. No code changes needed.

### 2. Adaptive Video Quality for Massive Scale Calls

**Plan:** `PLAN-adaptive-video-quality.md`
**Status:** 100% Complete (implemented 2026-01-16)

**SDK Impact: HIGH -- New channel events already deployed but not documented in SDKs**

This plan introduced attention-based quality tiers for video calls, enabling 100+ participants per room. All backend and frontend components are implemented.

| New Channel Event | Direction | Payload | SDK Coverage |
|-------------------|-----------|---------|--------------|
| `speaking_state` | Client -> Server | `{speaking: bool}` | Not in any SDK |
| `attention_state` | Client -> Server | `{level: "high\|medium\|low"}` | Not in any SDK |
| `video_snapshot` | Client -> Server | `{data, width, height, timestamp}` | Not in any SDK |
| `request_quality_tier` | Client -> Server | `{target_user_id, tier}` | Not in any SDK |
| `tier_changed` | Server -> Client | `{user_id, tier}` | Rust has `QualityChanged` event |
| `quality_tier_request` | Server -> Client | `{from_user_id, target_user_id, tier}` | Not in any SDK |
| `participant_audio_changed` | Server -> Client (intercepted) | `{user_id, enabled}` | Rust + TypeScript have events |
| `participant_video_changed` | Server -> Client (intercepted) | `{user_id, enabled}` | Rust + TypeScript have events |
| `participant_speaking` | Server -> Client (intercepted) | `{user_id, speaking}` | Not in any SDK |
| `video_snapshot` | Server -> Client (intercepted) | `{user_id, data, ...}` | Not in any SDK |

**Quality Tiers (already deployed):**
| Tier | Mode | Resolution | Bandwidth |
|------|------|------------|-----------|
| `:active` | Full Video | 720p @ 30fps | ~2.5 Mbps |
| `:recent` | Reduced Video | 480p @ 15fps | ~500 Kbps |
| `:viewer` | Snapshot | 240p @ 1fps JPEG | ~50-100 Kbps |
| `:idle` | Static Avatar | N/A | ~0 |

**Recommendation:** Add `speaking_state`, `attention_state`, `video_snapshot`, `request_quality_tier` methods to all SDK call session classes. Add `tier_changed` and `quality_tier_request` event handlers.

### 3. Sensor Component Migration (LiveView to LiveComponent)

**Plan:** `PLAN-sensor-component-migration.md`
**Status:** Planned

**SDK Impact: NONE** -- Purely server-side/frontend architecture change. No WebSocket protocol, REST API, or channel event changes.

### 4. Startup Time Optimization

**Plan:** `PLAN-startup-optimization.md`
**Status:** IMPLEMENTED (2026-01-31)

**SDK Impact: LOW** -- HTTP server now responsive within 1-2 seconds. `/health/ready` returns faster. Sensor lists populate gradually after start. No protocol changes.

### 5. Delta Encoding for High-Frequency ECG Data

**Plan:** `plans/delta-encoding-ecg.md`
**Status:** Planned

**SDK Impact: HIGH -- New binary encoding format for ECG data**

Introduces delta encoding for ECG waveform data, reducing bandwidth by approximately 84% (from ~1000 bytes to ~162 bytes for 50 samples).

| Aspect | Details |
|--------|---------|
| New event | `composite_measurement_encoded` (LiveView push event) |
| Encoding format | Binary: 1-byte header + 8-byte base timestamp + 4-byte first value + int8 deltas |
| Feature flag | `DELTA_ENCODING_ENABLED` env var, disabled by default |
| Affected data | ECG attribute only (initially) |
| Backward compatible | Yes -- unencoded path preserved when flag is off |

**SDK Requirements When Delta Encoding Ships:**

1. **All SDKs** need a delta decoder that mirrors `Sensocto.Encoding.DeltaEncoder`:
   - Read 1-byte header (version in lower nibble)
   - Read 8-byte base timestamp (int64 LE)
   - Read 4-byte first value (float32 LE)
   - Read deltas: int8 value delta (0x80 = reset marker) + uint16 timestamp delta (LE)
   - Quantization step: 0.01 mV per int8 unit

2. **SDKs receiving sensor data** (subscription mode) must detect `__delta_encoded__: true` in payloads and decode accordingly

3. **SDKs sending ECG data** could optionally encode on the client side for bandwidth savings

**Recommendation:** Prepare delta decoder implementations for each SDK language. Rust: use `byteorder` crate. Python: use `struct` module. Unity: use `BinaryReader`. TypeScript: use `DataView` (already planned).

### 6. Cluster-Wide Sensor Visibility (Horde Migration)

**Plan:** `plans/PLAN-cluster-sensor-visibility.md`
**Status:** Planned (HIGH priority)

**SDK Impact: LOW** -- Transparent to clients. Migrates sensor registry to Horde for cluster-wide discovery. More sensors visible from any node. No protocol changes.

### 7. Distributed Discovery System

**Plan:** `plans/PLAN-distributed-discovery.md`
**Status:** Planned (HIGH priority, depends on cluster sensor visibility)

**SDK Impact: MEDIUM -- New Discovery API could become REST endpoints**

Introduces a 4-layer Discovery Service with a public API including `Discovery.list_sensors()`, `Discovery.get_sensor_state()`, and `Discovery.cluster_health()`. Currently internal Elixir API but could power new REST endpoints:
- `GET /api/sensors` -- powered by `Discovery.list_sensors()`
- `GET /api/sensors/:id` -- powered by `Discovery.get_sensor_state(id)`

Staleness indicator (`fresh` vs `stale`) in sensor state could be exposed to SDKs.

**Recommendation:** When this plan ships, add corresponding REST endpoints and update all SDKs with sensor listing and discovery methods.

### 8. Sensor Scaling Refactor

**Plan:** `plans/PLAN-sensor-scaling-refactor.md`
**Status:** Planned

**SDK Impact: MEDIUM -- PubSub topic structure changes affect subscription patterns**

Major refactor for 1000+ sensor scale: hybrid registry (pg + local), sharded PubSub topics (`data:attention:high/medium/low`, `data:sensor:{id}`), per-socket ETS buffers, sensor-side ring buffers.

New capability: sensor-specific topic `data:sensor:{sensor_id}` enables direct subscriptions. Ring buffers enable `get_buffered_data(from, to)` for historical windows.

**Recommendation:** When sharded topics ship, add `subscribeTo(sensorId)` and `requestHistory(sensorId, from, to)` methods to SDKs.

### 9. Research-Grade Synchronization Metrics

**Plan:** `plans/PLAN-research-grade-synchronization.md`
**Status:** Planned

**SDK Impact: HIGH -- Major new API surface for analysis**

Introduces research-grade interpersonal physiological synchronization metrics (PLV, TLCC, WTC, CRQA, DTW, IRN). Real-time metrics run client-side in Svelte; post-hoc analysis runs server-side via Pythonx.

New database schema `sync_reports` stores analysis results. New REST endpoints needed:
- `GET /api/sessions/:id/sync-report` -- Fetch sync analysis results
- `POST /api/sessions/:id/sync-report` -- Trigger sync report generation

**Recommendation:** When sync reports ship, add `SyncReport` models and API methods to Python SDK (primary research audience). Consider dedicated `sensocto-analysis` Python package.

### 10. TURN Server and Cloudflare Realtime Integration

**Plan:** `plans/PLAN-turn-cloudflare.md`
**Status:** Partially Complete (module done, secrets not deployed)

**SDK Impact: MEDIUM -- ICE server configuration changes**

Call join response now includes 7 STUN + optional Cloudflare TURN servers. SDKs must pass full `ice_servers` array to `RTCPeerConnection`. TURN enables mobile users behind symmetric NAT/CGNAT.

**Recommendation:** Verify all SDKs correctly propagate `ice_servers` from call join response to WebRTC config.

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

---

## Recent Changes (2026-01-30 to 2026-02-02)

### Server-Side Architecture Changes

#### 1. Distributed Sensors (Horde Registry)

**Commit:** `97c9fbd` - distributed sensors

The platform now uses `Horde.Registry` for cluster-wide sensor discovery instead of a local `Registry`. This is a **backend-only change** that is transparent to clients.

**Impact on SDKs:** None - the WebSocket channel API remains unchanged.

#### 2. Reactive Backpressure Philosophy Change

**Commits:** `cc60ecb`, `08add49`, `3ba49c0`, `c0910a1`

**Previous Behavior:**
- Quality levels: high (20Hz), medium (10Hz), low (1s digests), minimal (2s digests)
- Preemptive throttling based on sensor count

**New Behavior:**
- Quality levels now target higher throughput: high (~60fps/32ms), medium (~20fps/50ms), low (~10fps/100ms), minimal (~5fps/200ms)
- New `paused` quality level stops data flow entirely (critical backpressure)
- **No preemptive throttling** - system starts at maximum quality regardless of sensor count
- Degradation only occurs based on actual backpressure (mailbox depth)

---

## 1. Current API Surface

Sensocto provides multiple API entry points for external clients to interact with the platform.

### 1.1 WebSocket Channels (Phoenix Channels)

#### User Socket (`/socket/websocket`)

**Endpoint:** `wss://{server}/socket/websocket`

| Channel Topic | Handler | Purpose |
|--------------|---------|---------|
| `sensocto:sensor:{sensor_id}` | SensorDataChannel | Real-time sensor data streaming |
| `sensocto:connector:{connector_id}` | SensorDataChannel | Connector registration |
| `sensocto:lvntest:{connector_id}` | SensorDataChannel | LiveView Native test connector |
| `call:{room_id}` | CallChannel | WebRTC signaling for video/voice calls |
| `hydration:room:{room_id}` | HydrationChannel | Client-side room snapshot storage |

#### Bridge Socket (`/bridge/websocket`)

**Endpoint:** `wss://{server}/bridge/websocket`

| Channel Topic | Handler | Purpose |
|--------------|---------|---------|
| `bridge:control` | BridgeChannel | Iroh bridge control channel |
| `bridge:topic:{topic}` | BridgeChannel | Subscribe to Phoenix PubSub topics |

### 1.2 REST API Endpoints

#### Authentication
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET/POST | `/api/auth/verify` | MobileAuthController | Verify JWT token |
| GET | `/api/me` | MobileAuthController | Get current user info |
| POST | `/api/auth/debug` | MobileAuthController | Debug token verification |

#### Rooms
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/api/rooms` | RoomController | List user's rooms |
| GET | `/api/rooms/public` | RoomController | List public rooms |
| GET | `/api/rooms/:id` | RoomController | Get room details |
| GET | `/api/rooms/:id/ticket` | RoomTicketController | Generate P2P room ticket |
| GET | `/api/rooms/by-code/:code/ticket` | RoomTicketController | Get ticket by join code |
| POST | `/api/rooms/verify-ticket` | RoomTicketController | Verify room ticket |

#### Guest Authentication
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/auth/guest/:guest_id/:token` | GuestAuthController | Guest user sign-in |

#### Health Checks
| Method | Path | Controller | Purpose |
|--------|------|------------|---------|
| GET | `/health/live` | HealthController | Liveness probe (shallow) |
| GET | `/health/ready` | HealthController | Readiness probe (deep) |

### 1.3 Phoenix LiveView (Browser-Only)

LiveView routes require browser sessions with CSRF protection:
- `/lobby/*` - Real-time sensor monitoring dashboard
- `/rooms/*` - Room management and viewing
- `/simulator` - Sensor simulation interface
- `/settings` - User settings

---

## 2. Client Platforms

### 2.1 Unity/C# SDK

**Location:** `clients/unity/SensoctoSDK/`
**Status:** Production-ready but missing critical backpressure fields

**Strengths:** Unity-idiomatic ScriptableObject config, async/await, event-driven, thread-safe, auto-reconnection (1s-30s backoff), serial port integration, deep link auth, `ShouldFlushImmediate()` for high attention

**Critical Issues:**
- BackpressureConfig missing `paused`, `system_load`, `load_multiplier`, `memory_protection_active`
- `FromPayload()` (Models.cs lines 149-174) only parses 4 of 8 fields
- `BackpressureManager.cs` has no pause check
- Missing `SDK_NAME` and `VERSION` constants

### 2.2 Rust SDK

**Location:** `clients/rust/`
**Status:** Most complete SDK alongside TypeScript

**Strengths:** Idiomatic Rust, async tokio, builder pattern, thiserror errors, `SDK_NAME = "sensocto-rust"`, full backpressure with `paused`/`system_load`/`load_multiplier`, `should_pause()` + `effective_batch_window()`, pause checks in all send paths, force-flush on close

**Issues:** Missing `memory_protection_active`, `blocking` feature flag not implemented, examples commented out

### 2.3 Python SDK

**Location:** `clients/python/`
**Status:** Functional but incomplete

**Strengths:** Async context manager, type hints, Pydantic models, good error hierarchy, `__version__` exposed

**Critical Issues:**
- BackpressureConfig missing `paused`, `system_load`, `load_multiplier`, `memory_protection_active`
- Tests directory empty
- Reconnection not implemented (config exists, socket does not use it)
- Missing `SDK_NAME`

### 2.4 TypeScript/Three.js SDK

**Location:** `clients/threejs/`
**Status:** Feature-complete with best backpressure handling

**Strengths:** Full TypeScript, `BackpressureConfig` with `paused`/`systemLoad`/`loadMultiplier`, `parseBackpressureConfig()`, `isPaused` getter, pause checks everywhere, force-flush on close, handler unsubscribe pattern, ESM + CJS

**Issues:** Missing `memory_protection_active`, missing `SDK_NAME`

### 2.5 Livebook/Elixir

**Status:** Interactive `livebooks/api-developer-experience.livemd` available. Not formally packaged.

---

## 3. WebSocket Protocol

### 3.1 Connection Flow

```
1. Connect to wss://{server}/socket/websocket
2. Heartbeat every 30s to "phoenix" topic
3. Join channel with topic + params (auth happens here)
4. Exchange messages
5. Leave / disconnect
```

### 3.2 Sensor Data Channel Protocol

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

### 3.3 Call Channel Protocol

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

### 3.4 Bridge Channel Protocol

Iroh P2P bridge with envelope format (version 1), `publish`/`subscribe`/`unsubscribe`/`heartbeat` events. Optional token-based auth.

### 3.5 Hydration Channel Protocol

**Topic:** `hydration:room:{room_id}` (supports `*` wildcard)

Client-to-server: `snapshot:offer`, `snapshot:data`, `snapshot:batch_offer`, `snapshot:stored`
Server-to-client: `snapshot:request`, `snapshot:store`, `snapshot:delete`

---

## 4. Authentication

| Method | Format | Where Used |
|--------|--------|-----------|
| JWT Bearer Token | Standard JWT (AshAuthentication) | REST API + Channel join params |
| Guest Token | `guest:{guest_id}:{token}` | Channel join params |
| Development Token | `"missing"` literal | Channel join (bypass -- TODO disable in prod) |
| Basic Auth | Env vars | Admin routes |

**Socket-Level:** UserSocket accepts ALL connections. Auth deferred to channel join. BridgeSocket has optional token validation.

**Rate Limiting:** ETS sliding window. Auth: 10/60s, Registration: 5/60s, API auth: 20/60s, Guest: 10/60s. POST only. Headers: `X-RateLimit-*`, `Retry-After`.

---

## 5. Summary Recommendations

### Immediate Actions (Priority: Critical)

1. **Add `paused`, `system_load`, `load_multiplier` to Unity BackpressureConfig**
2. **Add `paused`, `system_load`, `load_multiplier` to Python BackpressureConfig**
3. **Add `memory_protection_active` to ALL SDK BackpressureConfig models**
4. **Add pause checks to Unity BackpressureManager and Python sensor streaming**

### Short-term Actions (Priority: High)

5. **Implement Python reconnection logic** -- Config exists but socket has no reconnection code
6. **Add Python SDK tests** -- Currently empty directory
7. **Expose `update_connector` event in SDKs**
8. **Document HydrationChannel protocol**
9. **Add SDK_NAME and VERSION constants** to Unity, Python, and TypeScript SDKs
10. **Document adaptive video quality events** in SDK call session classes

### Medium-term Actions (Priority: Medium)

11. **Prepare delta decoders** for each SDK ahead of delta encoding rollout
12. **Publish SDKs** to package registries (crates.io, PyPI, npm, OpenUPM)
13. **Add `blocking` API** to Rust SDK
14. **Add sync wrapper** for Python SDK
15. **Create cross-SDK backpressure handling guide**
16. **Add sensor listing API** when Distributed Discovery ships

### Long-term Actions (Priority: Low)

17. **Create Elixir/Livebook SDK** with Kino integration
18. **Add binary protocol option** for high-frequency data
19. **Implement API versioning** strategy
20. **Build developer portal** with interactive docs
21. **Add WebWorker support** to TypeScript SDK
22. **Add sync report API** to Python SDK when research sync metrics ship
23. **Verify ICE server propagation** across all SDKs for TURN support

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
| HealthController | `lib/sensocto_web/controllers/health_controller.ex` |
| GuestAuthController | `lib/sensocto_web/controllers/guest_auth_controller.ex` |

### Documentation

| Document | Location |
|----------|----------|
| API Attributes Reference | `docs/api-attributes-reference.md` |
| Getting Started | `docs/getting-started.md` |
| Architecture | `docs/architecture.md` |
| Simulator Integration | `docs/simulator-integration.md` |
| API Developer Experience Livebook | `livebooks/api-developer-experience.livemd` |
| OpenAPI Spec Module | `lib/sensocto_web/api_spec.ex` |
| Rate Limiter | `lib/sensocto_web/plugs/rate_limiter.ex` |

---

*Report generated by api-client-developer agent*
*Last review: 2026-02-08*

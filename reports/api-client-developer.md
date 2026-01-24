# Sensocto API Client Developer Assessment

**Assessment Date:** January 17, 2026 (Updated: January 20, 2026)
**Analyst:** API Client Developer Agent (Claude Opus 4.5)
**Application:** Sensocto - IoT Sensor Platform
**Focus:** SDK Quality, Developer Experience, API Surface Analysis

---

## 🆕 Update: January 20, 2026

### New REST API Endpoints Discovered

The platform now has a REST API alongside WebSocket channels:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/auth/verify` | POST | JWT token verification |
| `/api/me` | GET | Current user info |
| `/api/rooms` | GET | List user's rooms |
| `/api/rooms/public` | GET | List public rooms |
| `/api/rooms/:id` | GET | Room details |
| `/api/rooms/:id/ticket` | GET | P2P room ticket generation (Iroh) |
| `/api/rooms/by-code/:code/ticket` | GET | Ticket by join code |
| `/api/rooms/verify-ticket` | POST | Ticket verification |

### New Bridge Channel for P2P

The `BridgeChannel` (`lib/sensocto_web/channels/bridge_channel.ex`) enables P2P connectivity via Iroh with message envelope format supporting Phoenix-to-Iroh bridging.

### Updated SDK Assessment

| SDK | Files | Key Features | README |
|-----|-------|-------------|--------|
| **Unity/C#** | 17 .cs files | Full-featured: sensors, calls, reconnection, serial port, deep links | **Missing** |
| **Rust** | 7 source files | Async/await, builder pattern | Excellent |
| **Python** | 8 source files | Async-first, context managers | Excellent |
| **TypeScript** | Full package | Three.js visualizers, test coverage | Excellent |

### Call Channel Events (Expanded)

New adaptive quality events:
- `speaking_state`, `attention_state`, `video_snapshot`
- Quality control: `set_quality`, `request_quality_tier`, `quality_changed`, `tier_changed`
- Full WebRTC lifecycle support

### Comprehensive Attribute Types

Located in `docs/api-attributes-reference.md` (831 lines):
- Health/Cardiac: ECG, HR, HRV, SpO2
- Motion/IMU: accelerometer, gyroscope, quaternion, euler
- Location: geolocation, altitude, speed
- Environment: temperature, humidity, pressure
- Marine: water temp, salinity, pH, dissolved oxygen
- Device: battery, button, LED
- AI/Inference: fish count, species diversity, coral coverage

### Priority Recommendations (Updated)

1. **URGENT:** Add Unity SDK README.md
2. Publish all SDKs to package registries (crates.io, PyPI, npm)
3. Create OpenAPI specification for REST endpoints
4. Build Livebook/Elixir SDK with Kino Smart Cells
5. Document the new P2P room ticket system for SDK integration

---

## Executive Summary

Sensocto provides a real-time sensor platform with WebSocket-based communication using Phoenix Channels. The platform currently offers client SDKs for **four ecosystems**: Unity/C#, Rust, Python, and TypeScript/Three.js.

### Overall Assessment: GOOD with Room for Improvement

| Aspect | Score | Notes |
|--------|-------|-------|
| API Design | 8/10 | Clean WebSocket channels, good backpressure |
| SDK Coverage | 7/10 | 4 platforms, but none published |
| Documentation | 5/10 | Unity SDK lacks README |
| Developer Onboarding | 5/10 | 10-30 min to first API call |
| Feature Parity | 6/10 | Backpressure implemented, some gaps |

---

## API Surface Analysis

### Communication Protocol

The platform uses **Phoenix WebSocket Channels** as the primary communication mechanism with three main channel topics:

| Topic Pattern | Purpose | Authentication |
|---------------|---------|----------------|
| `sensocto:connector:{id}` | Connector registration | Optional bearer token |
| `sensocto:sensor:{id}` | Sensor data streaming | Via connector |
| `call:{room_id}` | WebRTC signaling | Room membership |

**Note:** There is **no REST API** for external clients - all communication is real-time WebSocket-based.

### Key Channel Events

#### Sensor Data Channel (`sensocto:*`)

| Event | Direction | Description |
|-------|-----------|-------------|
| `join_lobby` | Client → Server | Register connector/sensor |
| `measurement` | Client → Server | Send sensor data |
| `batch_measurement` | Client → Server | Send batched data |
| `attention_change` | Server → Client | Backpressure signal |
| `config_update` | Server → Client | Configuration changes |

#### Call Channel (`call:*`)

| Event | Direction | Description |
|-------|-----------|-------------|
| `join_call` | Client → Server | Join video/voice call |
| `leave_call` | Client → Server | Leave call |
| `media_event` | Bidirectional | WebRTC signaling |
| `participant_joined` | Server → Client | New participant notification |
| `participant_left` | Server → Client | Participant left notification |

---

## Client SDK Status

### Overview

| SDK | Location | README | Published | Tests | Backpressure |
|-----|----------|--------|-----------|-------|--------------|
| **Unity/C#** | `/clients/unity/SensoctoSDK/` | Missing | No | No | Yes |
| **Rust** | `/clients/rust/` | Excellent | No (crates.io) | Partial | Yes |
| **Python** | `/clients/python/` | Excellent | No (PyPI) | Empty | Yes |
| **TypeScript** | `/clients/threejs/` | Good | No (npm) | Yes | Yes |
| **Livebook** | N/A | N/A | N/A | N/A | N/A |

### Standout Feature: Backpressure System

All SDKs implement server-driven backpressure with attention levels:

| Level | Batch Window | Batch Size | Use Case |
|-------|--------------|------------|----------|
| `:high` | 100ms | 1 | Real-time viewing |
| `:medium` | 500ms | 5 | Normal operation |
| `:low` | 2000ms | 10 | Background |
| `:none` | 5000ms | 20 | No viewers |

---

## SDK Deep Dive

### 1. Unity/C# SDK

**Location:** `/clients/unity/SensoctoSDK/`

**Structure:**
```
SensoctoSDK/
├── Runtime/
│   ├── SensoctoClient.cs
│   ├── SensorConnection.cs
│   ├── PhoenixChannel.cs
│   └── BackpressureManager.cs
├── Editor/
└── package.json (for UPM)
```

**Strengths:**
- Clean separation of concerns
- Backpressure handling implemented
- Unity Package Manager compatible structure

**Critical Gaps:**
- No README.md
- No example scenes
- No documentation comments
- Not published to OpenUPM

**Recommendations:**
1. Add comprehensive README with quick start guide
2. Create example Unity scene with sensor simulation
3. Add XML documentation comments for IntelliSense
4. Publish to OpenUPM for easy installation

### 2. Rust SDK

**Location:** `/clients/rust/`

**Structure:**
```
rust/
├── src/
│   ├── lib.rs
│   ├── client.rs
│   ├── channel.rs
│   ├── sensor.rs
│   └── backpressure.rs
├── examples/
│   └── basic_sensor.rs
├── Cargo.toml
└── README.md (Excellent)
```

**Strengths:**
- Excellent README with examples
- Async/await support (tokio)
- Type-safe API
- Examples included

**Gaps:**
- Not published to crates.io
- Incomplete test coverage
- Missing benchmarks

**Recommendations:**
1. Publish to crates.io
2. Add integration tests
3. Create performance benchmarks
4. Add documentation examples in doc comments

### 3. Python SDK

**Location:** `/clients/python/`

**Structure:**
```
python/
├── sensocto/
│   ├── __init__.py
│   ├── client.py
│   ├── channel.py
│   └── backpressure.py
├── examples/
│   └── basic_usage.py
├── tests/ (empty)
├── pyproject.toml
└── README.md (Excellent)
```

**Strengths:**
- Clean Pythonic API
- Async support (asyncio)
- Good README documentation
- Type hints throughout

**Gaps:**
- Not published to PyPI
- No tests
- Missing Jupyter notebook examples

**Recommendations:**
1. Publish to PyPI
2. Add pytest test suite
3. Create Jupyter notebook tutorial
4. Add type stubs for better IDE support

### 4. TypeScript/Three.js SDK

**Location:** `/clients/threejs/`

**Structure:**
```
threejs/
├── src/
│   ├── index.ts
│   ├── SensoctoClient.ts
│   ├── SensorManager.ts
│   └── ThreeJsIntegration.ts
├── examples/
│   └── basic.html
├── package.json
├── tsconfig.json
└── README.md (Good)
```

**Strengths:**
- TypeScript for type safety
- Three.js integration
- Good documentation
- Test coverage

**Gaps:**
- Not published to npm
- Three.js integration could be more comprehensive
- Missing React/Vue wrapper components

**Recommendations:**
1. Publish to npm
2. Create React component wrapper
3. Add more Three.js visualization examples
4. Create CodeSandbox demos

---

## Missing: Livebook/Elixir SDK

The existing Livebook notebooks use raw `PhoenixClient` rather than a proper SDK. This is a significant gap for the Elixir ecosystem.

**Proposed Solution:** Create Kino Smart Cells for interactive exploration.

### Proposed Kino Smart Cells

1. **Sensor Connection Cell**
   - Visual UI for connecting to sensors
   - Auto-generates connection code
   - Live preview of incoming data

2. **Sensor Data Visualization Cell**
   - Real-time charts for sensor data
   - Configurable visualization types
   - Export to VegaLite

3. **Room Explorer Cell**
   - Browse and join rooms
   - View room members and sensors
   - Interactive room management

**Example Usage:**
```elixir
# In Livebook
{:ok, client} = Sensocto.Client.connect("ws://localhost:4000/socket")
{:ok, sensor} = Sensocto.Sensor.register(client, "my_sensor", type: :ecg)

# Send data
Sensocto.Sensor.send_measurement(sensor, %{ecg: [1.2, 1.3, 1.4], hr: 72})
```

---

## Time to First API Call

Current developer experience metrics:

| Platform | Current Time | Target Time | Blockers |
|----------|--------------|-------------|----------|
| Unity | 15-20 min | 5 min | No README, no UPM |
| Rust | 10-15 min | 5 min | Not on crates.io |
| Python | 10-15 min | 5 min | Not on PyPI |
| TypeScript | 10-15 min | 5 min | Not on npm |
| Livebook | 30+ min | 2 min | No SDK, no Smart Cells |

### Reducing Time to First API Call

**For all SDKs:**
1. Publish to package registries (immediate 5-10 min savings)
2. Add copy-paste quick start examples
3. Create sandbox/playground environments
4. Provide test server endpoint

**Unity-specific:**
1. Create .unitypackage for drag-and-drop import
2. Add "Getting Started" wizard in Unity Editor
3. Include sample scene that works out of the box

**Livebook-specific:**
1. Create installable Mix package
2. Build Kino Smart Cells
3. Provide hosted Livebook with SDK pre-installed

---

## API Design Recommendations

### 1. Add REST API for Management Operations

While real-time data should stay on WebSockets, management operations would benefit from REST:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/api/v1/rooms` | GET | List rooms |
| `/api/v1/rooms` | POST | Create room |
| `/api/v1/rooms/:id` | GET | Get room details |
| `/api/v1/sensors` | GET | List sensors |
| `/api/v1/health` | GET | Health check |

### 2. Improve Error Messages

Current error responses are often generic. Recommend:

```json
{
  "error": {
    "code": "SENSOR_NOT_FOUND",
    "message": "Sensor 'abc123' not found",
    "details": {
      "sensor_id": "abc123",
      "suggestion": "Check sensor ID or ensure sensor is connected"
    }
  }
}
```

### 3. Add OpenAPI Specification

Create OpenAPI/Swagger spec for any REST endpoints to enable:
- Auto-generated client SDKs
- Interactive API documentation
- Automated testing

---

## Priority Recommendations

### Immediate (This Week)

1. **Add Unity SDK README** - Critical documentation gap
2. **Publish Rust SDK to crates.io** - Enables `cargo add sensocto`
3. **Publish Python SDK to PyPI** - Enables `pip install sensocto`

### Short-Term (2 Weeks)

1. **Publish TypeScript SDK to npm** - Enables `npm install sensocto`
2. **Create Elixir SDK with Kino Smart Cells** - Fills Livebook gap
3. **Add quick start examples** to all SDKs

### Medium-Term (1 Month)

1. **Add REST API** for management operations
2. **Create interactive playgrounds** (CodeSandbox, Replit)
3. **Build OpenAPI specification**
4. **Improve error messages** across all channels

### Long-Term (Quarter)

1. **Create mobile SDKs** (Swift, Kotlin)
2. **Build SDK generator** from API spec
3. **Add GraphQL API** for flexible queries
4. **Create developer portal** with unified documentation

---

## Appendix: Files Reviewed

### Client SDKs
- `/clients/unity/SensoctoSDK/` - Unity/C# SDK
- `/clients/rust/` - Rust SDK
- `/clients/python/` - Python SDK
- `/clients/threejs/` - TypeScript/Three.js SDK

### Server Channels
- `lib/sensocto_web/channels/sensor_data_channel.ex`
- `lib/sensocto_web/channels/call_channel.ex`
- `lib/sensocto_web/channels/user_socket.ex`

### Existing Livebooks
- `livebook-phoenixclient.livemd`
- `livebook-ash.livemd`

---

*Report generated by API Client Developer Agent*
*Sensocto Platform - January 17, 2026*

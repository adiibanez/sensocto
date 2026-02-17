# Security Assessment Report: Sensocto Platform

**Assessment Date:** 2026-02-08 | **Updated:** 2026-02-16
**Previous Assessment:** 2026-02-15
**Assessor:** Security Advisor Agent (Claude Opus 4.6)
**Platform Version:** Current main branch
**Risk Framework:** OWASP Top 10 2021 + Elixir/Phoenix Best Practices

---

## Executive Summary

The Sensocto platform demonstrates a **mature security posture** with well-implemented security controls. This assessment identifies several areas requiring attention while acknowledging significant improvements since previous reviews.

**Overall Security Grade: B+ (Good)**

### Key Changes Since Last Assessment (2026-02-15 to 2026-02-16)

- **RESOLVED**: Session cookie encryption (M-004) -- `encryption_salt` now configured in endpoint.ex
- **STABLE**: All other findings unchanged. No new attack surface introduced by recent commits (graph improvements, resilience updates, lobby/index refactoring, translations)
- **NEW OBSERVATION**: `create_test_user` action in User resource -- verified test-only usage
- **NEW OBSERVATION**: Rate limiter only applies to POST requests -- GET-based auth routes (guest sign-in) bypass rate limiting

### Priority Findings Summary

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| H-001 | HIGH | 10-year token lifetime | Open |
| H-002 | HIGH | No socket-level authentication (UserSocket) | Open |
| H-003 | HIGH | API room endpoints missing auth pipeline | Open |
| H-004 | HIGH | Bridge.decode/1 atom exhaustion via `String.to_atom` | **VERIFIED: Not present** |
| H-005 | HIGH | No bot protection | Open |
| M-001 | MEDIUM | "missing" token development backdoor | **RESOLVED**: gated on `:allow_missing_token` config |
| M-002 | MEDIUM | Bridge token not required | Open |
| M-003 | MEDIUM | Debug endpoint exposed in production | **RESOLVED**: behind `dev_routes` |
| M-004 | MEDIUM | Session cookie not encrypted | **RESOLVED**: `encryption_salt` added |
| M-005 | MEDIUM | Timing-unsafe guest token comparison | **RESOLVED**: uses `Plug.Crypto.secure_compare` |
| M-006 | MEDIUM | /dev/mailbox route not gated | **RESOLVED**: behind `dev_routes` |
| M-007 | MEDIUM | Rate limiter skips GET requests (guest auth is GET) | **NEW** |
| L-001 | LOW | No force_ssl / HSTS | Open |
| L-002 | LOW | `create_test_user` action accessible via Ash policies bypass | **NEW** (low risk) |
| L-003 | LOW | No `Plug.Parsers` body size limit configured | **NEW** |

---

## 1. Authentication Architecture

### 1.1 Overview

Sensocto uses **Ash Authentication** with multiple authentication strategies:

| Strategy | Status | Security Notes |
|----------|--------|----------------|
| Google OAuth | Active | Client credentials via environment variables |
| Magic Link | Active | 1-hour token lifetime, `require_interaction?: true` |
| Password | Commented Out | Available but disabled -- passwordless preferred |
| Guest Sessions | Active | Database-backed with configurable TTL |

### 1.2 Token Configuration (H-001)

**File:** `lib/sensocto/accounts/user.ex`

```elixir
tokens do
  enabled? true
  token_resource Sensocto.Accounts.Token
  signing_secret Sensocto.Secrets
  store_all_tokens? true
  require_token_presence_for_authentication? true
  token_lifetime {3650, :days}  # <-- 10 YEARS
end
```

**Finding H-001: HIGH - Excessive Token Lifetime**
- **Risk**: Compromised tokens valid for extremely long period
- **Positive**: `require_token_presence_for_authentication?` enables revocation
- **Recommendation**: Reduce to 30 days, implement refresh tokens

---

## 2. WebSocket Channel Security

### 2.1 UserSocket Authentication (H-002)

**File:** `lib/sensocto_web/channels/user_socket.ex`

```elixir
@impl true
def connect(_params, socket, _connect_info) do
  {:ok, socket}
end
```

**Finding H-002: HIGH - No Socket-Level Authentication**
- Socket accepts all connections without authentication
- Allows anonymous connections to sensor data, call, and hydration channels
- Channels: `sensocto:*` (SensorDataChannel), `call:*` (CallChannel), `hydration:room:*` (HydrationChannel)

**Recommendation:**
```elixir
def connect(%{"token" => token}, socket, _connect_info) do
  case verify_token(token) do
    {:ok, user_or_guest} -> {:ok, assign(socket, :current_user, user_or_guest)}
    {:error, _reason} -> :error
  end
end
def connect(_params, _socket, _connect_info), do: :error
```

### 2.2 Development Backdoor (M-001)

**File:** `lib/sensocto_web/channels/sensor_data_channel.ex`

**Status: RESOLVED.** The "missing" token path checks `Application.get_env(:sensocto, :allow_missing_token, false)` and only allows bypass when explicitly enabled. Production config defaults to `false`.

### 2.3 Bridge Socket (M-002)

**File:** `lib/sensocto_web/channels/bridge_socket.ex`

Bridge token validation is optional -- missing token allows connection. When `bridge_token` is not configured (nil), any token is accepted. When no token is provided at all, the connection is also accepted.

**Recommendation:** Require bridge token in production. Add environment check:
```elixir
def connect(params, socket, _connect_info) do
  case {Map.get(params, "token"), Application.get_env(:sensocto, :bridge_token)} do
    {_, nil} when Mix.env() == :prod ->
      {:error, :bridge_token_not_configured}
    {nil, nil} ->
      {:ok, socket}  # dev only
    {token, expected} when is_binary(expected) ->
      if Plug.Crypto.secure_compare(token, expected), do: {:ok, socket}, else: {:error, :unauthorized}
    _ ->
      {:error, :unauthorized}
  end
end
```

---

## 3. API Security

### 3.1 API Room Endpoints Missing Auth Pipeline (H-003)

**File:** `lib/sensocto_web/router.ex` (lines 207-227)

The `/api/rooms/*` scope has no `pipe_through` at all -- no `:api` pipeline, no `:load_from_bearer`, no rate limiting.

**Current mitigation:** `RoomController` manually parses the `Authorization` header and verifies JWT tokens in its own `get_current_user/1` private function. `RoomTicketController.show/2` reads from `conn.assigns[:current_user]` which will be nil since no plug populates it -- it falls back to allowing access for public rooms only.

**Risks:**
- No rate limiting on room API endpoints (could be used for enumeration)
- No standardized error handling for malformed tokens
- `RoomTicketController.show/2` silently treats all requests as unauthenticated
- `verify-ticket` POST endpoint is completely unauthenticated (anyone can decode tickets)

**Recommendation**: Add `pipe_through [:api, :load_from_bearer]` to the rooms API scope. This would populate `conn.assigns[:current_user]` via Ash Authentication's bearer token plug.

### 3.2 Rate Limiter Skips GET Requests (M-007)

**File:** `lib/sensocto_web/plugs/rate_limiter.ex` (line 116)

```elixir
# Only rate limit POST requests (actual auth attempts), not page views
conn.method != "POST" ->
  conn
```

The guest authentication route is a GET request:
```elixir
get "/auth/guest/:guest_id/:token", GuestAuthController, :sign_in
```

This means the guest auth rate limiter (`rate_limit_guest_auth`) never actually limits guest sign-in attempts, since they are GET requests.

**Risk:** Brute-force guest token enumeration is not rate-limited.

**Recommendation:** Either change guest auth to POST, or add GET to the rate-limited methods for the `:guest_auth` type.

---

## 4. Session and Cookie Security

### 4.1 Session Cookie Configuration (M-004 -- RESOLVED)

**File:** `lib/sensocto_web/endpoint.ex`

```elixir
@session_options [
  store: :cookie,
  path: "/",
  key: "_sensocto_key",
  signing_salt: "4mNzZysc",
  encryption_salt: "k8Xp2vQe",  # <-- NOW PRESENT
  same_site: "Lax",
  max_age: 315_360_000,
  http_only: true
]
```

**Status: RESOLVED.** The `encryption_salt` has been added. Session cookies are now both signed and encrypted. The 10-year `max_age` mirrors the token lifetime strategy (intentional "remember me" pattern).

---

## 5. Verified Security Controls (Excellent)

### 5.1 Rate Limiting

**File:** `lib/sensocto_web/plugs/rate_limiter.ex`

- ETS-based sliding window counter
- Per-IP, per-endpoint-type buckets
- Proper X-Forwarded-For header handling
- Separate limits: auth (10/min), registration (5/min), API (20/min), guest (10/min)
- Note: Only applies to POST requests (see M-007)

**Assessment: Good** (downgraded from Excellent due to M-007)

### 5.2 Atom Exhaustion Protection

**File:** `lib/sensocto/types/safe_keys.ex`

Whitelist approach with comprehensive allowed keys list. **Assessment: Excellent.** H-004 (bridge.ex bypass) was verified as not present. ConnectorServer and SensorServer also migrated to SafeKeys.

### 5.3 DoS Resistance

| Mechanism | Implementation | Effectiveness |
|-----------|---------------|---------------|
| Rate Limiting | ETS-based sliding window | High (POST only) |
| Backpressure | PriorityLens quality levels | High |
| Memory Protection | 85%/92% thresholds | High |
| Socket Cleanup | Monitor + periodic GC | High |
| Request Timeouts | 2-5 second limits | Medium |

### 5.4 Security Headers

**File:** `lib/sensocto_web/endpoint.ex`

- x-frame-options: SAMEORIGIN
- x-content-type-options: nosniff
- x-xss-protection: 1; mode=block
- referrer-policy: strict-origin-when-cross-origin

### 5.5 Ash Policies

Default-deny on User and Token resources. **Assessment: Excellent**

### 5.6 Request Logger

**File:** `lib/sensocto_web/plugs/request_logger.ex`

Properly sanitizes sensitive data. **Assessment: Excellent**

### 5.7 Authenticated Tidewave

**File:** `lib/sensocto_web/plugs/authenticated_tidewave.ex`

Uses `Plug.Crypto.secure_compare/2` for timing-safe comparison. Production access requires Basic Auth with env vars. **Assessment: Excellent**

### 5.8 Guest Token Verification

**File:** `lib/sensocto_web/controllers/guest_auth_controller.ex`

Uses `Plug.Crypto.secure_compare/2` for timing-safe token comparison. **Assessment: Excellent**

### 5.9 Sensor Data Channel Authentication

**File:** `lib/sensocto_web/channels/sensor_data_channel.ex`

Multi-strategy token verification: JWT bearer tokens via `AshAuthentication.Jwt.verify/2`, guest tokens via `Plug.Crypto.secure_compare/2`, development bypass gated on config. **Assessment: Good**

---

## 6. New Observations (Feb 16, 2026)

### 6.1 `create_test_user` Action (L-002)

**File:** `lib/sensocto/accounts/user.ex` (lines 338-365)

The `create_test_user` action bypasses AshAuthentication validation and auto-confirms users. It uses `Bcrypt.hash_pwd_salt` directly rather than going through the password strategy.

**Current mitigation:** Ash policies default-deny all non-AshAuthentication interactions. The action is only used in test files (`object3d_player_component_test.exs`, `object3d_player_server_test.exs`).

**Risk:** LOW. The Ash policy layer prevents external callers from invoking this action. However, any code running with `authorize?: false` could create users without proper validation.

**Recommendation:** Add a guard comment or consider using `config :sensocto, :env` to conditionally compile this action only in test.

### 6.2 No Plug.Parsers Body Size Limit (L-003)

**File:** `lib/sensocto_web/endpoint.ex` (lines 81-84)

```elixir
plug Plug.Parsers,
  parsers: [:urlencoded, :multipart, :json],
  pass: ["*/*"],
  json_decoder: Phoenix.json_library()
```

No `length` option is specified. The default is 8MB for urlencoded/multipart and 1MB for JSON, which is reasonable for most cases. However, the `pass: ["*/*"]` allows any content type through unparsed.

**Risk:** LOW. Default limits are reasonable. The `pass: ["*/*"]` is standard for Phoenix apps that handle multiple content types.

### 6.3 Shared Helper Module (No Security Impact)

**File:** `lib/sensocto_web/live/helpers/sensor_data.ex`

New helper module `SensoctoWeb.LiveHelpers.SensorData` extracted from lobby/index live views. Contains only data transformation logic (grouping sensors, enriching with attention levels). No security implications.

### 6.4 SyncComputer / Bio Modules (No Security Impact)

Recent resilience improvements to Bio modules, SyncComputer, CircuitBreaker, and attention tracking. These are internal computation modules with no external input surface. No security implications.

---

## 7. Bot Protection Recommendation (H-005)

**Why Paraxial.io for Sensocto:**

1. **Native Elixir Integration**: Designed specifically for Phoenix/LiveView
2. **Invisible Security**: Bot detection without CAPTCHAs degrading UX
3. **IP Intelligence**: Real-time reputation scoring
4. **Minimal Overhead**: Designed for Elixir's concurrency model

---

## 8. Security Metrics

### Authentication Security Score: B

| Metric | Score | Notes |
|--------|-------|-------|
| Strategy Security | A | Magic Link with interaction required |
| Token Storage | A | Database-backed with revocation |
| Token Lifetime | D | 10 years is excessive |
| MFA | F | Not implemented |
| Rate Limiting | B | Comprehensive but skips GET requests |

### Authorization Security Score: A-

| Metric | Score | Notes |
|--------|-------|-------|
| Default Deny | A | Ash policies correctly configured |
| Room Access | A | Membership validation enforced |
| Channel Auth | B | Good but socket-level missing |
| API Auth | B | JWT validation good, room endpoints gap |

### Input Validation Score: A-

| Metric | Score | Notes |
|--------|-------|-------|
| Atom Protection | A | SafeKeys excellent, bridge.ex verified clean |
| SQL Injection | A | Ecto parameterized queries |
| XSS Prevention | B | Headers good, CSP missing |

### DoS Resistance Score: A

| Metric | Score | Notes |
|--------|-------|-------|
| Rate Limiting | A- | Multi-tier implementation (GET gap) |
| Backpressure | A | Quality-based throttling |
| Memory Protection | A | Configurable thresholds |
| Resource Cleanup | A | Monitor + GC patterns |

---

## 9. Planned Work: Security Implications

### 9.1 Room Iroh Migration (PLAN-room-iroh-migration.md)

**Security Impact: MEDIUM**

- **Risk**: Moving from PostgreSQL (with Ash policies) to in-memory GenServer + Iroh docs removes the authorization layer. Room CRUD operations currently go through Ash which enforces default-deny policies. The new `RoomStore` GenServer has no equivalent access control.
- **Risk**: Iroh P2P sync introduces a new trust boundary. Data synced between nodes via Iroh docs must be validated on receipt to prevent poisoned state propagation.
- **Risk**: No encryption-at-rest. PostgreSQL had this via disk encryption; in-memory + Iroh docs need explicit encryption for sensitive room data.
- **Recommendation**: Implement authorization checks in `RoomStore` API functions before migration. Validate all Iroh-synced data. Consider encrypting room metadata in Iroh docs.

### 9.2 Adaptive Video Quality (PLAN-adaptive-video-quality.md) - IMPLEMENTED

**Security Impact: LOW**

- **Positive**: SnapshotManager uses ETS with TTL-based cleanup (60s), preventing unbounded memory growth from snapshot data.
- **Risk**: `video_snapshot` channel event broadcasts base64-encoded JPEG data. No size validation on incoming snapshots could allow memory exhaustion via oversized payloads.
- **Recommendation**: Add max size validation (e.g., 100KB) for incoming `video_snapshot` events in `call_channel.ex`.

### 9.3 Sensor Component Migration (PLAN-sensor-component-migration.md)

**Security Impact: LOW**

- Purely internal architecture change (LiveView to LiveComponent). No new attack surface.
- **Positive**: Reduces process count from 73 to 1, reducing the surface for process-targeting attacks.

### 9.4 Startup Optimization (PLAN-startup-optimization.md) - IMPLEMENTED

**Security Impact: NONE**

- Deferred hydration timing only. No security implications.
- **Positive**: Faster HTTP server availability means health checks respond sooner, reducing window where the app is unprotected.

### 9.5 Delta Encoding ECG (plans/delta-encoding-ecg.md)

**Security Impact: LOW-MEDIUM**

- **Risk**: Binary protocol parsing (both Elixir encoder and JS decoder) introduces potential for buffer-related bugs. Malformed binary data could cause decoder errors or unexpected behavior.
- **Risk**: Feature flag via `Application.get_env` is mutable at runtime via IEx. An attacker with IEx access could toggle encoding to disrupt data flow.
- **Recommendation**: Validate binary header version and bounds-check all offsets in the decoder. Use `:persistent_term` for the feature flag (harder to tamper).

### 9.6 Cluster Sensor Visibility (plans/PLAN-cluster-sensor-visibility.md)

**Security Impact: MEDIUM**

- **Risk**: Migrating to Horde.Registry makes sensor processes discoverable from any node. Currently, sensors are only visible on their local node, providing implicit isolation.
- **Risk**: Cross-node sensor state fetching via PubSub request/reply or `:rpc.call` introduces new RPC surface. Malicious node could request sensitive sensor data.
- **Recommendation**: Validate node membership before processing cross-node requests. Use libcluster's node authorization. Rate-limit cross-node state requests.

### 9.7 Distributed Discovery (plans/PLAN-distributed-discovery.md)

**Security Impact: MEDIUM**

- **Risk**: DiscoveryCache stores sensor/room metadata in ETS with `:public` access. Any process on the node can read/write this data.
- **Risk**: PubSub-based sync (`discovery:sensors` topic) could be poisoned by a compromised node broadcasting fake sensor registrations.
- **Risk**: Circuit breaker `NodeHealth` uses `:net_kernel.monitor_nodes(true)` -- should validate that joining nodes are authorized.
- **Recommendation**: Use `:protected` ETS tables instead of `:public`. Validate discovery events against Horde registry state. Ensure libcluster's topology configuration restricts which nodes can join.

### 9.8 Sensor Scaling Refactor (plans/PLAN-sensor-scaling-refactor.md)

**Security Impact: LOW-MEDIUM**

- **Risk**: Per-socket ETS tables (`:"lens_buffer_#{socket_id}"`) use dynamically generated atom names. If `socket_id` comes from untrusted input, this is an atom exhaustion vector.
- **Risk**: `:pg` process groups are cluster-wide by default. Any node can join groups and receive sensor data.
- **Recommendation**: Use integer-keyed ETS tables (not atom names) for per-socket buffers. Validate `:pg` group membership.

### 9.9 Research-Grade Synchronization (plans/PLAN-research-grade-synchronization.md)

**Security Impact: LOW-MEDIUM**

- **Risk**: Pythonx (NIF) introduces native code execution. Python dependency chain (`scipy`, `neurokit2`, `pywt`, `pyrqa`, `networkx`) significantly expands the attack surface via supply chain.
- **Risk**: New `sync_reports` PostgreSQL table stores JSONB results. Ensure no user-controlled strings are stored without sanitization.
- **Risk**: Post-hoc analysis runs potentially expensive computations (CRQA is O(T^2)). Unbounded session data could cause OOM.
- **Recommendation**: Pin Python dependency versions. Limit maximum session length for analysis. Run Pythonx computations in a sandboxed Task with memory limits. Validate JSONB payloads before storage.

### 9.10 TURN/Cloudflare (plans/PLAN-turn-cloudflare.md) - IMPLEMENTED

**Security Impact: LOW**

- **Positive**: Uses `persistent_term` for credential caching (no GenServer state to leak).
- **Positive**: Credentials are ephemeral (24h TTL) and auto-refresh.
- **Positive**: Graceful degradation when Cloudflare API is unavailable.
- **Risk**: `CLOUDFLARE_TURN_API_TOKEN` is a long-lived secret. If compromised, attacker can generate TURN credentials and relay traffic through your Cloudflare account.
- **Recommendation**: Rotate Cloudflare API tokens periodically. Monitor Cloudflare TURN usage for anomalies.

### Security Implications Summary Matrix

| Plan | Impact | Auth | Data | Network | Priority |
|------|--------|------|------|---------|----------|
| Room Iroh Migration | MEDIUM | Lost Ash policies | No encryption-at-rest | P2P trust boundary | Before migration |
| Adaptive Video | LOW | N/A | Snapshot size validation | N/A | Low priority |
| Sensor Component | LOW | N/A | N/A | N/A | No action needed |
| Startup Optimization | NONE | N/A | N/A | N/A | No action needed |
| Delta Encoding | LOW-MED | N/A | Binary parsing validation | N/A | During implementation |
| Cluster Visibility | MEDIUM | Node authorization | Cross-node data access | RPC surface | Before implementation |
| Distributed Discovery | MEDIUM | Node validation | ETS access control | PubSub poisoning | Before implementation |
| Sensor Scaling | LOW-MED | N/A | Atom exhaustion risk | pg group access | During implementation |
| Research Sync | LOW-MED | N/A | JSONB sanitization | Python supply chain | During implementation |
| TURN/Cloudflare | LOW | Token rotation | N/A | Relay abuse | Monitoring |

---

## 10. Implementation Roadmap

### Phase 1: Immediate (1-2 days)
- [ ] Reduce token lifetime from 10 years to 30 days (H-001)
- [x] Gate "missing" token behind configuration (M-001) -- **already implemented**
- [x] Replace `String.to_atom` in bridge.ex with SafeKeys (H-004) -- **verified: not present in code**
- [x] Use `Plug.Crypto.secure_compare` for guest tokens (M-005) -- **already implemented**
- [x] Protect /dev/mailbox route (M-006) -- **already behind `dev_routes`**
- [x] Gate debug endpoint behind dev_routes (M-003) -- **already behind `dev_routes`**
- [x] Add session cookie encryption_salt (M-004) -- **already implemented**

### Phase 2: Short-term (1 week)
- [ ] Add socket-level authentication to UserSocket (H-002)
- [ ] Add auth pipeline to room API endpoints (H-003)
- [ ] Fix rate limiter to cover GET-based auth routes (M-007)
- [ ] Integrate Paraxial.io for bot protection (H-005)
- [ ] Add Content-Security-Policy headers

### Phase 3: Medium-term (2-4 weeks)
- [ ] Implement refresh token pattern
- [ ] Add MFA for admin operations
- [ ] Security monitoring/alerting setup
- [ ] Pre-migration security review for Room Iroh Migration
- [ ] Pre-migration security review for Cluster Visibility plans
- [ ] Require bridge token in production (M-002)

### Phase 4: Ongoing
- [ ] Penetration testing
- [ ] Python dependency auditing (for research-grade sync)
- [ ] Cloudflare TURN token rotation schedule
- [ ] Node authorization for distributed features

---

## 11. Security Configuration Checklist

```elixir
# config/prod.exs - Recommended security settings
config :sensocto,
  allow_missing_token: false,
  bridge_token: System.fetch_env!("BRIDGE_TOKEN")

config :sensocto, SensoctoWeb.Endpoint,
  check_origin: [
    "https://sensocto.ddns.net",
    "https://#{System.get_env("PHX_HOST")}",
    "https://sensocto.fly.dev"
  ]

config :sensocto, :memory_pressure,
  protection_start: 0.85,
  critical: 0.92

# Paraxial.io (recommended addition)
config :paraxial,
  api_key: System.get_env("PARAXIAL_API_KEY"),
  fetch_cloud_ips: true
```

---

## 12. Changes Applied (Feb 15, 2026)

The following improvements were made during low-hanging fruit optimization rounds:

1. **IO.puts/IO.inspect cleanup**: Replaced debug output with `Logger.debug` in 6 files (registry_utils.ex, lobby_live.ex, index_live.ex, sense_live.ex, otp_dsl_genserver.ex). Prevents information leakage via stdout and enables proper log filtering.
2. **GenServer call timeouts**: Added explicit `@call_timeout 3_000` to RoomPresenceServer (8 client functions), complementing existing timeouts in RoomStore, SimpleSensor, and AttentionTracker.
3. **Email sender centralization**: Replaced hardcoded/placeholder sender addresses in 3 email sender modules with `Application.get_env(:sensocto, :mailer_from)`. Added env var override in `runtime.exs` for production flexibility.
4. **SafeKeys migration**: ConnectorServer and SensorServer now use SafeKeys whitelist for atom conversion, preventing atom exhaustion from external input.
5. **ETS write_concurrency**: Enabled on Bio module ETS tables, PriorityLens tables, and AttentionTracker tables for improved concurrent write performance.
6. **Bio.Supervisor restart limits**: Added explicit `max_restarts: 10, max_seconds: 60` (was using defaults 3/5s which was too aggressive for non-critical bio components).

---

## References

- [Ash Authentication Documentation](https://hexdocs.pm/ash_authentication/)
- [Phoenix Security Best Practices](https://hexdocs.pm/phoenix/security.html)
- [Paraxial.io Documentation](https://hexdocs.pm/paraxial/)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [Elixir Security Best Practices](https://paraxial.io/blog/elixir-security)

---

*Report generated by Security Advisor Agent (Claude Opus 4.6). Last updated: 2026-02-16*

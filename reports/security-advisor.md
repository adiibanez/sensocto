# Security Assessment Report: Sensocto Platform

**Assessment Date:** 2026-02-08
**Previous Assessment:** 2026-02-05
**Assessor:** Security Advisor Agent (Claude Opus 4.6)
**Platform Version:** Current main branch
**Risk Framework:** OWASP Top 10 2021 + Elixir/Phoenix Best Practices

---

## Executive Summary

The Sensocto platform demonstrates a **mature security posture** with well-implemented security controls. This assessment identifies several areas requiring attention while acknowledging significant improvements since previous reviews.

**Overall Security Grade: B+ (Good)**

### Key Changes Since Last Assessment (2026-02-05 to 2026-02-08)

- **IMPROVED**: Serverside sync calculation added
- **IMPROVED**: Graph improvements and tooltips
- **STABLE**: Rate limiting, SafeKeys, backpressure systems all verified

### Priority Findings Summary

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| H-001 | HIGH | 10-year token lifetime | Open |
| H-002 | HIGH | No socket-level authentication (UserSocket) | Open |
| H-003 | HIGH | API room endpoints missing auth pipeline | **NEW** |
| H-004 | HIGH | Bridge.decode/1 atom exhaustion via `String.to_atom` | **NEW** |
| H-005 | HIGH | No bot protection | Open |
| M-001 | MEDIUM | "missing" token development backdoor | Open |
| M-002 | MEDIUM | Bridge token not required | Open |
| M-003 | MEDIUM | Debug endpoint exposed in production | **NEW** |
| M-004 | MEDIUM | Session cookie not encrypted | **NEW** |
| M-005 | MEDIUM | Timing-unsafe guest token comparison | **NEW** |
| M-006 | MEDIUM | /dev/mailbox route not gated | Open |
| L-001 | LOW | No force_ssl / HSTS | **NEW** |

---

## 1. Authentication Architecture

### 1.1 Overview

Sensocto uses **Ash Authentication** with multiple authentication strategies:

| Strategy | Status | Security Notes |
|----------|--------|----------------|
| Google OAuth | Active | Client credentials via environment variables |
| Magic Link | Active | 1-hour token lifetime, `require_interaction?: true` |
| Password | Commented Out | Available but disabled - passwordless preferred |
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
- Allows anonymous connections to sensor data and call channels

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

```elixir
"missing" ->
  Logger.debug("Authorization allowed: guest/development access...")
  true  # BYPASSES ALL AUTHENTICATION
```

**Recommendation**: Gate behind environment check using `Application.get_env(:sensocto, :allow_missing_token, false)`.

### 2.3 Bridge Socket (M-002)

**File:** `lib/sensocto_web/channels/bridge_socket.ex`

Bridge token validation is optional - missing token allows connection.

---

## 3. New Findings

### 3.1 API Room Endpoints Missing Auth Pipeline (H-003)

**File:** `lib/sensocto_web/router.ex` (lines 200-221)

The `/api/rooms/*` scope has no `pipe_through` at all - no `:api` pipeline, no `:load_from_bearer`, no rate limiting. `RoomTicketController.show/2` reads from `conn.assigns[:current_user]` which will always be nil since no plug populates it.

**Risk**: Unauthenticated access to room management API endpoints.

**Recommendation**: Add `pipe_through [:api, :load_from_bearer]` to the rooms API scope.

### 3.2 Bridge.decode/1 Atom Exhaustion (H-004)

**File:** `lib/sensocto/bridge.ex` (lines 178-179)

Uses `String.to_atom(name)` on untrusted input from the bridge protocol. The safe alternative `SafeKeys.safe_bridge_atom/1` already exists in the codebase but is not used here.

**Risk**: Remote atom table exhaustion via crafted bridge messages.

**Recommendation**: Replace `String.to_atom(name)` with `SafeKeys.safe_bridge_atom(name)`.

### 3.3 Debug Endpoint Exposed (M-003)

**File:** `lib/sensocto_web/router.ex` (line 197)

`POST /api/auth/debug` calls `MobileAuthController.debug_verify/2` which returns all user IDs from the database in error messages.

**Risk**: Information disclosure in production.

**Recommendation**: Wrap in `if Application.compile_env(:sensocto, :dev_routes)`.

### 3.4 Session Cookie Not Encrypted (M-004)

**File:** `lib/sensocto_web/endpoint.ex` (lines 12-20)

Session cookie uses `signing_salt` but no `encryption_salt`, meaning session data is readable (though not tamperable).

**Recommendation**: Add `encryption_salt` to session configuration.

### 3.5 Timing-Unsafe Token Comparison (M-005)

**File:** `lib/sensocto_web/controllers/guest_auth_controller.ex` (line 14)

Uses `guest.token == token` instead of `Plug.Crypto.secure_compare/2`. Same issue in `sensor_data_channel.ex` (line 514).

**Risk**: Timing side-channel attack on token comparison.

**Recommendation**: Use `Plug.Crypto.secure_compare/2` for all token comparisons (already used correctly in `authenticated_tidewave.ex`).

### 3.6 No force_ssl / HSTS (L-001)

**File:** `config/runtime.exs` (lines 226-232)

The `force_ssl` configuration is commented out. While Fly.io handles TLS termination, HSTS provides defense-in-depth.

---

## 4. Verified Security Controls (Excellent)

### 4.1 Rate Limiting

**File:** `lib/sensocto_web/plugs/rate_limiter.ex`

- ETS-based sliding window counter
- Per-IP, per-endpoint-type buckets
- Proper X-Forwarded-For header handling
- Separate limits: auth (10/min), registration (5/min), API (20/min), guest (10/min)

**Assessment: Excellent**

### 4.2 Atom Exhaustion Protection

**File:** `lib/sensocto/types/safe_keys.ex`

Whitelist approach with comprehensive allowed keys list. **Assessment: Excellent** (except H-004 bypass in bridge.ex).

### 4.3 DoS Resistance

| Mechanism | Implementation | Effectiveness |
|-----------|---------------|---------------|
| Rate Limiting | ETS-based sliding window | High |
| Backpressure | PriorityLens quality levels | High |
| Memory Protection | 85%/92% thresholds | High |
| Socket Cleanup | Monitor + periodic GC | High |
| Request Timeouts | 2-5 second limits | Medium |

### 4.4 Security Headers

**File:** `lib/sensocto_web/endpoint.ex`

- x-frame-options: SAMEORIGIN
- x-content-type-options: nosniff
- x-xss-protection: 1; mode=block
- referrer-policy: strict-origin-when-cross-origin

### 4.5 Ash Policies

Default-deny on User and Token resources. **Assessment: Excellent**

### 4.6 Request Logger

**File:** `lib/sensocto_web/plugs/request_logger.ex`

Properly sanitizes sensitive data. **Assessment: Excellent**

### 4.7 Authenticated Tidewave

**File:** `lib/sensocto_web/plugs/authenticated_tidewave.ex`

Uses `Plug.Crypto.secure_compare/2` for timing-safe comparison. **Assessment: Excellent**

---

## 5. Bot Protection Recommendation (H-005)

**Why Paraxial.io for Sensocto:**

1. **Native Elixir Integration**: Designed specifically for Phoenix/LiveView
2. **Invisible Security**: Bot detection without CAPTCHAs degrading UX
3. **IP Intelligence**: Real-time reputation scoring
4. **Minimal Overhead**: Designed for Elixir's concurrency model

---

## 6. /dev/mailbox Route (M-006)

**File:** `lib/sensocto_web/router.ex` (lines 229-232)

```elixir
scope "/dev" do
  pipe_through :browser
  forward "/mailbox", Plug.Swoosh.MailboxPreview
end
```

Not wrapped in `dev_routes` conditional. **Risk**: May expose email contents in production.

---

## 7. Security Metrics

### Authentication Security Score: B

| Metric | Score | Notes |
|--------|-------|-------|
| Strategy Security | A | Magic Link with interaction required |
| Token Storage | A | Database-backed with revocation |
| Token Lifetime | D | 10 years is excessive |
| MFA | F | Not implemented |
| Rate Limiting | A | Comprehensive implementation |

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
| Atom Protection | B+ | SafeKeys excellent, bridge.ex bypass |
| SQL Injection | A | Ecto parameterized queries |
| XSS Prevention | B | Headers good, CSP missing |

### DoS Resistance Score: A

| Metric | Score | Notes |
|--------|-------|-------|
| Rate Limiting | A | Multi-tier implementation |
| Backpressure | A | Quality-based throttling |
| Memory Protection | A | Configurable thresholds |
| Resource Cleanup | A | Monitor + GC patterns |

---

## 8. Planned Work: Security Implications

### 8.1 Room Iroh Migration (PLAN-room-iroh-migration.md)

**Security Impact: MEDIUM**

- **Risk**: Moving from PostgreSQL (with Ash policies) to in-memory GenServer + Iroh docs removes the authorization layer. Room CRUD operations currently go through Ash which enforces default-deny policies. The new `RoomStore` GenServer has no equivalent access control.
- **Risk**: Iroh P2P sync introduces a new trust boundary. Data synced between nodes via Iroh docs must be validated on receipt to prevent poisoned state propagation.
- **Risk**: No encryption-at-rest. PostgreSQL had this via disk encryption; in-memory + Iroh docs need explicit encryption for sensitive room data.
- **Recommendation**: Implement authorization checks in `RoomStore` API functions before migration. Validate all Iroh-synced data. Consider encrypting room metadata in Iroh docs.

### 8.2 Adaptive Video Quality (PLAN-adaptive-video-quality.md) - IMPLEMENTED

**Security Impact: LOW**

- **Positive**: SnapshotManager uses ETS with TTL-based cleanup (60s), preventing unbounded memory growth from snapshot data.
- **Risk**: `video_snapshot` channel event broadcasts base64-encoded JPEG data. No size validation on incoming snapshots could allow memory exhaustion via oversized payloads.
- **Recommendation**: Add max size validation (e.g., 100KB) for incoming `video_snapshot` events in `call_channel.ex`.

### 8.3 Sensor Component Migration (PLAN-sensor-component-migration.md)

**Security Impact: LOW**

- Purely internal architecture change (LiveView → LiveComponent). No new attack surface.
- **Positive**: Reduces process count from 73 to 1, reducing the surface for process-targeting attacks.

### 8.4 Startup Optimization (PLAN-startup-optimization.md) - IMPLEMENTED

**Security Impact: NONE**

- Deferred hydration timing only. No security implications.
- **Positive**: Faster HTTP server availability means health checks respond sooner, reducing window where the app is unprotected.

### 8.5 Delta Encoding ECG (plans/delta-encoding-ecg.md)

**Security Impact: LOW-MEDIUM**

- **Risk**: Binary protocol parsing (both Elixir encoder and JS decoder) introduces potential for buffer-related bugs. Malformed binary data could cause decoder errors or unexpected behavior.
- **Risk**: Feature flag via `Application.get_env` is mutable at runtime via IEx. An attacker with IEx access could toggle encoding to disrupt data flow.
- **Recommendation**: Validate binary header version and bounds-check all offsets in the decoder. Use `:persistent_term` for the feature flag (harder to tamper).

### 8.6 Cluster Sensor Visibility (plans/PLAN-cluster-sensor-visibility.md)

**Security Impact: MEDIUM**

- **Risk**: Migrating to Horde.Registry makes sensor processes discoverable from any node. Currently, sensors are only visible on their local node, providing implicit isolation.
- **Risk**: Cross-node sensor state fetching via PubSub request/reply or `:rpc.call` introduces new RPC surface. Malicious node could request sensitive sensor data.
- **Recommendation**: Validate node membership before processing cross-node requests. Use libcluster's node authorization. Rate-limit cross-node state requests.

### 8.7 Distributed Discovery (plans/PLAN-distributed-discovery.md)

**Security Impact: MEDIUM**

- **Risk**: DiscoveryCache stores sensor/room metadata in ETS with `:public` access. Any process on the node can read/write this data.
- **Risk**: PubSub-based sync (`discovery:sensors` topic) could be poisoned by a compromised node broadcasting fake sensor registrations.
- **Risk**: Circuit breaker `NodeHealth` uses `:net_kernel.monitor_nodes(true)` - should validate that joining nodes are authorized.
- **Recommendation**: Use `:protected` ETS tables instead of `:public`. Validate discovery events against Horde registry state. Ensure libcluster's topology configuration restricts which nodes can join.

### 8.8 Sensor Scaling Refactor (plans/PLAN-sensor-scaling-refactor.md)

**Security Impact: LOW-MEDIUM**

- **Risk**: Per-socket ETS tables (`:"lens_buffer_#{socket_id}"`) use dynamically generated atom names. If `socket_id` comes from untrusted input, this is an atom exhaustion vector.
- **Risk**: `:pg` process groups are cluster-wide by default. Any node can join groups and receive sensor data.
- **Recommendation**: Use integer-keyed ETS tables (not atom names) for per-socket buffers. Validate `:pg` group membership.

### 8.9 Research-Grade Synchronization (plans/PLAN-research-grade-synchronization.md)

**Security Impact: LOW-MEDIUM**

- **Risk**: Pythonx (NIF) introduces native code execution. Python dependency chain (`scipy`, `neurokit2`, `pywt`, `pyrqa`, `networkx`) significantly expands the attack surface via supply chain.
- **Risk**: New `sync_reports` PostgreSQL table stores JSONB results. Ensure no user-controlled strings are stored without sanitization.
- **Risk**: Post-hoc analysis runs potentially expensive computations (CRQA is O(T^2)). Unbounded session data could cause OOM.
- **Recommendation**: Pin Python dependency versions. Limit maximum session length for analysis. Run Pythonx computations in a sandboxed Task with memory limits. Validate JSONB payloads before storage.

### 8.10 TURN/Cloudflare (plans/PLAN-turn-cloudflare.md) - IMPLEMENTED

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

## 9. Implementation Roadmap

### Phase 1: Immediate (1-2 days)
- [ ] Reduce token lifetime from 10 years to 30 days (H-001)
- [ ] Gate "missing" token behind configuration (M-001)
- [ ] Replace `String.to_atom` in bridge.ex with SafeKeys (H-004)
- [ ] Use `Plug.Crypto.secure_compare` for guest tokens (M-005)
- [ ] Protect /dev/mailbox route (M-006)
- [ ] Gate debug endpoint behind dev_routes (M-003)

### Phase 2: Short-term (1 week)
- [ ] Add socket-level authentication to UserSocket (H-002)
- [ ] Add auth pipeline to room API endpoints (H-003)
- [ ] Add session cookie encryption_salt (M-004)
- [ ] Integrate Paraxial.io for bot protection (H-005)
- [ ] Add Content-Security-Policy headers

### Phase 3: Medium-term (2-4 weeks)
- [ ] Implement refresh token pattern
- [ ] Add MFA for admin operations
- [ ] Security monitoring/alerting setup
- [ ] Pre-migration security review for Room Iroh Migration
- [ ] Pre-migration security review for Cluster Visibility plans

### Phase 4: Ongoing
- [ ] Penetration testing
- [ ] Python dependency auditing (for research-grade sync)
- [ ] Cloudflare TURN token rotation schedule
- [ ] Node authorization for distributed features

---

## 10. Security Configuration Checklist

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

## References

- [Ash Authentication Documentation](https://hexdocs.pm/ash_authentication/)
- [Phoenix Security Best Practices](https://hexdocs.pm/phoenix/security.html)
- [Paraxial.io Documentation](https://hexdocs.pm/paraxial/)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [Elixir Security Best Practices](https://paraxial.io/blog/elixir-security)

---

*Report generated by Security Advisor Agent (Claude Opus 4.6). Last updated: 2026-02-08*

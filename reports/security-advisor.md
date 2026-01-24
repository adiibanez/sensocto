# Sensocto Security Assessment Report

**Assessment Date**: January 12, 2026 (Updated: January 20, 2026)
**Assessor**: Claude Security Advisor
**Application**: Sensocto - IoT Sensor Platform
**Technology Stack**: Elixir, Phoenix, Ash Framework, PostgreSQL, WebSockets, WebRTC

---

## Executive Summary

This security assessment covers the Sensocto IoT sensor platform, an Elixir/Phoenix application that provides real-time sensor data visualization, room-based collaboration, video/voice calling, and user authentication.

### Overall Security Posture: **LOW RISK** ✅ (Improved)

---

## 🆕 Update: January 20, 2026

### Resolved Issues (Verified)

| ID | Issue | Status | Evidence |
|----|-------|--------|----------|
| **H-003** | Weak Sensor Channel Authorization | ✅ **RESOLVED** | `lib/sensocto_web/channels/sensor_data_channel.ex` lines 404-444 now properly validates JWT tokens using `AshAuthentication.Jwt.verify(token, :sensocto)` |
| **L-006** | Session Cookie Max Age | ✅ **RESOLVED** | `lib/sensocto_web/endpoint.ex` line 17: `max_age: 2_592_000` (30 days) |
| **M-001** | Excessive Token Lifetime | ✅ **RESOLVED** | `lib/sensocto/accounts/user.ex` line 26: `token_lifetime {14, :days}` |
| **H-002** | Request Logger Sensitive Data | ✅ **RESOLVED** | Comprehensive sanitization with `@sensitive_params`, `@sensitive_headers`, `@sensitive_cookies` |
| **C-001/C-002** | Hardcoded Credentials | ✅ **RESOLVED** | All secrets use environment variables with safe development defaults |
| **H-001** | WebSocket Origin Check | ✅ **RESOLVED** | `check_origin` properly configured in both dev and prod |
| **L-003** | Missing Security Headers | ✅ **RESOLVED** | X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy added |

### Remaining Open Issues

#### M-002: No Rate Limiting on Authentication (MEDIUM)
**Status**: Open - Recommend implementing Paraxial.io

No rate limiting exists on:
- Magic link requests (`/auth/user/magic_link`)
- API authentication endpoints (`/api/auth/verify`)
- Room ticket generation endpoints

**Recommendation**: Add Paraxial.io to `mix.exs`:
```elixir
{:paraxial, "~> 2.7"}
```

Paraxial.io provides native Elixir integration with:
- Bot detection without CAPTCHAs
- IP intelligence and reputation scoring
- Application-level rate limiting
- Real-time threat dashboards

#### M-004: Missing Content Security Policy (MEDIUM)
**File**: `lib/sensocto_web/endpoint.ex`

Add CSP header to the existing security headers configuration for XSS protection.

#### L-005: Dev Mailbox Route (LOW)
**File**: `lib/sensocto_web/router.ex` lines 188-191

The `/dev/mailbox` route is not wrapped in the `dev_routes` conditional. Consider protecting it.

#### L-007: UserSocket Anonymous Connection (LOW - Informational)
**File**: `lib/sensocto_web/channels/user_socket.ex`

Socket-level authentication is not implemented (acceptable since channel-level auth is properly enforced).

### Positive Security Implementations Verified

1. **Sensor Channel JWT Validation**: Bearer tokens now verified via `AshAuthentication.Jwt.verify/2`
2. **SafeKeys Module**: Prevents atom exhaustion attacks with whitelisted keys
3. **Call Channel Authorization**: Room membership validated via `Calls.can_join_call?/2`
4. **Room API Authorization**: JWT verification and membership checks in place
5. **Magic Link Security**: Uses `require_interaction? true` preventing automatic token consumption
6. **Admin Route Protection**: Basic auth via `AUTH_USERNAME` and `AUTH_PASSWORD` environment variables
7. **Ash Policy Authorizer**: Resource-level policies on User, Token, SensorManager

### Priority Actions

1. **Immediate**: Add rate limiting (Paraxial.io recommended)
2. **Short-term**: Add Content Security Policy headers
3. **Medium-term**: Consider socket-level authentication for defense in depth

---

## Previous Update: January 17, 2026

### Issues Resolved in January 17 Assessment

| ID | Issue | Status | Notes |
|----|-------|--------|-------|
| **C-001** | Hardcoded Database Credentials | ✅ **RESOLVED** | Database credentials now use environment variables with safe local defaults |
| **C-002** | Hardcoded Secret Keys | ✅ **RESOLVED** | `secret_key_base` and `token_signing_secret` now use environment variables. Development defaults clearly marked as non-production values |
| **H-001** | WebSocket Origin Check Disabled | ✅ **RESOLVED** | Development: `check_origin: ["http://localhost:4000", "https://localhost:4001"]`. Production: Properly configured with allowed domains |
| **H-002** | Request Logger Exposes Sensitive Data | ✅ **RESOLVED** | `lib/sensocto_web/plugs/request_logger.ex` now implements comprehensive sanitization of passwords, tokens, headers, and cookies |
| **L-003** | Missing Security Headers | ✅ **RESOLVED** | Added X-Frame-Options, X-Content-Type-Options, X-XSS-Protection, Referrer-Policy in `lib/sensocto_web/endpoint.ex` |

---

## Original Assessment (January 12, 2026)

### Overall Security Posture: **MEDIUM RISK** (Historical)

The application demonstrates good foundational security practices leveraging the Ash Framework's built-in security features. However, several critical and high-severity issues were identified that require immediate attention:

**Critical Issues (2)**:
1. Hardcoded database credentials in development configuration committed to version control
2. Hardcoded secret keys and token signing secrets in configuration files

**High Issues (3)**:
1. WebSocket origin checking disabled (`check_origin: false`) in both development and production
2. Request logging plug exposes sensitive data (cookies, headers, params) in debug logs
3. Overly permissive CORS/origin configuration for WebRTC calls

**Medium Issues (5)**:
1. Very long token lifetime (365 days) increases token theft risk window
2. No rate limiting on authentication endpoints
3. Neo4j default credentials hardcoded in configuration
4. Missing Content Security Policy headers
5. Debug routes enabled without sufficient protection

**Low Issues (4)**:
1. Information disclosure via debug authentication failures logging
2. Development-only sensitive data exposure flag enabled
3. TURN server credentials passed via environment without rotation mechanism
4. Missing security headers (X-Frame-Options, X-Content-Type-Options)

---

## Security Architecture Overview

### Authentication System

The application uses **AshAuthentication** with multiple authentication strategies:

1. **Google OAuth2**: External identity provider integration
2. **Magic Link**: Passwordless email-based authentication
3. **Password Authentication**: Traditional email/password (partially configured)

**Token Management**:
- JWT tokens with configurable signing secret
- Token storage in database via `Sensocto.Accounts.Token`
- Token lifetime: 365 days (1 year)

### Authorization Model

- **Ash Policy Authorizer**: Integrated at the resource level
- **Room-based Access Control**: Owner, Admin, Member roles
- **LiveView Authentication**: Custom `on_mount` hooks for session validation

### Data Flow

```
Client <-> Phoenix Endpoint <-> Router <-> LiveView/Controller
                                   |
                                   v
                            Ash Resources <-> PostgreSQL
                                   |
                                   v
                            WebSocket Channels <-> Sensor Data
```

---

## Detailed Findings

### CRITICAL FINDINGS

#### C-001: Hardcoded Database Credentials in Version Control

**Severity**: Critical
**Category**: Secrets Management
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/dev.exs`
**Lines**: 8, 22

**Current State**:
```elixir
# config/dev.exs lines 6-10
config :sensocto, Sensocto.Repo,
  database: "neondb",
  username: "neondb_owner",
  password: "npg_JYAldE0u5Xmk",  # CRITICAL: Hardcoded production-grade credential
  hostname: "ep-dark-mountain-a2nvkl0o-pooler.eu-central-1.aws.neon.tech",
```

**Risk**: The Neon.tech database credentials are hardcoded in the development configuration file. If this file is committed to a public or shared repository, attackers gain direct database access. The hostname suggests this is a real cloud-hosted database, not a local development instance.

**Recommendation**:
1. Immediately rotate the Neon.tech database password
2. Move all database credentials to environment variables
3. Use `.env` files that are gitignored (already present in `.gitignore`)
4. Consider using a secrets manager (Vault, AWS Secrets Manager, Fly.io secrets)

```elixir
# Recommended approach in config/dev.exs
config :sensocto, Sensocto.Repo,
  database: System.get_env("DEV_DATABASE_NAME", "sensocto_dev"),
  username: System.get_env("DEV_DATABASE_USER", "postgres"),
  password: System.get_env("DEV_DATABASE_PASSWORD"),
  hostname: System.get_env("DEV_DATABASE_HOST", "localhost")
```

---

#### C-002: Hardcoded Secret Keys in Configuration

**Severity**: Critical
**Category**: Secrets Management
**Files**:
- `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/dev.exs` (lines 78, 176)
- `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/test.exs` (lines 2, 21)

**Current State**:
```elixir
# config/dev.exs line 78
secret_key_base: "0EViyDRvvk8yO72jkyPMGrvTm0iqLuDckbHUdqrBkZb2Td2NDLkS590D08E9qLL6",

# config/dev.exs line 176
token_signing_secret: "9fhsVJSpOCeIGPWB7AL7/Q3Emgy34xJK"
```

**Risk**:
- `secret_key_base` is used to sign cookies and session data. If compromised, attackers can forge sessions.
- `token_signing_secret` is used to sign JWTs. If compromised, attackers can forge authentication tokens.

**Recommendation**:
1. Generate new secrets: `mix phx.gen.secret`
2. Store all secrets in environment variables
3. Add pre-commit hooks to detect secrets in code

---

### HIGH FINDINGS

#### H-001: WebSocket Origin Check Disabled

**Severity**: High
**Category**: Cross-Site WebSocket Hijacking
**Files**:
- `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/dev.exs` (line 75)
- `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/prod.exs` (line 36)

**Current State**:
```elixir
# config/dev.exs line 75
check_origin: false,

# config/prod.exs line 36
check_origin: false
```

**Risk**: Disabling `check_origin` allows any website to establish WebSocket connections to the application. This enables Cross-Site WebSocket Hijacking (CSWSH) attacks where malicious sites can:
- Read sensor data in real-time
- Join rooms without user consent
- Potentially manipulate sensor data if write operations are exposed

**Recommendation**:
```elixir
# config/prod.exs - Enable strict origin checking
config :sensocto, SensoctoWeb.Endpoint,
  check_origin: ["https://sensocto.ddns.net", "https://yourdomain.com"]

# config/dev.exs - Use specific origins even in development
config :sensocto, SensoctoWeb.Endpoint,
  check_origin: ["http://localhost:4000", "https://localhost:4001"]
```

---

#### H-002: Request Logger Exposes Sensitive Data

**Severity**: High
**Category**: Information Disclosure
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto_web/plugs/request_logger.ex`
**Lines**: 16-26

**Current State**:
```elixir
defp log_cookies(conn) do
  Logger.debug("Cookies: #{inspect(conn.cookies)}")  # Logs all cookies including session tokens
end

defp log_headers(conn) do
  Logger.debug("Headers: #{inspect(conn.req_headers)}")  # Logs Authorization headers
end

defp log_params(conn) do
  Logger.debug("Request Parameters: #{inspect(conn.params)}")  # Logs passwords, tokens
end
```

**Risk**: This plug logs all cookies (including session tokens), all headers (including Authorization headers), and all request parameters (including passwords and sensitive data). Even in debug mode, these logs may be persisted and could expose credentials.

**Recommendation**:
1. Remove this plug from production
2. Filter sensitive parameters before logging
3. Use structured logging with explicit field selection

```elixir
defmodule SensoctoWeb.Plugs.RequestLogger do
  @sensitive_params ~w(password password_confirmation token api_key secret)
  @sensitive_headers ~w(authorization cookie)

  defp sanitize_params(params) do
    Enum.reduce(@sensitive_params, params, fn key, acc ->
      if Map.has_key?(acc, key), do: Map.put(acc, key, "[FILTERED]"), else: acc
    end)
  end
end
```

---

#### H-003: Missing CORS/Origin Protection for WebRTC

**Severity**: High
**Category**: Cross-Origin Security
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto_web/channels/call_channel.ex`

**Current State**: The CallChannel handles WebRTC signaling without explicit origin validation beyond Phoenix's disabled check_origin.

**Risk**: Combined with H-001, malicious sites can join video/voice calls without user consent, potentially eavesdropping on conversations.

**Recommendation**:
1. Enable `check_origin` in production (fixes H-001)
2. Add room membership validation in the channel join handler
3. Require explicit user consent before joining calls

---

### MEDIUM FINDINGS

#### M-001: Excessive Token Lifetime

**Severity**: Medium
**Category**: Session Management
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto/accounts/user.ex`
**Lines**: 21-22

**Current State**:
```elixir
tokens do
  enabled? true
  token_resource Sensocto.Accounts.Token
  signing_secret Sensocto.Secrets
  store_all_tokens? true
  token_lifetime {365, :days}  # 1 year token lifetime
end
```

**Risk**: A one-year token lifetime significantly extends the attack window if a token is compromised. Tokens can be stolen via XSS, network interception, or device theft.

**Recommendation**:
- Reduce token lifetime to 7-30 days for web sessions
- Implement token refresh mechanism
- Consider shorter lifetimes (1-4 hours) with refresh tokens

```elixir
tokens do
  token_lifetime {7, :days}
  # Implement refresh tokens for better security
end
```

---

#### M-002: No Rate Limiting on Authentication

**Severity**: Medium
**Category**: Authentication Security
**Files**: Router, Auth Controller, LiveView authentication

**Current State**: No rate limiting is implemented on:
- Magic link requests
- Password login attempts
- Password reset requests
- Google OAuth callbacks

**Risk**: Attackers can perform:
- Brute force attacks on password endpoints
- Email enumeration via timing attacks on magic link requests
- Resource exhaustion via repeated authentication attempts

**Recommendation**: Implement Paraxial.io for comprehensive rate limiting and bot protection.

```elixir
# In mix.exs
{:paraxial, "~> 2.7"}

# In endpoint.ex
plug Paraxial.AllowedPlug
```

Paraxial.io provides:
- Native Elixir integration designed for Phoenix/LiveView
- Bot detection without degrading UX with CAPTCHAs
- IP intelligence and reputation scoring
- Application-level rate limiting
- Invisible security measures
- Real-time threat dashboards

Alternatively, implement basic rate limiting with Hammer:
```elixir
defmodule SensoctoWeb.Plugs.RateLimiter do
  import Plug.Conn

  def rate_limit_auth(conn, _opts) do
    case Hammer.check_rate("auth:#{conn.remote_ip}", 60_000, 10) do
      {:allow, _count} -> conn
      {:deny, _limit} ->
        conn
        |> send_resp(429, "Too many requests")
        |> halt()
    end
  end
end
```

---

#### M-003: Hardcoded Neo4j Credentials

**Severity**: Medium
**Category**: Secrets Management
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/config.exs`
**Lines**: 52-55

**Current State**:
```elixir
config :boltx, Bolt,
  uri: "bolt://localhost:7687",
  auth: [username: "neo4j", password: "sensocto123"],
  pool_size: 10
```

**Risk**: Default/weak Neo4j credentials are committed to version control. If Neo4j is exposed or the codebase is leaked, the graph database is immediately compromised.

**Recommendation**:
```elixir
config :boltx, Bolt,
  uri: System.get_env("NEO4J_URI", "bolt://localhost:7687"),
  auth: [
    username: System.get_env("NEO4J_USERNAME", "neo4j"),
    password: System.get_env("NEO4J_PASSWORD")
  ],
  pool_size: 10
```

---

#### M-004: Missing Content Security Policy

**Severity**: Medium
**Category**: XSS Prevention
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/lib/sensocto_web/endpoint.ex`

**Current State**: No Content Security Policy (CSP) headers are configured.

**Risk**: Without CSP, the application is more vulnerable to XSS attacks as browsers won't block unauthorized script execution.

**Recommendation**:
```elixir
# In endpoint.ex
plug :put_secure_browser_headers, %{
  "content-security-policy" => """
    default-src 'self';
    script-src 'self' 'unsafe-inline' https://www.youtube.com;
    style-src 'self' 'unsafe-inline';
    img-src 'self' data: https:;
    connect-src 'self' wss: https:;
    frame-src https://www.youtube.com;
  """
}
```

---

#### M-005: Debug Routes Enabled

**Severity**: Medium
**Category**: Information Disclosure
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/dev.exs`
**Line**: 176

**Current State**:
```elixir
config :sensocto, dev_routes: true, token_signing_secret: "..."
```

**Risk**: Development routes like `/dev/mailbox` and LiveDashboard may expose sensitive debugging information if accidentally enabled in production or if the development server is publicly accessible.

**Recommendation**:
1. Ensure `dev_routes: false` in production
2. Add IP-based restrictions for development routes
3. Consider authentication for LiveDashboard even in development

---

### LOW FINDINGS

#### L-001: Debug Authentication Failure Logging

**Severity**: Low
**Category**: Information Disclosure
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/dev.exs`
**Line**: 173

**Current State**:
```elixir
config :ash_authentication, debug_authentication_failures?: true
```

**Risk**: Detailed authentication failure messages may reveal information about valid usernames or authentication mechanisms.

**Recommendation**: Ensure this is `false` in production environments.

---

#### L-002: Sensitive Data Exposure on Connection Error

**Severity**: Low
**Category**: Information Disclosure
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/dev.exs`
**Line**: 12

**Current State**:
```elixir
show_sensitive_data_on_connection_error: true,
```

**Risk**: Database connection errors may expose connection strings, hostnames, and credentials in error messages.

**Recommendation**: Ensure this is `false` in production.

---

#### L-003: Missing Security Headers

**Severity**: Low
**Category**: Security Headers
**File**: Endpoint configuration

**Current State**: Missing recommended security headers.

**Recommendation**: Add comprehensive security headers:
```elixir
plug :put_secure_browser_headers, %{
  "x-frame-options" => "DENY",
  "x-content-type-options" => "nosniff",
  "x-xss-protection" => "1; mode=block",
  "referrer-policy" => "strict-origin-when-cross-origin",
  "permissions-policy" => "camera=(), microphone=(), geolocation=()"
}
```

---

#### L-004: Unrotated TURN Credentials

**Severity**: Low
**Category**: Credential Management
**File**: `/Users/adrianibanez/Documents/projects/2024_sensor-platform/sensocto/config/runtime.exs`
**Lines**: 37-51

**Current State**: TURN server credentials are loaded from environment variables without any rotation mechanism.

**Risk**: Long-lived TURN credentials could be abused if compromised.

**Recommendation**: Consider implementing time-based TURN credentials (TURN REST API) or regular credential rotation.

---

## Positive Security Observations

The following security best practices are already implemented:

1. **Ash Framework Authorization**: Resource-level policies with `Ash.Policy.Authorizer`
2. **Password Hashing**: AshAuthentication handles password hashing securely
3. **CSRF Protection**: Phoenix's built-in CSRF protection is enabled
4. **Parameterized Queries**: Ecto and Ash use parameterized queries, preventing SQL injection
5. **Token Storage**: Tokens are stored in the database for revocation capability
6. **SSL Configuration**: SSL is configured with strong cipher suites
7. **Environment-Based Configuration**: Production uses environment variables for secrets
8. **Confirmation Emails**: New user email confirmation is implemented
9. **Input Validation**: Ash Changesets provide structured input validation
10. **Room Authorization**: Owner/member checks are performed for room operations

---

## Recommendations Summary

### Immediate Actions (Within 24 hours)

1. **Rotate all compromised credentials**:
   - Neon.tech database password
   - Neo4j password
   - Generate new `secret_key_base` values

2. **Enable WebSocket origin checking** in production

3. **Remove or protect the RequestLogger plug**

### Short-Term Actions (Within 1 week)

1. **Implement rate limiting** using Paraxial.io or Hammer
2. **Reduce token lifetime** to 7-30 days
3. **Add Content Security Policy** headers
4. **Move all secrets to environment variables**

### Medium-Term Actions (Within 1 month)

1. **Implement comprehensive security headers**
2. **Add IP-based restrictions** for admin routes
3. **Set up security monitoring** and alerting
4. **Conduct penetration testing**
5. **Review and document security policies**

---

## Security Best Practices Recommendations

### For Signup/Authentication

1. **Passwordless First**: Continue promoting magic link authentication
2. **Progressive Security**: Add MFA for sensitive operations
3. **Bot Protection**: Implement Paraxial.io for invisible bot detection
4. **Account Recovery**: Implement secure account recovery flows

### For Real-Time Features

1. **Channel Authorization**: Add room membership validation to all channel joins
2. **Message Validation**: Use `MessageValidator` consistently across all channels
3. **Rate Limiting**: Implement per-user message rate limits
4. **Audit Logging**: Log security-relevant events

### For API Security

1. **API Versioning**: Implement API versioning for breaking changes
2. **Input Sanitization**: Use `SafeKeys` type consistently
3. **Output Encoding**: Ensure proper HTML encoding in all templates
4. **Error Handling**: Return generic error messages to clients

---

## Appendix: File References

| Finding | File | Lines |
|---------|------|-------|
| C-001 | config/dev.exs | 8, 22 |
| C-002 | config/dev.exs, config/test.exs | 78, 176, 2, 21 |
| H-001 | config/dev.exs, config/prod.exs | 75, 36 |
| H-002 | lib/sensocto_web/plugs/request_logger.ex | 16-26 |
| M-001 | lib/sensocto/accounts/user.ex | 21-22 |
| M-003 | config/config.exs | 52-55 |
| M-005 | config/dev.exs | 176 |
| L-001 | config/dev.exs | 173 |
| L-002 | config/dev.exs | 12 |

---

## Disclaimer

This security assessment was performed through static code analysis and configuration review. It does not include dynamic testing, penetration testing, or infrastructure security review. Additional vulnerabilities may exist that require hands-on testing to identify.

---

*Report generated by Claude Security Advisor*
*Anthropic Claude - Application Security Specialist for Elixir/Phoenix/Ash*

# Security Assessment Report: Sensocto Platform

**Assessment Date:** 2026-02-08 | **Updated:** 2026-03-25
**Previous Assessment:** 2026-03-01
**Assessor:** Security Advisor Agent (Claude Opus 4.6)
**Platform Version:** Current main branch
**Risk Framework:** OWASP Top 10 2021 + Elixir/Phoenix Best Practices

---

## Executive Summary

The Sensocto platform demonstrates a **mature security posture** with well-implemented security controls. This assessment identifies several areas requiring attention while acknowledging significant improvements since previous reviews.

**Overall Security Grade: A- (Very Good)** -- upgraded from B+ due to resolution of 6 findings.

### Key Changes Since Last Assessment (2026-03-01 to 2026-03-25)

| Change | Impact |
|--------|--------|
| LobbyChannel: new Phoenix channel for room list with user_id validation on join | **REVIEW NEEDED**: Join validates `socket.assigns.user_id == user_id`. But `room_to_json/1` exposes `join_code` to all channel subscribers. See M-015. |
| UserSocket: now validates `Phoenix.Token` with 24h max_age on connect | **IMPROVED**: Token verification added. However, invalid/missing tokens still fall back to `"anonymous"` with a warning log. H-002 partially addressed. |
| RateLimiter: GET requests now rate-limited for `:guest_auth` type | **RESOLVED M-007**: The `conn.method not in ["POST", "GET"]` guard plus `conn.method == "GET" and type != :guest_auth` correctly rate-limits guest auth GET requests. |
| ProfileLive: ownership checks added to `remove_skill` and `remove_connection` | **RESOLVED M-012**: Guards `when skill.user_id == user.id` and `when conn.from_user_id == user.id` added. |
| ProfileLive: `String.to_existing_atom(level)` replaced with explicit case matching | **RESOLVED M-013**: Explicit case matching on `"beginner"/"intermediate"/"expert"` with default to `:beginner`. |
| ChatComponent: `@max_message_length 1000` guard added to `send_message` | **RESOLVED L-008**: Messages exceeding 1000 bytes are rejected by the guard clause. |
| Plug.Parsers: `length: 4_000_000` added to endpoint | **RESOLVED L-003**: 4MB request body limit prevents oversized payloads. |
| UserSettingsLive: locale validated against compile-time `@valid_locale_codes` | **RESOLVED L-007**: `when locale in @valid_locale_codes` guard clause rejects invalid locales before redirect. |
| CustomSignInLive: reworked with sensor background, ball presence, locale support | **NEUTRAL**: Locale validation uses `@supported_locales` whitelist. Presence tracking on sign-in page is public by design. |
| MobileAuthController: exchange endpoint with multi-strategy token verification | **REVIEW NEEDED**: Token type confusion risk in exchange flow. See M-016. |
| User.ex: `set_sensualocto` action with `authorize_if always()` policy | **LOW RISK**: Relies on router-level basic auth (`admins_only` pipeline). See L-009. |
| Rust client: lobby.rs and room_session.rs -- read-only channel consumers | **NEUTRAL**: Client-side code, no server security impact. Auth handled at socket level. |
| AuthOverrides: purely cosmetic CSS class overrides | **NEUTRAL**: No security impact. |
| Locale plug: properly validates against `@supported_locales` whitelist | **POSITIVE**: All locale sources (params, session, cookie, Accept-Language) are validated. |

**Findings resolved this round: 6**

| ID | Status | Notes |
|----|--------|-------|
| M-007 | **RESOLVED** | RateLimiter now covers GET requests for `:guest_auth` |
| M-012 | **RESOLVED** | ProfileLive skill/connection deletion has ownership checks |
| M-013 | **RESOLVED** | ProfileLive skill level uses explicit case matching |
| L-003 | **RESOLVED** | Plug.Parsers body size limit (4MB) configured |
| L-007 | **RESOLVED** | UserSettingsLive locale validated before redirect |
| L-008 | **RESOLVED** | ChatComponent message length capped at 1000 bytes |

**New findings this round: 3**

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| M-015 | MEDIUM | LobbyChannel: `room_to_json/1` exposes `join_code` to all channel subscribers | Open |
| M-016 | MEDIUM | MobileAuthController: token type confusion in exchange endpoint | Open |
| L-009 | LOW | `set_sensualocto` Ash policy relies solely on router-level basic auth | Open |

### Priority Findings Summary

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| H-001 | HIGH | 10-year token lifetime | **RESOLVED**: reduced to 30-day session + 365-day remember_me |
| H-002 | HIGH | No socket-level authentication (UserSocket) | **PARTIALLY RESOLVED**: token verified but anonymous fallback remains |
| H-003 | HIGH | API room endpoints missing auth pipeline | Open |
| H-004 | HIGH | Bridge.decode/1 atom exhaustion via `String.to_atom` | **VERIFIED: Not present** |
| H-005 | HIGH | No bot protection | Open |
| M-001 | MEDIUM | "missing" token development backdoor | **RESOLVED**: gated on `:allow_missing_token` config |
| M-002 | MEDIUM | Bridge token not required | Open |
| M-003 | MEDIUM | Debug endpoint exposed in production | **RESOLVED**: behind `dev_routes` |
| M-004 | MEDIUM | Session cookie not encrypted | **RESOLVED**: `encryption_salt` added |
| M-005 | MEDIUM | Timing-unsafe guest token comparison | **RESOLVED**: uses `Plug.Crypto.secure_compare` |
| M-006 | MEDIUM | /dev/mailbox route not gated | **RESOLVED**: behind `dev_routes` |
| M-007 | MEDIUM | Rate limiter skips GET requests (guest auth is GET) | **RESOLVED**: GET now covered for `:guest_auth` |
| M-008 | MEDIUM | `Ash.create!` crash on channel write failure | **RESOLVED**: replaced with `Ash.create()` |
| M-009 | MEDIUM | Guided Session: no rate limiting on invite code lookups | Open |
| M-010 | MEDIUM | Guided Session: `authorize?: false` on all Ash operations | Open |
| M-011 | MEDIUM | `String.to_existing_atom` crash risk in multiple LiveViews | Open |
| M-012 | MEDIUM | ProfileLive: skill/connection deletion lacks ownership check | **RESOLVED**: ownership guard added |
| M-013 | MEDIUM | ProfileLive: `String.to_existing_atom` on user-supplied skill level | **RESOLVED**: explicit case matching |
| M-014 | MEDIUM | ProfileLive: user search exposes emails of all public users | Open |
| M-015 | MEDIUM | LobbyChannel: `join_code` exposed to all subscribers | Open |
| M-016 | MEDIUM | MobileAuthController: token type confusion in exchange | Open |
| L-001 | LOW | No force_ssl / HSTS | Open |
| L-002 | LOW | `create_test_user` action accessible via Ash policies bypass | Open (low risk) |
| L-003 | LOW | No `Plug.Parsers` body size limit configured | **RESOLVED**: 4MB limit added |
| L-004 | LOW | Guided Session: invite codes never expire | Open |
| L-005 | LOW | Guided Session: no limit on concurrent sessions per guide | Open |
| L-006 | LOW | Guided Session: unbounded annotations list in SessionServer | Open |
| L-007 | LOW | UserSettingsLive: unsanitized locale in redirect URL | **RESOLVED**: compile-time locale validation |
| L-008 | LOW | ChatComponent: no message length or rate limiting | **RESOLVED**: 1000-byte guard added |
| L-009 | LOW | `set_sensualocto` Ash policy relies solely on router auth | Open |

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
| Remember Me | Active | 365-day cookie, separate from session token |

### 1.2 Token Configuration (H-001 -- RESOLVED)

**File:** `lib/sensocto/accounts/user.ex`

**Status: RESOLVED as of 2026-02-17.** Token lifetime reduced from 3650 days (10 years) to 30 days, and a proper remember_me strategy has been added via AshAuthentication's built-in mechanism.

```elixir
tokens do
  enabled? true
  token_resource Sensocto.Accounts.Token
  signing_secret Sensocto.Secrets
  store_all_tokens? true
  require_token_presence_for_authentication? true
  token_lifetime {30, :days}   # session token: 30 days
end

strategies do
  # ... other strategies ...
  remember_me do
    # cookie lifetime: 365 days; silently re-authenticates when session expires
  end
end
```

**Authentication flow with remember_me:**

1. User authenticates (magic link / Google OAuth)
2. Session cookie issued with 30-day lifetime
3. `remember_me` cookie issued with 365-day lifetime (separate)
4. When session token expires, `sign_in_with_remember_me` plug (runs before `load_from_session` in browser pipeline) silently re-authenticates via the long-lived remember_me cookie
5. On explicit logout: `delete_all_remember_me_cookies(:sensocto)` clears both session and remember_me cookies

**Security properties of this approach:**
- Short-lived session tokens (30 days) reduce window of opportunity if a session token is stolen
- Remember_me tokens are separate from session tokens -- a leaked session cookie does not give long-term access
- Explicit logout invalidates both cookies, preventing persistent access
- `require_token_presence_for_authentication?` still enables server-side revocation for both token types

**Usability Impact:** Transparent to users. The remember_me mechanism silently refreshes sessions in the background. Users who explicitly log out lose persistent access as expected.

### 1.3 Sign-In Page Security (Updated Mar 2026)

**File:** `lib/sensocto_web/live/custom_sign_in_live.ex`

The custom sign-in page has been significantly reworked with sensor background visualizations, draggable ball presence, and locale support. Security-relevant observations:

1. **Guest session validation on mount**: Correctly checks both `session["is_guest"]` AND backend store existence before redirecting. Prevents stale session access.

2. **Locale validation**: Uses compile-time `@supported_locales` whitelist:
   ```elixir
   @supported_locales ~w(en de gsw fr es pt_BR zh ja ar)

   def handle_event("change_locale", %{"locale" => locale}, socket) do
     if locale in @supported_locales do
       {:noreply, redirect(socket, to: "/sign-in?locale=#{locale}")}
     else
       {:noreply, socket}
     end
   end
   ```
   **Assessment: Good.** Invalid locales are silently ignored.

3. **Theme validation**: Uses compile-time `@valid_themes` guard:
   ```elixir
   def handle_event("set_bg_theme", %{"theme" => theme}, socket) when theme in @valid_themes do
   ```
   **Assessment: Good.** Invalid themes hit the catch-all no-op clause.

4. **Presence tracking on sign-in page**: The `@presence_topic "signin_presence"` is public and visible to all sign-in page visitors. Ball positions and anonymous/authenticated user type are shared. This is intentional for the interactive experience and does not leak sensitive data.

5. **Guest creation**: `join_as_guest` creates a guest via `GuestUserStore.create_guest()` and redirects to the guest auth URL. The redirect includes the guest token in the URL path, which is appropriate since guest auth uses GET with URL params (now rate-limited per M-007 resolution).

6. **Error message in flash**: `inspect(reason)` in the guest creation error path could leak internal error details. LOW risk since guest creation failures are rare.

---

## 2. WebSocket Channel Security

### 2.1 UserSocket Authentication (H-002 -- PARTIALLY RESOLVED)

**File:** `lib/sensocto_web/channels/user_socket.ex`

```elixir
def connect(%{"token" => token}, socket, _connect_info) do
  case Phoenix.Token.verify(socket, "user_socket", token, max_age: 86_400) do
    {:ok, user_id} ->
      {:ok, assign(socket, :user_id, user_id)}

    {:error, _reason} ->
      # Log but still allow connection during migration period
      Logger.warning("UserSocket: invalid token, allowing anonymous connection")
      {:ok, assign(socket, :user_id, "anonymous")}
  end
end

def connect(_params, socket, _connect_info) do
  # Allow connections without token during migration period (with warning)
  Logger.warning("UserSocket: no token provided, allowing anonymous connection")
  {:ok, assign(socket, :user_id, "anonymous")}
end
```

**Status: PARTIALLY RESOLVED.** Token verification has been added with a 24-hour max_age, which is a significant improvement. However, the anonymous fallback on invalid/missing tokens remains. This is documented as a "migration period" concession.

**Positive change:** The `assign_user_socket_token` plug in the router now generates tokens signed with `"user_socket"` salt, matching the verification in `connect/3`. The token encodes the user_id (or `"anonymous"` for unauthenticated users).

**Remaining risk:** Any client that connects without a token or with an expired token still gets socket access as `"anonymous"`. The LobbyChannel mitigates this by validating `socket.assigns.user_id == user_id` on join, but other channels (SensorDataChannel, CallChannel, HydrationChannel) perform their own authentication at the channel level.

**Recommendation:** Remove the anonymous fallback and return `:error` for invalid/missing tokens. Channel-level auth should be defense-in-depth, not the primary control.

### 2.2 LobbyChannel Security (NEW -- Mar 2026)

**File:** `lib/sensocto_web/channels/lobby_channel.ex`

The LobbyChannel is a new read-only channel for live room list updates. Security analysis:

**Authentication on join -- Good:**
```elixir
def join("lobby:" <> user_id, _params, socket) do
  if socket.assigns.user_id == user_id do
    send(self(), :after_join)
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "rooms:lobby")
    Phoenix.PubSub.subscribe(Sensocto.PubSub, "lobby:#{user_id}")
    {:ok, socket}
  else
    {:error, %{reason: "unauthorized"}}
  end
end
```

The join validation correctly verifies that the requested `user_id` in the topic matches the authenticated `user_id` from the socket. This prevents users from subscribing to other users' lobby topics.

**Caveat:** If the UserSocket allowed anonymous connection (H-002), a client could join `"lobby:anonymous"` and receive broadcasts on the `"rooms:lobby"` global topic. This would expose all public room creation/deletion events. The `"lobby:anonymous"` user-specific topic would receive no targeted events since no rooms belong to "anonymous".

**Finding M-015: MEDIUM -- `room_to_json/1` exposes `join_code` to all channel subscribers**

```elixir
defp room_to_json(room) do
  %{
    id: room.id,
    name: room.name,
    description: Map.get(room, :description),
    owner_id: room.owner_id,
    join_code: Map.get(room, :join_code),  # <-- exposed to all subscribers
    is_public: Map.get(room, :is_public, false),
    # ...
  }
end
```

The `join_code` is the secret code used to join private rooms. Broadcasting it to all channel subscribers means:
- Any authenticated user subscribed to `"rooms:lobby"` receives join codes for all rooms (public and private) as they are created or updated.
- The Rust client (`lobby.rs`) receives and can deserialize these join codes.

**Risk:** An authenticated user can passively collect join codes for all rooms, including private rooms they are not members of.

**Recommendation:** Only include `join_code` for rooms owned by the subscribing user:
```elixir
defp room_to_json(room, user_id \\ nil) do
  %{
    id: room.id,
    name: room.name,
    # ...
    join_code: if(to_string(room.owner_id) == to_string(user_id), do: Map.get(room, :join_code)),
    # ...
  }
end
```

Or remove `join_code` entirely from the lobby broadcast -- it belongs in the room detail view, not the room list.

**Read-only design -- Good:** The channel has no `handle_in` callbacks. It only pushes events to clients and does not accept client-to-server messages. This eliminates a class of input validation concerns.

**PubSub topics -- Acceptable:** Subscribes to `"rooms:lobby"` (global) and `"lobby:#{user_id}"` (user-specific). The global topic is appropriate for room list updates. The user-specific topic receives targeted events like room invitations.

### 2.3 Development Backdoor (M-001 -- RESOLVED)

**File:** `lib/sensocto_web/channels/sensor_data_channel.ex`

**Status: RESOLVED.** The "missing" token path checks `Application.get_env(:sensocto, :allow_missing_token, false)` and only allows bypass when explicitly enabled. Production config defaults to `false`.

### 2.4 Bridge Socket (M-002)

**File:** `lib/sensocto_web/channels/bridge_socket.ex`

Bridge token validation is optional -- missing token allows connection. When `bridge_token` is not configured (nil), any token is accepted. When no token is provided at all, the connection is also accepted.

**Recommendation:** Require bridge token in production.

### 2.5 ViewerDataChannel (Verified Good)

**File:** `lib/sensocto_web/channels/viewer_data_channel.ex`

Uses `Phoenix.Token.verify/4` with `"viewer_data"` salt and 1-hour max_age on join. The token is generated by LobbyLive and encodes the LiveView socket ID. **Assessment: Good.**

---

## 3. API Security

### 3.1 API Room Endpoints Missing Auth Pipeline (H-003)

**File:** `lib/sensocto_web/router.ex` (lines 227-254)

The `/api/rooms/*` and `/api/connectors/*` endpoints now go through the `:api` pipeline which includes `ApiCookieAuth` and `:load_from_bearer`. This is a significant improvement. However, the mobile auth endpoints (lines 207-216) use `:rate_limit_api_auth` but not the `:api` pipeline -- they handle auth manually in the controller.

**Status: Improved.** The room and connector API endpoints now have proper auth pipeline. The mobile auth endpoints intentionally handle auth manually since they are the authentication endpoints themselves.

### 3.2 Rate Limiter (M-007 -- RESOLVED)

**File:** `lib/sensocto_web/plugs/rate_limiter.ex`

**Status: RESOLVED as of 2026-03-25.** The rate limiter now properly handles GET requests for the `:guest_auth` type:

```elixir
# Only rate limit POST requests for most auth endpoints.
# GET is included for guest_auth since it authenticates via URL params.
conn.method not in ["POST", "GET"] ->
  conn

conn.method == "GET" and type != :guest_auth ->
  conn
```

This correctly rate-limits the GET-based guest authentication route while leaving other GET requests (page views) unaffected.

### 3.3 Mobile Auth Exchange Endpoint (NEW -- M-016)

**File:** `lib/sensocto_web/controllers/api/mobile_auth_controller.ex`

**Finding M-016: MEDIUM -- Token type confusion in exchange endpoint**

The `/api/auth/exchange` endpoint accepts a token and tries multiple verification strategies in sequence:

1. First tries `Phoenix.Token.verify` with `"mobile_auth"` salt (10-minute max_age)
2. On `:expired` error, falls back to `AshAuthentication.Jwt.verify` (treats as JWT)
3. On any other error, also falls back to JWT verification

This multi-strategy approach creates a token type confusion risk:

```elixir
case Phoenix.Token.verify(SensoctoWeb.Endpoint, "mobile_auth", token, max_age: 600) do
  {:ok, %{user_id: user_id} = data} ->
    # ... handle Phoenix.Token
  {:error, :expired} ->
    # Falls back to JWT verification
    case verify_token_and_load_user(token) do ...
  {:error, reason} ->
    # Also falls back to JWT verification
    case verify_token_and_load_user(token) do ...
end
```

**Risks:**
- A valid JWT (30-day lifetime) can be "exchanged" for a new JWT, effectively acting as a token refresh without going through the dedicated `/api/auth/refresh` endpoint. This bypasses any future token rotation logic.
- The exchange endpoint returns a `socket_token` (signed with `"user_socket"` salt) alongside the JWT. This means any holder of a valid JWT can also obtain a socket token.
- Guest user handling creates a `Phoenix.Token` with 30-day expiry as a fallback JWT, which is not a real JWT and would not be verifiable by `AshAuthentication.Jwt.verify`.

**Recommendation:** Make the exchange endpoint strict about token types. Only accept Phoenix.Token with `"mobile_auth"` salt. Reject expired tokens instead of falling back to JWT:
```elixir
case Phoenix.Token.verify(SensoctoWeb.Endpoint, "mobile_auth", token, max_age: 600) do
  {:ok, %{user_id: user_id} = data} ->
    # ... handle valid Phoenix.Token
  {:error, :expired} ->
    conn |> put_status(:unauthorized) |> json(%{ok: false, error: "Token expired"})
  {:error, _reason} ->
    conn |> put_status(:unauthorized) |> json(%{ok: false, error: "Invalid token"})
end
```

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
  encryption_salt: "k8Xp2vQe",
  same_site: "Lax",
  max_age: 315_360_000,
  http_only: true
]
```

**Status: RESOLVED.** Session cookies are signed and encrypted.

---

## 5. Verified Security Controls (Excellent)

### 5.1 Rate Limiting

**File:** `lib/sensocto_web/plugs/rate_limiter.ex`

- ETS-based sliding window counter
- Per-IP, per-endpoint-type buckets
- Proper X-Forwarded-For header handling
- Separate limits: auth (10/min), registration (5/min), API (20/min), guest (10/min)
- GET requests now covered for guest_auth type

**Assessment: Good** (upgraded from "downgraded" status)

### 5.2 Atom Exhaustion Protection

**File:** `lib/sensocto/types/safe_keys.ex`

Whitelist approach with comprehensive allowed keys list. **Assessment: Excellent.** H-004 (bridge.ex bypass) was verified as not present. ConnectorServer and SensorServer also migrated to SafeKeys.

### 5.3 DoS Resistance

| Mechanism | Implementation | Effectiveness |
|-----------|---------------|---------------|
| Rate Limiting | ETS-based sliding window | High |
| Backpressure | PriorityLens quality levels | High |
| Memory Protection | 85%/92% thresholds | High |
| Socket Cleanup | Monitor + periodic GC | High |
| Request Timeouts | 2-5 second limits | Medium |
| Request Body Limit | Plug.Parsers 4MB | High |
| Chat Message Limit | 1000 bytes | High |

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

### 5.10 Locale Plug Validation

**File:** `lib/sensocto_web/plugs/locale.ex`

The locale plug validates all sources against `@supported_locales` whitelist:
```elixir
locale = if locale in @supported_locales, do: locale, else: default_locale()
```

The `Accept-Language` header parser normalizes locale tags before validation. No locale value reaches Gettext without passing through the whitelist. **Assessment: Excellent**

### 5.11 ProfileLive Authorization (M-012, M-013 -- RESOLVED)

**File:** `lib/sensocto_web/live/profile_live.ex`

Both findings have been addressed:

```elixir
# M-012: Ownership checks added
def handle_event("remove_skill", %{"id" => skill_id}, socket) do
  user = socket.assigns.user
  case Ash.get(UserSkill, skill_id, authorize?: false) do
    {:ok, skill} when skill.user_id == user.id ->
      Ash.destroy!(skill, authorize?: false)
    # ...
  end
end

def handle_event("remove_connection", %{"id" => conn_id}, socket) do
  user = socket.assigns.user
  case Ash.get(UserConnection, conn_id, authorize?: false) do
    {:ok, conn} when conn.from_user_id == user.id ->
      Ash.destroy!(conn, authorize?: false)
    # ...
  end
end

# M-013: Explicit case matching replaces String.to_existing_atom
level_atom =
  case level do
    "beginner" -> :beginner
    "intermediate" -> :intermediate
    "expert" -> :expert
    _ -> :beginner
  end
```

**Assessment: Good.** The ownership pattern-match guards are correct. The explicit case matching for skill levels eliminates both the atom exhaustion risk and the crash-on-unknown-string risk.

---

## 6. Privacy and Profile System

### 6.1 Privacy Default Change (I-004 -- Verified Good)

**File:** `lib/sensocto/accounts/user.ex`

The `is_public` attribute defaults to `false`. New users are hidden from directory until they opt in. **Assessment: Excellent.**

### 6.2 User Settings Privacy Toggle

**File:** `lib/sensocto_web/live/user_settings_live.ex`

Guest guard on `toggle_public` is correct. The update uses `actor: user` which goes through Ash policies. Locale validation uses compile-time guard (L-007 resolved). **Assessment: Good.**

### 6.3 User Search Email Exposure (M-014 -- Open)

**File:** `lib/sensocto_web/live/profile_live.ex`

All public users are loaded into socket assigns including email addresses. The search function filters client-side. Any authenticated user can view emails by inspecting LiveView assigns or DOM.

**Recommendation:** Strip emails from search results. Use server-side search with `Ash.Query.select([:id, :display_name])`.

### 6.4 Search Index Privacy (I-003 -- Verified Good)

The search index correctly filters users by `is_public == true`. Privacy changes propagate within 30 seconds.

---

## 7. User Account and Feature Gating

### 7.1 Sensualocto Feature Flag (L-009 -- NEW)

**File:** `lib/sensocto/accounts/user.ex`

The `set_sensualocto` action is intended for admin-only use but has an `authorize_if always()` policy:

```elixir
policy action(:set_sensualocto) do
  description "Admin-only: protected by basic auth at router level"
  authorize_if always()
end
```

This means any code path that calls `Ash.update(user, %{sensualocto: true}, action: :set_sensualocto)` will succeed regardless of the actor. The intent is that this action is only reachable through the admin panel (behind basic auth), but the Ash policy itself provides no protection.

**Risk:** LOW. The admin panel is behind the `admins_only` pipeline (basic auth). However, if any non-admin code path accidentally calls this action, it would succeed. Defense-in-depth would suggest restricting the policy to actual admin actors.

**Recommendation:** Add an actor check if an admin user concept exists, or at minimum require that the action is only callable with `authorize?: false` from a known admin context:
```elixir
policy action(:set_sensualocto) do
  description "Admin-only"
  forbid_if always()  # Only callable with authorize?: false from admin panel
end
```

### 7.2 Mobile Token Lifetime Mismatch (Informational)

**File:** `lib/sensocto_web/live/user_settings_live.ex`

The mobile QR token displays a 5-minute countdown, but the underlying JWT has a 30-day lifetime. The `@token_lifetime_seconds` only controls the UI countdown. The actual security token remains valid for its full JWT lifetime.

**Recommendation (unchanged):** Use `Phoenix.Token.sign/4` with explicit `max_age` for mobile linking tokens, or generate one-time-use tokens that are invalidated after first use.

---

## 8. Chat Component Security (L-008 -- RESOLVED)

**File:** `lib/sensocto_web/live/components/chat_component.ex`

The chat component now has a 1000-byte message length guard:

```elixir
@max_message_length 1000

def handle_event("send_message", %{"message" => message}, socket)
    when message != "" and byte_size(message) <= @max_message_length do
  # ...
end
```

Messages exceeding the limit silently fail to send (no error flash). The `ChatStore` also caps messages per room at 100 with 24-hour TTL and 30-minute cleanup intervals.

**Assessment: Good.** The guard clause prevents oversized messages. The ChatStore prevents unbounded memory growth.

---

## 9. `String.to_existing_atom` Audit (M-011 -- Updated)

The previous assessment flagged `String.to_existing_atom` in guided session events. A broader audit reveals widespread usage. While `String.to_existing_atom` is the correct choice over `String.to_atom` (it prevents atom table exhaustion), it can crash on unknown strings.

**Progress since last assessment:**
- **M-013 RESOLVED**: ProfileLive skill level now uses explicit case matching
- **CustomSignInLive**: Locale uses `in @supported_locales` guard (no atom conversion needed)
- **UserSettingsLive**: Locale uses `in @valid_locale_codes` guard

**Files still with `String.to_existing_atom` on user-supplied input:**

| File | Input Source | Risk |
|------|-------------|------|
| `lobby_live.ex` (9 call sites) | LiveView events | MEDIUM: crash on unknown values |
| `tabbed_footer_live.ex` | LiveView event | LOW: limited tab values |
| `polls_live.ex` | Form params | MEDIUM: crash on unknown poll type |
| `about_content_component.ex` (2 sites) | LiveView events | LOW: limited values |
| `sensor_detail_live.ex` (2 sites) | URL params | MEDIUM: crash on unknown lens |
| `system_status_live.ex` | LiveView event | LOW: admin page |

**Remaining `String.to_atom` usage (unsafe):**

| File | Context | Risk |
|------|---------|------|
| `lobby_live.ex` line ~2565 | `String.to_atom(type)` on guide suggested action type | MEDIUM: unbounded atom creation from guide events |

**Recommendation:** Apply the `safe_atom/2` pattern (already used successfully in `profile_live.ex`) consistently across all call sites. Create a shared helper module.

---

## 10. Dependabot and CI Security

### 10.1 GitHub Actions Supply Chain

All CI actions kept current through dependabot. No known CVEs in bumped versions.

### 10.2 Elixir Dependency Updates

`ash_admin` bumped from 0.13.24 to 0.13.26. `usage_rules` bumped to 1.2.3.

---

## 11. Bot Protection Recommendation (H-005)

**Why Paraxial.io for Sensocto:**

1. **Native Elixir Integration**: Designed specifically for Phoenix/LiveView
2. **Invisible Security**: Bot detection without CAPTCHAs degrading UX
3. **IP Intelligence**: Real-time reputation scoring
4. **Minimal Overhead**: Designed for Elixir's concurrency model

---

## 12. Security Metrics

### Authentication Security Score: A- (upgraded from B+)

| Metric | Score | Notes |
|--------|-------|-------|
| Strategy Security | A | Magic Link with interaction required |
| Token Storage | A | Database-backed with revocation |
| Token Lifetime | B+ | 30-day session + 365-day remember_me |
| MFA | F | Not implemented |
| Rate Limiting | A- | Comprehensive, covers GET guest auth |
| Socket Auth | B | Token verification added, anonymous fallback remains |

### Authorization Security Score: A- (upgraded from B+)

| Metric | Score | Notes |
|--------|-------|-------|
| Default Deny | A | Ash policies correctly configured |
| Room Access | A | Membership validation enforced |
| Channel Auth | B+ | LobbyChannel validates user_id, ViewerData uses signed token |
| API Auth | B+ | Room/connector endpoints have auth pipeline |
| Profile Operations | A- | Ownership checks added (M-012 resolved) |
| Feature Gating | B | sensualocto flag relies on router-level auth only |

### Privacy Score: A- (unchanged)

| Metric | Score | Notes |
|--------|-------|-------|
| Default Privacy | A | `is_public` defaults to `false` |
| User Control | A | Settings page toggle, clear UX |
| Search Index | A | Respects `is_public` filter |
| Data Exposure | B | Email addresses visible in profile search (M-014) |
| Guest Privacy | A | Display names use hash, not ID prefix |
| Room Codes | B | join_code exposed in LobbyChannel (M-015) |

### Input Validation Score: B+ (unchanged)

| Metric | Score | Notes |
|--------|-------|-------|
| Atom Protection | A | SafeKeys excellent for data layer |
| SQL Injection | A | Ecto parameterized queries |
| XSS Prevention | B | Headers good, CSP missing |
| LiveView Events | B | `String.to_existing_atom` crash risk improved but not eliminated |
| Request Body | A | 4MB Plug.Parsers limit (L-003 resolved) |
| Message Length | A | Chat component 1000-byte guard (L-008 resolved) |

### DoS Resistance Score: A (unchanged)

| Metric | Score | Notes |
|--------|-------|-------|
| Rate Limiting | A | Multi-tier, covers GET routes |
| Backpressure | A | Quality-based throttling |
| Memory Protection | A | Configurable thresholds |
| Resource Cleanup | A | Monitor + GC patterns |

---

## 13. Planned Work: Security Implications

### 13.1 Room Iroh Migration

**Security Impact: MEDIUM** -- Moving from PostgreSQL (with Ash policies) to in-memory GenServer + Iroh docs removes the authorization layer. Validate all Iroh-synced data. Consider encrypting room metadata in Iroh docs.

### 13.2 Other Plans

All plan assessments from previous report remain valid.

---

## 14. Guided Session Feature -- Security Analysis

See previous report (Feb 24, 2026) for full analysis. Findings M-009 through L-006 remain open.

**Overall feature security: B-** -- Functional authorization is sound, but lacks defense-in-depth at the Ash policy layer and needs rate limiting on the join flow.

---

## 15. Implementation Roadmap

### Phase 1: Immediate (1-2 days) -- ALL RESOLVED
- [x] Reduce token lifetime from 10 years to 30 days (H-001)
- [x] Add remember_me strategy (H-001 companion)
- [x] Replace `Ash.create!` with `Ash.create()` in sensor_data_channel.ex (M-008)
- [x] Gate "missing" token behind configuration (M-001)
- [x] Use `Plug.Crypto.secure_compare` for guest tokens (M-005)
- [x] Protect /dev/mailbox route (M-006)
- [x] Gate debug endpoint behind dev_routes (M-003)
- [x] Add session cookie encryption_salt (M-004)
- [x] Add ownership checks to ProfileLive (M-012)
- [x] Replace `String.to_existing_atom` with case matching in ProfileLive (M-013)
- [x] Add chat message length limit (L-008)
- [x] Add Plug.Parsers body size limit (L-003)
- [x] Fix rate limiter for GET-based guest auth (M-007)
- [x] Validate locale in settings redirect (L-007)

### Phase 2: Short-term (1 week)
- [ ] Remove `join_code` from LobbyChannel room broadcasts (M-015)
- [ ] Make exchange endpoint strict about token types (M-016)
- [ ] Limit email exposure in profile user search (M-014)
- [ ] Remove anonymous fallback from UserSocket (complete H-002)
- [ ] Replace `String.to_existing_atom` with whitelists across remaining LiveViews (M-011)
- [ ] Integrate Paraxial.io for bot protection (H-005)
- [ ] Add Content-Security-Policy headers
- [ ] Add rate limiting to guided session join page (M-009)
- [ ] Add Ash policies to GuidedSession resource (M-010)
- [ ] Add invite code expiration (L-004)
- [ ] Restrict `set_sensualocto` Ash policy (L-009)

### Phase 3: Medium-term (2-4 weeks)
- [ ] Add MFA for admin operations
- [ ] Security monitoring/alerting setup
- [ ] Pre-migration security review for Room Iroh Migration
- [ ] Pre-migration security review for Cluster Visibility plans
- [ ] Require bridge token in production (M-002)
- [ ] Add Ash policies to UserSkill and UserConnection resources

### Phase 4: Ongoing
- [ ] Penetration testing
- [ ] Dependency auditing
- [ ] Cloudflare TURN token rotation schedule
- [ ] Node authorization for distributed features

---

## 16. Security Configuration Checklist

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

## 17. Changes Applied by Assessment Round

### Mar 25, 2026

Review of commits fefbf69 through current HEAD. Key security-relevant changes:

1. **LobbyChannel (NEW)**: New Phoenix channel for read-only room list updates. Join validates `socket.assigns.user_id` match -- good. However, `room_to_json/1` broadcasts `join_code` to all subscribers (M-015). No `handle_in` callbacks -- read-only design eliminates input validation concerns.

2. **UserSocket token verification**: `connect/3` now verifies `Phoenix.Token` with `"user_socket"` salt and 24h max_age. Significant improvement. Anonymous fallback remains for migration compatibility (H-002 partially resolved).

3. **RateLimiter GET coverage (M-007 RESOLVED)**: The rate limiter now correctly handles GET requests for `:guest_auth` type via a two-condition guard. All other GET requests remain unaffected.

4. **ProfileLive ownership checks (M-012, M-013 RESOLVED)**: `remove_skill` and `remove_connection` now guard with `when skill.user_id == user.id` and `when conn.from_user_id == user.id`. `String.to_existing_atom` for skill level replaced with explicit case matching defaulting to `:beginner`.

5. **ChatComponent message length (L-008 RESOLVED)**: `@max_message_length 1000` guard added to `send_message` handler.

6. **Plug.Parsers body limit (L-003 RESOLVED)**: `length: 4_000_000` added to endpoint Plug.Parsers configuration.

7. **UserSettingsLive locale validation (L-007 RESOLVED)**: `@valid_locale_codes` compile-time module attribute derived from `@locales`. Guard clause `when locale in @valid_locale_codes` rejects invalid locales.

8. **CustomSignInLive rework**: Significant UI changes (sensor background, draggable balls, locale support). Locale validation uses `@supported_locales` whitelist. Guest session validation on mount checks backend store. No new security surface.

9. **MobileAuthController exchange endpoint**: Multi-strategy token verification creates token type confusion risk (M-016). Guest users get long-lived Phoenix.Token fallback.

10. **Sensualocto feature flag**: New `set_sensualocto` action with `authorize_if always()` policy relies entirely on router-level basic auth (L-009). Feature gating in SimulatorLive and LobbyLive correctly checks the user attribute.

11. **Locale plug**: Properly validates all locale sources against `@supported_locales`. Accept-Language parsing normalizes before validation. No injection risk.

12. **AuthOverrides**: Purely cosmetic CSS class overrides for sign-in component. No security impact.

13. **Rust client (lobby.rs, room_session.rs)**: Read-only channel consumers. No server security impact. Auth handled at socket level.

14. **Overall**: Security grade upgraded from B+ to A-. Six findings resolved. Three new findings (M-015, M-016, L-009) identified. Authorization score upgraded from B+ to A- due to ProfileLive fixes. Rate limiting score upgraded to A- due to M-007 resolution.

### Mar 1, 2026

Privacy default change, profile system with authorization gaps (M-012, M-013, M-014), user settings, chat fix, guest display names, guided session join fix, sign-in guards, dependabot bumps, String.to_existing_atom audit expansion.

### Feb 24, 2026

Guided Session feature analysis. See Section 14 for full details. Findings M-009 through L-006.

### Feb 22, 2026

Token refresh, connector persistence, CRDT sessions.

### Feb 20, 2026

Audio/MIDI system, Polls domain, User Profiles/Social Graph, Delta Encoding, Health Check Endpoint.

### Feb 17, 2026

Remember Me token strategy, token lifetime reduction (H-001 resolved), Ash.create! fix (M-008), WCAG contrast, bio factor logging.

### Feb 15, 2026

IO.puts cleanup, GenServer call timeouts, email sender centralization, SafeKeys migration, ETS write_concurrency, Bio.Supervisor restart limits.

---

## References

- [Ash Authentication Documentation](https://hexdocs.pm/ash_authentication/)
- [Phoenix Security Best Practices](https://hexdocs.pm/phoenix/security.html)
- [Paraxial.io Documentation](https://hexdocs.pm/paraxial/)
- [OWASP Top 10 2021](https://owasp.org/Top10/)
- [Elixir Security Best Practices](https://paraxial.io/blog/elixir-security)

---

*Report generated by Security Advisor Agent (Claude Opus 4.6). Last updated: 2026-03-25*

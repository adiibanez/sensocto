# Security Assessment Report: Sensocto Platform

**Assessment Date:** 2026-02-08 | **Updated:** 2026-03-01
**Previous Assessment:** 2026-02-24
**Assessor:** Security Advisor Agent (Claude Opus 4.6)
**Platform Version:** Current main branch
**Risk Framework:** OWASP Top 10 2021 + Elixir/Phoenix Best Practices

---

## Executive Summary

The Sensocto platform demonstrates a **mature security posture** with well-implemented security controls. This assessment identifies several areas requiring attention while acknowledging significant improvements since previous reviews.

**Overall Security Grade: B+ (Good)**

### Key Changes Since Last Assessment (2026-02-24 to 2026-03-01)

| Change | Impact |
|--------|--------|
| Privacy default change: `is_public` now defaults to `false` in User resource + migration | **POSITIVE**: Privacy-by-default is the correct posture. New users are hidden from directory until they opt in. |
| Profile system expanded: `ProfileLive` with skills, connections, user search, graph visualization | **REVIEW NEEDED**: Authorization gaps in skill/connection management. See M-012, M-013. |
| User Settings page: new `UserSettingsLive` with privacy toggle, mobile QR linking, locale | **POSITIVE**: Privacy controls are user-facing. Guest guard on `toggle_public` is correct. |
| Chat component: duplicate PubSub subscription fix via Process dictionary | **POSITIVE**: Prevents duplicate message delivery. No new security surface. |
| Guest user store: display name uses `phash2` instead of raw guest ID prefix | **POSITIVE**: Eliminates information leakage of guest ID prefix in display names. |
| Guided session join: action name corrected from `:create` to `:assign_follower` | **POSITIVE**: Fixes potential Ash action mismatch bug noted in previous assessment. |
| Magic sign-in: locale support added, sign-in guard on custom_sign_in_live | **NEUTRAL**: No security impact from locale addition. Sign-in guard redirects already-authenticated guests. |
| Dependabot: bumped `actions/github-script` 7->8, `actions/cache` 4->5, `actions/setup-node` 4->6, `actions/upload-artifact` 4->6, `actions/setup-dotnet` 4->5, `ash_admin` 0.13.24->0.13.26, `rollup` 4.55.1->4.59.0 | **POSITIVE**: CI action supply chain kept current. No known CVEs in bumped versions. |
| Claude PR review workflow: `allowed_bots: "dependabot[bot]"` added | **POSITIVE**: Allows automated review of dependabot PRs without manual trigger. |

**New findings from this review:**

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| M-012 | MEDIUM | ProfileLive: `remove_skill` and `remove_connection` lack ownership validation | Open |
| M-013 | MEDIUM | ProfileLive: `String.to_existing_atom(level)` on user-supplied skill level | Open |
| M-014 | MEDIUM | ProfileLive: user search exposes all public users' emails to authenticated users | Open |
| L-007 | LOW | UserSettingsLive: locale redirect uses unsanitized locale in URL | Open |
| L-008 | LOW | ChatComponent: no message length or rate limiting on chat messages | Open |
| I-003 | INFO | SearchIndex correctly filters users by `is_public == true` | Verified Good |
| I-004 | INFO | Privacy default changed to `false` -- aligns with GDPR/privacy-by-default | Verified Good |

**Resolved from previous assessment:**

| ID | Status | Notes |
|----|--------|-------|
| (partial) M-011 context | IMPROVED | `lobby_live.ex` still uses `String.to_existing_atom` in many places, but `profile_live.ex` now uses `safe_atom/2` whitelist for connection types. Mixed progress. |

### Key Changes Since Last Assessment (2026-02-22 to 2026-02-24)

| Change | Impact |
|--------|--------|
| Guided Session feature: New `Sensocto.Guidance` domain with invite-code-based session joining, SessionServer GenServer, DynamicSupervisor, and join LiveView | **REVIEW NEEDED**: New feature introduces invite code brute-force surface, PubSub topic access control questions, and authorization checks in SessionServer. See Section 14 for detailed analysis. |

### Key Changes Since Last Assessment (2026-02-20 to 2026-02-22)

| Change | Impact |
|--------|--------|
| Token Refresh (#37): HttpOnly cookie auth plug (`api_cookie_auth.ex`), POST `/api/auth/refresh` endpoint | **POSITIVE**: HttpOnly cookies prevent XSS-based token theft. Refresh endpoint enables short-lived access tokens with longer-lived refresh cookies. Verify `Secure` and `SameSite=Strict` flags are set on the cookie. |
| Connector Persistence (#39): Migrated to AshPostgres with Ash policies for user-scoped access | **POSITIVE**: Ash policies enforce user ownership on connector CRUD. Replaces ETS (no access control) with database-backed authorization. Verify policies deny cross-user connector access. |
| Connector REST API (#40): New controller with OpenApiSpex operation macros, routes at `/api/connectors(/:id)` | **REVIEW NEEDED**: Verify connector controller uses proper auth pipeline (not the unauthenticated room API pattern from H-003). Ensure rate limiting applies to connector endpoints. |
| Connector Broadcasts (#43): User-scoped PubSub on `user:#{user_id}:connectors` | **LOW RISK**: User-scoped topics prevent cross-user data leakage. Verify `user_id` in topic name comes from authenticated session, not client input. |
| CRDT Sessions (#36): LWW CRDT document_worker.ex with per-user GenServer, DynamicSupervisor | **LOW RISK**: Per-user isolation via DynamicSupervisor. Auto-shutdown on idle prevents resource exhaustion. Verify no cross-user document access is possible. |
| E2E Tests (#35): Auth flow feature test verifies authentication pipeline end-to-end | **POSITIVE**: Browser-based auth flow testing catches regressions in the authentication pipeline. |
| Phase 3 of security roadmap partially addressed: Refresh token pattern now implemented (was in Phase 3 recommendations). H-003 (API room endpoints missing auth) status should be re-checked for connector endpoints. |

### Key Changes Since Last Assessment (2026-02-16 to 2026-02-17)

- **RESOLVED**: Token lifetime reduced from 3650 days (10 years) to 30 days (H-001) -- major security improvement
- **RESOLVED**: Remember Me strategy added via AshAuthentication built-in -- proper session/persistent token separation
- **IMPROVED**: `Ash.create!` replaced with `Ash.create()` in sensor_data_channel.ex -- crash on error eliminated
- **IMPROVED**: WCAG color contrast fixed -- `text-gray-400` changed to `text-gray-300` across lobby and app layouts (25 instances, no security impact but improves accessibility audit posture)
- **IMPROVED**: AttentionTracker now logs warnings when bio factor computations fail -- better observability for anomaly detection
- **STABLE**: H-002, H-003, H-005, M-002, M-007, L-001 remain open

### Key Changes Since Assessment (2026-02-15 to 2026-02-16)

- **RESOLVED**: Session cookie encryption (M-004) -- `encryption_salt` now configured in endpoint.ex
- **STABLE**: All other findings unchanged. No new attack surface introduced by recent commits (graph improvements, resilience updates, lobby/index refactoring, translations)
- **NEW OBSERVATION**: `create_test_user` action in User resource -- verified test-only usage
- **NEW OBSERVATION**: Rate limiter only applies to POST requests -- GET-based auth routes (guest sign-in) bypass rate limiting

### Priority Findings Summary

| ID | Severity | Finding | Status |
|----|----------|---------|--------|
| H-001 | HIGH | 10-year token lifetime | **RESOLVED**: reduced to 30-day session + 365-day remember_me |
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
| M-007 | MEDIUM | Rate limiter skips GET requests (guest auth is GET) | Open |
| M-008 | MEDIUM | `Ash.create!` crash on channel write failure | **RESOLVED**: replaced with `Ash.create()` |
| M-009 | MEDIUM | Guided Session: no rate limiting on invite code lookups | Open |
| M-010 | MEDIUM | Guided Session: `authorize?: false` on all Ash operations | Open |
| M-011 | MEDIUM | `String.to_existing_atom` crash risk in multiple LiveViews | Open |
| M-012 | MEDIUM | ProfileLive: skill/connection deletion lacks ownership check | Open |
| M-013 | MEDIUM | ProfileLive: `String.to_existing_atom` on user-supplied skill level | Open |
| M-014 | MEDIUM | ProfileLive: user search exposes emails of all public users | Open |
| L-001 | LOW | No force_ssl / HSTS | Open |
| L-002 | LOW | `create_test_user` action accessible via Ash policies bypass | Open (low risk) |
| L-003 | LOW | No `Plug.Parsers` body size limit configured | Open (low risk) |
| L-004 | LOW | Guided Session: invite codes never expire | Open |
| L-005 | LOW | Guided Session: no limit on concurrent sessions per guide | Open |
| L-006 | LOW | Guided Session: unbounded annotations list in SessionServer | Open |
| L-007 | LOW | UserSettingsLive: unsanitized locale in redirect URL | Open |
| L-008 | LOW | ChatComponent: no message length or rate limiting | Open |

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

### 1.3 Sign-In Guards (NEW -- Feb 2026)

**File:** `lib/sensocto_web/live/custom_sign_in_live.ex`

The custom sign-in page now checks for valid existing guest sessions on mount:

```elixir
valid_guest? =
  session["is_guest"] == true and
    match?({:ok, _}, Sensocto.Accounts.GuestUserStore.get_guest(session["guest_id"]))

if valid_guest? do
  {:ok, redirect(socket, to: ~p"/lobby")}
end
```

**Assessment: Good.** This prevents authenticated guests from seeing the sign-in page, which is the correct UX behavior. The validation checks both the session flag AND the backend store, preventing stale session data from granting access to a deleted guest.

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

## 6. Privacy and Profile System (NEW -- Mar 2026)

### 6.1 Privacy Default Change (I-004 -- Verified Good)

**File:** `lib/sensocto/accounts/user.ex` (line 482)
**Migration:** `priv/repo/migrations/20260226195225_default_is_public_to_false.exs`

The `is_public` attribute now defaults to `false`:

```elixir
attribute :is_public, :boolean do
  allow_nil? false
  default false  # was: true
end
```

**Assessment: Excellent.** This is a privacy-by-default change aligned with GDPR Article 25 (Data Protection by Design). New users must explicitly opt in to directory visibility. The migration updates the database default. The `UserSettingsLive` page provides a clear toggle for users to control their visibility.

### 6.2 User Settings Privacy Toggle

**File:** `lib/sensocto_web/live/user_settings_live.ex`

```elixir
# Guest users cannot change visibility
def handle_event("toggle_public", _params,
      %{assigns: %{current_user: %{is_guest: true}}} = socket) do
  {:noreply, put_flash(socket, :error, gettext("Guest users cannot change visibility"))}
end

# Authenticated users use Ash with actor-based authorization
def handle_event("toggle_public", _params, socket) do
  user = socket.assigns.current_user
  new_value = !socket.assigns.is_public
  case user
       |> Ash.Changeset.for_update(:update_profile, %{is_public: new_value}, actor: user)
       |> Ash.update() do
    # ...
  end
end
```

**Assessment: Good.** The guest guard is correct. The update uses `actor: user` which goes through Ash policies. The `on_mount` guard ensures authentication.

### 6.3 Profile Management Authorization Gaps

**File:** `lib/sensocto_web/live/profile_live.ex`

**Finding M-012: MEDIUM -- Skill and connection deletion lacks ownership validation**

The `remove_skill` and `remove_connection` event handlers look up resources by ID and delete them without verifying the requesting user owns them:

```elixir
def handle_event("remove_skill", %{"id" => skill_id}, socket) do
  case Ash.get(UserSkill, skill_id, authorize?: false) do
    {:ok, skill} ->
      Ash.destroy!(skill, authorize?: false)  # No ownership check!
      # ...
  end
end

def handle_event("remove_connection", %{"id" => conn_id}, socket) do
  case Ash.get(UserConnection, conn_id, authorize?: false) do
    {:ok, conn} ->
      Ash.destroy!(conn, authorize?: false)  # No ownership check!
      # ...
  end
end
```

A user could craft a `phx-value-id` attribute in the DOM (via browser devtools) to delete another user's skills or connections. The `authorize?: false` bypasses any Ash policy that might otherwise prevent this.

**Risk:** An authenticated user can delete any other user's skills or connections by providing their UUIDs. UUID guessing is impractical, but if skill/connection IDs are ever leaked (e.g., in API responses, logs, or DOM attributes), this becomes exploitable.

**Recommendation:** Add ownership validation:
```elixir
def handle_event("remove_skill", %{"id" => skill_id}, socket) do
  user_id = socket.assigns.user.id
  case Ash.get(UserSkill, skill_id, authorize?: false) do
    {:ok, %{user_id: ^user_id} = skill} ->
      Ash.destroy!(skill, authorize?: false)
    _ ->
      {:noreply, socket}
  end
end
```

Or better, add Ash policies to `UserSkill` and `UserConnection` and use `actor: socket.assigns.user`.

**Finding M-013: MEDIUM -- `String.to_existing_atom(level)` on user-supplied skill level**

```elixir
def handle_event("add_skill", %{"skill_name" => name, "level" => level}, socket) do
  # ...
  level: String.to_existing_atom(level)
  # ...
end
```

The `level` parameter comes from a form select, but a malicious client can send any string. If the atom does not exist, this raises `ArgumentError` and crashes the LiveView process. LiveView will reconnect, but repeated crashes degrade UX.

**Current mitigation:** The `UserSkill` resource has `constraints one_of: [...]` which would reject invalid atoms at the Ash level. However, the crash happens before the Ash call.

**Recommendation:** Use a whitelist like `safe_atom/2` (already used in `profile_live.ex` for connection types):
```elixir
defp safe_skill_level(str) do
  case str do
    "beginner" -> :beginner
    "intermediate" -> :intermediate
    "advanced" -> :advanced
    "expert" -> :expert
    _ -> :beginner
  end
end
```

**Finding M-014: MEDIUM -- User search exposes all public users' emails**

```elixir
all_users =
  User
  |> Ash.Query.filter(is_public == true and id != ^user_id)
  |> Ash.read!(authorize?: false)
  |> Enum.sort_by(fn u -> u.display_name || to_string(u.email) end)
```

All public users are loaded into the socket assigns, including their email addresses. The search function then filters client-side. The user search results are rendered in the dropdown, potentially exposing email addresses in the DOM.

**Risk:** Any authenticated user can view the email addresses of all public users by inspecting the LiveView assigns or DOM.

**Recommendation:** Only load display names and IDs for the user search. Strip email addresses unless the user is viewing their own profile. Use server-side search with an Ash query instead of loading all users into memory:
```elixir
defp search_users(query, current_user_id) do
  User
  |> Ash.Query.filter(is_public == true and id != ^current_user_id)
  |> Ash.Query.filter(fragment("? ILIKE ?", display_name, ^"%#{query}%"))
  |> Ash.Query.select([:id, :display_name])
  |> Ash.Query.limit(8)
  |> Ash.read!(authorize?: false)
end
```

### 6.4 Search Index Privacy (I-003 -- Verified Good)

**File:** `lib/sensocto/search/search_index.ex`

The search index correctly filters users by `is_public == true`:

```elixir
User
|> Ash.Query.filter(is_public == true)
|> Ash.read(authorize?: false)
```

This respects the privacy default change. Users who have not opted in to directory visibility will not appear in search results. The index rebuilds every 30 seconds, so privacy changes propagate within 30 seconds.

### 6.5 Guest User Display Name Privacy (Positive Change)

**File:** `lib/sensocto/accounts/guest_user_store.ex`

Previously: `"Guest #{String.slice(guest_id, 0..5)}"` -- leaked a prefix of the guest ID
Now: `"Guest #{:erlang.phash2(guest_id, 10_000) |> Integer.to_string() |> String.pad_leading(4, "0")}"` -- uses a deterministic hash

**Assessment: Good.** The `phash2` approach prevents information leakage of the guest ID while maintaining a stable, human-readable display name. The same pattern is applied in `ChatComponent.get_user_name/1`.

---

## 7. Chat Component Security (NEW -- Mar 2026)

### 7.1 Duplicate Subscription Fix (Positive Change)

**File:** `lib/sensocto_web/live/components/chat_component.ex`

```elixir
already_subscribed = Process.get({:chat_subscribed, room_id}, false)
unless already_subscribed do
  ChatStore.subscribe(room_id)
  Process.put({:chat_subscribed, room_id}, true)
end
```

The fix uses the process dictionary to prevent duplicate PubSub subscriptions when a component is unmounted and remounted within the same parent LiveView process. The corresponding `room_show_live.ex` also marks the subscription in the process dictionary before the component mounts.

**Assessment: Good.** This is a correctness fix, not a security fix, but it prevents a potential message amplification issue where duplicate subscriptions could cause the same message to be processed multiple times.

### 7.2 Chat Message Input Validation

**Finding L-008: LOW -- No message length or rate limiting on chat messages**

```elixir
def handle_event("send_message", %{"message" => message}, socket) when message != "" do
  # Sends directly to ChatStore without length validation
  user_message = %{
    role: "user",
    content: message,  # no length limit
    user_id: user_id,
    user_name: user_name
  }
  ChatStore.add_message(room_id, user_message)
end
```

A user could send very long messages or flood the chat with rapid submissions. The ChatStore presumably holds messages in memory, so large payloads could contribute to memory pressure.

**Risk:** LOW. The LiveView socket has natural backpressure (events are processed sequentially). However, there is no explicit protection against:
- Messages exceeding a reasonable length (e.g., 10KB of text)
- Rapid message submission (no client-side or server-side rate limiting)

**Recommendation:** Add a message length check and simple per-user rate limit:
```elixir
@max_message_length 2_000
@max_messages_per_minute 30

def handle_event("send_message", %{"message" => message}, socket)
    when byte_size(message) > @max_message_length do
  {:noreply, put_flash(socket, :error, "Message too long")}
end
```

---

## 8. User Settings Security (NEW -- Mar 2026)

### 8.1 Mobile Token Generation

**File:** `lib/sensocto_web/live/user_settings_live.ex`

The settings page generates short-lived tokens (5 minutes) for mobile device linking via QR code:

```elixir
@token_lifetime_seconds 5 * 60

defp generate_mobile_token(user) do
  expires_at = DateTime.add(DateTime.utc_now(), @token_lifetime_seconds, :second)
  case AshAuthentication.Jwt.token_for_user(user) do
    {:ok, token, _claims} -> {token, expires_at}
    {:error, _} -> generate_fallback_token(user, expires_at)
  end
end
```

**Assessment: Good.** The 5-minute lifetime is appropriate for a QR-based authentication flow. The fallback token uses `Phoenix.Token.sign/4` which is signed but not encrypted. The QR code is only shown when explicitly toggled.

**Concern:** The JWT generated by `AshAuthentication.Jwt.token_for_user/1` has its own expiration (30 days per the token configuration), not the 5-minute lifetime displayed in the UI. The `@token_lifetime_seconds` only controls the countdown timer and auto-regeneration in the UI. The actual token is valid for 30 days.

**Recommendation:** If the intent is to provide a short-lived token for mobile linking, use `Phoenix.Token.sign/4` with a `max_age` option instead of the full JWT, or generate a one-time-use token that is invalidated on first use.

### 8.2 Locale Redirect

**Finding L-007: LOW -- Unsanitized locale in redirect URL**

```elixir
def handle_event("change_locale", %{"locale" => locale}, socket) do
  {:noreply, redirect(socket, to: "/settings?locale=#{locale}")}
end
```

The `locale` parameter is user-supplied and interpolated directly into the redirect URL. While Phoenix's `redirect/2` prevents open redirects (it only allows path-based redirects), an attacker could inject query parameters or URL fragments.

**Risk:** LOW. The locale value is rendered in the URL bar but does not flow into any dangerous context. The Locale plug presumably validates the locale against a known list. However, the string interpolation could inject additional query parameters (e.g., `locale=en&admin=true`).

**Recommendation:** Validate the locale against the known list before using it in the redirect:
```elixir
def handle_event("change_locale", %{"locale" => locale}, socket) do
  valid_locales = Enum.map(@locales, &elem(&1, 1))
  if locale in valid_locales do
    {:noreply, redirect(socket, to: "/settings?locale=#{locale}")}
  else
    {:noreply, put_flash(socket, :error, "Invalid locale")}
  end
end
```

---

## 9. `String.to_existing_atom` Audit (M-011 -- Updated)

The previous assessment flagged `String.to_existing_atom` in guided session events. A broader audit reveals widespread usage across the codebase. While `String.to_existing_atom` is the correct choice over `String.to_atom` (it prevents atom table exhaustion), it can crash on unknown strings.

**Files with `String.to_existing_atom` on user-supplied input:**

| File | Input Source | Risk |
|------|-------------|------|
| `lobby_live.ex` (9 call sites) | LiveView events | MEDIUM: crash on unknown values |
| `profile_live.ex` | Form select | MEDIUM: crash on unknown values |
| `tabbed_footer_live.ex` | LiveView event | LOW: limited tab values |
| `polls_live.ex` | Form params | MEDIUM: crash on unknown poll type |
| `about_content_component.ex` (2 sites) | LiveView events | LOW: limited values |
| `sensor_detail_live.ex` (2 sites) | URL params | MEDIUM: crash on unknown lens |
| `system_status_live.ex` | LiveView event | LOW: admin page |

**Remaining `String.to_atom` usage (unsafe):**

| File | Context | Risk |
|------|---------|------|
| `lobby_live.ex` line 2565 | `String.to_atom(type)` on guide suggested action type | MEDIUM: unbounded atom creation from guide events |
| `button.ex` line 1955 | Component helper converting string to atom | LOW: internal component usage |

**Positive patterns already in use:**

The `profile_live.ex` file uses a `safe_atom/2` whitelist for connection types:
```elixir
defp safe_atom(str, default) when is_binary(str) do
  case str do
    "follows" -> :follows
    "collaborates" -> :collaborates
    "mentors" -> :mentors
    _ -> default
  end
end
```

**Recommendation:** Apply this pattern consistently across all call sites. Create a shared helper module:
```elixir
defmodule SensoctoWeb.LiveHelpers.SafeAtom do
  @lenses ~w(sensors heartrate ecg breathing hrv gaze geolocation pressure)a
  @qualities ~w(auto high medium low)a
  @sorts ~w(activity name type)a

  def to_lens(str), do: safe(str, @lenses, :sensors)
  def to_quality(str), do: safe(str, @qualities, :auto)
  def to_sort(str), do: safe(str, @sorts, :activity)

  defp safe(str, allowed, default) do
    atom = String.to_existing_atom(str)
    if atom in allowed, do: atom, else: default
  rescue
    ArgumentError -> default
  end
end
```

---

## 10. Dependabot and CI Security (Updated Mar 2026)

### 10.1 GitHub Actions Supply Chain

Recent dependabot bumps have kept CI actions current:

| Action | Previous | Current | Security Impact |
|--------|----------|---------|-----------------|
| `actions/github-script` | v7 | v8 | Major version bump; review changelog |
| `actions/cache` | v4 | v5 | Cache isolation improvements |
| `actions/setup-node` | v4 | v6 | Node.js security patches |
| `actions/upload-artifact` | v4 | v6 | Artifact handling improvements |
| `actions/setup-dotnet` | v4 | v5 | .NET SDK security |

**Assessment: Good.** Keeping CI actions current reduces supply chain risk. All bumps are from the official `actions/` organization.

### 10.2 Claude PR Review Workflow

**File:** `.github/workflows/claude-pr-review.yml`

The addition of `allowed_bots: "dependabot[bot]"` enables automated Claude review of dependabot PRs. This is a positive security practice -- automated dependency updates get reviewed before merge.

### 10.3 Elixir Dependency Updates

`ash_admin` bumped from 0.13.24 to 0.13.26. `usage_rules` bumped to 1.2.3. No known CVEs in these versions.

---

## 11. Bot Protection Recommendation (H-005)

**Why Paraxial.io for Sensocto:**

1. **Native Elixir Integration**: Designed specifically for Phoenix/LiveView
2. **Invisible Security**: Bot detection without CAPTCHAs degrading UX
3. **IP Intelligence**: Real-time reputation scoring
4. **Minimal Overhead**: Designed for Elixir's concurrency model

---

## 12. Security Metrics

### Authentication Security Score: B+ (unchanged)

| Metric | Score | Notes |
|--------|-------|-------|
| Strategy Security | A | Magic Link with interaction required |
| Token Storage | A | Database-backed with revocation |
| Token Lifetime | B+ | 30-day session + 365-day remember_me |
| MFA | F | Not implemented |
| Rate Limiting | B | Comprehensive but skips GET requests |

### Authorization Security Score: B+ (downgraded from A-)

| Metric | Score | Notes |
|--------|-------|-------|
| Default Deny | A | Ash policies correctly configured |
| Room Access | A | Membership validation enforced |
| Channel Auth | B | Good but socket-level missing |
| API Auth | B | JWT validation good, room endpoints gap |
| Profile Operations | C | Skill/connection CRUD lacks ownership checks (M-012) |

### Privacy Score: A- (NEW)

| Metric | Score | Notes |
|--------|-------|-------|
| Default Privacy | A | `is_public` defaults to `false` |
| User Control | A | Settings page toggle, clear UX |
| Search Index | A | Respects `is_public` filter |
| Data Exposure | B | Email addresses visible in profile search (M-014) |
| Guest Privacy | A | Display names use hash, not ID prefix |

### Input Validation Score: B+ (downgraded from A-)

| Metric | Score | Notes |
|--------|-------|-------|
| Atom Protection | A | SafeKeys excellent for data layer |
| SQL Injection | A | Ecto parameterized queries |
| XSS Prevention | B | Headers good, CSP missing |
| LiveView Events | B- | Widespread `String.to_existing_atom` crash risk (M-011) |

### DoS Resistance Score: A (unchanged)

| Metric | Score | Notes |
|--------|-------|-------|
| Rate Limiting | A- | Multi-tier implementation (GET gap) |
| Backpressure | A | Quality-based throttling |
| Memory Protection | A | Configurable thresholds |
| Resource Cleanup | A | Monitor + GC patterns |

---

## 13. Planned Work: Security Implications

### 13.1 Room Iroh Migration (PLAN-room-iroh-migration.md)

**Security Impact: MEDIUM**

- **Risk**: Moving from PostgreSQL (with Ash policies) to in-memory GenServer + Iroh docs removes the authorization layer. Room CRUD operations currently go through Ash which enforces default-deny policies. The new `RoomStore` GenServer has no equivalent access control.
- **Risk**: Iroh P2P sync introduces a new trust boundary. Data synced between nodes via Iroh docs must be validated on receipt to prevent poisoned state propagation.
- **Risk**: No encryption-at-rest. PostgreSQL had this via disk encryption; in-memory + Iroh docs need explicit encryption for sensitive room data.
- **Recommendation**: Implement authorization checks in `RoomStore` API functions before migration. Validate all Iroh-synced data. Consider encrypting room metadata in Iroh docs.

### 13.2 Adaptive Video Quality (PLAN-adaptive-video-quality.md) - IMPLEMENTED

**Security Impact: LOW**

- **Positive**: SnapshotManager uses ETS with TTL-based cleanup (60s), preventing unbounded memory growth from snapshot data.
- **Risk**: `video_snapshot` channel event broadcasts base64-encoded JPEG data. No size validation on incoming snapshots could allow memory exhaustion via oversized payloads.
- **Recommendation**: Add max size validation (e.g., 100KB) for incoming `video_snapshot` events in `call_channel.ex`.

### 13.3 Other Plans

All plan assessments from previous report remain valid:

| Plan | Impact | Priority |
|------|--------|----------|
| Sensor Component Migration | LOW | No action needed |
| Startup Optimization (IMPLEMENTED) | NONE | No action needed |
| Delta Encoding ECG | LOW-MED | During implementation |
| Cluster Sensor Visibility | MEDIUM | Before implementation |
| Distributed Discovery | MEDIUM | Before implementation |
| Sensor Scaling Refactor | LOW-MED | During implementation |
| Research-Grade Synchronization | LOW-MED | During implementation |
| TURN/Cloudflare (IMPLEMENTED) | LOW | Monitoring |

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

## 14. Guided Session Feature -- Security Analysis (Feb 24, 2026)

### 14.1 Feature Overview

The Guided Session feature enables a "guide" user to share their navigation state (lens view, focused sensor, annotations, suggested actions) with a "follower" user in real time. The guide creates a session, receives a 6-character invite code, and shares it with the follower. The follower visits `/guide/join?code=ABCDEF`, accepts the invitation, and their lobby view begins mirroring the guide's navigation.

**Files analyzed:**
- `lib/sensocto/guidance.ex` -- Ash domain
- `lib/sensocto/guidance/guided_session.ex` -- Ash resource (invite codes, session status)
- `lib/sensocto/guidance/session_server.ex` -- GenServer managing guide/follower state
- `lib/sensocto/guidance/session_supervisor.ex` -- DynamicSupervisor
- `lib/sensocto_web/live/guided_session_join_live.ex` -- Join page LiveView
- `lib/sensocto_web/router.ex` -- Route at `/guide/join`
- `lib/sensocto_web/live/lobby_live.ex` -- Guidance event handling and PubSub subscriptions

### 14.2 Invite Code Brute-Force Resistance

**Alphabet:** 31 characters (`ABCDEFGHJKLMNPQRSTUVWXYZ23456789` -- no I, O, 0, 1)
**Code length:** 6 characters
**Total keyspace:** 31^6 = ~887 million combinations

**Risk assessment:** With a single active invite code, the probability of a correct guess per attempt is ~1 in 887 million. This is adequate for a low-value target. However:

- The join page (`GuidedSessionJoinLive.mount/3`) performs a database lookup on every page load with the provided code. There is no rate limiting on this lookup because the page is a GET request and the existing rate limiter only covers POST requests (see M-007).
- An attacker could enumerate codes by scripting GET requests to `/guide/join?code=XXXXXX` and observing whether the response contains the error message or the accept button.
- If multiple sessions are active simultaneously, the probability of hitting any valid code increases proportionally.

**Finding M-009: MEDIUM -- No rate limiting on invite code lookups**

**Recommendation:** Add rate limiting to the join page, either by:
1. Moving the code validation to a POST action (submit a form with the code) so the existing rate limiter applies
2. Adding a dedicated rate limit check in the LiveView mount for the join page
3. Using Paraxial.io to detect automated enumeration patterns

Additionally, consider adding a short delay or requiring the user to be authenticated before the code is looked up.

### 14.3 Authorization Model

**Finding M-010: MEDIUM -- `authorize?: false` on all Guidance Ash operations**

Every Ash operation in the Guidance domain uses `authorize?: false`:

```elixir
# guided_session_join_live.ex
Ash.read_one(GuidedSession, action: :by_invite_code, ..., authorize?: false)
Ash.update(session, ..., action: :assign_follower, authorize?: false)
Ash.update(session, ..., action: :accept, authorize?: false)

# session_server.ex
Ash.get(Sensocto.Guidance.GuidedSession, state.session_id, authorize?: false)
Ash.update(session, %{}, action: :end_session, authorize?: false)

# lobby_live.ex
Ash.read(Sensocto.Guidance.GuidedSession, action: :active_for_user, ..., authorize?: false)
```

The GuidedSession resource has no `policies` block defined. This means:
- Any code path with `authorize?: false` can read, create, update, or destroy any guided session
- There is no Ash-level enforcement that only the guide can modify guide-only fields or that only participants can end sessions

**Current mitigation:** The SessionServer GenServer performs its own `is_guide?`/`is_follower?` checks on every call, which provides runtime authorization. This is effective for the GenServer-mediated operations. However, the Ash resource itself is unprotected -- any code that directly calls `Ash.update(session, ...)` without going through the SessionServer bypasses these checks.

**Recommendation:** Add Ash policies to the GuidedSession resource:
```elixir
policies do
  policy action_type(:read) do
    authorize_if always()  # Read is acceptable for code lookup
  end

  policy action(:accept) do
    authorize_if expr(status == :pending)
  end

  policy action(:end_session) do
    authorize_if actor_attribute_equals(:id, :guide_user_id)
    authorize_if actor_attribute_equals(:id, :follower_user_id)
  end
end
```

### 14.4 SessionServer Authorization Checks

The SessionServer uses `is_guide?/2` and `is_follower?/2` to gate operations:

```elixir
defp is_guide?(%{guide_user_id: guide_id}, user_id) do
  to_string(guide_id) == to_string(user_id)
end

defp is_follower?(%{follower_user_id: follower_id}, user_id) do
  to_string(follower_id) == to_string(user_id)
end
```

**Assessment: Good.** The `to_string/1` comparison handles the UUID type mismatch (binary vs string) safely. Every guide-only action (`set_lens`, `set_focused_sensor`, `add_annotation`, `suggest_action`) checks `is_guide?`. Every follower-only action (`break_away`, `rejoin`, `report_activity`) checks `is_follower?`. The `end_session` action correctly allows either party. The `get_state` action returns state to any caller -- this is acceptable since the PubSub topic is already scoped to participants.

**One concern:** The `connect` and `disconnect` casts silently ignore unknown `user_id` values (the `true` branch in the `cond`). This is fine -- no state mutation occurs for unknown users.

### 14.5 Atom Exhaustion Risk in Guide Events

**Finding M-011: MEDIUM -- `String.to_existing_atom` in guide events can crash on unknown atoms**

```elixir
# lobby_live.ex line 2941
def handle_event("guide_set_lens", %{"lens" => lens_str}, socket) do
  lens = String.to_existing_atom(lens_str)
  ...
end

# lobby_live.ex line 2961
def handle_event("guide_suggest", %{"type" => type, ...}, socket) do
  action = %{type: String.to_existing_atom(type), ...}
  ...
end
```

`String.to_existing_atom/1` raises `ArgumentError` if the atom does not exist. While this prevents atom table exhaustion (which is good -- the correct function to use over `String.to_atom/1`), an attacker sending a crafted event with an unknown string will crash the LiveView process. LiveView will reconnect, but repeated crashes could degrade the user experience.

**Recommendation:** Wrap in a try/rescue or use a whitelist:
```elixir
defp safe_to_lens(lens_str) do
  case lens_str do
    "sensors" -> :sensors
    "heartrate" -> :heartrate
    "ecg" -> :ecg
    # ... all known lenses
    _ -> nil
  end
end
```

### 14.6 PubSub Topic Access Control

**Topics used:**
- `"guidance:#{session_id}"` -- session events (lens changes, annotations, presence, etc.)
- `"user:#{user_id}:guidance"` -- per-user notification when an invitation is accepted

**Assessment: Acceptable (I-001).** The session_id is a UUID, making topic enumeration impractical. PubSub subscription happens server-side in `subscribe_to_guided_session/2` and the `handle_info` for `:guidance_invitation_accepted`, both of which validate participation. A client cannot subscribe to arbitrary PubSub topics -- subscription is controlled entirely by server-side LiveView code.

**Privacy verification (I-002):** When the follower breaks away, the guide receives a `{:guided_break_away, %{follower_user_id: user_id}}` event. The guide knows the follower broke away but cannot see what the follower is viewing. The follower's independent navigation does not broadcast to the guidance topic. When the follower drifts back or rejoins, the guide is notified. This is the correct privacy boundary.

### 14.7 Join Flow Validation

The join flow in `GuidedSessionJoinLive`:

1. **Mount:** Looks up session by invite code (no auth required for the page load)
2. **Accept:** Checks `current_user` is not nil before proceeding
3. **Update:** Sets `follower_user_id` and transitions to `:active` status
4. **Start server:** Creates/gets SessionServer with follower info
5. **Notify guide:** Broadcasts acceptance on user-scoped topic

**Concerns:**
- The route is in the `live_user_optional` scope. An unauthenticated user will see the invite page but get a flash error when clicking Accept. This is acceptable UX -- they can see the invitation exists before signing in.
- However, this means an unauthenticated user can confirm whether an invite code is valid by observing the page response (error message vs. accept button). Combined with no rate limiting (M-009), this makes enumeration slightly easier.
- **UPDATE (Mar 2026):** The action name on the follower assignment has been corrected from `:create` to `:assign_follower`, fixing the action mismatch noted in the previous assessment.

**Recommendation:** Add a dedicated update action like `:join` that accepts `follower_user_id` if not already covered by `:assign_follower`.

### 14.8 Resource Exhaustion Vectors

**Finding L-005: LOW -- No limit on concurrent active sessions per guide**

A malicious guide could create many pending sessions, each consuming a database row and (upon acceptance) a GenServer process. The SessionServer has a 5-minute idle timeout, which provides some natural cleanup.

**Recommendation:** Add a check before session creation that limits active/pending sessions per guide (e.g., max 5).

**Finding L-006: LOW -- Unbounded annotations list in SessionServer**

The `add_annotation` handler appends to the annotations list indefinitely:
```elixir
new_state = %{state | annotations: state.annotations ++ [annotation]}
```

In a long session, this could grow unbounded. The `++` operator also has O(n) performance on each append.

**Recommendation:** Cap annotations at a reasonable limit (e.g., 100) and use a prepend + reverse pattern or a queue data structure.

### 14.9 Invite Code Expiration

**Finding L-004: LOW -- Invite codes never expire**

The `by_invite_code` read action filters for `status in [:pending, :active]` but has no time-based expiration. A pending invite code remains valid indefinitely until manually cancelled.

**Recommendation:** Add an `expires_at` attribute (e.g., `inserted_at + 1 hour` for pending sessions) and filter on it in the `by_invite_code` action:
```elixir
filter expr(
  invite_code == ^arg(:invite_code) and
  status in [:pending, :active] and
  (status == :active or inserted_at > ago(1, :hour))
)
```

### 14.10 Summary: Guided Session Security Grade

| Aspect | Grade | Notes |
|--------|-------|-------|
| Authorization (SessionServer) | B+ | Proper is_guide?/is_follower? checks on all actions |
| Authorization (Ash layer) | D | No policies, all `authorize?: false` |
| Invite Code Strength | B | ~887M keyspace adequate; lacks rate limiting and expiration |
| PubSub Access Control | A | Server-side subscription, UUID-based topics |
| Privacy (break-away) | A | Guide cannot see follower's independent navigation |
| Input Validation | C+ | `String.to_existing_atom` can crash; no annotation limits |
| Resource Management | B | Idle timeout good; missing session count limits |

**Overall feature security: B-** -- Functional authorization is sound, but lacks defense-in-depth at the Ash policy layer and needs rate limiting on the join flow.

---

## 15. Implementation Roadmap

### Phase 1: Immediate (1-2 days) -- ALL RESOLVED
- [x] Reduce token lifetime from 10 years to 30 days (H-001) -- **RESOLVED 2026-02-17**
- [x] Add remember_me strategy with 365-day cookie (H-001 companion) -- **RESOLVED 2026-02-17**
- [x] Replace `Ash.create!` with `Ash.create()` in sensor_data_channel.ex (M-008) -- **RESOLVED 2026-02-17**
- [x] Gate "missing" token behind configuration (M-001) -- **already implemented**
- [x] Replace `String.to_atom` in bridge.ex with SafeKeys (H-004) -- **verified: not present in code**
- [x] Use `Plug.Crypto.secure_compare` for guest tokens (M-005) -- **already implemented**
- [x] Protect /dev/mailbox route (M-006) -- **already behind `dev_routes`**
- [x] Gate debug endpoint behind dev_routes (M-003) -- **already behind `dev_routes`**
- [x] Add session cookie encryption_salt (M-004) -- **already implemented**

### Phase 2: Short-term (1 week)
- [ ] Add ownership checks to ProfileLive skill/connection operations (M-012)
- [ ] Replace `String.to_existing_atom` with whitelists across LiveViews (M-011, M-013)
- [ ] Limit email exposure in profile user search (M-014)
- [ ] Add socket-level authentication to UserSocket (H-002)
- [ ] Add auth pipeline to room API endpoints (H-003)
- [ ] Fix rate limiter to cover GET-based auth routes (M-007)
- [ ] Integrate Paraxial.io for bot protection (H-005)
- [ ] Add Content-Security-Policy headers
- [ ] Add rate limiting to guided session join page (M-009)
- [ ] Add Ash policies to GuidedSession resource (M-010)
- [ ] Add invite code expiration (L-004)
- [ ] Validate locale in settings redirect (L-007)
- [ ] Add chat message length limit (L-008)

### Phase 3: Medium-term (2-4 weeks)
- [ ] Implement refresh token pattern
- [ ] Add MFA for admin operations
- [ ] Security monitoring/alerting setup
- [ ] Pre-migration security review for Room Iroh Migration
- [ ] Pre-migration security review for Cluster Visibility plans
- [ ] Require bridge token in production (M-002)
- [ ] Add Ash policies to UserSkill and UserConnection resources

### Phase 4: Ongoing
- [ ] Penetration testing
- [ ] Python dependency auditing (for research-grade sync)
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

### Mar 1, 2026

Review of commits bb7db7f through d9321a8, plus e53fb41, ce729b2, 2797fa9, and dependabot PRs.

1. **Privacy default**: `is_public` changed from `true` to `false` in User resource with corresponding migration. All new users are private by default. SearchIndex and UserDirectoryLive correctly filter by `is_public`. **I-004: Verified Good.**
2. **Profile system**: New `ProfileLive` with skills, connections, and user graph. Authorization gaps identified (M-012, M-013, M-014). The `safe_atom/2` pattern for connection types is a positive security pattern that should be applied more broadly.
3. **User Settings**: New `UserSettingsLive` with privacy toggle, locale selection, and mobile device linking via QR code. Guest guard on privacy toggle is correct. Mobile token lifetime concern noted (JWT lifetime vs displayed lifetime).
4. **Chat fix**: Duplicate PubSub subscription prevented via process dictionary. No new security surface.
5. **Guest display names**: Switched from ID prefix to `phash2` hash. Eliminates guest ID information leakage.
6. **Guided session join**: Action name corrected from `:create` to `:assign_follower`. This was noted as a potential bug in the previous assessment.
7. **Sign-in guards**: Custom sign-in page validates guest session existence before redirecting. Prevents stale session access.
8. **Dependabot**: 6 GitHub Actions bumped to latest major versions. 2 Elixir dependencies updated. No known CVEs.
9. **`String.to_existing_atom` audit**: Expanded scope of M-011. Found widespread usage across codebase. Also found remaining `String.to_atom` usage in `lobby_live.ex` line 2565 (guide suggested action type). Profile already uses `safe_atom/2` whitelist for connection types -- this pattern should be applied consistently.
10. **Overall**: Security grade maintained at B+. Authorization score downgraded from A- to B+ due to profile operation gaps. New Privacy score added at A-. Three new MEDIUM findings (M-012, M-013, M-014) and two new LOW findings (L-007, L-008).

### Feb 24, 2026

Guided Session feature analysis. See Section 14 for full details. Findings M-009 through L-006.

### Feb 22, 2026

Token refresh, connector persistence, CRDT sessions. See archived changelog.

### Feb 20, 2026

Audio/MIDI system (client-side only), Polls domain, User Profiles/Social Graph, Delta Encoding, Health Check Endpoint.

### Feb 17, 2026

1. **Remember Me token strategy**: Added AshAuthentication's built-in `remember_me` strategy to `lib/sensocto/accounts/user.ex`. Session tokens last 30 days; remember_me cookie lasts 365 days. When the session token expires, the remember_me cookie silently re-authenticates. On explicit logout, both cookies are cleared via `delete_all_remember_me_cookies(:sensocto)`. The `sign_in_with_remember_me` plug runs before `load_from_session` in the browser pipeline. **Resolves H-001.**
2. **Token lifetime reduced**: Session token lifetime reduced from 3650 days (10 years) to 30 days. This is the primary security improvement of this round. **Resolves H-001.**
3. **Ash.create! replaced**: `Ash.create!` replaced with `Ash.create()` in `sensor_data_channel.ex` to properly handle write errors instead of crashing the channel process. **Resolves M-008.**
4. **WCAG color contrast**: `text-gray-400` changed to `text-gray-300` across lobby and app layouts (25 instances). Improves readability of security-relevant UI text.
5. **Bio factor error logging**: AttentionTracker now logs `Logger.warning` when novelty, predictive, competitive, or circadian factor computations fail. Improves anomaly detection observability.

### Feb 15, 2026

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

*Report generated by Security Advisor Agent (Claude Opus 4.6). Last updated: 2026-03-01*

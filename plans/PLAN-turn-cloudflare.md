# TURN Server & Cloudflare Realtime Integration Plan

**Status: CODE COMPLETE** (deploy/verification steps remain)

## Problem

WebRTC video calls fail on mobile devices (tested: Chrome on Samsung) when connecting to sensocto.fly.dev. Desktop Chrome works fine.

**Root cause**: Mobile carriers use symmetric NAT / CGNAT. STUN alone cannot traverse symmetric NAT — a TURN relay server is required. The platform had no TURN server configured.

**Secondary issue**: `Calls.get_ice_servers/0` was reading from `:sensocto, :calls` config (which had no `:ice_servers` key), falling back to a single Google STUN server. The server-side Membrane SFU had 7 STUN servers in `:membrane_rtc_engine_ex_webrtc` config, but clients only got 1.

## Completed Work

### 1. ICE Config Unification (done)

`Calls.get_ice_servers/0` now reads from `:membrane_rtc_engine_ex_webrtc` — same config the server-side SFU uses. Clients now get all 7 STUN servers.

**File**: `lib/sensocto/calls/calls.ex`

### 2. Cloudflare TURN Module (done)

New module `Sensocto.Calls.CloudflareTurn` generates ephemeral TURN credentials via Cloudflare's Realtime API.

**File**: `lib/sensocto/calls/cloudflare_turn.ex`

**Design decisions**:
- Credentials cached in `persistent_term` (24h TTL, refreshed when <1h remaining)
- Falls back gracefully — returns `nil` when not configured, calls still work via STUN
- No GenServer needed — `persistent_term` is process-independent and lock-free for reads

### 3. Runtime Config (done)

`config/runtime.exs` reads `CLOUDFLARE_TURN_KEY_ID` and `CLOUDFLARE_TURN_API_TOKEN` env vars.

---

## Remaining Setup Steps

### Step 1: Create Cloudflare TURN Key

1. Go to [Cloudflare Dashboard](https://dash.cloudflare.com) > **Realtime** > **TURN**
2. Click **Create TURN Key**
3. Save the **Key ID** and **API Token**

Cloudflare free tier: 1000 GB/month relay traffic.

### Step 2: Set fly.dev Secrets

```bash
fly secrets set CLOUDFLARE_TURN_KEY_ID="<key-id>" -a sensocto
fly secrets set CLOUDFLARE_TURN_API_TOKEN="<api-token>" -a sensocto
```

### Step 3: Deploy

```bash
fly deploy -a sensocto
```

### Step 4: Verify

1. Open sensocto.fly.dev on mobile Chrome (Samsung)
2. Join a room and start a video call
3. Verify call connects successfully
4. Check server logs for: `CloudflareTurn: Generated credentials (TTL: 86400s)`

---

## Architecture

### ICE Server Flow

```
Client joins call
    |
    v
CallChannel.join/3
    |
    v
Calls.get_ice_servers/0
    |
    +---> membrane_rtc_engine_ex_webrtc config (7 STUN servers)
    |         stun:stun.l.google.com:19302
    |         stun:stun1.l.google.com:19302
    |         stun:stun2.l.google.com:19302
    |         stun:stun3.l.google.com:19302
    |         stun:stun4.l.google.com:19302
    |         stun:global.stun.twilio.com:3478
    |         stun:stun.cloudflare.com:3478
    |
    +---> CloudflareTurn.get_ice_servers/0
    |         |
    |         +---> cached in persistent_term? -> return cached
    |         |
    |         +---> expired/missing -> POST Cloudflare API
    |                   |
    |                   v
    |               turn:turn.cloudflare.com:3478 (UDP)
    |               turn:turn.cloudflare.com:3478 (TCP)
    |               turn:turn.cloudflare.com:80   (TCP)
    |               turn:turn.cloudflare.com:443  (TLS)
    |               + ephemeral username/credential
    |
    v
Merged ICE config sent to client via channel join response
    |
    v
membrane_client.js sets rtcConfig.iceServers
    |
    v
WebRTC ICE negotiation uses STUN first, falls back to TURN relay
```

### Credential Lifecycle

```
First call join after deploy:
  1. CloudflareTurn checks persistent_term -> nil (cache miss)
  2. POST to Cloudflare API with TTL=86400s (24h)
  3. Store {ice_servers, expires_at} in persistent_term
  4. Return ice_servers

Subsequent call joins (within 23h):
  1. CloudflareTurn checks persistent_term -> found
  2. Check remaining time > 3600s (1h threshold) -> yes
  3. Return cached ice_servers (no API call)

After 23h (refresh threshold):
  1. CloudflareTurn checks persistent_term -> found
  2. Check remaining time > 3600s -> no (expired)
  3. POST to Cloudflare API for fresh credentials
  4. Update persistent_term cache
  5. Return new ice_servers
```

### Failure Mode

If Cloudflare API is unreachable:
- `get_ice_servers/0` returns only the 7 STUN servers (no TURN)
- Desktop users on normal networks: unaffected (STUN works)
- Mobile users behind symmetric NAT: call will fail to connect
- Error logged: `CloudflareTurn: Failed to generate credentials: ...`
- Next call join attempt will retry the API

---

## Future Considerations

### Per-Session Credentials
Currently credentials are shared across all call participants for up to 24h. For stricter security, could generate per-session credentials (shorter TTL, unique per call join). Trade-off: more API calls vs. credential isolation.

### Server-Side TURN for Membrane SFU
The current implementation provides TURN credentials to the client-side WebRTC peer connection. The server-side Membrane RTC Engine (ExWebRTC) also needs ICE servers for its peer connections. Currently both read from the same `:membrane_rtc_engine_ex_webrtc` config, but the Cloudflare TURN credentials are only merged into the client-side path. If the SFU itself is behind NAT (unlikely on fly.dev), the server-side config would also need TURN.

### Monitoring
Could add telemetry events for:
- TURN credential generation (success/failure/latency)
- Cache hit/miss ratio
- TURN relay usage per call (via Cloudflare analytics API)

### Alternative: Fly.dev Private Networking
Fly.dev instances have private IPs reachable from other fly instances. If both SFU and TURN were on fly.dev, could potentially use Fly's internal networking. But Cloudflare TURN is simpler and free.

---

## Files Changed

| File | Status | Description |
|------|--------|-------------|
| `lib/sensocto/calls/cloudflare_turn.ex` | **New** | Cloudflare TURN credential generation + caching |
| `lib/sensocto/calls/calls.ex` | Modified | `get_ice_servers/0` reads from membrane config + merges Cloudflare TURN |
| `config/runtime.exs` | Modified | Added `CLOUDFLARE_TURN_KEY_ID` / `CLOUDFLARE_TURN_API_TOKEN` config |
| `.env.example` | Modified | Documented both Cloudflare TURN and static TURN options |

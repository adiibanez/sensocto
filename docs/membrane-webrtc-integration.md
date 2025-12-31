# Membrane WebRTC Integration

## Overview

This document summarizes the current state of the Membrane RTC Engine integration for video/voice calls in the Sensocto platform.

## Architecture

### Server-Side Components

1. **CallServer** (`lib/sensocto/calls/call_server.ex`)
   - GenServer managing call state for each room
   - Wraps Membrane RTC Engine
   - Handles participant management, track registry, and quality settings
   - Key features:
     - Reconnection handling (removes old endpoint before creating new one)
     - Track cleanup when endpoints are removed/crashed
     - Inactivity timeout (30 minutes)
     - Quality profile management (auto/high/medium/low)

2. **CallChannel** (`lib/sensocto_web/channels/call_channel.ex`)
   - Phoenix Channel for WebRTC signaling
   - Handles SDP offers/answers, ICE candidates, and media events
   - Forwards events between browser clients and Membrane RTC Engine
   - Events: `join_call`, `leave_call`, `media_event`, `toggle_audio`, `toggle_video`, `set_quality`

3. **QualityManager** (`lib/sensocto/calls/quality_manager.ex`)
   - Calculates video quality based on participant count
   - Provides video constraints for different quality levels

### Client-Side Components

1. **MembraneClient** (`assets/js/webrtc/membrane_client.js`)
   - Wrapper around `@jellyfish-dev/membrane-webrtc-js` WebRTCEndpoint
   - Handles connection, track management, and event forwarding
   - Key methods: `connect()`, `addLocalMedia()`, `handleMediaEvent()`, `disconnect()`

2. **MediaManager** (`assets/js/webrtc/media_manager.js`)
   - Handles getUserMedia, device enumeration, and device switching
   - Quality profiles for video constraints
   - Screen sharing support via `getDisplayMedia()`

3. **CallHooks** (`assets/js/webrtc/call_hooks.js`)
   - Phoenix LiveView hooks for call UI integration
   - Track buffering system for handling race conditions
   - MutationObserver for detecting new participant containers
   - Retry logic for attaching local video stream

## Current Issues

### 1. Video Track Not Registering on Server (UNRESOLVED)

**Symptom:** Server only shows audio track, not video track, despite client adding both.

**Evidence:**
- Client logs show both audio and video tracks being added
- Server logs only show `TrackAdded :audio` message
- `remoteTracks: 0` in browser despite server having tracks

**Potential causes:**
- Issue with Membrane RTC Engine track negotiation
- Timing issue between client track addition and server registration
- WebRTC endpoint configuration issue

### 2. Remote Video Not Displaying (CONSEQUENCE OF #1)

**Symptom:** Users can see their own camera but not other participants' video.

**Related to:** Video track not being registered on server properly.

### 3. Race Condition - Tracks Before Containers (FIXED)

**Problem:** Tracks arrive before participant containers are rendered in DOM.

**Solution:** Implemented track buffering with `pendingTracks` Map and MutationObserver to attach tracks when containers appear.

### 4. Local Video Not Showing Initially (FIXED)

**Problem:** Video element doesn't exist when `attachLocalStream()` first runs.

**Solution:** Added `attachLocalStreamWithRetry()` with exponential backoff.

### 5. Reconnection Issues (FIXED)

**Problem:** Users rejoining calls got "already_joined" error.

**Solution:** Modified `add_participant` in CallServer to detect existing user and remove old endpoint before creating new one.

### 6. Stale Tracks in Registry (FIXED)

**Problem:** Old tracks from disconnected users remained in track registry.

**Solution:** Added track cleanup in:
- `remove_participant` handler
- `EndpointRemoved` handler
- `EndpointCrashed` handler

## Configuration

### ICE Servers

ICE servers are configured via application config for `:membrane_rtc_engine_ex_webrtc`. Currently uses default STUN servers.

### Membrane Dependencies

```elixir
{:membrane_rtc_engine, "~> 0.24.0"},
{:membrane_rtc_engine_ex_webrtc, "~> 0.10.0"},
```

### Client Dependencies

```json
"@jellyfish-dev/membrane-webrtc-js": "^0.6.0"
```

## Debugging Tips

### Server-Side Logging

Debug statements added to CallServer:
```elixir
IO.puts(">>> CallServer: TrackAdded #{track_type} from #{endpoint_id}")
IO.puts(">>> CallServer: EndpointMessage media_event from #{endpoint_id}")
```

Debug statements in CallChannel:
```elixir
IO.puts(">>> CallChannel: User #{user_id} attempting to join call in room #{room_id}")
IO.puts(">>> CallChannel: Forwarding media event to #{socket.assigns.user_id}")
```

### Client-Side Debugging

In browser console:
```javascript
// Check WebRTC state
window.membraneClient.getRemoteTracks()
window.membraneClient.getLocalTracks()
window.membraneClient.getParticipants()

// Check call state from server
Calls.get_state(room_id)
```

### GenServer State Issues

Note: GenServer processes don't hot-reload code. To apply changes to CallServer:
1. Stop all active calls
2. Or restart the CallServer process manually
3. Or restart the application

## Next Steps

1. **Investigate video track registration** - Deep dive into why video tracks aren't being registered on the server
2. **Add TURN server support** - For NAT traversal in production environments
3. **Implement screen sharing** - MediaManager already has `getDisplayMedia()` support
4. **Add call recording** - Membrane supports recording via additional endpoints
5. **Improve quality adaptation** - Implement bandwidth-based quality switching

## Related Files

- `lib/sensocto/calls.ex` - Main Calls context module
- `lib/sensocto/calls/call_supervisor.ex` - DynamicSupervisor for CallServers
- `lib/sensocto_web/live/room_live.ex` - Room LiveView with call UI
- `assets/svelte/RoomCall.svelte` - Svelte component for call UI (if exists)

## References

- [Membrane RTC Engine Documentation](https://hexdocs.pm/membrane_rtc_engine/)
- [ExWebRTC Endpoint](https://hexdocs.pm/membrane_rtc_engine_ex_webrtc/)
- [Membrane WebRTC JS SDK](https://github.com/jellyfish-dev/membrane-webrtc-js)

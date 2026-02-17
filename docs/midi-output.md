# MIDI Output System

Sensocto translates real-time biometric sensor data into MIDI messages, enabling musicians and performers to use physiological signals as musical controllers. The system is designed for live performance scenarios where the goal is to **inspire human synchronization through music**.

## Architecture

```
Sensors → SimpleSensor → PubSub → PriorityLens → LobbyLive
                                                      │
                                                push_event("composite_measurement")
                                                      │
                                                      ▼
                                              CompositeMeasurementHandler (JS hook)
                                                      │
                                              window CustomEvent: "composite-measurement-event"
                                                      │
                                                      ▼
                                              MidiOutputHook (JS hook)
                                                      │
                               ┌────────────┬─────────┼─────────┬────────────┐
                               │            │         │         │            │
                          Ch 1 Breath  Ch 2 Heart  Ch 3 Mind  Ch 4 Energy  Ch 5 Sync
                          (CC LFO)    (Note-On)   (CC HRV)   (CC Arousal) (CC Sync)
                               │            │         │         │            │
                               └────────────┴─────────┼─────────┴────────────┘
                                                      │
                                              + MIDI Clock (channel-less)
                                              + Ch 10 Sync Drums (Note triggers)
                                                      │
                                              WebMIDI API → output.send()
                                                      │
                                              Virtual MIDI Bus (IAC Driver)
                                                      │
                                              DAW / Synth / Max/MSP
```

The entire MIDI layer is **pure client-side JavaScript**. No server-side MIDI processing is needed. The hook taps into the existing `composite-measurement-event` window events that are already flowing for the Svelte composite views.

## Files

| File | Purpose |
|------|---------|
| `assets/js/midi_output.js` | Standalone WebMIDI wrapper class (`MidiOutput`) |
| `assets/js/hooks/midi_output_hook.js` | LiveView hook: mapping logic, clock, threshold detection |
| `lib/sensocto_web/live/lobby_live.html.heex` | MIDI panel UI (toggle, device select, meters) |

## Channel Layout — One Instrument Per Channel

Each MIDI channel represents a separate **instrument** in the DAW. Create one MIDI track per channel, each routed to a different synth or effect.

| Channel | Name | Role | Instrument Idea |
|---------|------|------|-----------------|
| **1** | Breath | Breathing waveform controller | Pad synth, wind instrument, filter sweeps |
| **2** | Heart | Heartbeat pulse trigger | Bass synth, kick drum, rhythmic pulse |
| **3** | Mind | HRV / nervous system state | Drone, texture, ambient layer |
| **4** | Energy | Collective arousal dynamics | Master bus, compressor sidechain, intensity |
| **5** | Sync | Group synchronization level | Chord/harmony generator, consonance control |
| **10** | Drums | Sync threshold triggers | GM drum kit, scene changes, transitions |
| *n/a* | Clock | MIDI Timing Clock (24 PPQN) | DAW transport sync (channel-less) |

### Why separate channels?

In a DAW, each MIDI track filters by channel. With one instrument per channel:

- No need for complex CC routing or MIDI Learn
- Each track gets exactly the data it needs
- A musician can solo/mute individual biometric layers
- Different synths/effects per body signal — breath drives a pad, heartbeat drives a bass, HRV drives a drone
- Mixable: balance the "body orchestra" like any multi-track session

## CC Mapping Reference

### Channel 1 — Breath Instrument

| CC# | Name | Source | Input Range | Description |
|-----|------|--------|-------------|-------------|
| 2 | Breath Controller | Group breath phase | Sinusoidal 0–127 | Biological LFO oscillating with the group's breathing. Route to filter cutoff, reverb wet/dry, volume swell. |
| 11 | Expression | Individual breath depth | 50–100% torso | Per-sensor breath depth. Controls dynamics within the breath instrument. |
| 74 | Brightness | Group breathing rate | 8–24 breaths/min | Breathing tempo as a filter parameter. Fast breathing = brighter timbre. |

### Channel 2 — Heart Instrument

| Message | Data | Description |
|---------|------|-------------|
| Note-On | Note 60 (Middle C) | Fires on each heartbeat measurement |
| Velocity | 0–127 (scaled from 50–140 BPM) | Soft at resting HR, hard at elevated HR |
| Note-Off | After 50ms | Auto-release for short percussive triggers |

Multiple sensors fire independently — with N people, you get N heartbeat streams on the same channel, creating natural polyrhythms.

### Channel 3 — Mind Instrument (HRV)

| CC# | Name | Source | Input Range | Description |
|-----|------|--------|-------------|-------------|
| 1 | Mod Wheel | Group mean HRV RMSSD | 5–80 ms | Nervous system state. Low HRV (stress) → low CC → dark/tense timbre. High HRV (relaxed) → high CC → warm/open timbre. |

### Channel 4 — Energy (Collective Arousal)

| CC# | Name | Source | Description |
|-----|------|--------|-------------|
| 7 | Volume | Computed arousal envelope | Fused signal: `0.4×HR + 0.35×(1/HRV) + 0.25×breathRate`. Controls the music's overall intensity. Heavily smoothed (α=0.15) — changes glacially over minutes, not seconds. |

### Channel 5 — Sync

| CC# | Name | Source | Input Range | Description |
|-----|------|--------|-------------|-------------|
| 16 | General Purpose 1 | Breathing sync (Kuramoto R) | 0–100 | How synchronized the group's breathing is. 0 = chaos, 100 = perfect unison. Route to harmonic consonance, chord complexity, or reverb size. |
| 17 | General Purpose 2 | HRV sync (Kuramoto R) | 0–100 | How synchronized the group's HRV is. Cardiac coherence indicator. |

### Channel 10 — Sync Drums (GM Percussion)

| Sync Level | Threshold | GM Drum | Musical Meaning |
|------------|-----------|---------|-----------------|
| Emerging | R ≥ 30 | 42 (Closed Hi-Hat) | Patterns starting to form |
| Locking | R ≥ 50 | 38 (Snare Drum) | Rhythm solidifying |
| Coherent | R ≥ 70 | 36 (Bass Drum) | Group locked in |
| Deep Sync | R ≥ 90 | 49 (Crash Cymbal) | Transcendent alignment |

When sync drops below a threshold, the corresponding Note-Off is sent. These events trigger **scene changes, clip launches, or dramatic musical transitions**.

## MIDI Clock

The system generates **MIDI Timing Clock** messages (0xF8) at 24 PPQN, synced to the group's average heart rate. MIDI Clock is channel-less — it syncs the entire DAW.

- **Tempo source**: Mean heart rate across all connected sensors
- **BPM range**: 30–240 (safety clamped)
- **Transport**: Sends MIDI Start (0xFA) when clock begins, MIDI Stop (0xFC) when disabled
- **Jitter suppression**: BPM changes below 0.5 BPM are ignored
- **Stale sensor pruning**: Sensors not seen for 10 seconds are removed from the average

### DAW Sync Setup

| DAW | Setting |
|-----|---------|
| **Ableton Live** | Preferences → Link/Tempo/MIDI → enable "Sync" on IAC input |
| **Logic Pro** | Project Settings → Synchronization → MIDI → receive MIDI Clock |
| **Max/MSP** | `[midiin]` → route clock messages |

The DAW's tempo display will follow the group's collective heartbeat.

## Collective Arousal Envelope

A computed meta-signal fusing multiple biometric streams:

```
arousal = 0.40 × HR_component    (heart rate: 60→0, 140→1)
        + 0.35 × HRV_component   (HRV inverted: 80ms→0, 5ms→1)
        + 0.25 × BR_component    (breath rate: 8/min→0, 24/min→1)
```

Output as **CC7 (Volume) on Channel 4**. Heavily smoothed for macro dynamics — think of it as a "how alive is this room" knob that moves over minutes.

## Breath Phase LFO

The system extracts a **sinusoidal phase signal** from the group's breathing waveform:

1. Maintains a rolling window of 60 breath samples
2. Normalizes the latest value against the window's min/max
3. Outputs as CC2 on Channel 1: 0 at exhale trough, 127 at inhale peak

This creates a **biological LFO** synchronized to the group's actual breathing rhythm. Route it to filter cutoff for a room that "breathes" together.

The breathing rate is estimated via zero-crossing analysis and output as **CC74 on Channel 1**, providing a tempo indicator for the breath cycle.

## Smoothing

All CC values pass through an Exponential Moving Average (EMA) filter:

| Parameter | EMA alpha | Responsiveness |
|-----------|-----------|----------------|
| Breath depth/phase | 0.3 | Moderate — preserves waveform shape |
| HRV | 0.2 | Heavier — RMSSD is naturally noisy |
| Sync values | 0.4 | Lighter — already smoothed server-side |
| Arousal | 0.15 | Very heavy — should change slowly |
| Breath rate | 0.2 | Heavy — rate estimate is noisy |

## UI Panel

The MIDI panel appears in the lobby as a compact toolbar:

- **Toggle button**: MIDI On/Off (persisted to localStorage)
- **Device selector**: Auto-populated from WebMIDI outputs, auto-selects remembered device
- **Live meters**: Color-coded bars — BPM (red), Arousal (amber), HRV (purple), Breath (cyan), BreathSync (teal), HRVSync (indigo)
- **Sync trigger flash**: Brief `▲ coherent` / `▼ locking` indicator on threshold crossings

Uses `phx-update="ignore"` so LiveView DOM patches don't reset JS state.

## Setup Guide

### Prerequisites

1. A browser with WebMIDI support (Chrome, Edge, Opera — not Safari)
2. A virtual MIDI bus for routing to a DAW

### macOS Setup (IAC Driver)

1. Open **Audio MIDI Setup** (Spotlight → "Audio MIDI Setup")
2. Window → Show MIDI Studio (Cmd+2)
3. Double-click **IAC Driver**
4. Check **"Device is online"**
5. Click Apply

### Windows Setup

1. Install [loopMIDI](https://www.tobias-erichsen.de/software/loopmidi.html) (free)
2. Create a virtual port (e.g., "Sensocto MIDI")

### Using with Sensocto

1. Navigate to any lobby view (`/lobby/breathing`, `/lobby/hrv`, `/lobby/graph`, etc.)
2. Click **"MIDI Off"** to toggle to **"MIDI On"**
3. Select your virtual MIDI device from the dropdown
4. The device selection persists across page loads and is auto-restored

### Monitoring MIDI Output

```bash
brew install --cask midi-monitor   # macOS
```

Open MIDI Monitor, enable IAC Driver as a source. You'll see CC messages on channels 1-5, note triggers on channels 2 and 10, and clock messages.

### DAW Quick Start — Ableton Live

1. **Preferences → Link/Tempo/MIDI**: Enable "Sync" and "Remote" on IAC Driver input
2. Create **5 MIDI tracks**, one per channel:
   - Track 1: Input = IAC, Channel = 1 → Load a pad synth → Map CC2 to filter cutoff
   - Track 2: Input = IAC, Channel = 2 → Load a bass synth → Receives heartbeat Note-On
   - Track 3: Input = IAC, Channel = 3 → Load a drone/texture → Map CC1 to timbre
   - Track 4: Input = IAC, Channel = 4 → Use as sidechain → CC7 controls master volume
   - Track 5: Input = IAC, Channel = 5 → Load a chord instrument → Map CC16 to consonance
3. Optional: Track 6 on Channel 10 for GM drums (sync triggers as transitions)
4. Tempo follows the group's heart rate automatically via MIDI Clock

### Code Examples

#### SuperCollider
```supercollider
MIDIClient.init;
MIDIIn.connectAll;
// Channel 1: Breath LFO
MIDIdef.cc(\breath, { |val| ~breathLFO = val / 127 }, 2, 0);
// Channel 3: HRV
MIDIdef.cc(\hrv, { |val| ~hrvState = val / 127 }, 1, 2);
// Channel 4: Arousal
MIDIdef.cc(\arousal, { |val| ~arousal = val / 127 }, 7, 3);
// Channel 2: Heartbeat
MIDIdef.noteOn(\heartbeat, { |vel, note| Synth(\kick, [\amp, vel / 127]) }, nil, 1);
```

#### Max/MSP
```
[midiin] → [midiparse]
           |
  [route 176]  ← Control Change
           |
  [route 0 2 4]  ← Filter by channel (0=Ch1, 2=Ch3, 4=Ch5)
           |
  Ch1: [route 2 11 74]  ← CC2=breath, CC11=depth, CC74=rate
  Ch3: [route 1]         ← CC1=HRV
  Ch5: [route 16 17]     ← CC16=breathSync, CC17=hrvSync
```

## Resilience

| Failure Mode | Behavior |
|-------------|----------|
| No WebMIDI (Safari/iOS) | Silent no-op, panel renders but stays inert |
| Permission denied | `console.warn`, panel stays inert |
| Device disconnects | Auto-clear output, dropdown updates, all sends become no-ops |
| Device reconnects | Auto-re-selected if previously remembered via localStorage |
| Malformed payload | `parseFloat` + `isNaN` guard → skip |
| Exception in handler | try/catch → `console.warn`, continues |
| LiveView DOM patch | `phx-update="ignore"` prevents state reset |
| No heartrate data | Clock doesn't start (requires BPM ≥ 30) |
| No breathing data | Phase tracker returns neutral (64), rate returns 0 |
| Stale sensor | Pruned from average after 10s of silence |

## Performance Considerations

- MIDI hook processes events on the main thread alongside Svelte components
- `output.send()` is non-blocking (browser handles scheduling)
- MIDI Clock uses `setInterval` — accuracy ±1-4ms (sufficient for musical tempo)
- EMA smoothing: zero allocations, single multiply-add per sample
- Sensor maps pruned every 5 seconds to prevent memory leaks

### Server-Side Optimizations

#### Sync Channel Throttling

`SyncComputer` throttles PubSub broadcasts to a maximum of **one per 200ms per sync type**. Without throttling, sync values (`breathing_sync`, `hrv_sync`, `rsa_coherence`) can be recomputed on every sensor measurement, which with 10+ sensors can produce 300+ events/second on the `sync:updates` topic. This flood reaches the MIDI hook fast enough to cause MIDI crackling — too many CC messages arriving in a single browser tick.

The throttle is implemented via a `last_broadcast` map keyed by attribute ID. Each call to `maybe_broadcast_sync/4` compares `System.system_time(:millisecond)` against the last broadcast time and silently drops the broadcast if less than `@broadcast_throttle_ms` (200) milliseconds have elapsed. AttributeStoreTiered is still written on every update — only the PubSub broadcast is throttled.

Relevant constant in `lib/sensocto/bio/sync_computer.ex`:

```elixir
@broadcast_throttle_ms 200
```

#### Demand-Driven SyncComputer Activation

`SyncComputer` is idle by default. It subscribes to sensor data topics only when at least one viewer is registered. This avoids paying the subscription and computation cost on deployments where nobody is using MIDI.

Activation happens from two sources:

1. **Sync-native views** (`:respiration`, `:hrv`): `LobbyLive` calls `SyncComputer.register_viewer()` in `ensure_attention_for_composite_sensors/2` when entering those views, and `unregister_viewer()` in the cleanup path when leaving.

2. **Graph and all other views**: The JS hook calls `this.pushEvent("midi_toggled", { enabled: true/false })` on every toggle. `LobbyLive.handle_event("midi_toggled", ...)` registers or unregisters the viewer and subscribes/unsubscribes to the `"sync:updates"` PubSub topic accordingly — but only when the current view is not already a sync-native view (to avoid double-counting).

When the viewer count drops to zero, `SyncComputer` unsubscribes from all tracked sensor `data:{sensor_id}` topics but preserves the phase buffers and smoothed values so reactivation is fast. The `active` flag gates all message processing during idle.

Flow for a graph-view MIDI toggle:

```
User clicks "MIDI On"
  → MidiOutputHook.toggleMidi()
  → this.pushEvent("midi_toggled", { enabled: true })
  → LobbyLive.handle_event("midi_toggled", %{"enabled" => true}, socket)
  → SyncComputer.register_viewer()           # viewer_count: 0 → 1
  → SyncComputer activates, discovers sensors
  → Phoenix.PubSub.subscribe("sync:updates")
  → {:sync_update, attr_id, value, ts} messages flow to LobbyLive
  → push_event("composite_measurement", ...)
  → MidiOutputHook receives sync CC values

User clicks "MIDI Off"
  → this.pushEvent("midi_toggled", { enabled: false })
  → SyncComputer.unregister_viewer()         # viewer_count: 1 → 0
  → SyncComputer deactivates, unsubscribes from all sensor topics
  → Phoenix.PubSub.unsubscribe("sync:updates")
```

## The Synchronization Feedback Loop

The system is designed to create a self-reinforcing cycle:

```
┌──────────────────────────────┐
│       LIVE AUDIENCE          │
│    (wearing sensors)         │
└──────────┬───────────────────┘
           │ biometric data
           ▼
┌──────────────────────────────┐
│        SENSOCTO              │
│  sync computation            │
│  attention tracking          │
│  MIDI output                 │
└──────────┬───────────────────┘
           │ MIDI (5 instruments + clock + drums)
           ▼
┌──────────────────────────────┐
│     DAW / SYNTHESIZER        │
│  breath → pad swells         │
│  heartbeat → bass pulse      │
│  HRV → drone timbre          │
│  arousal → overall volume    │
│  sync → harmonic consonance  │
│  tempo → group heart rate    │
└──────────┬───────────────────┘
           │ sound
           ▼
┌──────────────────────────────┐
│      SPEAKERS / ROOM         │
│  audience HEARS their own    │
│  collective state as music   │
└──────────┬───────────────────┘
           │ rhythmic entrainment
           └───────► back to audience
```

When the group syncs, the music rewards with consonance, groove, and power. When desync, the music fragments. The audience doesn't need to "try" — rhythmic entrainment does the work.

## Future Enhancements

### Phase-to-Harmony Mapping
Map Kuramoto phase offsets between individuals to musical intervals. In-phase → unison. Anti-phase → tritone. Requires exposing per-sensor phase data from `SyncComputer`.

### Per-Person MIDI Channels
Assign each sensor to a unique MIDI channel (up to 16), creating a polyphonic "body orchestra."

### Outlier Detection → Solo Voice
When one person's biometrics diverge from the group, give them a prominent solo voice that dissolves when they re-sync.

### OSC Output
Open Sound Control (UDP) for continuous parameters — avoids MIDI's 7-bit resolution limit. For SuperCollider, Max/MSP, TouchDesigner.

### IMU Gesture → MIDI
Accelerometer/gyroscope data: tilt → pitch, shake → trigger, twist → modulation.

// MidiOutputHook — bridges biometric sensor data → WebMIDI output.
//
// Two modes:
//   ABSTRACT — Raw sensor CCs. Breath phase LFO, HRV modulation, heartbeat triggers.
//   GROOVY  — Musical engine. Chord progressions, quantized notes, bass, pads, drums.
//
// === Abstract Channel Layout ===
//   Ch 1  Breath    CC2 (phase LFO), CC11 (depth), CC74 (rate)
//   Ch 2  Heart     Note-On per heartbeat (velocity ~ BPM)
//   Ch 3  Mind/HRV  CC1 (group RMSSD)
//   Ch 4  Energy    CC7 (collective arousal envelope)
//   Ch 5  Sync      CC16 (breathing sync), CC17 (HRV sync)
//   Ch 10 Drums     Note triggers on sync threshold crossings
//   --    Clock     MIDI Clock (0xF8) from group mean HR (channel-less)
//
// === Groovy Channel Layout ===
//   Ch 1  Bass      Low root notes, driven by heartbeat
//   Ch 2  Pad       Sustained chord tones, driven by breathing
//   Ch 3  Lead      Melodic hits, driven by HRV/arousal
//   Ch 4  Arp       Arpeggiated chord tones, driven by sync level
//   Ch 10 Drums     Kick, snare, hi-hat pattern, tempo from group HR

import { AudioOutputRouter } from '../audio_output_router.js';
import { VOICE_INSTRUMENTS } from '../tone_output.js';
import { MagentaEngine } from '../magenta_engine.js';

// ─── Abstract mode constants ────────────────────────────────────────────────
const CH = {
  breath: 0, heart: 1, mind: 2, energy: 3, sync: 4, drums: 9,
};
const CC = {
  breath_phase: 2, breath_depth: 11, breath_rate: 74,
  hrv: 1, arousal: 7, breathing_sync: 16, hrv_sync: 17,
};
const SYNC_THRESHOLDS = [
  { level: 30, note: 42, name: 'emerging' },
  { level: 50, note: 38, name: 'locking' },
  { level: 70, note: 36, name: 'coherent' },
  { level: 90, note: 49, name: 'deep_sync' },
];

// ─── Groovy mode constants ──────────────────────────────────────────────────
const GROOVY_CH = {
  bass: 0, pad: 1, lead: 2, arp: 3, drums: 9,
};

// GM drum map (extended with Latin percussion)
const DRUM = {
  kick: 36, snare: 38, closedHat: 42, openHat: 46, clap: 39, rimshot: 37, shaker: 70,
  conga: 63, bongo: 62, timbale: 65, claves: 75, cowbell: 56,
};

// ─── Genre configs ────────────────────────────────────────────────────────────
// Each genre: chords, drum patterns, play behaviors, display metadata.
// The GroovyEngine reads from the active genre config.

const GENRE_JAZZ = {
  id: 'jazz',
  label: '🎶 Groovy',
  btnClass: ['bg-pink-600', 'text-white'],
  swing: 0.33,
  bpmFromHr: (hr) => clamp(Math.round(hr / 2) + 30, 60, 110),
  chordBars: 2,
  bassMode: 'walking',
  padMode: 'sustain',
  chords: [
    { name: 'Cm9',   root: 48, tones: [60, 63, 67, 70, 74], arp: [60, 63, 67, 70, 74, 77] },
    { name: 'Fm9',   root: 53, tones: [60, 65, 68, 72, 75], arp: [65, 68, 72, 75, 77, 80] },
    { name: 'Abmaj7',root: 56, tones: [60, 63, 68, 72, 75], arp: [56, 60, 63, 68, 72, 75] },
    { name: 'G7#9',  root: 55, tones: [59, 62, 66, 70, 74], arp: [55, 59, 62, 66, 70, 74] },
    { name: 'Ebmaj9',root: 51, tones: [58, 63, 67, 70, 74], arp: [51, 58, 63, 67, 70, 74] },
    { name: 'Dm7b5', root: 50, tones: [57, 62, 65, 69, 72], arp: [50, 57, 62, 65, 69, 72] },
    { name: 'G7alt', root: 43, tones: [59, 63, 66, 70, 73], arp: [55, 59, 63, 66, 70, 73] },
    { name: 'Cm9',   root: 48, tones: [60, 63, 67, 70, 74], arp: [60, 63, 67, 70, 74, 77] },
  ],
  drumPatterns: {
    kick:      [110,0,0,0, 0,0,85,0, 110,0,0,55, 0,0,85,0],
    snare:     [0,0,0,0, 110,0,0,0, 0,0,0,0, 110,0,0,40],
    closedHat: [80,50,70,50, 80,50,70,50, 80,50,70,50, 80,50,70,50],
    openHat:   [0,0,0,0, 0,0,0,70, 0,0,0,0, 0,0,0,70],
    shaker:    [40,25,35,25, 40,25,35,25, 40,25,35,25, 40,25,35,25],
  },
  drumVoices: [
    { key: 'kick',      minActivity: 0.05, durMs: 50 },
    { key: 'snare',     minActivity: 0.2,  durMs: 50 },
    { key: 'closedHat', minActivity: 0.1,  durMs: 30 },
    { key: 'openHat',   minActivity: 0.35, durMs: 80 },
    { key: 'shaker',    minActivity: 0.4,  durMs: 25, minEnergy: 0.4 },
  ],
};

const GENRE_PERCUSSION = {
  id: 'percussion',
  label: '🥁 Percussion',
  btnClass: ['bg-orange-600', 'text-white'],
  swing: 0.0,
  bpmFromHr: (hr) => clamp(Math.round(hr * 0.8 + 10), 80, 130),
  chordBars: 4,
  bassMode: 'groove',
  padMode: 'block',
  chords: [
    { name: 'Cm7', root: 48, tones: [60, 63, 67, 70], arp: [60, 63, 67, 70, 72, 75] },
    { name: 'Fm7', root: 53, tones: [60, 65, 68, 72], arp: [65, 68, 72, 75, 77, 80] },
    { name: 'Cm7', root: 48, tones: [60, 63, 67, 70], arp: [60, 63, 67, 70, 72, 75] },
    { name: 'Gm7', root: 55, tones: [62, 65, 67, 71], arp: [55, 62, 65, 67, 71, 74] },
  ],
  drumPatterns: {
    kick:      [100,0,0,0, 0,0,0,0, 85,0,0,0, 0,0,0,0],
    snare:     [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
    closedHat: [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
    openHat:   [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
    claves:    [100,0,0,95, 0,0,90,0, 0,0,95,0, 90,0,0,0],
    conga:     [0,0,80,0, 0,90,0,0, 80,0,0,85, 0,70,0,90],
    bongo:     [95,0,70,0, 0,85,0,70, 95,0,70,0, 0,85,0,70],
    rimshot:   [0,0,0,0, 80,0,0,0, 0,0,0,0, 80,0,0,0],
    shaker:    [60,45,55,45, 60,45,55,45, 60,45,55,45, 60,45,55,45],
    cowbell:   [90,0,0,0, 0,0,0,0, 85,0,0,0, 0,0,0,0],
  },
  drumVoices: [
    { key: 'kick',    minActivity: 0.05, durMs: 60 },
    { key: 'claves',  minActivity: 0.1,  durMs: 30, note: 75 },
    { key: 'conga',   minActivity: 0.1,  durMs: 40, note: 63 },
    { key: 'bongo',   minActivity: 0.2,  durMs: 40, note: 62 },
    { key: 'rimshot', minActivity: 0.25, durMs: 35 },
    { key: 'shaker',  minActivity: 0.15, durMs: 25, note: 70 },
    { key: 'cowbell', minActivity: 0.3,  durMs: 45, note: 56 },
  ],
};

const GENRE_REGGAE = {
  id: 'reggae',
  label: '🌿 Reggae',
  btnClass: ['bg-green-600', 'text-white'],
  swing: 0.0,
  bpmFromHr: (hr) => clamp(Math.round(hr * 0.5 + 25), 65, 90),
  chordBars: 4,
  bassMode: 'one_drop',
  padMode: 'skank',
  chords: [
    { name: 'Dm7',    root: 50, tones: [62, 65, 69, 72], arp: [50, 62, 65, 69, 72, 74] },
    { name: 'Gm7',    root: 55, tones: [62, 65, 67, 70], arp: [55, 62, 65, 67, 70, 74] },
    { name: 'Bbmaj7', root: 58, tones: [62, 65, 67, 70], arp: [58, 62, 65, 67, 70, 74] },
    { name: 'A7',     root: 57, tones: [61, 64, 67, 69], arp: [57, 61, 64, 67, 69, 72] },
    { name: 'Dm7',    root: 50, tones: [62, 65, 69, 72], arp: [50, 62, 65, 69, 72, 74] },
    { name: 'Gm7',    root: 55, tones: [62, 65, 67, 70], arp: [55, 62, 65, 67, 70, 74] },
    { name: 'C7',     root: 48, tones: [60, 64, 67, 70], arp: [48, 60, 64, 67, 70, 72] },
    { name: 'A7',     root: 57, tones: [61, 64, 67, 69], arp: [57, 61, 64, 67, 69, 72] },
  ],
  drumPatterns: {
    kick:      [0,0,0,0, 0,0,0,0, 110,0,0,0, 55,0,0,0],
    snare:     [0,0,0,0, 0,0,0,0, 110,0,0,0, 0,0,0,50],
    closedHat: [70,0,0,0, 70,0,0,0, 70,0,0,0, 70,0,0,0],
    openHat:   [0,0,60,0, 0,0,60,0, 0,0,60,0, 0,0,60,0],
    rimshot:   [0,50,0,50, 0,50,0,50, 0,50,0,50, 0,50,0,50],
    shaker:    [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
  },
  drumVoices: [
    { key: 'kick',      minActivity: 0.05, durMs: 60 },
    { key: 'snare',     minActivity: 0.15, durMs: 70 },
    { key: 'closedHat', minActivity: 0.1,  durMs: 35 },
    { key: 'openHat',   minActivity: 0.2,  durMs: 100 },
    { key: 'rimshot',   minActivity: 0.3,  durMs: 40 },
  ],
};

const GENRE_DEEPHOUSE = {
  id: 'deephouse',
  label: '🏠 Deep House',
  btnClass: ['bg-violet-600', 'text-white'],
  swing: 0.0,
  bpmFromHr: (hr) => clamp(Math.round(hr * 0.6 + 50), 118, 128),
  chordBars: 4,
  bassMode: 'pulse',
  padMode: 'filter_swell',
  chords: [
    { name: 'Am7',   root: 45, tones: [57, 60, 64, 67], arp: [57, 60, 64, 67, 69, 72] },
    { name: 'Fmaj7', root: 41, tones: [53, 57, 60, 64], arp: [53, 57, 60, 64, 65, 69] },
    { name: 'Dm9',   root: 38, tones: [50, 53, 57, 62, 64], arp: [50, 53, 57, 62, 64, 69] },
    { name: 'Em7',   root: 40, tones: [52, 55, 59, 62], arp: [52, 55, 59, 62, 64, 67] },
    { name: 'Am7',   root: 45, tones: [57, 60, 64, 67], arp: [57, 60, 64, 67, 69, 72] },
    { name: 'Fmaj7', root: 41, tones: [53, 57, 60, 64], arp: [53, 57, 60, 64, 65, 69] },
    { name: 'G7',    root: 43, tones: [55, 59, 62, 65], arp: [55, 59, 62, 65, 67, 71] },
    { name: 'Em7',   root: 40, tones: [52, 55, 59, 62], arp: [52, 55, 59, 62, 64, 67] },
  ],
  drumPatterns: {
    kick:      [110,0,0,0, 110,0,0,0, 110,0,0,0, 110,0,0,0],
    snare:     [0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0],
    closedHat: [0,0,70,0, 0,0,70,0, 0,0,70,0, 0,0,70,0],
    openHat:   [0,0,0,0, 0,0,0,60, 0,0,0,0, 0,0,0,60],
    clap:      [0,0,0,0, 100,0,0,0, 0,0,0,0, 100,0,0,0],
    shaker:    [50,30,45,30, 50,30,45,30, 50,30,45,30, 50,30,45,30],
    rimshot:   [0,0,0,0, 0,0,0,0, 0,0,0,40, 0,0,0,0],
  },
  drumVoices: [
    { key: 'kick',      minActivity: 0.02, durMs: 60 },
    { key: 'clap',      minActivity: 0.1,  durMs: 50 },
    { key: 'closedHat', minActivity: 0.08, durMs: 25 },
    { key: 'openHat',   minActivity: 0.25, durMs: 90 },
    { key: 'shaker',    minActivity: 0.15, durMs: 25, note: 70 },
    { key: 'rimshot',   minActivity: 0.4,  durMs: 35 },
  ],
};

const GENRES = [GENRE_JAZZ, GENRE_PERCUSSION, GENRE_REGGAE, GENRE_DEEPHOUSE];

// ─── Utilities ──────────────────────────────────────────────────────────────
function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)); }
function scale(value, inLo, inHi) {
  return Math.round(clamp((value - inLo) / (inHi - inLo), 0, 1) * 127);
}
function makeSmoother(alpha) {
  let prev = null;
  return (raw) => {
    if (prev === null) { prev = raw; return raw; }
    prev = alpha * raw + (1 - alpha) * prev;
    return Math.round(prev);
  };
}
function extractBpm(payload) {
  if (typeof payload === 'number') return payload;
  if (typeof payload === 'object' && payload !== null) {
    return payload.bpm ?? payload.heartRate ?? payload.heart_rate ?? 0;
  }
  const n = parseFloat(payload);
  return isNaN(n) ? 0 : n;
}
function hashString(str) {
  let h = 0;
  for (let i = 0; i < str.length; i++) h = ((h << 5) - h + str.charCodeAt(i)) | 0;
  return Math.abs(h);
}

// ─── MIDI Clock ─────────────────────────────────────────────────────────────
class MidiClock {
  constructor(midiOutput) {
    this.midi = midiOutput;
    this.bpm = 0;
    this._intervalId = null;
    this._running = false;
  }
  setBpm(bpm) {
    if (bpm < 30 || bpm > 240) return;
    if (Math.abs(bpm - this.bpm) < 0.5) return;
    this.bpm = bpm;
    if (this._running) this._restart();
  }
  start() {
    if (this._running) return;
    if (this.bpm < 30) return;
    this._running = true;
    this.midi.sendStart();
    this._restart();
  }
  stop() {
    if (!this._running) return;
    this._running = false;
    if (this._intervalId) { clearInterval(this._intervalId); this._intervalId = null; }
    this.midi.sendStop();
  }
  _restart() {
    if (this._intervalId) clearInterval(this._intervalId);
    const intervalMs = (60000 / this.bpm) / 24;
    this._intervalId = setInterval(() => this.midi.sendClock(), intervalMs);
  }
  dispose() { this.stop(); }
}

// ─── Sync Threshold Detector ────────────────────────────────────────────────
class SyncThresholdDetector {
  constructor(midiOutput, thresholds, channel) {
    this.midi = midiOutput;
    this.thresholds = thresholds;
    this.channel = channel;
    this.currentLevel = -1;
    this.activeNotes = new Set();
    this.onThresholdCross = null;
  }
  update(syncValue) {
    let newLevel = -1;
    for (let i = this.thresholds.length - 1; i >= 0; i--) {
      if (syncValue >= this.thresholds[i].level) { newLevel = i; break; }
    }
    if (newLevel === this.currentLevel) return;
    if (newLevel > this.currentLevel) {
      for (let i = this.currentLevel + 1; i <= newLevel; i++) {
        const t = this.thresholds[i];
        const velocity = 80 + Math.round((syncValue / 100) * 47);
        this.midi.sendNoteOn(this.channel, t.note, velocity);
        this.activeNotes.add(t.note);
        if (this.onThresholdCross) this.onThresholdCross(t.name, 'up');
      }
    } else {
      for (let i = this.currentLevel; i > newLevel; i--) {
        const t = this.thresholds[i];
        this.midi.sendNoteOff(this.channel, t.note, 0);
        this.activeNotes.delete(t.note);
        if (this.onThresholdCross) this.onThresholdCross(t.name, 'down');
      }
    }
    this.currentLevel = newLevel;
  }
  reset() {
    for (const note of this.activeNotes) this.midi.sendNoteOff(this.channel, note, 0);
    this.activeNotes.clear();
    this.currentLevel = -1;
  }
}

// ─── Breath Phase Tracker ───────────────────────────────────────────────────
class BreathPhaseTracker {
  constructor() {
    this._values = [];
    this._maxWindow = 60;
    this._rateSmooth = makeSmoother(0.15);
    this.breathsPerMin = 0;
  }
  addSample(value, timestamp) {
    this._values.push({ value, time: timestamp });
    if (this._values.length > this._maxWindow) this._values.shift();
  }
  getPhaseCC() {
    if (this._values.length < 3) return 64;
    const vals = this._values;
    let min = Infinity, max = -Infinity;
    for (const v of vals) { if (v.value < min) min = v.value; if (v.value > max) max = v.value; }
    const range = max - min;
    if (range < 1) return 64;
    const latest = vals[vals.length - 1].value;
    return Math.round(clamp(((latest - min) / range) * 127, 0, 127));
  }
  getBreathRate() {
    if (this._values.length < 10) return 0;
    const vals = this._values;
    const mean = vals.reduce((s, v) => s + v.value, 0) / vals.length;
    let crossings = 0;
    for (let i = 1; i < vals.length; i++) {
      if ((vals[i].value > mean) !== (vals[i - 1].value > mean)) crossings++;
    }
    const spanMs = vals[vals.length - 1].time - vals[0].time;
    if (spanMs < 2000) return 0;
    const rawRate = (crossings / 2) / (spanMs / 60000);
    this.breathsPerMin = this._rateSmooth(clamp(rawRate, 4, 40));
    return this.breathsPerMin;
  }
}

// ─── Groovy Engine ──────────────────────────────────────────────────────────
// Turns biometric data into a musical jam with chord progressions, quantized
// notes, walking bass, pad sustains, melodic leads, arpeggios, and drums.
class GroovyEngine {
  constructor(midiOutput, genreConfig = GENRE_JAZZ) {
    this.midi = midiOutput;
    this.genre = genreConfig;
    this.bpm = 90;
    this.chordIndex = 0;
    this.step = 0;        // 0-15 (16th note position in the bar)
    this.bar = 0;
    this._stepTimeout = null;
    this._running = false;
    this._activeNotes = new Map(); // channel → Set of active notes
    this._swingAmount = genreConfig.swing;

    // Sensor-driven parameters (0-1 range)
    this.energy = 0.5;     // drives velocity, density
    this.breathPhase = 0.5;// modulates pad filter / expression
    this.syncLevel = 0;    // drives arp density & drum fills
    this.heartActivity = 0;// triggers bass accents

    // Sensor → stable note index mapping
    this._sensorSlots = new Map();
    this._nextSlot = 0;

    // Pending notes from sensor events (queued for next quantized step)
    this._pendingLeads = [];
    this._pendingBass = false;

    // EMA smoothers
    this._energySmooth = makeSmoother(0.12);
    this._breathSmooth = makeSmoother(0.25);
    this._syncSmooth = makeSmoother(0.3);

    // Activity tracking — how alive is the sensor data?
    this._lastFeedTime = 0;          // timestamp of last sensor event
    this._activeSensors = new Set();  // sensors seen in the last window
    this._sensorLastSeen = new Map(); // sensorId → timestamp
    this.activity = 0;                // 0-1, decays when no data flows
    this._activityDecayRate = 0.02;   // per step decay (reaches ~0 in ~50 steps / ~3 bars)

    // Step timing diagnostics
    this._lastStepTime = 0;
    this._gapCount = 0;      // steps where gap > 2x expected
    this._totalSteps = 0;
    this._maxGapMs = 0;
  }

  setGenre(config) {
    this.genre = config;
    this._swingAmount = config.swing;
    this.chordIndex = 0;
    this.bar = 0;
  }

  get chord() { return this.genre.chords[this.chordIndex % this.genre.chords.length]; }

  start() {
    if (this._running) return;
    this._running = true;
    this._startStepClock();
  }

  stop() {
    if (!this._running) return;
    this._running = false;
    if (this._stepTimeout) { clearTimeout(this._stepTimeout); this._stepTimeout = null; }
    this._allNotesOff();
  }

  setBpm(bpm) {
    bpm = clamp(bpm, 60, 180);
    // Just update the value — the self-scheduling loop reads it each step.
    // No timer restart needed, so no timing gaps.
    this.bpm = bpm;
  }

  // ─── Activity tracking ────────────────────────────────────────────
  _pulse(sensorId) {
    const now = performance.now();
    this._lastFeedTime = now;
    if (sensorId) {
      this._activeSensors.add(sensorId);
      this._sensorLastSeen.set(sensorId, now);
    }
    // Boost activity based on how many sensors are feeding
    const sensorCount = this._activeSensors.size;
    // Scale: 1 sensor → 0.2, 5 → 0.6, 10+ → 1.0
    const target = clamp(sensorCount / 10, 0.1, 1.0);
    // Quick rise, slow fall (rise handled here, fall in _decayActivity)
    this.activity = Math.max(this.activity, target);
  }

  _decayActivity() {
    const now = performance.now();
    // Expire sensors not seen in 5 seconds
    for (const [id, lastSeen] of this._sensorLastSeen) {
      if (now - lastSeen > 5000) {
        this._activeSensors.delete(id);
        this._sensorLastSeen.delete(id);
      }
    }
    // Decay activity toward target based on current active sensor count
    const sensorCount = this._activeSensors.size;
    const target = sensorCount > 0 ? clamp(sensorCount / 10, 0.1, 1.0) : 0;
    if (this.activity > target) {
      this.activity = Math.max(target, this.activity - this._activityDecayRate);
    }
    // Also decay sensor parameters toward neutral when data stops
    if (now - this._lastFeedTime > 3000) {
      this.energy = this.energy * 0.98;
      this.heartActivity = this.heartActivity * 0.97;
      this.syncLevel = this.syncLevel * 0.97;
      this.breathPhase = this.breathPhase * 0.99 + 0.5 * 0.01; // drift toward 0.5
    }
  }

  // Feed sensor data in
  feedHeartbeat(bpm, sensorId) {
    this._pulse(sensorId);
    this.heartActivity = clamp((bpm - 50) / 100, 0, 1);
    this._pendingBass = true;
    // HR drives tempo via genre-specific mapping
    this.setBpm(this.genre.bpmFromHr(bpm));
  }

  feedBreathing(phase01) {
    this._pulse();
    this.breathPhase = this._breathSmooth(phase01);
  }

  feedHrv(normalized01) {
    this._pulse();
    // Low HRV = high energy, high HRV = chill
    this.energy = this._energySmooth(1 - normalized01);
  }

  feedSync(sync01) {
    this._pulse();
    this.syncLevel = this._syncSmooth(sync01);
  }

  feedSensorNote(sensorId) {
    this._pulse(sensorId);
    // Queue a lead note for the next quantized step
    if (!this._sensorSlots.has(sensorId)) {
      this._sensorSlots.set(sensorId, this._nextSlot++);
    }
    const slot = this._sensorSlots.get(sensorId);
    this._pendingLeads.push(slot);
    // Cap queue
    if (this._pendingLeads.length > 4) this._pendingLeads.shift();
  }

  // ─── Internal step clock (self-scheduling, no restart needed) ───────
  _startStepClock() {
    if (this._stepTimeout) clearTimeout(this._stepTimeout);
    this._lastStepTime = performance.now();
    this._scheduleNextStep();
  }

  _scheduleNextStep() {
    if (!this._running) return;
    const sixteenthMs = (60000 / this.bpm) / 4;
    this._stepTimeout = setTimeout(() => this._onStep(), sixteenthMs);
  }

  _onStep() {
    if (!this._running) return;

    // Diagnostics: track timing gaps
    const now = performance.now();
    this._totalSteps++;
    if (this._lastStepTime > 0) {
      const expectedMs = (60000 / this.bpm) / 4;
      const actualMs = now - this._lastStepTime;
      if (actualMs > expectedMs * 2) {
        this._gapCount++;
        if (actualMs > this._maxGapMs) this._maxGapMs = actualMs;
      }
    }
    this._lastStepTime = now;

    // Decay activity every step
    this._decayActivity();
    const a = this.activity; // 0-1 activity level

    // If activity is essentially zero, go silent (just keep clock ticking)
    if (a < 0.01) {
      // Release any sustained notes
      if (this._activeNotes.size > 0) this._allNotesOff();
      // Still advance step/bar for chord position
      this.step = (this.step + 1) % 16;
      if (this.step === 0) { this.bar++; if (this.bar % this.genre.chordBars === 0) this.chordIndex = (this.chordIndex + 1) % this.genre.chords.length; }
      for (let i = 0; i < 6; i++) this.midi.sendClock();
      this._scheduleNextStep();
      return;
    }

    const chord = this.chord;

    // ── Drums: thin out as activity drops ──
    // Full kit at a > 0.5, just kick+hat at a < 0.2, nothing below 0.05
    if (a > 0.05) this._playDrums(chord);

    // ── Bass: on beats 1 and 3, or heartbeat — needs activity > 0.15 ──
    if (a > 0.15 && (this.step === 0 || this.step === 8 || this._pendingBass)) {
      this._playBass(chord);
      this._pendingBass = false;
    }

    // ── Pad: behavior depends on genre padMode ──
    if (a > 0.1) {
      this._playPad(chord);
    } else {
      this._releaseChannel(GROOVY_CH.pad);
    }

    // ── Arp: needs activity > 0.3 ──
    if (a > 0.3) this._playArp(chord);

    // ── Lead: play queued sensor notes — needs activity > 0.2 ──
    if (a > 0.2 && this.step % 2 === 0 && this._pendingLeads.length > 0) {
      this._playLead(chord);
    }

    // Advance step
    this.step = (this.step + 1) % 16;
    if (this.step === 0) {
      this.bar++;
      if (this.bar % this.genre.chordBars === 0) {
        this._releaseChannel(GROOVY_CH.pad);
        this.chordIndex = (this.chordIndex + 1) % this.genre.chords.length;
      }
    }

    // Send MIDI clock (24 ppqn = 6 per 16th note, we approximate)
    for (let i = 0; i < 6; i++) this.midi.sendClock();

    // Schedule next step (reads current this.bpm, so BPM changes are seamless)
    this._scheduleNextStep();
  }

  _playDrums(chord) {
    const a = this.activity;
    const actVel = 0.5 + a * 0.5;
    const vel = (v) => v > 0 ? clamp(Math.round(v * (0.7 + this.energy * 0.3) * actVel), 20, 127) : 0;

    for (const voice of this.genre.drumVoices) {
      if (a < voice.minActivity) continue;
      if (voice.minEnergy && this.energy < voice.minEnergy) continue;
      const pattern = this.genre.drumPatterns[voice.key];
      if (!pattern) continue;
      const v = vel(pattern[this.step]);
      if (v > 0) {
        const note = voice.note || DRUM[voice.key];
        this._noteOnOff(GROOVY_CH.drums, note, v, voice.durMs);
      }
    }

    // Ghost snares at high energy + activity
    if (this.energy > 0.7 && a > 0.5 && this.step % 4 === 3 && Math.random() < 0.3) {
      this._noteOnOff(GROOVY_CH.drums, DRUM.rimshot, Math.round(40 + Math.random() * 30), 40);
    }

    // Sync-driven fills
    if (this.syncLevel > 0.5 && a > 0.5 && this.step === 15) {
      this._noteOnOff(GROOVY_CH.drums, DRUM.snare, 90, 40);
      if (this.syncLevel > 0.7) {
        this._noteOnOff(GROOVY_CH.drums, DRUM.clap, 80, 40);
      }
    }
  }

  _playBass(chord) {
    this._releaseChannel(GROOVY_CH.bass);
    const actScale = 0.5 + this.activity * 0.5;
    const velocity = clamp(Math.round((90 + this.heartActivity * 37) * actScale), 60, 127);
    const chords = this.genre.chords;
    const nextChord = chords[(this.chordIndex + 1) % chords.length];
    let note = chord.root;
    let durFraction = 0.8;

    switch (this.genre.bassMode) {
      case 'walking':
        if (this.step === 8) note = chord.root + 7;
        else if (this.step === 12) note = nextChord.root + (Math.random() < 0.5 ? 1 : -1);
        break;
      case 'one_drop':
        // Reggae: root on beat 1, chromatic approach note before beat 3
        if (this.step !== 0 && this.step !== 6) return;
        if (this.step === 6) note = chord.root + (Math.random() < 0.5 ? 1 : -1);
        durFraction = 0.9;
        break;
      case 'groove':
        // Latin: root on 1, octave on the "and" of 2, 5th on 3
        if (this.step === 0) note = chord.root;
        else if (this.step === 6) note = chord.root + 12;
        else if (this.step === 8) note = chord.root + 7;
        else return;
        break;
      case 'pulse':
        // Deep house: steady eighth-note root pulse, octave on beat 3
        if (this.step % 2 !== 0) return;
        if (this.step === 8) note = chord.root + 12;
        else if (this.step === 12) note = chord.root + 7;
        durFraction = 0.6;
        break;
    }

    this.midi.sendNoteOn(GROOVY_CH.bass, note, velocity);
    this._trackNote(GROOVY_CH.bass, note);

    const dur = (60000 / this.bpm) / 2;
    setTimeout(() => {
      if (this.midi) this.midi.sendNoteOff(GROOVY_CH.bass, note, 0);
    }, dur * durFraction);
  }

  _playPad(chord) {
    const actScale = 0.4 + this.activity * 0.6;
    const velocity = clamp(Math.round((60 + this.breathPhase * 55) * actScale), 40, 110);

    switch (this.genre.padMode) {
      case 'sustain':
        // Jazz: lush sustained chord on beat 1 only
        if (this.step !== 0) return;
        this._releaseChannel(GROOVY_CH.pad);
        for (let i = 0; i < Math.min(this.energy > 0.6 ? 4 : 3, chord.tones.length); i++) {
          this.midi.sendNoteOn(GROOVY_CH.pad, chord.tones[i], velocity);
          this._trackNote(GROOVY_CH.pad, chord.tones[i]);
        }
        break;

      case 'skank': {
        // Reggae: offbeat staccato stabs on steps 2, 6, 10, 14
        const skankSteps = [2, 6, 10, 14];
        if (!skankSteps.includes(this.step)) return;
        this._releaseChannel(GROOVY_CH.pad);
        const skankVel = clamp(Math.round(velocity * 0.85), 30, 100);
        for (let i = 0; i < Math.min(3, chord.tones.length); i++) {
          this.midi.sendNoteOn(GROOVY_CH.pad, chord.tones[i], skankVel);
        }
        // Short staccato release
        const dur = (60000 / this.bpm) / 8;
        const tones = chord.tones.slice(0, 3);
        setTimeout(() => {
          if (this.midi) tones.forEach(n => this.midi.sendNoteOff(GROOVY_CH.pad, n, 0));
        }, dur);
        return;
      }

      case 'block':
        // Latin: block chord on beat 1 only
        if (this.step !== 0) return;
        this._releaseChannel(GROOVY_CH.pad);
        for (let i = 0; i < Math.min(4, chord.tones.length); i++) {
          this.midi.sendNoteOn(GROOVY_CH.pad, chord.tones[i], velocity);
          this._trackNote(GROOVY_CH.pad, chord.tones[i]);
        }
        // Release after a beat
        const blockDur = (60000 / this.bpm);
        const blockTones = chord.tones.slice(0, 4);
        setTimeout(() => {
          if (this.midi) blockTones.forEach(n => this.midi.sendNoteOff(GROOVY_CH.pad, n, 0));
        }, blockDur * 0.9);
        return;

      case 'filter_swell':
        // Deep house: sustained chord with breath-driven filter modulation
        if (this.step === 0) {
          this._releaseChannel(GROOVY_CH.pad);
          const swellVel = clamp(Math.round(velocity * 0.85), 40, 100);
          for (let i = 0; i < Math.min(4, chord.tones.length); i++) {
            this.midi.sendNoteOn(GROOVY_CH.pad, chord.tones[i], swellVel);
            this._trackNote(GROOVY_CH.pad, chord.tones[i]);
          }
        }
        // Continuous filter sweep driven by breath phase
        this.midi.sendCC(GROOVY_CH.pad, 74, clamp(Math.round(30 + this.breathPhase * 97), 0, 127));
        this.midi.sendCC(GROOVY_CH.pad, 11, clamp(Math.round(50 + this.energy * 77), 0, 127));
        return;
    }

    // CC modulation (for sustain mode)
    this.midi.sendCC(GROOVY_CH.pad, 74, Math.round(this.breathPhase * 127));
    this.midi.sendCC(GROOVY_CH.pad, 11, Math.round(40 + this.energy * 87));
  }

  _playLead(chord) {
    if (this._pendingLeads.length === 0) return;
    const slot = this._pendingLeads.shift();

    // Pick a note from chord tones based on sensor slot
    const tones = chord.tones;
    const noteIndex = slot % tones.length;
    let note = tones[noteIndex];

    // Octave variation based on energy
    if (this.energy > 0.7 && Math.random() < 0.3) note += 12;
    if (this.energy < 0.3 && Math.random() < 0.3) note -= 12;

    const velocity = clamp(Math.round(75 + this.energy * 45 + Math.random() * 15), 60, 127);
    this.midi.sendNoteOn(GROOVY_CH.lead, note, velocity);

    // Short note — 16th to 8th depending on energy
    const baseDur = (60000 / this.bpm) / 4; // 16th
    const dur = baseDur * (1 + this.energy * 0.8);
    setTimeout(() => {
      if (this.midi) this.midi.sendNoteOff(GROOVY_CH.lead, note, 0);
    }, dur * 0.9);
  }

  _playArp(chord) {
    // Arp density: at low sync, play rarely. At high sync, constant 16ths.
    const playProbability = this.syncLevel * 0.8;
    if (Math.random() > playProbability) return;

    const arpNotes = chord.arp;
    const note = arpNotes[this.step % arpNotes.length];
    const velocity = clamp(Math.round(50 + this.syncLevel * 60 + Math.random() * 20), 40, 115);

    this.midi.sendNoteOn(GROOVY_CH.arp, note, velocity);

    const dur = (60000 / this.bpm) / 4;
    setTimeout(() => {
      if (this.midi) this.midi.sendNoteOff(GROOVY_CH.arp, note, 0);
    }, dur * 0.6); // staccato arps
  }

  _noteOnOff(ch, note, vel, durMs) {
    this.midi.sendNoteOn(ch, note, vel);
    setTimeout(() => {
      if (this.midi) this.midi.sendNoteOff(ch, note, 0);
    }, durMs);
  }

  _trackNote(ch, note) {
    if (!this._activeNotes.has(ch)) this._activeNotes.set(ch, new Set());
    this._activeNotes.get(ch).add(note);
  }

  _releaseChannel(ch) {
    const notes = this._activeNotes.get(ch);
    if (!notes) return;
    for (const n of notes) this.midi.sendNoteOff(ch, n, 0);
    notes.clear();
  }

  _allNotesOff() {
    for (const [ch, notes] of this._activeNotes) {
      for (const n of notes) this.midi.sendNoteOff(ch, n, 0);
      notes.clear();
    }
    // Also send All Notes Off CC on each groovy channel
    for (const ch of Object.values(GROOVY_CH)) {
      this.midi.sendCC(ch, 123, 0); // All Notes Off
    }
  }

  getStats() {
    return {
      genre: this.genre.id,
      totalSteps: this._totalSteps,
      gapCount: this._gapCount,
      maxGapMs: Math.round(this._maxGapMs),
      gapRate: this._totalSteps > 0 ? (this._gapCount / this._totalSteps * 100).toFixed(1) + '%' : '0%',
      bpm: this.bpm,
      chordIndex: this.chordIndex,
      chord: this.chord.name,
      bar: this.bar,
      step: this.step,
      running: this._running,
      activity: Math.round(this.activity * 100) / 100,
      activeSensors: this._activeSensors.size,
      energy: Math.round(this.energy * 100) / 100,
      syncLevel: Math.round(this.syncLevel * 100) / 100,
      heartActivity: Math.round(this.heartActivity * 100) / 100,
    };
  }

  resetStats() {
    this._gapCount = 0;
    this._totalSteps = 0;
    this._maxGapMs = 0;
  }

  dispose() {
    this.stop();
  }
}

// ─── Main hook ──────────────────────────────────────────────────────────────
const MidiOutputHook = {
  mounted() {
    this.midi = new AudioOutputRouter();
    this.clock = new MidiClock(this.midi);
    this.syncDetector = new SyncThresholdDetector(this.midi, SYNC_THRESHOLDS, CH.drums);
    this.breathTracker = new BreathPhaseTracker();
    this.groovy = new GroovyEngine(this.midi);
    this.magenta = new MagentaEngine(this.midi);

    // Mode: 'abstract', 'groovy', or 'magenta'
    this._mode = 'abstract';
    this._genreIndex = 0; // index into GENRES array

    // Muted attributes — meter IDs that are toggled off
    // Maps meter id → attribute_ids that get silenced
    this._mutedAttrs = new Set(); // e.g. {'tempo', 'hrv', 'breath', ...}
    this._attrToMeter = {
      heartrate: 'tempo', hr: 'tempo',
      hrv: 'hrv',
      respiration: 'breath',
      breathing_sync: 'bsync',
      hrv_sync: 'hsync',
    };

    this.smoothers = {
      respiration: makeSmoother(0.3),
      hrv: makeSmoother(0.2),
      breathing_sync: makeSmoother(0.4),
      hrv_sync: makeSmoother(0.4),
      arousal: makeSmoother(0.15),
      breath_rate: makeSmoother(0.2),
    };

    this._hrMap = new Map();
    this._hrCleanupInterval = setInterval(() => {
      const now = Date.now();
      for (const [id, entry] of this._hrMap) {
        if (now - entry.time > 10000) this._hrMap.delete(id);
      }
    }, 5000);

    this._hrvMap = new Map();

    this.syncDetector.onThresholdCross = (name, dir) => this._flashSyncIndicator(name, dir);

    this._meters = {};
    const meterIds = ['hrv', 'breath', 'bsync', 'hsync', 'tempo', 'arousal'];
    for (const id of meterIds) {
      this._meters[id] = {
        bar: this.el.querySelector(`#midi-bar-${id}`),
        val: this.el.querySelector(`#midi-val-${id}`),
      };
    }
    this._metersContainer = this.el.querySelector('#midi-meters');
    this._clockIndicator = this.el.querySelector('#midi-clock-dot');
    this._syncTriggerEl = this.el.querySelector('#midi-sync-trigger');

    this.midi.onDeviceListChange = (devices) => this._updateDeviceSelect(devices);

    this._onMeasurement = (e) => this._handleMeasurement(e);
    window.addEventListener('composite-measurement-event', this._onMeasurement);

    this._restoreState();
    this._setupUI();

    // Expose diagnostics on window for console access
    window.__midiGroovy = {
      stats: () => this.groovy.getStats(),
      resetStats: () => this.groovy.resetStats(),
    };
    window.__audioRouter = { backend: () => this.midi._backend, toneGenre: () => this.midi.tone._genreId };
    window.__magenta = { stats: () => this.magenta.getStats() };
  },

  destroyed() {
    window.removeEventListener('composite-measurement-event', this._onMeasurement);
    if (this._hrCleanupInterval) clearInterval(this._hrCleanupInterval);
    this.syncDetector.reset();
    // Stop engines first so their noteOff messages reach Tone.js
    // synths while they still exist, then dispose everything.
    this.groovy.dispose();
    this.magenta.dispose();
    this.clock.dispose();
    if (this.midi) {
      this.midi.setEnabled(false);
      this.midi.dispose();
    }
    this.midi = null;
  },

  _handleMeasurement(event) {
    if (!this.midi || !this.midi.enabled) return;
    try {
      const { sensor_id, attribute_id, payload, timestamp } = event.detail;

      // Check if this attribute's meter is muted
      const meterId = this._attrToMeter[attribute_id];
      if (meterId && this._mutedAttrs.has(meterId)) return;

      if (this._mode === 'groovy') {
        this._handleGroovyMeasurement(sensor_id, attribute_id, payload, timestamp);
      } else if (this._mode === 'magenta') {
        this._handleMagentaMeasurement(sensor_id, attribute_id, payload, timestamp);
      } else {
        this._handleAbstractMeasurement(sensor_id, attribute_id, payload, timestamp);
      }
    } catch (err) {
      console.warn('[MidiOutputHook] Error:', err.message);
    }
  },

  // ─── Abstract mode handler (original behavior) ─────────────────────
  _handleAbstractMeasurement(sensor_id, attribute_id, payload, timestamp) {
    switch (attribute_id) {
      case 'respiration': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        const depthVal = this.smoothers.respiration(scale(value, 50, 100));
        this.midi.sendCC(CH.breath, CC.breath_depth, depthVal);
        this.breathTracker.addSample(value, timestamp || Date.now());
        const phaseCC = this.breathTracker.getPhaseCC();
        this.midi.sendCC(CH.breath, CC.breath_phase, phaseCC);
        this._updateMeter('breath', phaseCC);
        const rate = this.breathTracker.getBreathRate();
        if (rate > 0) {
          const rateCC = this.smoothers.breath_rate(scale(rate, 8, 24));
          this.midi.sendCC(CH.breath, CC.breath_rate, rateCC);
        }
        break;
      }
      case 'hrv': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this._hrvMap.set(sensor_id, { value, time: Date.now() });
        const meanHrv = this._computeGroupMean(this._hrvMap);
        const hrvVal = this.smoothers.hrv(scale(meanHrv, 5, 80));
        this.midi.sendCC(CH.mind, CC.hrv, hrvVal);
        this._updateMeter('hrv', hrvVal);
        this._updateArousal();
        break;
      }
      case 'heartrate':
      case 'hr': {
        const bpm = extractBpm(payload);
        if (bpm < 30 || bpm > 240) return;
        this._hrMap.set(sensor_id, { value: bpm, time: Date.now() });
        const meanHr = this._computeGroupMean(this._hrMap);
        this.clock.setBpm(meanHr);
        if (!this.clock._running && meanHr >= 30) this.clock.start();
        this._updateMeter('tempo', Math.round(meanHr));
        const velocity = scale(bpm, 50, 140);
        this.midi.sendNoteOn(CH.heart, 60, velocity);
        setTimeout(() => { if (this.midi) this.midi.sendNoteOff(CH.heart, 60, 0); }, 50);
        this._updateArousal();
        break;
      }
      case 'breathing_sync': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        const syncVal = this.smoothers.breathing_sync(scale(value, 0, 100));
        this.midi.sendCC(CH.sync, CC.breathing_sync, syncVal);
        this._updateMeter('bsync', syncVal);
        this.syncDetector.update(value);
        break;
      }
      case 'hrv_sync': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        const syncVal = this.smoothers.hrv_sync(scale(value, 0, 100));
        this.midi.sendCC(CH.sync, CC.hrv_sync, syncVal);
        this._updateMeter('hsync', syncVal);
        break;
      }
    }
  },

  // ─── Groovy mode handler ───────────────────────────────────────────
  _handleGroovyMeasurement(sensor_id, attribute_id, payload, timestamp) {
    switch (attribute_id) {
      case 'respiration': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this.breathTracker.addSample(value, timestamp || Date.now());
        const phase01 = this.breathTracker.getPhaseCC() / 127;
        this.groovy.feedBreathing(phase01);
        this._updateMeter('breath', Math.round(phase01 * 127));
        break;
      }
      case 'hrv': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this._hrvMap.set(sensor_id, { value, time: Date.now() });
        const meanHrv = this._computeGroupMean(this._hrvMap);
        const normalized = clamp((meanHrv - 5) / 75, 0, 1); // 5-80ms → 0-1
        this.groovy.feedHrv(normalized);
        this._updateMeter('hrv', Math.round(normalized * 127));
        break;
      }
      case 'heartrate':
      case 'hr': {
        const bpm = extractBpm(payload);
        if (bpm < 30 || bpm > 240) return;
        this._hrMap.set(sensor_id, { value: bpm, time: Date.now() });
        const meanHr = this._computeGroupMean(this._hrMap);
        this.groovy.feedHeartbeat(meanHr, sensor_id);
        this._updateMeter('tempo', Math.round(meanHr));
        // Also queue a lead note for this sensor
        this.groovy.feedSensorNote(sensor_id);
        break;
      }
      case 'breathing_sync': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this.groovy.feedSync(value / 100);
        this._updateMeter('bsync', Math.round((value / 100) * 127));
        break;
      }
      case 'hrv_sync': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this._updateMeter('hsync', scale(value, 0, 100));
        break;
      }
    }
  },

  // ─── Magenta AI mode handler ─────────────────────────────────────────
  _handleMagentaMeasurement(sensor_id, attribute_id, payload, timestamp) {
    switch (attribute_id) {
      case 'respiration': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this.breathTracker.addSample(value, timestamp || Date.now());
        const phase01 = this.breathTracker.getPhaseCC() / 127;
        this.magenta.feedBreathing(phase01);
        this._updateMeter('breath', Math.round(phase01 * 127));
        break;
      }
      case 'hrv': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this._hrvMap.set(sensor_id, { value, time: Date.now() });
        const meanHrv = this._computeGroupMean(this._hrvMap);
        const normalized = clamp((meanHrv - 5) / 75, 0, 1);
        this.magenta.feedHrv(normalized);
        this._updateMeter('hrv', Math.round(normalized * 127));
        break;
      }
      case 'heartrate':
      case 'hr': {
        const bpm = extractBpm(payload);
        if (bpm < 30 || bpm > 240) return;
        this._hrMap.set(sensor_id, { value: bpm, time: Date.now() });
        const meanHr = this._computeGroupMean(this._hrMap);
        this.magenta.feedHeartbeat(meanHr, sensor_id);
        this._updateMeter('tempo', Math.round(meanHr));
        this.magenta.feedSensorNote(sensor_id);
        break;
      }
      case 'breathing_sync': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this.magenta.feedSync(value / 100);
        this._updateMeter('bsync', Math.round((value / 100) * 127));
        break;
      }
      case 'hrv_sync': {
        const value = typeof payload === 'number' ? payload : parseFloat(payload);
        if (isNaN(value)) return;
        this._updateMeter('hsync', scale(value, 0, 100));
        break;
      }
    }
  },

  _updateArousal() {
    if (this._mutedAttrs.has('arousal')) return;
    const meanHr = this._computeGroupMean(this._hrMap);
    const meanHrv = this._computeGroupMean(this._hrvMap);
    const breathRate = this.breathTracker.breathsPerMin;
    if (meanHr < 30) return;
    const hrComponent = clamp((meanHr - 60) / 80, 0, 1);
    const hrvComponent = clamp((80 - meanHrv) / 75, 0, 1);
    const brComponent = breathRate > 0 ? clamp((breathRate - 8) / 16, 0, 1) : 0.5;
    const rawArousal = (hrComponent * 0.4 + hrvComponent * 0.35 + brComponent * 0.25);
    const arousalCC = this.smoothers.arousal(Math.round(rawArousal * 127));
    this.midi.sendCC(CH.energy, CC.arousal, arousalCC);
    this._updateMeter('arousal', arousalCC);
  },

  _computeGroupMean(map) {
    if (map.size === 0) return 0;
    let sum = 0;
    for (const entry of map.values()) sum += entry.value;
    return sum / map.size;
  },

  _updateMeter(id, value) {
    const m = this._meters[id];
    if (!m) return;
    if (id === 'tempo') {
      if (m.bar) m.bar.style.width = Math.round(clamp((value - 40) / 160, 0, 1) * 100) + '%';
      if (m.val) m.val.textContent = value > 0 ? value : '-';
    } else {
      const pct = Math.round((value / 127) * 100);
      if (m.bar) m.bar.style.width = pct + '%';
      if (m.val) m.val.textContent = value;
    }
  },

  _flashSyncIndicator(name, direction) {
    const el = this._syncTriggerEl;
    if (!el) return;
    el.textContent = direction === 'up' ? `▲ ${name}` : `▼ ${name}`;
    el.classList.remove('opacity-0');
    el.classList.add('opacity-100');
    setTimeout(() => {
      el.classList.remove('opacity-100');
      el.classList.add('opacity-0');
    }, 1500);
  },

  _showMeters(show) {
    if (!this._metersContainer) return;
    if (show) this._metersContainer.classList.remove('hidden');
    else this._metersContainer.classList.add('hidden');
  },

  _setupUI() {
    const toggleBtn = this.el.querySelector('#midi-toggle-btn');
    if (toggleBtn) {
      toggleBtn.addEventListener('click', () => this._handleToggle());
    }

    const deviceSelect = this.el.querySelector('#midi-device-select');
    if (deviceSelect) {
      deviceSelect.addEventListener('change', (e) => {
        this.midi.selectOutput(e.target.value);
        try { localStorage.setItem('sensocto_midi_device', e.target.value); } catch (_) {}
        this._updateStatusText();
      });
    }

    const backendSelect = this.el.querySelector('#midi-backend-select');
    if (backendSelect) {
      backendSelect.addEventListener('change', (e) => {
        const backend = e.target.value;
        this.midi.setBackend(backend);
        const deviceSel = this.el.querySelector('#midi-device-select');
        if (deviceSel) deviceSel.style.display = (backend === 'tone') ? 'none' : '';
        const instPanel = this.el.querySelector('#tone-instruments');
        if (instPanel) instPanel.classList.toggle('hidden', backend === 'midi');
        if (this.midi.enabled && (backend === 'tone' || backend === 'both')) {
          this.midi.tone.requestAccess().then(() => {
            if (this._mode === 'groovy') {
              this.midi.tone.setGenre(GENRES[this._genreIndex].id);
            }
          });
        }
        this._updateToggleUI(this.midi.enabled);
        try { localStorage.setItem('sensocto_audio_backend', backend); } catch (_) {}
      });
    }

    const modeBtn = this.el.querySelector('#midi-mode-btn');
    if (modeBtn) {
      modeBtn.addEventListener('click', () => this._toggleMode());
    }

    // Meter click-to-mute handlers
    const meters = this.el.querySelectorAll('.midi-meter[data-midi-attr]');
    for (const meter of meters) {
      meter.addEventListener('click', () => {
        const attr = meter.dataset.midiAttr;
        if (this._mutedAttrs.has(attr)) {
          this._mutedAttrs.delete(attr);
          meter.style.opacity = '1';
        } else {
          this._mutedAttrs.add(attr);
          meter.style.opacity = '0.3';
        }
        try { localStorage.setItem('sensocto_midi_muted', JSON.stringify([...this._mutedAttrs])); } catch (_) {}
      });
    }

    // Restore muted state
    try {
      const saved = localStorage.getItem('sensocto_midi_muted');
      if (saved) {
        const arr = JSON.parse(saved);
        for (const attr of arr) {
          this._mutedAttrs.add(attr);
          const el = this.el.querySelector(`.midi-meter[data-midi-attr="${attr}"]`);
          if (el) el.style.opacity = '0.3';
        }
      }
    } catch (_) {}

    // Populate and wire Tone.js instrument selectors
    const roles = ['bass', 'pad', 'lead', 'arp'];
    const savedInstruments = {};
    try {
      const s = localStorage.getItem('sensocto_tone_instruments');
      if (s) Object.assign(savedInstruments, JSON.parse(s));
    } catch (_) {}

    for (const role of roles) {
      const sel = this.el.querySelector(`#tone-inst-${role}`);
      if (!sel) continue;
      const instruments = VOICE_INSTRUMENTS[role] || [];
      sel.innerHTML = '';
      for (const inst of instruments) {
        const opt = document.createElement('option');
        opt.value = inst.id;
        opt.textContent = inst.label;
        sel.appendChild(opt);
      }
      // Restore saved instrument
      const savedId = savedInstruments[role];
      if (savedId) {
        sel.value = savedId;
        this.midi.tone.setInstrument(role, savedId);
      }
      sel.addEventListener('change', (e) => {
        this.midi.tone.setInstrument(role, e.target.value);
        try {
          const all = {};
          for (const r of roles) {
            all[r] = this.midi.tone.getInstrument(r);
          }
          localStorage.setItem('sensocto_tone_instruments', JSON.stringify(all));
        } catch (_) {}
      });
    }

    // Show instrument panel if backend is tone/both
    const instPanel = this.el.querySelector('#tone-instruments');
    const currentBackend = this.midi.getBackend ? this.midi.getBackend() : 'midi';
    if (instPanel) instPanel.classList.toggle('hidden', currentBackend === 'midi');

    // ─── AI Settings Modal ────────────────────────────────────────
    this._setupAIModal();
  },

  _setupAIModal() {
    const el = this.el;
    const modal = el.querySelector('#ai-settings-modal');
    const openBtn = el.querySelector('#midi-ai-settings-btn');
    const closeBtn = el.querySelector('#ai-settings-close');
    const applyBtn = el.querySelector('#ai-settings-apply');
    const chordsInput = el.querySelector('#ai-chords-input');
    const keyRoot = el.querySelector('#ai-key-root');
    const keyQuality = el.querySelector('#ai-key-quality');
    const creativitySlider = el.querySelector('#ai-creativity-slider');
    const creativityAuto = el.querySelector('#ai-creativity-auto');
    const creativityLabel = el.querySelector('#ai-creativity-label');

    if (!modal || !openBtn) return;

    // Open/close modal
    openBtn.addEventListener('click', () => {
      this._restoreAISettings();
      modal.classList.remove('hidden');
    });
    if (closeBtn) {
      closeBtn.addEventListener('click', () => modal.classList.add('hidden'));
    }
    // Click backdrop to close
    modal.addEventListener('click', (e) => {
      if (e.target === modal) modal.classList.add('hidden');
    });

    // Chord preset buttons
    const presetBtns = el.querySelectorAll('.ai-preset-btn');
    for (const btn of presetBtns) {
      btn.addEventListener('click', () => {
        if (chordsInput) chordsInput.value = btn.dataset.chords;
        // Highlight active preset
        for (const b of presetBtns) {
          b.style.background = '#2d2845';
          b.style.borderColor = '#3b3556';
        }
        btn.style.background = '#4c1d95';
        btn.style.borderColor = '#7c3aed';
      });
    }

    // Creativity slider ↔ auto checkbox
    if (creativitySlider && creativityAuto && creativityLabel) {
      creativityAuto.addEventListener('change', () => {
        const isAuto = creativityAuto.checked;
        creativitySlider.disabled = isAuto;
        creativitySlider.style.opacity = isAuto ? '0.4' : '1';
        creativityLabel.textContent = isAuto ? '— Auto (from breathing)' : `— ${creativitySlider.value}%`;
      });
      creativitySlider.addEventListener('input', () => {
        creativityLabel.textContent = `— ${creativitySlider.value}%`;
      });
    }

    // Mood buttons
    const moodBtns = el.querySelectorAll('.ai-mood-btn');
    for (const btn of moodBtns) {
      btn.addEventListener('click', () => {
        for (const b of moodBtns) {
          b.style.background = '#2d2845';
          b.style.borderColor = '#3b3556';
        }
        btn.style.background = '#4c1d95';
        btn.style.borderColor = '#7c3aed';
        btn.dataset.selected = 'true';
        // Deselect others
        for (const b of moodBtns) {
          if (b !== btn) delete b.dataset.selected;
        }
      });
    }

    // Apply button
    if (applyBtn) {
      applyBtn.addEventListener('click', () => {
        // Gather settings
        const chords = chordsInput ? chordsInput.value : '';
        const transpose = keyRoot ? parseInt(keyRoot.value, 10) : 0;
        const isAutoTemp = creativityAuto ? creativityAuto.checked : true;
        const tempValue = creativitySlider ? parseInt(creativitySlider.value, 10) : 50;
        let mood = 'auto';
        for (const btn of moodBtns) {
          if (btn.dataset.selected) mood = btn.dataset.mood;
        }

        // Apply to engine
        this.magenta.setKeyTranspose(transpose);
        this.magenta.setChords(chords);
        this.magenta.setTemperatureOverride(isAutoTemp ? null : tempValue);
        this.magenta.setMoodOverride(mood);
        this.magenta.applySettings();

        // Save to localStorage
        try {
          localStorage.setItem('sensocto_ai_settings', JSON.stringify({
            chords, transpose, isAutoTemp, tempValue, mood,
          }));
        } catch (_) {}

        // Close modal
        modal.classList.add('hidden');

        // Update chord display
        const chordEl = this.el.querySelector('#midi-chord-display');
        if (chordEl && chords) {
          chordEl.textContent = chords;
          chordEl.style.display = 'inline';
        }
      });
    }
  },

  _restoreAISettings() {
    try {
      const saved = JSON.parse(localStorage.getItem('sensocto_ai_settings') || '{}');

      const chordsInput = this.el.querySelector('#ai-chords-input');
      const keyRoot = this.el.querySelector('#ai-key-root');
      const creativitySlider = this.el.querySelector('#ai-creativity-slider');
      const creativityAuto = this.el.querySelector('#ai-creativity-auto');
      const creativityLabel = this.el.querySelector('#ai-creativity-label');

      if (chordsInput && saved.chords) chordsInput.value = saved.chords;
      if (keyRoot && saved.transpose !== undefined) keyRoot.value = saved.transpose;
      if (creativityAuto && saved.isAutoTemp !== undefined) {
        creativityAuto.checked = saved.isAutoTemp;
        if (creativitySlider) {
          creativitySlider.disabled = saved.isAutoTemp;
          creativitySlider.style.opacity = saved.isAutoTemp ? '0.4' : '1';
        }
      }
      if (creativitySlider && saved.tempValue !== undefined) {
        creativitySlider.value = saved.tempValue;
      }
      if (creativityLabel) {
        creativityLabel.textContent = (saved.isAutoTemp !== false) ? '— Auto (from breathing)' : `— ${saved.tempValue || 50}%`;
      }

      // Highlight active preset if chords match
      const presetBtns = this.el.querySelectorAll('.ai-preset-btn');
      for (const btn of presetBtns) {
        if (saved.chords && btn.dataset.chords === saved.chords) {
          btn.style.background = '#4c1d95';
          btn.style.borderColor = '#7c3aed';
        } else {
          btn.style.background = '#2d2845';
          btn.style.borderColor = '#3b3556';
        }
      }

      // Highlight active mood
      const moodBtns = this.el.querySelectorAll('.ai-mood-btn');
      for (const btn of moodBtns) {
        if (btn.dataset.mood === (saved.mood || 'auto')) {
          btn.style.background = '#4c1d95';
          btn.style.borderColor = '#7c3aed';
          btn.dataset.selected = 'true';
        } else {
          btn.style.background = '#2d2845';
          btn.style.borderColor = '#3b3556';
          delete btn.dataset.selected;
        }
      }
    } catch (_) {}
  },

  _applyStoredAISettings() {
    try {
      const saved = JSON.parse(localStorage.getItem('sensocto_ai_settings') || '{}');
      if (saved.transpose !== undefined) this.magenta.setKeyTranspose(saved.transpose);
      if (saved.chords) this.magenta.setChords(saved.chords);
      this.magenta.setTemperatureOverride(saved.isAutoTemp !== false ? null : (saved.tempValue || 50));
      this.magenta.setMoodOverride(saved.mood || 'auto');
    } catch (_) {}
  },

  _toggleMode() {
    // Stop current engines
    if (this._mode === 'groovy') {
      this.groovy.stop();
    } else if (this._mode === 'magenta') {
      this.magenta.stop();
    } else {
      this.clock.stop();
      this.syncDetector.reset();
    }

    // Cycle: abstract → jazz → percussion → reggae → deephouse → magenta AI → abstract
    if (this._mode === 'abstract') {
      this._mode = 'groovy';
      this._genreIndex = 0;
    } else if (this._mode === 'groovy') {
      this._genreIndex++;
      if (this._genreIndex >= GENRES.length) {
        this._mode = 'magenta';
        this._genreIndex = 0;
      }
    } else {
      // magenta → abstract
      this._mode = 'abstract';
      this._genreIndex = 0;
    }

    // Apply genre config
    if (this._mode === 'groovy') {
      this.groovy.setGenre(GENRES[this._genreIndex]);
      this.midi.tone.setGenre(GENRES[this._genreIndex].id);
      if (this.midi.enabled) {
        this._initChannelVolumes();
        this.groovy.start();
      }
    } else if (this._mode === 'magenta') {
      if (this.midi.enabled) {
        this._initChannelVolumes();
        this.magenta.start();
      }
    } else if (this.midi.enabled) {
      this._initChannelVolumes();
    }

    this._updateModeUI();
    try {
      localStorage.setItem('sensocto_midi_mode', this._mode);
      localStorage.setItem('sensocto_midi_genre', this._genreIndex);
    } catch (_) {}
  },

  _updateModeUI() {
    const btn = this.el.querySelector('#midi-mode-btn');
    if (!btn) return;
    // Remove all possible genre button classes
    const allBtnClasses = ['bg-gray-600', 'text-gray-400', 'bg-pink-600', 'bg-orange-600', 'bg-green-600', 'bg-violet-600', 'bg-indigo-600', 'text-white'];
    btn.classList.remove(...allBtnClasses);

    if (this._mode === 'groovy') {
      const genre = GENRES[this._genreIndex];
      btn.textContent = genre.label;
      btn.classList.add(...genre.btnClass);
    } else if (this._mode === 'magenta') {
      btn.textContent = '🧠 Local AI';
      btn.classList.add('bg-violet-600', 'text-white');
    } else {
      btn.textContent = '🌊 Abstract';
      btn.classList.add('bg-gray-600', 'text-gray-400');
    }
    const chordEl = this.el.querySelector('#midi-chord-display');
    if (chordEl) {
      chordEl.style.display = (this._mode === 'groovy' || this._mode === 'magenta') ? 'inline' : 'none';
    }
    // Show/hide AI settings gear button
    const aiSettingsBtn = this.el.querySelector('#midi-ai-settings-btn');
    if (aiSettingsBtn) {
      aiSettingsBtn.classList.toggle('hidden', this._mode !== 'magenta');
    }
  },

  _initChannelVolumes() {
    // GarageBand and many DAWs start channels at zero volume.
    // Send full initialization on all channels we use.
    const allChannels = (this._mode === 'groovy' || this._mode === 'magenta')
      ? Object.values(GROOVY_CH)
      : Object.values(CH);
    // Deduplicate (drums ch 9 appears in both layouts)
    const channels = [...new Set(allChannels)];
    for (const ch of channels) {
      // Reset All Controllers (CC 121) — clears stuck notes, pitch bend, mod
      this.midi.sendCC(ch, 121, 0);
      // Channel Volume — LOUD (100/127 gives headroom for expression)
      this.midi.sendCC(ch, 7, 100);
      // Pan center
      this.midi.sendCC(ch, 10, 64);
      // Expression full
      this.midi.sendCC(ch, 11, 127);
      // Mod wheel off
      this.midi.sendCC(ch, 1, 0);
    }
    console.info('[MidiOutputHook] Channel volumes initialized on', channels.length, 'channels');
  },

  _handleToggle() {
    const newEnabled = !this.midi.enabled;

    if (newEnabled) {
      // Request MIDI access on first enable (deferred from page load)
      this.midi.requestAccess().then(() => {
        if (!this.midi) return;
        this.midi.setEnabled(true);
        this._updateToggleUI(true);
        this._showMeters(true);
        this._initChannelVolumes();
        if (this._mode === 'groovy') this.groovy.start();
        else if (this._mode === 'magenta') this.magenta.start();
        this.pushEvent("midi_toggled", { enabled: true });
        try { localStorage.setItem('sensocto_midi_enabled', 'true'); } catch (_) {}
      });
      return;
    }

    // Stop engines BEFORE disabling the router, so their noteOff
    // messages reach the Tone.js synths while they're still active.
    this.groovy.stop();
    this.magenta.stop();
    this.clock.stop();
    this.syncDetector.reset();
    this.midi.setEnabled(false);
    this._updateToggleUI(false);
    this._showMeters(false);

    this.pushEvent("midi_toggled", { enabled: false });
    try { localStorage.setItem('sensocto_midi_enabled', 'false'); } catch (_) {}
  },

  _restoreState() {
    try {
      const enabled = localStorage.getItem('sensocto_midi_enabled') === 'true';
      const deviceId = localStorage.getItem('sensocto_midi_device');
      const mode = localStorage.getItem('sensocto_midi_mode');
      const genreIdx = parseInt(localStorage.getItem('sensocto_midi_genre'), 10);
      const backend = localStorage.getItem('sensocto_audio_backend') || 'midi';

      // Restore audio backend
      if (['midi', 'tone', 'both'].includes(backend)) {
        this.midi.setBackend(backend);
        const backendSelect = this.el.querySelector('#midi-backend-select');
        if (backendSelect) backendSelect.value = backend;
        const deviceSel = this.el.querySelector('#midi-device-select');
        if (deviceSel) deviceSel.style.display = (backend === 'tone') ? 'none' : '';
      }

      if (mode === 'groovy' || mode === 'abstract' || mode === 'magenta') this._mode = mode;
      if (!isNaN(genreIdx) && genreIdx >= 0 && genreIdx < GENRES.length) {
        this._genreIndex = genreIdx;
      }
      if (this._mode === 'groovy') {
        this.groovy.setGenre(GENRES[this._genreIndex]);
        this.midi.tone.setGenre(GENRES[this._genreIndex].id);
      } else if (this._mode === 'magenta') {
        this._applyStoredAISettings();
      }
      this._updateModeUI();

      if (enabled) {
        this.midi.requestAccess().then(() => {
          if (!this.midi) return;
          if (deviceId) this.midi.selectOutput(deviceId);
          this.midi.setEnabled(true);
          this._initChannelVolumes();
          this._updateToggleUI(true);
          this._showMeters(true);
          if (this._mode === 'groovy') this.groovy.start();
          else if (this._mode === 'magenta') this.magenta.start();
          this.pushEvent("midi_toggled", { enabled: true });
        });
      }
    } catch (_) {}
  },

  _updateToggleUI(enabled) {
    const btn = this.el.querySelector('#midi-toggle-btn');
    const dot = this.el.querySelector('#midi-status-dot');
    if (btn) {
      const backend = this.midi.getBackend ? this.midi.getBackend() : 'midi';
      const label = backend === 'midi' ? 'MIDI' : backend === 'tone' ? 'Synth' : 'Audio';
      btn.textContent = enabled ? `${label} On` : `${label} Off`;
      if (enabled) {
        btn.classList.remove('bg-gray-700', 'hover:bg-gray-600', 'text-gray-300');
        btn.classList.add('bg-purple-600', 'hover:bg-purple-500', 'text-white');
      } else {
        btn.classList.remove('bg-purple-600', 'hover:bg-purple-500', 'text-white');
        btn.classList.add('bg-gray-700', 'hover:bg-gray-600', 'text-gray-300');
      }
    }
    if (dot) {
      if (enabled) {
        dot.classList.remove('bg-gray-500');
        dot.classList.add('bg-purple-400', 'animate-pulse');
      } else {
        dot.classList.remove('bg-purple-400', 'animate-pulse');
        dot.classList.add('bg-gray-500');
      }
    }
    this._updateStatusText();
  },

  _updateStatusText() {
    const avail = this.el.querySelector('#midi-availability');
    if (!avail) return;
    if (!this.midi.enabled) avail.textContent = '';
    else if (!this.midi.selectedOutput) avail.textContent = 'No device selected';
    else avail.textContent = '';
  },

  _updateDeviceSelect(devices) {
    const sel = this.el.querySelector('#midi-device-select');
    if (!sel) return;
    const current = sel.value;
    let savedId = null;
    try { savedId = localStorage.getItem('sensocto_midi_device'); } catch (_) {}
    sel.innerHTML = '<option value="">-- Select MIDI output --</option>';
    devices.forEach(({ id, name }) => {
      const opt = document.createElement('option');
      opt.value = id;
      opt.textContent = name;
      if (id === current || (!current && id === savedId)) opt.selected = true;
      sel.appendChild(opt);
    });
    if (!current && savedId && devices.some(d => d.id === savedId)) {
      sel.value = savedId;
      this.midi.selectOutput(savedId);
    }
    const avail = this.el.querySelector('#midi-availability');
    if (avail) avail.textContent = devices.length > 0 ? '' : 'No MIDI outputs detected';
    this._updateStatusText();
  },
};

export default MidiOutputHook;

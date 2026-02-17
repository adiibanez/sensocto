// MidiOutputHook — bridges biometric sensor data → WebMIDI output.
//
// === Channel Layout (one instrument per channel) ===
//   Ch 1  Breath    CC2 (phase LFO), CC11 (depth), CC74 (rate)
//   Ch 2  Heart     Note-On per heartbeat (velocity ~ BPM)
//   Ch 3  Mind/HRV  CC1 (group RMSSD)
//   Ch 4  Energy    CC7 (collective arousal envelope)
//   Ch 5  Sync      CC16 (breathing sync), CC17 (HRV sync)
//   Ch 10 Drums     Note triggers on sync threshold crossings
//   --    Clock     MIDI Clock (0xF8) from group mean HR (channel-less)

import { MidiOutput } from '../midi_output.js';

// 0-indexed MIDI channels → one instrument per channel
const CH = {
  breath: 0,    // Ch 1: Breath instrument (pad/wind)
  heart: 1,     // Ch 2: Heart instrument (bass/kick)
  mind: 2,      // Ch 3: Mind/HRV (texture/drone)
  energy: 3,    // Ch 4: Collective energy (master dynamics)
  sync: 4,      // Ch 5: Synchronization (harmony)
  drums: 9,     // Ch 10: GM percussion (sync triggers)
};

// CC numbers — semantically meaningful per channel
const CC = {
  breath_phase: 2,    // Ch 1: Breath phase LFO (sinusoidal 0-127)
  breath_depth: 11,   // Ch 1: Expression / breath depth
  breath_rate: 74,    // Ch 1: Brightness / breathing tempo
  hrv: 1,             // Ch 3: Mod Wheel / group HRV RMSSD
  arousal: 7,         // Ch 4: Volume / collective arousal
  breathing_sync: 16, // Ch 5: Breathing sync (Kuramoto R)
  hrv_sync: 17,       // Ch 5: HRV sync (Kuramoto R)
};

// Sync threshold levels → drum notes (GM percussion)
const SYNC_THRESHOLDS = [
  { level: 30, note: 42, name: 'emerging' },   // Closed Hi-Hat
  { level: 50, note: 38, name: 'locking' },     // Snare
  { level: 70, note: 36, name: 'coherent' },    // Bass Drum
  { level: 90, note: 49, name: 'deep_sync' },   // Crash Cymbal
];

function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)); }

function scale(value, inLo, inHi) {
  const t = (value - inLo) / (inHi - inLo);
  return Math.round(clamp(t, 0, 1) * 127);
}

function makeSmoother(alpha) {
  let prev = null;
  return (raw) => {
    if (prev === null) { prev = raw; return raw; }
    prev = alpha * raw + (1 - alpha) * prev;
    return Math.round(prev);
  };
}

// Extract BPM from heartrate payload (handles multiple formats)
function extractBpm(payload) {
  if (typeof payload === 'number') return payload;
  if (typeof payload === 'object' && payload !== null) {
    return payload.bpm ?? payload.heartRate ?? payload.heart_rate ?? 0;
  }
  const n = parseFloat(payload);
  return isNaN(n) ? 0 : n;
}

// ---------------------------------------------------------------------------
// MIDI Clock engine — sends 24 PPQN at the given BPM
// ---------------------------------------------------------------------------
class MidiClock {
  constructor(midiOutput) {
    this.midi = midiOutput;
    this.bpm = 0;
    this._intervalId = null;
    this._running = false;
  }

  setBpm(bpm) {
    if (bpm < 30 || bpm > 240) return; // safety bounds
    if (Math.abs(bpm - this.bpm) < 0.5) return; // ignore tiny fluctuations
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
    if (this._intervalId) {
      clearInterval(this._intervalId);
      this._intervalId = null;
    }
    this.midi.sendStop();
  }

  _restart() {
    if (this._intervalId) clearInterval(this._intervalId);
    // 24 PPQN: interval = (60000 / bpm) / 24 ms
    const intervalMs = (60000 / this.bpm) / 24;
    this._intervalId = setInterval(() => {
      this.midi.sendClock();
    }, intervalMs);
  }

  dispose() {
    this.stop();
  }
}

// ---------------------------------------------------------------------------
// Sync threshold detector — fires note events on level crossings
// ---------------------------------------------------------------------------
class SyncThresholdDetector {
  constructor(midiOutput, thresholds, channel) {
    this.midi = midiOutput;
    this.thresholds = thresholds; // sorted ascending
    this.channel = channel;
    this.currentLevel = -1; // index into thresholds, -1 = below all
    this.activeNotes = new Set();
    this.onThresholdCross = null; // callback(name, direction)
  }

  update(syncValue) {
    // Determine which threshold level we're at
    let newLevel = -1;
    for (let i = this.thresholds.length - 1; i >= 0; i--) {
      if (syncValue >= this.thresholds[i].level) {
        newLevel = i;
        break;
      }
    }

    if (newLevel === this.currentLevel) return;

    if (newLevel > this.currentLevel) {
      // Crossed UP — fire note-ons for each newly crossed threshold
      for (let i = this.currentLevel + 1; i <= newLevel; i++) {
        const t = this.thresholds[i];
        const velocity = 80 + Math.round((syncValue / 100) * 47); // 80-127
        this.midi.sendNoteOn(this.channel, t.note, velocity);
        this.activeNotes.add(t.note);
        if (this.onThresholdCross) this.onThresholdCross(t.name, 'up');
      }
    } else {
      // Crossed DOWN — send note-offs for thresholds we dropped below
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
    for (const note of this.activeNotes) {
      this.midi.sendNoteOff(this.channel, note, 0);
    }
    this.activeNotes.clear();
    this.currentLevel = -1;
  }
}

// ---------------------------------------------------------------------------
// Breath phase tracker — extracts sinusoidal phase from breathing waveform
// ---------------------------------------------------------------------------
class BreathPhaseTracker {
  constructor() {
    this._values = []; // rolling window of {value, time}
    this._maxWindow = 60; // samples
    this._lastPhase = 0; // 0-127 (0=exhale trough, 64=peak inhale, 127=back to trough)
    this._rateSmooth = makeSmoother(0.15);
    this.breathsPerMin = 0;
  }

  addSample(value, timestamp) {
    this._values.push({ value, time: timestamp });
    if (this._values.length > this._maxWindow) {
      this._values.shift();
    }
  }

  // Compute a 0-127 CC value representing the current breath phase position
  getPhaseCC() {
    if (this._values.length < 3) return 64;
    const vals = this._values;
    const recent = vals.slice(-10);

    // Find min/max in the window for normalization
    let min = Infinity, max = -Infinity;
    for (const v of vals) {
      if (v.value < min) min = v.value;
      if (v.value > max) max = v.value;
    }
    const range = max - min;
    if (range < 1) return 64; // no breathing movement detected

    // Normalize latest value to 0-127
    const latest = recent[recent.length - 1].value;
    const normalized = ((latest - min) / range) * 127;
    return Math.round(clamp(normalized, 0, 127));
  }

  // Estimate breathing rate from zero-crossing analysis
  getBreathRate() {
    if (this._values.length < 10) return 0;
    const vals = this._values;
    const mean = vals.reduce((s, v) => s + v.value, 0) / vals.length;

    // Count zero crossings (crossings of the mean)
    let crossings = 0;
    for (let i = 1; i < vals.length; i++) {
      if ((vals[i].value > mean) !== (vals[i - 1].value > mean)) {
        crossings++;
      }
    }

    // Time span in minutes
    const spanMs = vals[vals.length - 1].time - vals[0].time;
    if (spanMs < 2000) return 0; // need at least 2s of data

    // Each full breath cycle = 2 zero crossings
    const cycles = crossings / 2;
    const spanMin = spanMs / 60000;
    const rawRate = cycles / spanMin;
    this.breathsPerMin = this._rateSmooth(clamp(rawRate, 4, 40));
    return this.breathsPerMin;
  }
}

// ---------------------------------------------------------------------------
// Main hook
// ---------------------------------------------------------------------------
const MidiOutputHook = {
  mounted() {
    this.midi = new MidiOutput();
    this.clock = new MidiClock(this.midi);
    this.syncDetector = new SyncThresholdDetector(this.midi, SYNC_THRESHOLDS, CH.drums);
    this.breathTracker = new BreathPhaseTracker();

    this.smoothers = {
      respiration: makeSmoother(0.3),
      hrv: makeSmoother(0.2),
      breathing_sync: makeSmoother(0.4),
      hrv_sync: makeSmoother(0.4),
      arousal: makeSmoother(0.15),
      breath_rate: makeSmoother(0.2),
    };

    // Heartrate tracking (per-sensor → group average)
    this._hrMap = new Map(); // sensor_id → latest BPM
    this._hrCleanupInterval = setInterval(() => {
      // Prune sensors not seen in 10s
      const now = Date.now();
      for (const [id, entry] of this._hrMap) {
        if (now - entry.time > 10000) this._hrMap.delete(id);
      }
    }, 5000);

    // Group HRV tracking
    this._hrvMap = new Map(); // sensor_id → latest RMSSD

    // Sync threshold callback for UI
    this.syncDetector.onThresholdCross = (name, dir) => {
      this._flashSyncIndicator(name, dir);
    };

    // Cache meter DOM refs
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
  },

  destroyed() {
    window.removeEventListener('composite-measurement-event', this._onMeasurement);
    if (this._hrCleanupInterval) clearInterval(this._hrCleanupInterval);
    this.syncDetector.reset();
    this.clock.dispose();
    if (this.midi) this.midi.dispose();
    this.midi = null;
  },

  _handleMeasurement(event) {
    if (!this.midi || !this.midi.enabled) return;
    try {
      const { sensor_id, attribute_id, payload, timestamp } = event.detail;

      switch (attribute_id) {
        case 'respiration': {
          const value = typeof payload === 'number' ? payload : parseFloat(payload);
          if (isNaN(value)) return;

          // Individual breath depth → Ch1 CC11
          const depthVal = this.smoothers.respiration(scale(value, 50, 100));
          this.midi.sendCC(CH.breath, CC.breath_depth, depthVal);

          // Feed breath phase tracker
          this.breathTracker.addSample(value, timestamp || Date.now());

          // Group breath phase LFO → Ch1 CC2
          const phaseCC = this.breathTracker.getPhaseCC();
          this.midi.sendCC(CH.breath, CC.breath_phase, phaseCC);
          this._updateMeter('breath', phaseCC);

          // Breathing rate → Ch1 CC74 (brightness/filter)
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

          // Group mean HRV → Ch3 CC1
          const meanHrv = this._computeGroupMean(this._hrvMap);
          const hrvVal = this.smoothers.hrv(scale(meanHrv, 5, 80));
          this.midi.sendCC(CH.mind, CC.hrv, hrvVal);
          this._updateMeter('hrv', hrvVal);

          // Update arousal
          this._updateArousal();
          break;
        }

        case 'heartrate':
        case 'hr': {
          const bpm = extractBpm(payload);
          if (bpm < 30 || bpm > 240) return;
          this._hrMap.set(sensor_id, { value: bpm, time: Date.now() });

          // Group mean HR → MIDI Clock tempo
          const meanHr = this._computeGroupMean(this._hrMap);
          this.clock.setBpm(meanHr);

          // Start clock if not running
          if (!this.clock._running && meanHr >= 30) {
            this.clock.start();
          }

          // Update tempo meter
          this._updateMeter('tempo', Math.round(meanHr));

          // Heartbeat note trigger → Ch2
          // Velocity scales with BPM intensity (60=pp, 120=ff)
          const velocity = scale(bpm, 50, 140);
          this.midi.sendNoteOn(CH.heart, 60, velocity); // Middle C
          // Short note — auto-off after ~50ms
          setTimeout(() => {
            if (this.midi) this.midi.sendNoteOff(CH.heart, 60, 0);
          }, 50);

          // Update arousal
          this._updateArousal();
          break;
        }

        case 'breathing_sync': {
          const value = typeof payload === 'number' ? payload : parseFloat(payload);
          if (isNaN(value)) return;
          const syncVal = this.smoothers.breathing_sync(scale(value, 0, 100));
          this.midi.sendCC(CH.sync, CC.breathing_sync, syncVal);
          this._updateMeter('bsync', syncVal);

          // Feed sync threshold detector
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
    } catch (err) {
      console.warn('[MidiOutputHook] Error:', err.message);
    }
  },

  // Collective arousal = f(HR, HRV, breath rate)
  _updateArousal() {
    const meanHr = this._computeGroupMean(this._hrMap);
    const meanHrv = this._computeGroupMean(this._hrvMap);
    const breathRate = this.breathTracker.breathsPerMin;

    if (meanHr < 30) return; // no HR data yet

    // Arousal increases with HR and breath rate, decreases with HRV
    // Normalized: HR 60-140 → 0-1, HRV inverted 80-5 → 0-1, breath rate 8-24 → 0-1
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
    // For tempo meter, show BPM directly (not percentage)
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
    if (show) {
      this._metersContainer.classList.remove('hidden');
    } else {
      this._metersContainer.classList.add('hidden');
    }
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
  },

  _handleToggle() {
    const newEnabled = !this.midi.enabled;
    this.midi.setEnabled(newEnabled);
    this._updateToggleUI(newEnabled);
    this._showMeters(newEnabled);

    if (!newEnabled) {
      this.clock.stop();
      this.syncDetector.reset();
    }

    this.pushEvent("midi_toggled", { enabled: newEnabled });
    try { localStorage.setItem('sensocto_midi_enabled', newEnabled); } catch (_) {}
  },

  _restoreState() {
    try {
      const enabled = localStorage.getItem('sensocto_midi_enabled') === 'true';
      const deviceId = localStorage.getItem('sensocto_midi_device');

      if (enabled) {
        this.midi._ready.then(() => {
          if (!this.midi) return;
          if (deviceId) this.midi.selectOutput(deviceId);
          this.midi.setEnabled(true);
          this._updateToggleUI(true);
          this._showMeters(true);
          this.pushEvent("midi_toggled", { enabled: true });
        });
      }
    } catch (_) {}
  },

  _updateToggleUI(enabled) {
    const btn = this.el.querySelector('#midi-toggle-btn');
    const dot = this.el.querySelector('#midi-status-dot');

    if (btn) {
      btn.textContent = enabled ? 'MIDI On' : 'MIDI Off';
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
    if (!this.midi.enabled) {
      avail.textContent = '';
    } else if (!this.midi.selectedOutput) {
      avail.textContent = 'No device selected';
    } else {
      avail.textContent = '';
    }
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
    if (avail) {
      avail.textContent = devices.length > 0 ? '' : 'No MIDI outputs detected';
    }

    this._updateStatusText();
  },
};

export default MidiOutputHook;

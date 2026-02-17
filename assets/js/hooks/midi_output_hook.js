// MidiOutputHook — bridges composite-measurement-event → WebMIDI CC output.
//
// CC Mapping:
//   CC  1  Mod Wheel       ← HRV RMSSD (5–80 ms → 0–127)
//   CC  2  Breath Ctrl     ← Respiration (50–100 % → 0–127)
//   CC 16  General Purp. 1 ← Breathing sync (0–100 → 0–127)
//   CC 17  General Purp. 2 ← HRV sync (0–100 → 0–127)

import { MidiOutput } from '../midi_output.js';

const MIDI_CHANNEL = 0;

const CC = {
  hrv: 1,
  respiration: 2,
  breathing_sync: 16,
  hrv_sync: 17,
};

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

const MidiOutputHook = {
  mounted() {
    this.midi = new MidiOutput();
    this.smoothers = {
      respiration: makeSmoother(0.3),
      hrv: makeSmoother(0.2),
      breathing_sync: makeSmoother(0.4),
      hrv_sync: makeSmoother(0.4),
    };

    this.midi.onDeviceListChange = (devices) => this._updateDeviceSelect(devices);

    this._onMeasurement = (e) => this._handleMeasurement(e);
    window.addEventListener('composite-measurement-event', this._onMeasurement);

    this._restoreState();
    this._setupUI();
  },

  destroyed() {
    window.removeEventListener('composite-measurement-event', this._onMeasurement);
    if (this.midi) this.midi.dispose();
    this.midi = null;
  },

  _handleMeasurement(event) {
    if (!this.midi || !this.midi.enabled) return;
    try {
      const { attribute_id, payload } = event.detail;
      const value = typeof payload === 'number' ? payload : parseFloat(payload);
      if (isNaN(value)) return;

      let cc, midiVal;
      switch (attribute_id) {
        case 'respiration':
          midiVal = this.smoothers.respiration(scale(value, 50, 100));
          this.midi.sendCC(MIDI_CHANNEL, CC.respiration, midiVal);
          break;
        case 'hrv':
          midiVal = this.smoothers.hrv(scale(value, 5, 80));
          this.midi.sendCC(MIDI_CHANNEL, CC.hrv, midiVal);
          break;
        case 'breathing_sync':
          midiVal = this.smoothers.breathing_sync(scale(value, 0, 100));
          this.midi.sendCC(MIDI_CHANNEL, CC.breathing_sync, midiVal);
          break;
        case 'hrv_sync':
          midiVal = this.smoothers.hrv_sync(scale(value, 0, 100));
          this.midi.sendCC(MIDI_CHANNEL, CC.hrv_sync, midiVal);
          break;
      }
    } catch (err) {
      console.warn('[MidiOutputHook] Error:', err.message);
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
    const text = this.el.querySelector('#midi-status-text');
    if (!text) return;
    if (!this.midi.enabled) {
      text.textContent = 'Off';
    } else if (this.midi.selectedOutput) {
      text.textContent = this.midi.selectedOutput.name;
    } else {
      text.textContent = 'No device selected';
    }
  },

  _updateDeviceSelect(devices) {
    const sel = this.el.querySelector('#midi-device-select');
    if (!sel) return;
    const current = sel.value;
    sel.innerHTML = '<option value="">-- Select MIDI output --</option>';
    devices.forEach(({ id, name }) => {
      const opt = document.createElement('option');
      opt.value = id;
      opt.textContent = name;
      if (id === current) opt.selected = true;
      sel.appendChild(opt);
    });

    const avail = this.el.querySelector('#midi-availability');
    if (avail) {
      avail.textContent = devices.length > 0 ? '' : 'No MIDI outputs detected';
    }

    this._updateStatusText();
  },
};

export default MidiOutputHook;

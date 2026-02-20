// AudioOutputRouter — dispatches MIDI-level events to active backend(s).
// Implements the same interface as MidiOutput so the hook can use it transparently.

import { MidiOutput } from './midi_output.js';
import { ToneOutput } from './tone_output.js';

export class AudioOutputRouter {
  constructor() {
    this.midi = new MidiOutput();
    this.tone = new ToneOutput();
    this._backend = 'midi'; // 'midi' | 'tone' | 'both'
    this.enabled = false;
    this.onDeviceListChange = null;
    this._destroyed = false;

    this.midi.onDeviceListChange = (devices) => {
      if (this.onDeviceListChange) this.onDeviceListChange(devices);
    };
  }

  get selectedOutput() { return this.midi.selectedOutput; }

  setBackend(backend) {
    if (!['midi', 'tone', 'both'].includes(backend)) return;
    if (backend === this._backend) return;

    // Silence BOTH backends before switching to kill any sustained notes
    this._silenceAll();
    this._backend = backend;
  }

  getBackend() { return this._backend; }

  async requestAccess() {
    const promises = [];
    if (this._backend === 'midi' || this._backend === 'both') {
      promises.push(this.midi.requestAccess());
    }
    if (this._backend === 'tone' || this._backend === 'both') {
      promises.push(this.tone.requestAccess());
    }
    await Promise.all(promises);
  }

  setEnabled(val) {
    this.enabled = !!val;
    if (!val) {
      // Send All Notes Off on every channel before disabling backends,
      // so that sustained Tone.js pad notes get explicit release.
      this._silenceAll();
    }
    this.midi.setEnabled(val);
    this.tone.setEnabled(val);
  }

  // --- Proxy MIDI device methods ---

  getOutputs() { return this.midi.getOutputs(); }
  selectOutput(id) { this.midi.selectOutput(id); }

  // --- Core senders (delegate to active backend(s)) ---

  sendNoteOn(channel, note, velocity) {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendNoteOn(channel, note, velocity);
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendNoteOn(channel, note, velocity);
  }

  sendNoteOff(channel, note, velocity) {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendNoteOff(channel, note, velocity);
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendNoteOff(channel, note, velocity);
  }

  sendCC(channel, cc, value) {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendCC(channel, cc, value);
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendCC(channel, cc, value);
  }

  sendClock() {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendClock();
    // ToneOutput.sendClock() is a no-op but call for consistency
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendClock();
  }

  sendStart() {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendStart();
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendStart();
  }

  sendStop() {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendStop();
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendStop();
  }

  sendPitchBend(channel, value) {
    if (this._backend === 'midi' || this._backend === 'both')
      this.midi.sendPitchBend(channel, value);
    if (this._backend === 'tone' || this._backend === 'both')
      this.tone.sendPitchBend(channel, value);
  }

  _silenceAll() {
    // Send All Notes Off CC (123) on all used channels via both backends
    for (const ch of [0, 1, 2, 3, 9]) {
      this.tone.sendCC(ch, 123, 0);
      this.midi.sendCC(ch, 123, 0);
    }
    // Also explicitly release all active Tone notes
    if (this.tone._initialized) this.tone._allNotesOff();
  }

  dispose() {
    this._destroyed = true;
    this._silenceAll();
    this.midi.dispose();
    this.tone.dispose();
    this.onDeviceListChange = null;
  }
}

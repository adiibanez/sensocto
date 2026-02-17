// Honey-badger WebMIDI output wrapper.
// If WebMIDI is unavailable → silent no-op.
// If device disconnects → auto-clear selectedOutput, keep running.
// sendCC is a pure no-op when !enabled or !selectedOutput.

export class MidiOutput {
  constructor() {
    this.midiAccess = null;
    this.selectedOutput = null;
    this.enabled = false;
    this.onDeviceListChange = null;
    this._destroyed = false;
    this._ready = this._init();
  }

  async _init() {
    if (!navigator.requestMIDIAccess) {
      console.info('[MidiOutput] WebMIDI not supported in this browser.');
      return;
    }
    try {
      this.midiAccess = await navigator.requestMIDIAccess({ sysex: false });
      if (this._destroyed) return;
      this.midiAccess.addEventListener('statechange', (e) => this._onStateChange(e));
      this._notifyDeviceListChange();
      console.info('[MidiOutput] WebMIDI ready.');
    } catch (err) {
      console.warn('[MidiOutput] MIDI access denied:', err.message);
    }
  }

  _onStateChange(event) {
    if (this._destroyed) return;
    const port = event.port;
    if (this.selectedOutput && port.id === this.selectedOutput.id && port.state === 'disconnected') {
      console.warn('[MidiOutput] Selected output disconnected.');
      this.selectedOutput = null;
    }
    this._notifyDeviceListChange();
  }

  _notifyDeviceListChange() {
    if (typeof this.onDeviceListChange !== 'function') return;
    try {
      this.onDeviceListChange(this.getOutputs());
    } catch (_) { /* swallow callback errors */ }
  }

  getOutputs() {
    if (!this.midiAccess) return [];
    const out = [];
    this.midiAccess.outputs.forEach((output) => {
      out.push({ id: output.id, name: output.name });
    });
    return out;
  }

  selectOutput(id) {
    if (!this.midiAccess) return;
    this.selectedOutput = this.midiAccess.outputs.get(id) || null;
  }

  setEnabled(val) {
    this.enabled = !!val;
  }

  sendCC(channel, cc, value) {
    if (!this.enabled || !this.selectedOutput) return;
    try {
      const status = 0xB0 | (channel & 0x0F);
      this.selectedOutput.send([status, cc & 0x7F, value & 0x7F]);
    } catch (_) { /* swallow send errors */ }
  }

  dispose() {
    this._destroyed = true;
    this.selectedOutput = null;
    this.midiAccess = null;
    this.onDeviceListChange = null;
  }
}

// ToneOutput — In-browser audio synthesis via Tone.js.
// Same interface as MidiOutput so the hook can swap transparently.
// Tone.js is lazy-loaded from CDN on first requestAccess().

import { TONE_PATCHES, DRUM_MAP } from './tone_patches.js';

function clamp(x, lo, hi) { return Math.min(hi, Math.max(lo, x)); }

function midiToFreq(note) {
  return 440 * Math.pow(2, (note - 69) / 12);
}

// Available instruments per voice role
export const VOICE_INSTRUMENTS = {
  bass: [
    { id: 'default',  label: 'Default (genre)' },
    { id: 'mono_tri', label: 'Triangle Bass',  type: 'MonoSynth', options: { oscillator: { type: 'fattriangle', count: 2, spread: 6 }, envelope: { attack: 0.015, decay: 0.4, sustain: 0.5, release: 0.3 }, filter: { Q: 2.5, type: 'lowpass', rolloff: -24 }, filterEnvelope: { attack: 0.01, decay: 0.2, sustain: 0.4, release: 0.3, baseFrequency: 150, octaves: 2.2 } } },
    { id: 'mono_saw', label: 'Saw Bass',       type: 'MonoSynth', options: { oscillator: { type: 'fatsawtooth', count: 2, spread: 8 }, envelope: { attack: 0.005, decay: 0.2, sustain: 0.6, release: 0.15 }, filter: { Q: 5, type: 'lowpass', rolloff: -24 }, filterEnvelope: { attack: 0.003, decay: 0.12, sustain: 0.25, release: 0.1, baseFrequency: 60, octaves: 3.5 } } },
    { id: 'mono_sin', label: 'Sub Bass',       type: 'MonoSynth', options: { oscillator: { type: 'sine' }, envelope: { attack: 0.025, decay: 0.5, sustain: 0.75, release: 0.5 }, filter: { Q: 1, type: 'lowpass' }, filterEnvelope: { attack: 0.01, decay: 0.3, sustain: 0.55, release: 0.4, baseFrequency: 80, octaves: 1.5 } } },
    { id: 'fm_bass',  label: 'FM Bass',        type: 'FMSynth',   options: { harmonicity: 1, modulationIndex: 6, oscillator: { type: 'sine' }, envelope: { attack: 0.008, decay: 0.25, sustain: 0.35, release: 0.15 }, modulation: { type: 'square' }, modulationEnvelope: { attack: 0.005, decay: 0.15, sustain: 0.2, release: 0.1 } } },
    { id: 'am_bass',  label: 'AM Bass',        type: 'AMSynth',   options: { harmonicity: 2, oscillator: { type: 'fatsawtooth', count: 2, spread: 5 }, envelope: { attack: 0.008, decay: 0.25, sustain: 0.45, release: 0.18 }, modulation: { type: 'sine' }, modulationEnvelope: { attack: 0.008, decay: 0.18, sustain: 0.35, release: 0.15 } } },
  ],
  pad: [
    { id: 'default',   label: 'Default (genre)' },
    { id: 'fm_pad',    label: 'FM Pad',         type: 'FMSynth',  poly: true, options: { harmonicity: 2, modulationIndex: 2, oscillator: { type: 'sine' }, envelope: { attack: 0.4, decay: 0.6, sustain: 0.85, release: 2.0 }, modulation: { type: 'triangle' }, modulationEnvelope: { attack: 0.6, decay: 0.4, sustain: 0.55, release: 1.5 } } },
    { id: 'am_pad',    label: 'AM Pad',         type: 'AMSynth',  poly: true, options: { harmonicity: 3, oscillator: { type: 'sine' }, envelope: { attack: 0.5, decay: 0.7, sustain: 0.75, release: 2.5 }, modulation: { type: 'sine' }, modulationEnvelope: { attack: 0.4, decay: 0.5, sustain: 0.5, release: 2.0 } } },
    { id: 'saw_pad',   label: 'Saw Pad',        type: 'Synth',    poly: true, options: { oscillator: { type: 'fatsawtooth', count: 3, spread: 20 }, envelope: { attack: 0.6, decay: 0.9, sustain: 0.65, release: 2.5 } } },
    { id: 'square_pad',label: 'Square Pad',     type: 'Synth',    poly: true, options: { oscillator: { type: 'fatsquare', count: 2, spread: 12 }, envelope: { attack: 0.35, decay: 0.6, sustain: 0.7, release: 1.8 } } },
    { id: 'string_pad',label: 'String Pad',     type: 'FMSynth',  poly: true, options: { harmonicity: 1, modulationIndex: 3.5, oscillator: { type: 'fatsawtooth', count: 3, spread: 25 }, envelope: { attack: 1.0, decay: 0.4, sustain: 0.9, release: 3.0 }, modulation: { type: 'triangle' }, modulationEnvelope: { attack: 0.6, decay: 0.6, sustain: 0.8, release: 2.5 } } },
  ],
  lead: [
    { id: 'default',    label: 'Default (genre)' },
    { id: 'saw_lead',   label: 'Saw Lead',      type: 'Synth',    options: { oscillator: { type: 'fatsawtooth', count: 2, spread: 15 }, envelope: { attack: 0.008, decay: 0.28, sustain: 0.25, release: 0.4 } } },
    { id: 'square_lead',label: 'Square Lead',   type: 'Synth',    options: { oscillator: { type: 'fatsquare', count: 2, spread: 10 }, envelope: { attack: 0.005, decay: 0.2, sustain: 0.35, release: 0.3 } } },
    { id: 'fm_lead',    label: 'FM Lead',       type: 'FMSynth',  options: { harmonicity: 3, modulationIndex: 5, oscillator: { type: 'sine' }, envelope: { attack: 0.005, decay: 0.2, sustain: 0.25, release: 0.3 }, modulation: { type: 'sine' }, modulationEnvelope: { attack: 0.008, decay: 0.12, sustain: 0.15, release: 0.2 } } },
    { id: 'am_lead',    label: 'AM Lead',       type: 'AMSynth',  options: { harmonicity: 2, oscillator: { type: 'fatsawtooth', count: 2, spread: 12 }, envelope: { attack: 0.008, decay: 0.2, sustain: 0.25, release: 0.3 }, modulation: { type: 'square' }, modulationEnvelope: { attack: 0.008, decay: 0.1, sustain: 0.15, release: 0.2 } } },
    { id: 'pluck_lead', label: 'Pluck',         type: 'PluckSynth', options: { attackNoise: 1.2, dampening: 4500, resonance: 0.96 } },
  ],
  arp: [
    { id: 'default',   label: 'Default (genre)' },
    { id: 'sine_arp',  label: 'Sine Arp',       type: 'Synth',      options: { oscillator: { type: 'sine' }, envelope: { attack: 0.003, decay: 0.1, sustain: 0.04, release: 0.12 } } },
    { id: 'saw_arp',   label: 'Saw Arp',        type: 'Synth',      options: { oscillator: { type: 'fatsawtooth', count: 2, spread: 18 }, envelope: { attack: 0.003, decay: 0.07, sustain: 0.03, release: 0.08 } } },
    { id: 'fm_arp',    label: 'FM Arp',         type: 'FMSynth',    options: { harmonicity: 2, modulationIndex: 3.5, oscillator: { type: 'sine' }, envelope: { attack: 0.002, decay: 0.08, sustain: 0.04, release: 0.08 }, modulation: { type: 'sine' }, modulationEnvelope: { attack: 0.005, decay: 0.06, sustain: 0.08, release: 0.08 } } },
    { id: 'pluck_arp', label: 'Pluck Arp',      type: 'PluckSynth', options: { attackNoise: 2.5, dampening: 5500, resonance: 0.92 } },
  ],
};

// Map role name to MIDI channel
const ROLE_TO_CH = { bass: 0, pad: 1, lead: 2, arp: 3 };

export class ToneOutput {
  constructor() {
    this.enabled = false;
    this._ready = null;
    this._destroyed = false;
    this._initialized = false;

    // Synth instances per channel
    this._synths = {};    // channel -> Tone synth
    this._gains = {};     // channel -> Tone.Gain
    this._filters = {};   // channel -> Tone.Filter (for CC74)
    this._drums = {};     // drum name -> Tone synth

    // Effects
    this._reverb = null;
    this._delay = null;
    this._chorus = null;
    this._compressor = null;
    this._limiter = null;
    this._masterGain = null;

    // Active notes for noteOff tracking
    this._activeNotes = new Map(); // "ch:note" -> true

    // Current genre
    this._genreId = 'jazz';

    // Per-voice instrument overrides (null = use genre default)
    this._voiceOverrides = { bass: null, pad: null, lead: null, arp: null };

    // Muted channels (channel numbers)
    this._mutedChannels = new Set();

    // Volume level (master)
    this._volume = -6;
  }

  requestAccess() {
    if (this._ready) return this._ready;
    this._ready = this._loadAndInit().catch((err) => {
      // Allow retry on next call — don't cache a rejected promise
      console.error('[ToneOutput] Init failed, will retry on next requestAccess():', err);
      this._ready = null;
      throw err;
    });
    return this._ready;
  }

  async _loadAndInit() {
    if (!window.Tone) {
      await new Promise((resolve, reject) => {
        const existing = document.querySelector('script[src*="tone@"]');
        if (existing) {
          if (window.Tone) { resolve(); return; }
          existing.addEventListener('load', resolve);
          existing.addEventListener('error', reject);
          return;
        }
        const script = document.createElement('script');
        script.src = 'https://cdn.jsdelivr.net/npm/tone@15/build/Tone.min.js';
        script.crossOrigin = 'anonymous';
        script.onload = resolve;
        script.onerror = reject;
        document.head.appendChild(script);
      });
    }

    if (this._destroyed) return;

    // Tone.start() must be called from user gesture context
    await window.Tone.start();
    console.info('[ToneOutput] Tone.js ready, AudioContext started.');

    this._initEffects();
    this._initSynths();
    this._initialized = true;
  }

  _initEffects() {
    const Tone = window.Tone;
    const patch = TONE_PATCHES[this._genreId] || TONE_PATCHES.jazz;
    const fx = patch.effects;

    this._limiter = new Tone.Limiter(-2).toDestination();
    this._compressor = new Tone.Compressor({
      threshold: fx.compThreshold || -18,
      ratio: fx.compRatio || 3,
      attack: fx.compAttack || 0.01,
      release: fx.compRelease || 0.15,
    }).connect(this._limiter);
    this._masterGain = new Tone.Gain(Tone.dbToGain(this._volume)).connect(this._compressor);
    this._reverb = new Tone.Reverb({ decay: fx.reverbDecay, wet: fx.reverbWet }).connect(this._masterGain);
    this._delay = new Tone.FeedbackDelay({
      delayTime: fx.delayTime,
      feedback: fx.delayFeedback,
      wet: fx.delayWet,
    }).connect(this._masterGain);
    this._chorus = new Tone.Chorus({
      frequency: fx.chorusFreq || 0.8,
      depth: fx.chorusDepth || 0.35,
      wet: fx.chorusWet || 0.3,
    }).connect(this._masterGain);
    this._chorus.start();

    // Dry bus also goes to master
    this._dryBus = new Tone.Gain(1).connect(this._masterGain);
    // Wet buses
    this._wetBusReverb = new Tone.Gain(1).connect(this._reverb);
    this._wetBusDelay = new Tone.Gain(1).connect(this._delay);
    this._wetBusChorus = new Tone.Gain(1).connect(this._chorus);
  }

  _initSynths() {
    const Tone = window.Tone;
    const patch = TONE_PATCHES[this._genreId] || TONE_PATCHES.jazz;

    // Channel mapping: 0=bass, 1=pad, 2=lead, 3=arp
    const channelDefs = [
      { ch: 0, role: 'bass' },
      { ch: 1, role: 'pad' },
      { ch: 2, role: 'lead' },
      { ch: 3, role: 'arp' },
    ];

    for (const { ch, role } of channelDefs) {
      const p = patch[role];
      if (!p) continue;

      try {
        // Create gain node for this channel with role-specific routing
        const gain = new Tone.Gain(Tone.dbToGain(p.volume || -10));
        gain.connect(this._dryBus);
        if (role === 'pad') {
          gain.connect(this._wetBusChorus);
          gain.connect(this._wetBusReverb);
        } else if (role === 'lead' || role === 'arp') {
          gain.connect(this._wetBusDelay);
          gain.connect(this._wetBusReverb);
        } else {
          gain.connect(this._wetBusReverb);
        }
        this._gains[ch] = gain;

        // Create filter for CC74 control
        const filter = new Tone.Filter({ frequency: 5000, type: 'lowpass', rolloff: -12 });
        filter.connect(gain);
        this._filters[ch] = filter;

        // Create synth (check for user override first)
        this._synths[ch] = this._createSynth(role, p);
        this._synths[ch].connect(filter);
      } catch (err) {
        console.warn(`[ToneOutput] Failed to init ${role} (ch ${ch}):`, err.message);
      }
    }

    // Drums — channel 9 (create gain BEFORE initDrums so drums can connect to it)
    try {
      const drumGain = new Tone.Gain(Tone.dbToGain(-6));
      drumGain.connect(this._dryBus);
      drumGain.connect(this._wetBusReverb);
      this._gains[9] = drumGain;
      this._initDrums(patch.drums);
    } catch (err) {
      console.warn('[ToneOutput] Failed to init drums:', err.message);
    }

    // Re-apply muted channels after rebuilding gains
    for (const ch of this._mutedChannels) {
      const gain = this._gains[ch];
      if (gain) {
        try { gain.gain.setValueAtTime(0, Tone.now()); } catch (_) {}
      }
    }
  }

  _initDrums(drumPatches) {
    const Tone = window.Tone;
    this._drums = {};

    for (const [name, config] of Object.entries(drumPatches)) {
      try {
        if (config.pitchDecay !== undefined) {
          this._drums[name] = new Tone.MembraneSynth({
            pitchDecay: config.pitchDecay,
            octaves: config.octaves,
            envelope: config.envelope || { attack: 0.005, decay: 0.3, sustain: 0 },
          });
        } else if (config.type === 'white' || config.type === 'pink') {
          this._drums[name] = new Tone.NoiseSynth({
            noise: { type: config.type },
            envelope: { attack: config.attack || 0.001, decay: config.decay || 0.1, sustain: 0 },
          });
        } else if (config.frequency !== undefined) {
          this._drums[name] = new Tone.MetalSynth({
            frequency: config.frequency,
            harmonicity: config.harmonicity,
            modulationIndex: config.modulationIndex,
            resonance: config.resonance,
            octaves: config.octaves,
            envelope: { attack: 0.001, decay: config.decay || 0.1, release: 0.01 },
          });
        }

        if (this._drums[name] && this._gains[9]) {
          this._drums[name].connect(this._gains[9]);
        }
      } catch (err) {
        console.warn(`[ToneOutput] Failed to init drum "${name}":`, err.message);
      }
    }
  }

  _createSynth(role, genrePatch) {
    const Tone = window.Tone;
    const override = this._voiceOverrides[role];

    // If user selected a specific instrument (not 'default'), use that
    if (override && override !== 'default') {
      const instruments = VOICE_INSTRUMENTS[role] || [];
      const inst = instruments.find(i => i.id === override);
      if (inst && inst.type) {
        return this._buildSynth(inst.type, inst.options || {}, inst.poly);
      }
    }

    // Otherwise use genre default
    const p = genrePatch;
    if (p.type === 'PolySynth') {
      const voiceMap = { FMSynth: Tone.FMSynth, AMSynth: Tone.AMSynth, Synth: Tone.Synth };
      const VoiceClass = voiceMap[p.voiceType] || Tone.Synth;
      const synth = new Tone.PolySynth(VoiceClass, { maxPolyphony: p.maxPolyphony || 4 });
      synth.set(p.options || {});
      return synth;
    } else {
      return this._buildSynth(p.type || 'Synth', p.options || {}, false);
    }
  }

  _buildSynth(type, options, poly) {
    const Tone = window.Tone;
    if (poly) {
      const VoiceClass = type === 'FMSynth' ? Tone.FMSynth
        : type === 'AMSynth' ? Tone.AMSynth
        : Tone.Synth;
      const synth = new Tone.PolySynth(VoiceClass, { maxPolyphony: 6 });
      synth.set(options);
      return synth;
    }
    switch (type) {
      case 'MonoSynth':  return new Tone.MonoSynth(options);
      case 'FMSynth':    return new Tone.FMSynth(options);
      case 'AMSynth':    return new Tone.AMSynth(options);
      case 'PluckSynth': return new Tone.PluckSynth(options);
      default:           return new Tone.Synth(options);
    }
  }

  setInstrument(role, instrumentId) {
    if (!ROLE_TO_CH.hasOwnProperty(role)) return;
    this._voiceOverrides[role] = instrumentId || null;
    if (!this._initialized) return;

    const ch = ROLE_TO_CH[role];
    const patch = TONE_PATCHES[this._genreId] || TONE_PATCHES.jazz;

    // Release active notes on this channel
    for (const [key] of this._activeNotes) {
      const [chStr, noteStr] = key.split(':');
      if (parseInt(chStr) === ch) {
        try { this._synths[ch]?.triggerRelease?.(midiToFreq(parseInt(noteStr))); } catch (_) {}
        this._activeNotes.delete(key);
      }
    }
    if (this._synths[ch]?.releaseAll) {
      try { this._synths[ch].releaseAll(); } catch (_) {}
    }

    // Deferred disposal — disconnect now, dispose later to avoid
    // InvalidAccessError from pending noteOff timeouts
    const old = this._synths[ch];
    if (old) {
      try { old.disconnect(); } catch (_) {}
      setTimeout(() => { try { old.dispose(); } catch (_) {} }, 500);
    }

    try {
      this._synths[ch] = this._createSynth(role, patch[role]);
      this._synths[ch].connect(this._filters[ch]);
    } catch (err) {
      console.warn(`[ToneOutput] Failed to create instrument for ${role}:`, err.message);
      delete this._synths[ch];
    }
  }

  getInstrument(role) {
    return this._voiceOverrides[role] || 'default';
  }

  setChannelMute(channel, muted) {
    if (muted) {
      this._mutedChannels.add(channel);
      // Silence the channel immediately
      const gain = this._gains[channel];
      if (gain) {
        try { gain.gain.setValueAtTime(0, window.Tone.now()); } catch (_) {}
      }
      // Release any active notes on this channel
      for (const [key] of this._activeNotes) {
        const [chStr, noteStr] = key.split(':');
        if (parseInt(chStr) === channel) {
          try { this._synths[channel]?.triggerRelease?.(midiToFreq(parseInt(noteStr))); } catch (_) {}
          this._activeNotes.delete(key);
        }
      }
      if (this._synths[channel]?.releaseAll) {
        try { this._synths[channel].releaseAll(); } catch (_) {}
      }
    } else {
      this._mutedChannels.delete(channel);
      // Restore channel gain from patch volume
      const gain = this._gains[channel];
      if (gain) {
        const patch = TONE_PATCHES[this._genreId] || TONE_PATCHES.jazz;
        const roles = { 0: 'bass', 1: 'pad', 2: 'lead', 3: 'arp' };
        const role = roles[channel];
        const vol = role && patch[role] ? patch[role].volume || -10 : -6;
        try { gain.gain.setValueAtTime(window.Tone.dbToGain(vol), window.Tone.now()); } catch (_) {}
      }
    }
  }

  isChannelMuted(channel) {
    return this._mutedChannels.has(channel);
  }

  setGenre(genreId) {
    if (!genreId || genreId === this._genreId) return;
    this._genreId = genreId;
    if (!this._initialized) return;

    // Rebuild synths with new genre patches
    try {
      this._disposeSynths();
      this._initSynths();
    } catch (err) {
      console.error('[ToneOutput] setGenre synth rebuild failed:', err);
    }

    // Update effects
    try {
      const patch = TONE_PATCHES[genreId] || TONE_PATCHES.jazz;
      const fx = patch.effects;
      if (this._reverb) {
        this._reverb.decay = fx.reverbDecay;
        this._reverb.wet.value = fx.reverbWet;
      }
      if (this._delay) {
        this._delay.delayTime.value = fx.delayTime;
        this._delay.feedback.value = fx.delayFeedback;
        this._delay.wet.value = fx.delayWet;
      }
      if (this._chorus) {
        this._chorus.frequency.value = fx.chorusFreq || 0.8;
        this._chorus.depth = fx.chorusDepth || 0.35;
        this._chorus.wet.value = fx.chorusWet || 0.3;
      }
      if (this._compressor) {
        this._compressor.threshold.value = fx.compThreshold || -18;
        this._compressor.ratio.value = fx.compRatio || 3;
        this._compressor.attack.value = fx.compAttack || 0.01;
        this._compressor.release.value = fx.compRelease || 0.15;
      }
    } catch (err) {
      console.error('[ToneOutput] setGenre effects update failed:', err);
    }
  }

  setEnabled(val) {
    this.enabled = !!val;
    if (!val && this._initialized) {
      this._allNotesOff();
      // Immediately mute master gain so long-release envelopes (pads)
      // don't linger audibly after the user toggles off.
      if (this._masterGain) {
        try { this._masterGain.gain.setValueAtTime(0, window.Tone.now()); } catch (_) {}
      }
    } else if (val && this._initialized && this._masterGain) {
      // Restore master gain when re-enabling
      try {
        this._masterGain.gain.setValueAtTime(
          window.Tone.dbToGain(this._volume), window.Tone.now()
        );
      } catch (_) {}
    }
  }

  // --- Core MIDI-compatible senders ---

  sendNoteOn(channel, note, velocity) {
    if (!this.enabled || !this._initialized || this._destroyed) return;
    if (this._mutedChannels.has(channel)) return;
    try {
      const vel = clamp(velocity / 127, 0, 1);

      if (channel === 9) {
        this._triggerDrum(note, vel);
        return;
      }

      const synth = this._synths[channel];
      if (!synth) return;

      const freq = midiToFreq(note);
      const key = `${channel}:${note}`;

      // Release previous note if still active (for mono synths)
      if (this._activeNotes.has(key) && synth.triggerRelease) {
        try { synth.triggerRelease(freq); } catch (_) {}
      }

      const now = window.Tone.now();
      if (synth.triggerAttack) {
        synth.triggerAttack(freq, now, vel);
      }
      this._activeNotes.set(key, true);
    } catch (err) {
      console.warn('[ToneOutput] noteOn error:', err.message);
    }
  }

  sendNoteOff(channel, note, _velocity) {
    if (!this._initialized || this._destroyed) return;
    try {
      if (channel === 9) return; // Drums are fire-and-forget

      const synth = this._synths[channel];
      if (!synth) return;

      const freq = midiToFreq(note);
      const key = `${channel}:${note}`;

      if (synth.triggerRelease) {
        synth.triggerRelease(freq);
      }
      this._activeNotes.delete(key);
    } catch (err) {
      console.warn('[ToneOutput] noteOff error:', err.message);
    }
  }

  sendCC(channel, cc, value) {
    if (!this._initialized || this._destroyed) return;
    // CC 123 (All Notes Off) must always work, even when disabled,
    // to guarantee cleanup on navigation/toggle.
    if (!this.enabled && cc !== 123) return;
    try {
      const normalized = value / 127;

      switch (cc) {
        case 7: { // Volume — skip if channel is muted
          if (this._mutedChannels.has(channel)) break;
          const gain = this._gains[channel];
          if (gain) gain.gain.rampTo(normalized * 0.8, 0.05);
          break;
        }
        case 11: { // Expression — skip if channel is muted
          if (this._mutedChannels.has(channel)) break;
          const gain = this._gains[channel];
          if (gain) gain.gain.rampTo(normalized * 0.8, 0.05);
          break;
        }
        case 74: { // Filter cutoff
          const filter = this._filters[channel];
          if (filter) {
            const freq = 100 + normalized * 9900; // 100Hz - 10000Hz
            filter.frequency.rampTo(freq, 0.05);
          }
          break;
        }
        case 1: { // Mod wheel — subtle filter modulation
          const filter = this._filters[channel];
          if (filter) {
            const freq = 500 + normalized * 4500;
            filter.frequency.rampTo(freq, 0.1);
          }
          break;
        }
        case 123: // All notes off
          this._allNotesOff();
          break;
      }
    } catch (_) {}
  }

  // Clock/transport — no-op (GroovyEngine has its own step clock)
  sendClock() {}
  sendStart() {}
  sendStop() { if (this._initialized && !this._destroyed) this._allNotesOff(); }
  sendPitchBend(_channel, _value) {}

  _triggerDrum(note, velocity) {
    const drumName = DRUM_MAP[note];
    if (!drumName) return;

    const drum = this._drums[drumName];
    if (!drum) return;

    const now = window.Tone.now();
    try {
      if (drum instanceof window.Tone.MembraneSynth) {
        // Membrane drums need a pitch — use the note for pitch variation
        const pitch = midiToFreq(Math.max(note, 30));
        drum.triggerAttackRelease(pitch, '16n', now, velocity);
      } else if (drum instanceof window.Tone.NoiseSynth) {
        drum.triggerAttackRelease('16n', now, velocity);
      } else if (drum instanceof window.Tone.MetalSynth) {
        drum.triggerAttackRelease('32n', now, velocity);
      }
    } catch (_) {}
  }

  _allNotesOff() {
    for (const [key] of this._activeNotes) {
      const [chStr, noteStr] = key.split(':');
      const synth = this._synths[parseInt(chStr)];
      if (synth && synth.triggerRelease) {
        try {
          const freq = midiToFreq(parseInt(noteStr));
          synth.triggerRelease(freq);
        } catch (_) {}
      }
    }
    this._activeNotes.clear();

    // Also release all on poly synths
    for (const synth of Object.values(this._synths)) {
      if (synth && synth.releaseAll) {
        try { synth.releaseAll(); } catch (_) {}
      }
    }
  }

  _disposeSynths() {
    this._allNotesOff();

    // Collect old nodes — disconnect immediately but defer disposal so that
    // pending async noteOff callbacks (from GroovyEngine setTimeout) don't
    // hit disposed Web Audio nodes and throw InvalidAccessError.
    const old = [
      ...Object.values(this._synths),
      ...Object.values(this._drums),
      ...Object.values(this._filters),
      ...Object.values(this._gains),
    ];
    for (const node of old) {
      try { node.disconnect(); } catch (_) {}
    }
    setTimeout(() => {
      for (const node of old) {
        try { node.dispose(); } catch (_) {}
      }
    }, 500);

    this._synths = {};
    this._drums = {};
    this._filters = {};
    this._gains = {};
  }

  dispose() {
    this._destroyed = true;
    this._initialized = false;
    this.enabled = false;
    this._disposeSynths();
    try { this._reverb?.dispose(); } catch (_) {}
    try { this._delay?.dispose(); } catch (_) {}
    try { this._chorus?.dispose(); } catch (_) {}
    try { this._compressor?.dispose(); } catch (_) {}
    try { this._limiter?.dispose(); } catch (_) {}
    try { this._masterGain?.dispose(); } catch (_) {}
    try { this._dryBus?.dispose(); } catch (_) {}
    try { this._wetBusReverb?.dispose(); } catch (_) {}
    try { this._wetBusDelay?.dispose(); } catch (_) {}
    try { this._wetBusChorus?.dispose(); } catch (_) {}

    // Suspend the AudioContext to guarantee silence even if
    // a stray note survived disposal (e.g. pad sustain race).
    try {
      const ctx = window.Tone?.getContext()?.rawContext;
      if (ctx && ctx.state === 'running') ctx.suspend();
    } catch (_) {}
  }
}

// Genre-specific Tone.js synth patch definitions.
// Each genre defines synth parameters for bass, pad, lead, arp, and drum voices,
// plus shared effects settings.
// MIDI note numbers are converted to frequencies by ToneOutput.

// GM drum note → Tone.js drum type mapping
export const DRUM_MAP = {
  36: 'kick',       // Bass Drum
  38: 'snare',      // Snare
  39: 'clap',       // Hand Clap
  37: 'rimshot',    // Side Stick / Rimshot
  42: 'closedHat',  // Closed Hi-Hat
  46: 'openHat',    // Open Hi-Hat
  49: 'crash',      // Crash Cymbal (used by sync threshold)
  56: 'cowbell',    // Cowbell
  62: 'bongo',      // Mute Hi Bongo
  63: 'conga',      // Open Hi Conga
  65: 'timbale',    // High Timbale
  70: 'shaker',     // Maracas / Shaker
  75: 'claves',     // Claves
};

export const TONE_PATCHES = {
  jazz: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'triangle' },
        envelope: { attack: 0.02, decay: 0.4, sustain: 0.5, release: 0.3 },
        filter: { Q: 2, type: 'lowpass', rolloff: -12 },
        filterEnvelope: { attack: 0.01, decay: 0.2, sustain: 0.4, release: 0.3, baseFrequency: 200, octaves: 2 },
      },
      volume: -8,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'FMSynth',
      maxPolyphony: 6,
      options: {
        harmonicity: 2,
        modulationIndex: 1.5,
        oscillator: { type: 'sine' },
        envelope: { attack: 0.3, decay: 0.5, sustain: 0.8, release: 1.5 },
        modulation: { type: 'sine' },
        modulationEnvelope: { attack: 0.5, decay: 0.3, sustain: 0.6, release: 1.0 },
      },
      volume: -14,
    },
    lead: {
      type: 'Synth',
      options: {
        oscillator: { type: 'sawtooth' },
        envelope: { attack: 0.01, decay: 0.3, sustain: 0.3, release: 0.4 },
      },
      volume: -12,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'square' },
        envelope: { attack: 0.005, decay: 0.15, sustain: 0.1, release: 0.2 },
      },
      volume: -16,
    },
    drums: {
      kick:      { pitchDecay: 0.08, octaves: 6, envelope: { attack: 0.005, decay: 0.3, sustain: 0 } },
      snare:     { type: 'white', filterFreq: 3000, attack: 0.001, decay: 0.15 },
      closedHat: { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.05 },
      openHat:   { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.3 },
      clap:      { type: 'white', filterFreq: 2500, attack: 0.001, decay: 0.12 },
      rimshot:   { type: 'pink', filterFreq: 4000, attack: 0.001, decay: 0.06 },
      shaker:    { type: 'white', filterFreq: 8000, attack: 0.001, decay: 0.03 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.03, octaves: 3, envelope: { attack: 0.001, decay: 0.25, sustain: 0 } },
      bongo:     { pitchDecay: 0.02, octaves: 2.5, envelope: { attack: 0.001, decay: 0.15, sustain: 0 } },
      timbale:   { frequency: 600, harmonicity: 3, modulationIndex: 15, resonance: 4000, octaves: 1, decay: 0.12 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: { reverbDecay: 2.5, reverbWet: 0.25, delayTime: '8n', delayFeedback: 0.2, delayWet: 0.15 },
  },

  percussion: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'sawtooth' },
        envelope: { attack: 0.01, decay: 0.3, sustain: 0.4, release: 0.2 },
        filter: { Q: 3, type: 'lowpass', rolloff: -24 },
        filterEnvelope: { attack: 0.01, decay: 0.15, sustain: 0.3, release: 0.2, baseFrequency: 150, octaves: 2.5 },
      },
      volume: -6,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'Synth',
      maxPolyphony: 4,
      options: {
        oscillator: { type: 'triangle' },
        envelope: { attack: 0.1, decay: 0.4, sustain: 0.5, release: 0.8 },
      },
      volume: -16,
    },
    lead: {
      type: 'Synth',
      options: {
        oscillator: { type: 'pulse', width: 0.3 },
        envelope: { attack: 0.005, decay: 0.2, sustain: 0.2, release: 0.3 },
      },
      volume: -14,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'triangle' },
        envelope: { attack: 0.005, decay: 0.1, sustain: 0.05, release: 0.15 },
      },
      volume: -18,
    },
    drums: {
      kick:      { pitchDecay: 0.1, octaves: 7, envelope: { attack: 0.005, decay: 0.35, sustain: 0 } },
      snare:     { type: 'white', filterFreq: 2500, attack: 0.001, decay: 0.12 },
      closedHat: { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.05 },
      openHat:   { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.3 },
      clap:      { type: 'white', filterFreq: 2500, attack: 0.001, decay: 0.12 },
      rimshot:   { type: 'pink', filterFreq: 4000, attack: 0.001, decay: 0.06 },
      shaker:    { type: 'white', filterFreq: 8000, attack: 0.001, decay: 0.03 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.04, octaves: 3.5, envelope: { attack: 0.001, decay: 0.3, sustain: 0 } },
      bongo:     { pitchDecay: 0.03, octaves: 3, envelope: { attack: 0.001, decay: 0.2, sustain: 0 } },
      timbale:   { frequency: 600, harmonicity: 3, modulationIndex: 15, resonance: 4000, octaves: 1, decay: 0.12 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: { reverbDecay: 1.5, reverbWet: 0.15, delayTime: '16n', delayFeedback: 0.1, delayWet: 0.08 },
  },

  reggae: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'sine' },
        envelope: { attack: 0.03, decay: 0.5, sustain: 0.7, release: 0.5 },
        filter: { Q: 1, type: 'lowpass', rolloff: -12 },
        filterEnvelope: { attack: 0.01, decay: 0.3, sustain: 0.5, release: 0.4, baseFrequency: 100, octaves: 1.5 },
      },
      volume: -4,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'Synth',
      maxPolyphony: 4,
      options: {
        oscillator: { type: 'square' },
        envelope: { attack: 0.005, decay: 0.08, sustain: 0.0, release: 0.05 },
      },
      volume: -18,
    },
    lead: {
      type: 'Synth',
      options: {
        oscillator: { type: 'sine' },
        envelope: { attack: 0.02, decay: 0.4, sustain: 0.4, release: 0.5 },
      },
      volume: -14,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'triangle' },
        envelope: { attack: 0.01, decay: 0.12, sustain: 0.1, release: 0.2 },
      },
      volume: -18,
    },
    drums: {
      kick:      { pitchDecay: 0.12, octaves: 8, envelope: { attack: 0.005, decay: 0.4, sustain: 0 } },
      snare:     { type: 'white', filterFreq: 2000, attack: 0.001, decay: 0.2 },
      closedHat: { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.04 },
      openHat:   { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.25 },
      clap:      { type: 'white', filterFreq: 2500, attack: 0.001, decay: 0.12 },
      rimshot:   { type: 'pink', filterFreq: 3500, attack: 0.001, decay: 0.08 },
      shaker:    { type: 'white', filterFreq: 8000, attack: 0.001, decay: 0.03 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.03, octaves: 3, envelope: { attack: 0.001, decay: 0.25, sustain: 0 } },
      bongo:     { pitchDecay: 0.02, octaves: 2.5, envelope: { attack: 0.001, decay: 0.15, sustain: 0 } },
      timbale:   { frequency: 600, harmonicity: 3, modulationIndex: 15, resonance: 4000, octaves: 1, decay: 0.12 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: { reverbDecay: 3.0, reverbWet: 0.2, delayTime: '4n.', delayFeedback: 0.3, delayWet: 0.2 },
  },

  deephouse: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'sawtooth' },
        envelope: { attack: 0.005, decay: 0.2, sustain: 0.6, release: 0.15 },
        filter: { Q: 4, type: 'lowpass', rolloff: -24 },
        filterEnvelope: { attack: 0.005, decay: 0.15, sustain: 0.3, release: 0.1, baseFrequency: 80, octaves: 3 },
      },
      volume: -6,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'FMSynth',
      maxPolyphony: 6,
      options: {
        harmonicity: 1,
        modulationIndex: 2,
        oscillator: { type: 'sawtooth' },
        envelope: { attack: 0.8, decay: 0.6, sustain: 0.7, release: 2.0 },
        modulation: { type: 'sine' },
        modulationEnvelope: { attack: 0.5, decay: 0.5, sustain: 0.5, release: 1.5 },
      },
      volume: -18,
    },
    lead: {
      type: 'Synth',
      options: {
        oscillator: { type: 'pulse', width: 0.4 },
        envelope: { attack: 0.01, decay: 0.25, sustain: 0.2, release: 0.3 },
      },
      volume: -14,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'sawtooth' },
        envelope: { attack: 0.005, decay: 0.08, sustain: 0.05, release: 0.1 },
      },
      volume: -16,
    },
    drums: {
      kick:      { pitchDecay: 0.15, octaves: 8, envelope: { attack: 0.001, decay: 0.5, sustain: 0 } },
      snare:     { type: 'white', filterFreq: 3000, attack: 0.001, decay: 0.15 },
      closedHat: { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 6000, octaves: 1.5, decay: 0.04 },
      openHat:   { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5000, octaves: 1.5, decay: 0.35 },
      clap:      { type: 'white', filterFreq: 2000, attack: 0.005, decay: 0.18 },
      rimshot:   { type: 'pink', filterFreq: 4000, attack: 0.001, decay: 0.06 },
      shaker:    { type: 'white', filterFreq: 10000, attack: 0.001, decay: 0.025 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.03, octaves: 3, envelope: { attack: 0.001, decay: 0.25, sustain: 0 } },
      bongo:     { pitchDecay: 0.02, octaves: 2.5, envelope: { attack: 0.001, decay: 0.15, sustain: 0 } },
      timbale:   { frequency: 600, harmonicity: 3, modulationIndex: 15, resonance: 4000, octaves: 1, decay: 0.12 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: { reverbDecay: 4.0, reverbWet: 0.3, delayTime: '8n.', delayFeedback: 0.25, delayWet: 0.2 },
  },
};

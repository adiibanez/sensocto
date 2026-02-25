// Genre-specific Tone.js synth patch definitions.
// Each genre defines synth parameters for bass, pad, lead, arp, and drum voices,
// plus shared effects settings.
// MIDI note numbers are converted to frequencies by ToneOutput.
//
// Key technique: Tone.js "fat" oscillators (fatsawtooth, fatsquare, fattriangle)
// automatically stack multiple detuned voices for richness without extra code.

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
        oscillator: { type: 'fatsawtooth', count: 2, spread: 8 },
        envelope: { attack: 0.015, decay: 0.35, sustain: 0.45, release: 0.25 },
        filter: { Q: 3, type: 'lowpass', rolloff: -24 },
        filterEnvelope: { attack: 0.008, decay: 0.25, sustain: 0.3, release: 0.2, baseFrequency: 120, octaves: 2.5 },
      },
      volume: -7,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'FMSynth',
      maxPolyphony: 6,
      options: {
        harmonicity: 2,
        modulationIndex: 1.8,
        oscillator: { type: 'sine' },
        envelope: { attack: 0.4, decay: 0.6, sustain: 0.85, release: 2.0 },
        modulation: { type: 'triangle' },
        modulationEnvelope: { attack: 0.6, decay: 0.4, sustain: 0.55, release: 1.5 },
      },
      volume: -13,
    },
    lead: {
      type: 'FMSynth',
      options: {
        harmonicity: 1.5,
        modulationIndex: 3,
        oscillator: { type: 'sine' },
        envelope: { attack: 0.008, decay: 0.35, sustain: 0.25, release: 0.5 },
        modulation: { type: 'triangle' },
        modulationEnvelope: { attack: 0.02, decay: 0.2, sustain: 0.15, release: 0.3 },
      },
      volume: -11,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'fattriangle', count: 2, spread: 12 },
        envelope: { attack: 0.003, decay: 0.12, sustain: 0.08, release: 0.18 },
      },
      volume: -15,
    },
    drums: {
      kick:      { pitchDecay: 0.07, octaves: 6.5, envelope: { attack: 0.003, decay: 0.35, sustain: 0 } },
      snare:     { type: 'white', attack: 0.001, decay: 0.18 },
      closedHat: { frequency: 420, harmonicity: 5.1, modulationIndex: 36, resonance: 6000, octaves: 1.5, decay: 0.045 },
      openHat:   { frequency: 420, harmonicity: 5.1, modulationIndex: 36, resonance: 5500, octaves: 1.5, decay: 0.35 },
      clap:      { type: 'white', attack: 0.001, decay: 0.14 },
      rimshot:   { type: 'pink', attack: 0.001, decay: 0.055 },
      shaker:    { type: 'white', attack: 0.001, decay: 0.028 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.025, octaves: 3.2, envelope: { attack: 0.001, decay: 0.28, sustain: 0 } },
      bongo:     { pitchDecay: 0.018, octaves: 2.8, envelope: { attack: 0.001, decay: 0.16, sustain: 0 } },
      timbale:   { frequency: 620, harmonicity: 3.2, modulationIndex: 16, resonance: 4200, octaves: 1, decay: 0.11 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: {
      reverbDecay: 2.8, reverbWet: 0.22,
      delayTime: '8n', delayFeedback: 0.18, delayWet: 0.12,
      chorusFreq: 0.8, chorusDepth: 0.35, chorusWet: 0.3,
      compThreshold: -18, compRatio: 3, compAttack: 0.01, compRelease: 0.15,
    },
  },

  percussion: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'fatsawtooth', count: 2, spread: 10 },
        envelope: { attack: 0.008, decay: 0.25, sustain: 0.35, release: 0.15 },
        filter: { Q: 4, type: 'lowpass', rolloff: -24 },
        filterEnvelope: { attack: 0.005, decay: 0.18, sustain: 0.25, release: 0.12, baseFrequency: 100, octaves: 3 },
      },
      volume: -5,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'Synth',
      maxPolyphony: 4,
      options: {
        oscillator: { type: 'fattriangle', count: 3, spread: 15 },
        envelope: { attack: 0.08, decay: 0.35, sustain: 0.45, release: 0.7 },
      },
      volume: -15,
    },
    lead: {
      type: 'Synth',
      options: {
        oscillator: { type: 'pulse', width: 0.25 },
        envelope: { attack: 0.004, decay: 0.18, sustain: 0.15, release: 0.25 },
      },
      volume: -13,
    },
    arp: {
      type: 'FMSynth',
      options: {
        harmonicity: 2,
        modulationIndex: 2.5,
        oscillator: { type: 'sine' },
        envelope: { attack: 0.003, decay: 0.1, sustain: 0.04, release: 0.12 },
        modulation: { type: 'sine' },
        modulationEnvelope: { attack: 0.005, decay: 0.08, sustain: 0.05, release: 0.1 },
      },
      volume: -17,
    },
    drums: {
      kick:      { pitchDecay: 0.1, octaves: 7, envelope: { attack: 0.003, decay: 0.4, sustain: 0 } },
      snare:     { type: 'white', attack: 0.001, decay: 0.13 },
      closedHat: { frequency: 440, harmonicity: 5.1, modulationIndex: 34, resonance: 5500, octaves: 1.5, decay: 0.04 },
      openHat:   { frequency: 440, harmonicity: 5.1, modulationIndex: 34, resonance: 5000, octaves: 1.5, decay: 0.28 },
      clap:      { type: 'white', attack: 0.001, decay: 0.13 },
      rimshot:   { type: 'pink', attack: 0.001, decay: 0.055 },
      shaker:    { type: 'white', attack: 0.001, decay: 0.025 },
      cowbell:   { frequency: 820, harmonicity: 5.4, modulationIndex: 22, resonance: 3200, octaves: 0.5, decay: 0.14 },
      conga:     { pitchDecay: 0.04, octaves: 3.8, envelope: { attack: 0.001, decay: 0.32, sustain: 0 } },
      bongo:     { pitchDecay: 0.025, octaves: 3.2, envelope: { attack: 0.001, decay: 0.18, sustain: 0 } },
      timbale:   { frequency: 650, harmonicity: 3.5, modulationIndex: 18, resonance: 4500, octaves: 1.2, decay: 0.1 },
      claves:    { frequency: 2600, harmonicity: 3, modulationIndex: 10, resonance: 6500, octaves: 0.3, decay: 0.035 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: {
      reverbDecay: 1.2, reverbWet: 0.12,
      delayTime: '16n', delayFeedback: 0.08, delayWet: 0.06,
      chorusFreq: 0.5, chorusDepth: 0.2, chorusWet: 0.15,
      compThreshold: -14, compRatio: 4, compAttack: 0.005, compRelease: 0.1,
    },
  },

  reggae: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'sine' },
        envelope: { attack: 0.025, decay: 0.6, sustain: 0.75, release: 0.6 },
        filter: { Q: 1.5, type: 'lowpass', rolloff: -12 },
        filterEnvelope: { attack: 0.02, decay: 0.35, sustain: 0.55, release: 0.5, baseFrequency: 80, octaves: 1.8 },
      },
      volume: -3,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'Synth',
      maxPolyphony: 4,
      options: {
        oscillator: { type: 'fatsquare', count: 2, spread: 8 },
        envelope: { attack: 0.003, decay: 0.06, sustain: 0.0, release: 0.04 },
      },
      volume: -17,
    },
    lead: {
      type: 'FMSynth',
      options: {
        harmonicity: 1,
        modulationIndex: 1.5,
        oscillator: { type: 'sine' },
        envelope: { attack: 0.015, decay: 0.45, sustain: 0.35, release: 0.6 },
        modulation: { type: 'sine' },
        modulationEnvelope: { attack: 0.1, decay: 0.3, sustain: 0.2, release: 0.4 },
      },
      volume: -13,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'fattriangle', count: 2, spread: 10 },
        envelope: { attack: 0.008, decay: 0.1, sustain: 0.08, release: 0.18 },
      },
      volume: -17,
    },
    drums: {
      kick:      { pitchDecay: 0.14, octaves: 8.5, envelope: { attack: 0.003, decay: 0.45, sustain: 0 } },
      snare:     { type: 'white', attack: 0.001, decay: 0.22 },
      closedHat: { frequency: 380, harmonicity: 5.1, modulationIndex: 30, resonance: 4500, octaves: 1.5, decay: 0.035 },
      openHat:   { frequency: 380, harmonicity: 5.1, modulationIndex: 30, resonance: 4500, octaves: 1.5, decay: 0.28 },
      clap:      { type: 'white', attack: 0.001, decay: 0.12 },
      rimshot:   { type: 'pink', attack: 0.001, decay: 0.07 },
      shaker:    { type: 'white', attack: 0.001, decay: 0.028 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.03, octaves: 3, envelope: { attack: 0.001, decay: 0.25, sustain: 0 } },
      bongo:     { pitchDecay: 0.02, octaves: 2.5, envelope: { attack: 0.001, decay: 0.15, sustain: 0 } },
      timbale:   { frequency: 600, harmonicity: 3, modulationIndex: 15, resonance: 4000, octaves: 1, decay: 0.12 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: {
      reverbDecay: 3.5, reverbWet: 0.2,
      delayTime: '4n.', delayFeedback: 0.35, delayWet: 0.25,
      chorusFreq: 0.3, chorusDepth: 0.25, chorusWet: 0.2,
      compThreshold: -16, compRatio: 3, compAttack: 0.015, compRelease: 0.2,
    },
  },

  deephouse: {
    bass: {
      type: 'MonoSynth',
      options: {
        oscillator: { type: 'fattriangle', count: 2, spread: 8 },
        envelope: { attack: 0.005, decay: 0.4, sustain: 0.8, release: 0.2 },
        filter: { Q: 3, type: 'lowpass', rolloff: -24 },
        filterEnvelope: { attack: 0.01, decay: 0.3, sustain: 0.4, release: 0.15, baseFrequency: 80, octaves: 2.5 },
      },
      volume: -3,
    },
    pad: {
      type: 'PolySynth',
      voiceType: 'FMSynth',
      maxPolyphony: 6,
      options: {
        harmonicity: 1,
        modulationIndex: 1.5,
        oscillator: { type: 'sine' },
        envelope: { attack: 0.5, decay: 0.8, sustain: 0.8, release: 2.5 },
        modulation: { type: 'triangle' },
        modulationEnvelope: { attack: 0.5, decay: 0.5, sustain: 0.5, release: 2.0 },
      },
      volume: -12,
    },
    lead: {
      type: 'Synth',
      options: {
        oscillator: { type: 'pulse', width: 0.35 },
        envelope: { attack: 0.008, decay: 0.22, sustain: 0.18, release: 0.28 },
      },
      volume: -13,
    },
    arp: {
      type: 'Synth',
      options: {
        oscillator: { type: 'fatsawtooth', count: 2, spread: 18 },
        envelope: { attack: 0.003, decay: 0.07, sustain: 0.03, release: 0.08 },
      },
      volume: -15,
    },
    drums: {
      kick:      { pitchDecay: 0.08, octaves: 6, envelope: { attack: 0.001, decay: 0.8, sustain: 0.01 } },
      snare:     { type: 'white', attack: 0.001, decay: 0.16 },
      closedHat: { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 6000, octaves: 1.5, decay: 0.04 },
      openHat:   { frequency: 400, harmonicity: 5.1, modulationIndex: 32, resonance: 5500, octaves: 1.5, decay: 0.4 },
      clap:      { type: 'white', attack: 0.002, decay: 0.25 },
      rimshot:   { type: 'pink', attack: 0.001, decay: 0.05 },
      shaker:    { type: 'white', attack: 0.001, decay: 0.022 },
      cowbell:   { frequency: 800, harmonicity: 5.4, modulationIndex: 20, resonance: 3000, octaves: 0.5, decay: 0.15 },
      conga:     { pitchDecay: 0.03, octaves: 3, envelope: { attack: 0.001, decay: 0.25, sustain: 0 } },
      bongo:     { pitchDecay: 0.02, octaves: 2.5, envelope: { attack: 0.001, decay: 0.15, sustain: 0 } },
      timbale:   { frequency: 600, harmonicity: 3, modulationIndex: 15, resonance: 4000, octaves: 1, decay: 0.12 },
      claves:    { frequency: 2500, harmonicity: 3, modulationIndex: 8, resonance: 6000, octaves: 0.3, decay: 0.04 },
      crash:     { frequency: 300, harmonicity: 5.1, modulationIndex: 40, resonance: 4000, octaves: 2, decay: 0.8 },
    },
    effects: {
      reverbDecay: 3.5, reverbWet: 0.22,
      delayTime: '8n.', delayFeedback: 0.25, delayWet: 0.15,
      chorusFreq: 0.6, chorusDepth: 0.3, chorusWet: 0.2,
      compThreshold: -14, compRatio: 4, compAttack: 0.003, compRelease: 0.1,
    },
  },
};

// MagentaEngine — AI-powered music generation from biometric sensor data.
// Uses Magenta.js MusicRNN (chord-conditioned melody) + MusicVAE (drums)
// to generate sequences that play through the existing AudioOutputRouter.
//
// Biometric mapping:
//   heartrate → BPM + bass trigger density
//   breathing → temperature (calm=structured, fast=chaotic) + pad filter
//   HRV       → energy (low HRV=tense/dense, high HRV=sparse/calm)
//   sync      → harmony complexity + arp density

const MAGENTA_CDN = 'https://cdn.jsdelivr.net/npm/@magenta/music@1.23.1';
const TFJS_CDN = 'https://cdn.jsdelivr.net/npm/@tensorflow/tfjs@1.7.4/dist/tf.min.js';

const MELODY_CHECKPOINT = 'https://storage.googleapis.com/magentadata/js/checkpoints/music_rnn/chord_pitches_improv';
const DRUMS_CHECKPOINT = 'https://storage.googleapis.com/magentadata/js/checkpoints/music_vae/drums_2bar_lokl_small';

// Channel layout (same as Groovy)
const CH = { bass: 0, pad: 1, lead: 2, arp: 3, drums: 9 };

// GM drum note mapping for MusicVAE 9-class output
// MusicVAE drums use 9 classes mapped to these MIDI pitches:
const DRUM_CLASS_TO_MIDI = [36, 38, 42, 46, 45, 48, 50, 49, 51];

// Chord progressions per mood (MusicRNN uses chord symbols)
const CHORD_SETS = {
  calm: [
    { symbol: 'Dm', root: 50, tones: [62, 65, 69], arp: [50, 62, 65, 69, 72, 74] },
    { symbol: 'Am', root: 57, tones: [60, 64, 69], arp: [57, 60, 64, 69, 72, 76] },
    { symbol: 'F',  root: 53, tones: [60, 65, 69], arp: [53, 60, 65, 69, 72, 77] },
    { symbol: 'G',  root: 55, tones: [59, 62, 67], arp: [55, 59, 62, 67, 71, 74] },
  ],
  warm: [
    { symbol: 'Cmaj7', root: 48, tones: [60, 64, 67, 71], arp: [48, 60, 64, 67, 71, 76] },
    { symbol: 'Am7',   root: 57, tones: [60, 64, 69, 72], arp: [57, 60, 64, 69, 72, 76] },
    { symbol: 'Fmaj7', root: 53, tones: [60, 65, 69, 72], arp: [53, 60, 65, 69, 72, 77] },
    { symbol: 'G7',    root: 55, tones: [59, 62, 65, 67], arp: [55, 59, 62, 65, 67, 71] },
  ],
  tense: [
    { symbol: 'Cm',  root: 48, tones: [60, 63, 67], arp: [48, 60, 63, 67, 70, 75] },
    { symbol: 'Fm',  root: 53, tones: [60, 65, 68], arp: [53, 60, 65, 68, 72, 77] },
    { symbol: 'Abm', root: 56, tones: [60, 63, 68], arp: [56, 60, 63, 68, 72, 75] },
    { symbol: 'G',   root: 55, tones: [59, 62, 67], arp: [55, 59, 62, 67, 71, 74] },
  ],
  intense: [
    { symbol: 'Cm',  root: 48, tones: [60, 63, 67, 70], arp: [48, 60, 63, 67, 70, 75] },
    { symbol: 'Eb',  root: 51, tones: [63, 67, 70, 75], arp: [51, 63, 67, 70, 75, 79] },
    { symbol: 'Bb',  root: 58, tones: [62, 65, 70, 74], arp: [58, 62, 65, 70, 74, 77] },
    { symbol: 'Gm',  root: 55, tones: [62, 67, 70, 74], arp: [55, 62, 67, 70, 74, 79] },
  ],
};

// Note names for chord parsing and transposition
const NOTE_NAMES = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const NOTE_TO_SEMITONE = {
  'C': 0, 'C#': 1, 'Db': 1, 'D': 2, 'D#': 3, 'Eb': 3, 'E': 4, 'Fb': 4,
  'F': 5, 'F#': 6, 'Gb': 6, 'G': 7, 'G#': 8, 'Ab': 8, 'A': 9, 'A#': 10, 'Bb': 10, 'B': 11, 'Cb': 11,
};

// Parse a chord symbol like "Am7" into { root: 'A', quality: 'm7', rootSemitone: 9 }
function parseChordSymbol(symbol) {
  const match = symbol.match(/^([A-G][#b]?)(.*)/);
  if (!match) return null;
  const root = match[1];
  const quality = match[2] || '';
  const rootSemitone = NOTE_TO_SEMITONE[root];
  if (rootSemitone === undefined) return null;
  return { root, quality, rootSemitone };
}

// Transpose a chord symbol by N semitones
function transposeChordSymbol(symbol, semitones) {
  const parsed = parseChordSymbol(symbol);
  if (!parsed) return symbol;
  const newSemitone = ((parsed.rootSemitone + semitones) % 12 + 12) % 12;
  return NOTE_NAMES[newSemitone] + parsed.quality;
}

// Build chord voicings from a chord symbol string
// Returns { symbol, root (MIDI), tones (MIDI[]), arp (MIDI[]) }
function chordFromSymbol(symbol, octave = 4) {
  const parsed = parseChordSymbol(symbol);
  if (!parsed) return null;

  const base = parsed.rootSemitone + (octave - 1) * 12 + 12; // bass octave
  const mid = parsed.rootSemitone + octave * 12 + 12;         // chord octave
  const q = parsed.quality.toLowerCase().replace(/\s/g, '');

  let intervals;
  if (q.includes('dim'))         intervals = [0, 3, 6];
  else if (q.includes('aug'))    intervals = [0, 4, 8];
  else if (q.includes('sus4'))   intervals = [0, 5, 7];
  else if (q.includes('sus2'))   intervals = [0, 2, 7];
  else if (q.includes('m'))      intervals = [0, 3, 7]; // minor
  else                           intervals = [0, 4, 7]; // major

  // Extensions
  if (q.includes('maj7'))        intervals.push(11);
  else if (q.includes('7'))      intervals.push(10);
  if (q.includes('9'))           intervals.push(14);
  if (q.includes('11'))          intervals.push(17);
  if (q.includes('13'))          intervals.push(21);

  const tones = intervals.map(i => mid + i);
  const arp = [...intervals, ...intervals.map(i => i + 12)].slice(0, 6).map(i => mid + i);

  return { symbol, root: base, tones, arp };
}

// Parse a user chord string like "Am7 Dm7 G7 Cmaj7" into chord objects
function parseChordsString(str, keyTranspose = 0) {
  const symbols = str.trim().split(/[\s,→|]+/).filter(Boolean);
  const chords = [];
  for (const sym of symbols) {
    const transposed = keyTranspose !== 0 ? transposeChordSymbol(sym, keyTranspose) : sym;
    const chord = chordFromSymbol(transposed);
    if (chord) chords.push(chord);
  }
  return chords.length > 0 ? chords : null;
}

function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)); }

export class MagentaEngine {
  constructor(audioRouter) {
    this.midi = audioRouter;
    this._running = false;
    this._disposed = false;
    this._modelsReady = false;
    this._loading = false;

    // Models
    this._melodyRnn = null;
    this._drumsVae = null;

    // Biometric state (0-1 normalized)
    this._heartrate = 0;      // raw BPM stored separately
    this._heartBpm = 72;
    this._breathing = 0.5;    // breath phase 0-1
    this._hrv = 0.5;          // normalized HRV
    this._sync = 0;           // breathing sync 0-1
    this._energy = 0.5;       // derived from HRV (inverted)
    this._activity = 0;       // number of active sensors

    // Music state
    this._bpm = 80;
    this._temperature = 0.8;
    this._chordIndex = 0;
    this._mood = 'calm';
    this._chords = CHORD_SETS.calm;

    // User settings (from modal)
    this._customChords = null;       // parsed chord objects from user input, or null for auto
    this._customChordSymbols = '';    // raw user input string
    this._keyTranspose = 0;          // semitones to transpose (0-11)
    this._tempOverride = null;       // null = auto from breathing, number = fixed
    this._moodOverride = null;       // null = auto from biometrics, string = fixed

    // Generation buffers
    this._currentMelody = null;
    this._currentDrums = null;
    this._nextMelody = null;
    this._nextDrums = null;
    this._isGenerating = false;

    // Playback
    this._stepTimer = null;
    this._step = 0;           // current 16th note step within a 2-bar phrase (0-31)
    this._bar = 0;
    this._activeNotes = new Map(); // channel -> Set of active notes

    // Arp state
    this._arpIndex = 0;

    // Pad state
    this._padNotes = [];

    // Bass state
    this._lastBassNote = null;

    // Sensor tracking
    this._sensorLastSeen = new Map();

    // Stats
    this._genCount = 0;
    this._genTimeMs = 0;
  }

  // ─── CDN Loading ─────────────────────────────────────────────────────

  async loadModels() {
    if (this._modelsReady || this._loading) return;
    this._loading = true;

    try {
      // Load TensorFlow.js first
      if (!window.tf) {
        console.info('[MagentaEngine] Loading TensorFlow.js...');
        await this._loadScript(TFJS_CDN);
      }

      // Load Magenta.js core + modules (ES6 build exposes on separate globals)
      if (!window.core) {
        console.info('[MagentaEngine] Loading Magenta.js core...');
        await this._loadScript(`${MAGENTA_CDN}/es6/core.js`);
      }
      if (!window.music_rnn) {
        console.info('[MagentaEngine] Loading Magenta.js music_rnn...');
        await this._loadScript(`${MAGENTA_CDN}/es6/music_rnn.js`);
      }
      if (!window.music_vae) {
        console.info('[MagentaEngine] Loading Magenta.js music_vae...');
        await this._loadScript(`${MAGENTA_CDN}/es6/music_vae.js`);
      }

      if (!window.music_rnn || !window.music_vae || !window.core) {
        throw new Error('Magenta.js modules not found on window after loading');
      }

      // Initialize melody model (chord-conditioned improv)
      console.info('[MagentaEngine] Initializing MusicRNN (chord_pitches_improv)...');
      this._melodyRnn = new window.music_rnn.MusicRNN(MELODY_CHECKPOINT);
      await this._melodyRnn.initialize();
      console.info('[MagentaEngine] MusicRNN ready.');

      // Initialize drums model
      console.info('[MagentaEngine] Initializing MusicVAE (drums)...');
      this._drumsVae = new window.music_vae.MusicVAE(DRUMS_CHECKPOINT);
      await this._drumsVae.initialize();
      console.info('[MagentaEngine] MusicVAE drums ready.');

      this._modelsReady = true;
      console.info('[MagentaEngine] All models loaded.');
    } catch (err) {
      console.error('[MagentaEngine] Model loading failed:', err);
    } finally {
      this._loading = false;
    }
  }

  _loadScript(src) {
    return new Promise((resolve, reject) => {
      if (document.querySelector(`script[src="${src}"]`)) {
        resolve();
        return;
      }
      const s = document.createElement('script');
      s.src = src;
      s.onload = resolve;
      s.onerror = () => reject(new Error(`Failed to load ${src}`));
      document.head.appendChild(s);
    });
  }

  // ─── User Settings (from modal) ─────────────────────────────────────

  setChords(chordString) {
    this._customChordSymbols = chordString || '';
    if (!chordString || !chordString.trim()) {
      this._customChords = null;
      return;
    }
    this._customChords = parseChordsString(chordString, this._keyTranspose);
    if (this._customChords) {
      this._chords = this._customChords;
      this._chordIndex = 0;
      console.info('[MagentaEngine] Custom chords set:', this._customChords.map(c => c.symbol).join(' '));
    }
  }

  setKeyTranspose(semitones) {
    this._keyTranspose = ((semitones % 12) + 12) % 12;
    // Re-parse chords with new transposition
    if (this._customChordSymbols) {
      this.setChords(this._customChordSymbols);
    } else {
      // Transpose the mood-based chords too
      this._applyActiveChords();
    }
  }

  setTemperatureOverride(value) {
    // value: null for auto, 0-100 for slider position
    if (value === null || value === undefined) {
      this._tempOverride = null;
    } else {
      this._tempOverride = 0.4 + (value / 100) * 1.1; // 0.4 to 1.5
    }
  }

  setMoodOverride(mood) {
    // mood: null/'auto' for biometric-driven, or 'calm'/'warm'/'tense'/'intense'
    if (!mood || mood === 'auto') {
      this._moodOverride = null;
    } else {
      this._moodOverride = mood;
      this._applyActiveChords();
    }
  }

  // Apply settings and regenerate immediately
  applySettings() {
    this._applyActiveChords();
    // Force regeneration of the next phrase with new settings
    this._nextMelody = null;
    this._nextDrums = null;
    if (this._running && !this._isGenerating) {
      this._generateBoth();
    }
  }

  _applyActiveChords() {
    if (this._customChords) {
      this._chords = this._customChords;
    } else {
      const mood = this._moodOverride || this._mood;
      const baseChords = CHORD_SETS[mood] || CHORD_SETS.calm;
      if (this._keyTranspose !== 0) {
        this._chords = baseChords.map(c => {
          const transposed = transposeChordSymbol(c.symbol, this._keyTranspose);
          const built = chordFromSymbol(transposed);
          return built || c;
        });
      } else {
        this._chords = baseChords;
      }
    }
  }

  getSettings() {
    return {
      chords: this._customChordSymbols,
      keyTranspose: this._keyTranspose,
      tempOverride: this._tempOverride,
      moodOverride: this._moodOverride,
    };
  }

  // ─── Biometric Inputs ───────────────────────────────────────────────

  feedHeartbeat(bpm, sensorId) {
    this._heartBpm = bpm;
    this._heartrate = clamp((bpm - 50) / 100, 0, 1);
    this._bpm = clamp(Math.round(bpm * 0.6 + 30), 60, 130);
    this._pulse(sensorId);
  }

  feedBreathing(phase01) {
    this._breathing = phase01;
    // Only auto-adjust temperature if no override set
    if (this._tempOverride === null) {
      this._temperature = 0.5 + phase01 * 0.6;
    } else {
      this._temperature = this._tempOverride;
    }

    // Send filter CC for pad expressiveness
    if (this._running) {
      const cc74 = Math.round(30 + phase01 * 97);
      this.midi.sendCC(CH.pad, 74, cc74);
    }
  }

  feedHrv(normalized) {
    this._hrv = normalized;
    this._energy = 1 - normalized; // low HRV = high energy
    this._updateMood();
  }

  feedSync(value01) {
    this._sync = value01;
    this._updateMood();
  }

  feedSensorNote(sensorId) {
    this._pulse(sensorId);
  }

  _pulse(sensorId) {
    this._sensorLastSeen.set(sensorId, Date.now());
    const activeSensors = [...this._sensorLastSeen.values()]
      .filter(t => Date.now() - t < 5000).length;
    this._activity = clamp(activeSensors / 10, 0.05, 1);
  }

  _updateMood() {
    // Skip auto-mood if overridden or using custom chords
    if (this._moodOverride || this._customChords) return;

    const e = this._energy;
    const s = this._sync;

    if (e < 0.3 && s > 0.5) this._mood = 'calm';
    else if (e < 0.5) this._mood = 'warm';
    else if (e < 0.7) this._mood = 'tense';
    else this._mood = 'intense';

    this._chords = CHORD_SETS[this._mood];
  }

  // ─── Playback Control ───────────────────────────────────────────────

  async start() {
    if (this._running) return;
    if (!this._modelsReady) {
      console.warn('[MagentaEngine] Models not ready, loading...');
      await this.loadModels();
      if (!this._modelsReady) return;
    }

    this._running = true;
    this._step = 0;
    this._bar = 0;
    this._chordIndex = 0;
    this._arpIndex = 0;

    // Generate initial sequences
    await this._generateBoth();
    this._currentMelody = this._nextMelody;
    this._currentDrums = this._nextDrums;
    this._nextMelody = null;
    this._nextDrums = null;

    // Start step clock
    this._scheduleNextStep();

    // Pre-generate next phrase
    this._generateBoth();

    console.info('[MagentaEngine] Started.');
  }

  stop() {
    this._running = false;
    if (this._stepTimer) {
      clearTimeout(this._stepTimer);
      this._stepTimer = null;
    }
    this._allNotesOff();
    this._currentMelody = null;
    this._currentDrums = null;
    this._nextMelody = null;
    this._nextDrums = null;
    console.info('[MagentaEngine] Stopped.');
  }

  dispose() {
    this.stop();
    this._disposed = true;
    if (this._melodyRnn) {
      this._melodyRnn.dispose();
      this._melodyRnn = null;
    }
    if (this._drumsVae) {
      this._drumsVae.dispose();
      this._drumsVae = null;
    }
  }

  // ─── Generation ─────────────────────────────────────────────────────

  async _generateBoth() {
    if (this._isGenerating || !this._modelsReady) return;
    this._isGenerating = true;
    const t0 = performance.now();

    try {
      const [melody, drums] = await Promise.all([
        this._generateMelody(),
        this._generateDrums(),
      ]);
      this._nextMelody = melody;
      this._nextDrums = drums;

      this._genCount++;
      this._genTimeMs += performance.now() - t0;
    } catch (err) {
      console.warn('[MagentaEngine] Generation error:', err.message);
    } finally {
      this._isGenerating = false;
    }
  }

  async _generateMelody() {
    if (!this._melodyRnn) return null;

    const chord = this._chords[this._chordIndex % this._chords.length];
    const nextChord = this._chords[(this._chordIndex + 1) % this._chords.length];

    // Create a short seed (2 notes based on current chord)
    const seed = {
      notes: [
        { pitch: chord.root, startTime: 0, endTime: 0.5, instrument: 0 },
        { pitch: chord.tones[0], startTime: 0.5, endTime: 1.0, instrument: 0 },
      ],
      totalTime: 1.0,
      tempos: [{ time: 0, qpm: this._bpm }],
      quantizationInfo: { stepsPerQuarter: 4 },
    };

    // Quantize the seed
    const quantized = window.core.sequences.quantizeNoteSequence(seed, 4);

    // Generate 2 bars (32 steps at 4 steps/quarter, 4 quarters/bar)
    const chordProg = [chord.symbol, chord.symbol, nextChord.symbol, nextChord.symbol];
    const temp = clamp(this._temperature, 0.4, 1.5);

    const result = await this._melodyRnn.continueSequence(
      quantized, 32, temp, chordProg
    );

    return result;
  }

  async _generateDrums() {
    if (!this._drumsVae) return null;

    // Temperature: low energy → simple patterns, high energy → complex
    const temp = 0.5 + this._energy * 0.8;

    const results = await this._drumsVae.sample(1, temp);
    return results[0];
  }

  // ─── Step Sequencer ─────────────────────────────────────────────────

  _scheduleNextStep() {
    if (!this._running) return;
    const sixteenthMs = (60000 / this._bpm) / 4;
    this._stepTimer = setTimeout(() => this._onStep(), sixteenthMs);
  }

  _onStep() {
    if (!this._running || this._disposed) return;
    const a = this._activity;

    // Phrase position: 32 steps = 2 bars
    const phraseStep = this._step % 32;
    const beat = Math.floor(phraseStep / 4); // 0-7 across 2 bars

    // Every 2 bars, swap in the next generated phrase
    if (phraseStep === 0 && this._step > 0) {
      if (this._nextMelody) {
        this._currentMelody = this._nextMelody;
        this._nextMelody = null;
      }
      if (this._nextDrums) {
        this._currentDrums = this._nextDrums;
        this._nextDrums = null;
      }
      this._chordIndex = (this._chordIndex + 1) % this._chords.length;

      // Kick off generation of the next phrase
      this._generateBoth();
    }

    // Gate on activity
    if (a < 0.01) {
      this._step++;
      this._scheduleNextStep();
      return;
    }

    const chord = this._chords[this._chordIndex % this._chords.length];
    const sixteenthSec = (60 / this._bpm) / 4;

    // ─── DRUMS (from MusicVAE) ───
    if (a > 0.05 && this._currentDrums) {
      this._playDrumStep(phraseStep, sixteenthSec);
    }

    // ─── BASS ───
    if (a > 0.15 && (beat % 2 === 0) && phraseStep % 4 === 0) {
      this._playBass(chord, beat);
    }

    // ─── PAD (chord tones from breathing) ───
    if (a > 0.1 && phraseStep % 8 === 0) {
      this._playPad(chord);
    }

    // ─── LEAD (from MusicRNN melody) ───
    if (a > 0.2 && this._currentMelody) {
      this._playMelodyStep(phraseStep, sixteenthSec);
    }

    // ─── ARP ───
    if (a > 0.3 && this._sync > 0.2) {
      const playProb = this._sync * 0.7;
      if (Math.random() < playProb && phraseStep % 2 === 0) {
        this._playArp(chord);
      }
    }

    // Send MIDI clock pulses (6 per 16th = 24 PPQN)
    for (let i = 0; i < 6; i++) this.midi.sendClock();

    this._step++;
    this._scheduleNextStep();
  }

  // ─── Voice Players ──────────────────────────────────────────────────

  _playDrumStep(phraseStep, sixteenthSec) {
    const drums = this._currentDrums;
    if (!drums || !drums.notes) return;

    // Find drum notes that start at this step
    const stepsPerQuarter = drums.quantizationInfo?.stepsPerQuarter || 4;
    for (const note of drums.notes) {
      const noteStep = note.quantizedStartStep;
      if (noteStep === phraseStep) {
        const midiNote = DRUM_CLASS_TO_MIDI[note.pitch] || note.pitch;
        const vel = clamp(Math.round((note.velocity || 80) * (0.7 + this._energy * 0.3)), 1, 127);
        this.midi.sendNoteOn(CH.drums, midiNote, vel);
        setTimeout(() => {
          if (this.midi) this.midi.sendNoteOff(CH.drums, midiNote, 0);
        }, 50);
      }
    }
  }

  _playMelodyStep(phraseStep, sixteenthSec) {
    const melody = this._currentMelody;
    if (!melody || !melody.notes) return;

    for (const note of melody.notes) {
      if (note.quantizedStartStep === phraseStep) {
        const vel = clamp(Math.round(70 + this._energy * 50), 1, 127);
        const durSteps = (note.quantizedEndStep || note.quantizedStartStep + 2) - note.quantizedStartStep;
        const durMs = durSteps * sixteenthSec * 1000;

        this.midi.sendNoteOn(CH.lead, note.pitch, vel);
        this._trackNote(CH.lead, note.pitch);

        setTimeout(() => {
          if (this.midi) {
            this.midi.sendNoteOff(CH.lead, note.pitch, 0);
            this._untrackNote(CH.lead, note.pitch);
          }
        }, Math.max(durMs, 50));
      }
    }
  }

  _playBass(chord, beat) {
    // Release previous bass note
    if (this._lastBassNote !== null) {
      this.midi.sendNoteOff(CH.bass, this._lastBassNote, 0);
    }

    const vel = clamp(Math.round(70 + this._heartrate * 40), 1, 127);
    let note = chord.root;

    // On beat 4/8, approach the next chord's root
    if (beat === 3 || beat === 7) {
      const nextChord = this._chords[(this._chordIndex + 1) % this._chords.length];
      note = nextChord.root - 1; // chromatic approach from below
    }

    this.midi.sendNoteOn(CH.bass, note, vel);
    this._lastBassNote = note;
  }

  _playPad(chord) {
    // Release old pad notes
    for (const n of this._padNotes) {
      this.midi.sendNoteOff(CH.pad, n, 0);
    }

    // Velocity from breathing
    const vel = clamp(Math.round(50 + this._breathing * 60), 1, 127);

    // Number of tones based on energy
    const numTones = this._energy > 0.6 ? chord.tones.length : Math.min(3, chord.tones.length);
    const tones = chord.tones.slice(0, numTones);

    this._padNotes = tones;
    for (const n of tones) {
      this.midi.sendNoteOn(CH.pad, n, vel);
    }
  }

  _playArp(chord) {
    const arpNotes = chord.arp;
    if (!arpNotes || arpNotes.length === 0) return;

    const note = arpNotes[this._arpIndex % arpNotes.length];
    const vel = clamp(Math.round(40 + this._sync * 65), 1, 127);

    this.midi.sendNoteOn(CH.arp, note, vel);
    setTimeout(() => {
      if (this.midi) this.midi.sendNoteOff(CH.arp, note, 0);
    }, (60000 / this._bpm) / 8); // 32nd note duration

    this._arpIndex++;
  }

  // ─── Note Tracking ──────────────────────────────────────────────────

  _trackNote(ch, note) {
    if (!this._activeNotes.has(ch)) this._activeNotes.set(ch, new Set());
    this._activeNotes.get(ch).add(note);
  }

  _untrackNote(ch, note) {
    const set = this._activeNotes.get(ch);
    if (set) set.delete(note);
  }

  _allNotesOff() {
    for (const [ch, notes] of this._activeNotes) {
      for (const note of notes) {
        this.midi.sendNoteOff(ch, note, 0);
      }
      notes.clear();
    }
    // Release bass and pad
    if (this._lastBassNote !== null) {
      this.midi.sendNoteOff(CH.bass, this._lastBassNote, 0);
      this._lastBassNote = null;
    }
    for (const n of this._padNotes) {
      this.midi.sendNoteOff(CH.pad, n, 0);
    }
    this._padNotes = [];

    // All Notes Off CC on all channels
    for (const ch of Object.values(CH)) {
      this.midi.sendCC(ch, 123, 0);
    }
  }

  // ─── Stats ──────────────────────────────────────────────────────────

  getStats() {
    return {
      running: this._running,
      modelsReady: this._modelsReady,
      bpm: this._bpm,
      mood: this._moodOverride || this._mood,
      temperature: Math.round(this._temperature * 100) / 100,
      energy: Math.round(this._energy * 100) / 100,
      activity: Math.round(this._activity * 100) / 100,
      chords: this._chords.map(c => c.symbol).join(' '),
      customChords: !!this._customChords,
      keyTranspose: this._keyTranspose,
      genCount: this._genCount,
      avgGenMs: this._genCount > 0 ? Math.round(this._genTimeMs / this._genCount) : 0,
      step: this._step,
    };
  }
}

<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Graph from "graphology";
  import Sigma from "sigma";
  import EdgeCurveProgram from "@sigma/edge-curve";
  import forceAtlas2 from "graphology-layout-forceatlas2";
  import FA2Layout from "graphology-layout-forceatlas2/worker";

  interface Room {
    id: string;
    name: string;
    sensor_count: number;
  }

  interface User {
    connector_id: string;
    connector_name: string;
    sensor_count: number;
    sensors: Array<{ sensor_id: string; sensor_name: string }>;
    attributes_summary: Array<{ type: string; count: number; latest_value: any }>;
  }

  interface Sensor {
    sensor_id: string;
    sensor_name: string;
    connector_id: string;
    connector_name: string;
    attributes: Record<string, Attribute>;
  }

  interface Attribute {
    attribute_id: string;
    attribute_type: string;
    attribute_name?: string;
    lastvalue?: { payload: any; timestamp: number };
  }

  interface Props {
    rooms?: Room[];
    users?: User[];
    sensors?: Record<string, Sensor>;
    compact?: boolean;
  }

  let {
    rooms = [],
    users = [],
    sensors = {},
    compact = false
  }: Props = $props();

  let container: HTMLDivElement;
  let graph: Graph;
  let sigma: Sigma | null = null;
  let selectedNode = $state<string | null>(null);
  let hoveredNode = $state<string | null>(null);
  let hoverDetails = $state<any>(null);
  let selectedDetails = $state<any>(null);
  let mouseX = $state(0);
  let mouseY = $state(0);
  let isLayoutRunning = $state(false);
  let isFullscreen = $state(false);
  let showExportModal = $state(false);
  let leftBarOpen = $state(false);
  let rightBarOpen = $state(false);
  let exportFormat = $state<"png" | "jpeg">("png");
  let exportScale = $state(2);
  let exportBackground = $state(true);
  let isExporting = $state(false);
  let isRecording = $state(false);
  let recordingSeconds = $state(0);
  let mediaRecorder: MediaRecorder | null = null;
  let recordedChunks: Blob[] = [];
  let recordingTimer: ReturnType<typeof setInterval> | null = null;
  let recordingRaf: number | null = null;
  let recordingCanvas: HTMLCanvasElement | null = null;
  let graphRoot: HTMLDivElement;

  // ── Level-of-Detail (LOD) ──────────────────────────────────────────
  // Hide attribute nodes only on very large graphs when fully zoomed out.
  // Threshold scales with graph size: small graphs never trigger LOD.
  let lodAttributesVisible = $state(true);
  const LOD_MIN_NODES = 1000; // LOD only activates for graphs this large
  const LOD_ZOOM_THRESHOLD = 2.5; // camera ratio above this = very zoomed out

  // ── ForceAtlas2 Web Worker ─────────────────────────────────────────
  let fa2Worker: FA2Layout | null = null;

  // ── View Mode System ──────────────────────────────────────────────
  type ViewMode =
    | "topology"       // ForceAtlas2 organic clustering
    | "per-user"       // Circular clusters per user
    | "per-type"       // Column lanes per attribute type
    | "radial"         // Concentric rings
    | "constellation"  // Geometric star patterns per user
    | "flower"         // Rose-curve petal layout
    | "heatmap"        // Activity frequency coloring
    | "freshness"      // Time-since-data fading
    | "heartbeat"      // BPM-synchronized pulsing
    | "river"          // Animated data particles
    | "attention";     // Attention level visualization

  let viewMode = $state<ViewMode>("topology");
  let isTransitioning = $state(false);
  let lastLayoutMode = $state<ViewMode>("topology");

  // Activity tracking (heatmap mode)
  let activityCounts = new Map<string, number>();
  let activityDecayTimers: ReturnType<typeof setTimeout>[] = [];
  const ACTIVITY_WINDOW_MS = 10_000;

  // Freshness tracking (freshness mode)
  let nodeFreshness = new Map<string, number>();
  let freshnessTimer: ReturnType<typeof setInterval> | null = null;
  const FRESHNESS_INTERVAL_MS = 500;

  // Heartbeat tracking (heartbeat mode)
  let heartbeatBPMs = new Map<string, number>();
  let heartbeatAnimFrame: number | null = null;
  let heartbeatStartTime: number | null = null;

  // Data river particles (river mode)
  interface Particle {
    path: Array<{x: number; y: number}>;
    progress: number;
    speed: number;
    color: string;
    size: number;
  }
  let riverParticles: Particle[] = [];
  let riverAnimFrame: number | null = null;

  // Attention tracking (attention mode)
  let sensorAttentionLevels = new Map<string, string>();

  const layoutModes: ViewMode[] = ["topology", "per-type", "radial", "flower", "per-user", "constellation"];
  const visualModes: ViewMode[] = ["heatmap", "freshness", "heartbeat", "river", "attention"];

  // Sound engine — switchable themes for graph activity sonification
  type SoundTheme = "off" | "plasma" | "birds" | "underwater" | "chimes" | "heartbeat";
  const SOUND_THEMES: SoundTheme[] = ["off", "plasma", "birds", "underwater", "chimes", "heartbeat"];
  const THEME_LABELS: Record<SoundTheme, string> = {
    off: "Sound Off",
    plasma: "⚡ Plasma Crackle",
    birds: "🐦 Bird Song",
    underwater: "🫧 Underwater",
    chimes: "🎐 Wind Chimes",
    heartbeat: "💓 Heartbeat",
  };
  let soundTheme: SoundTheme = $state("off");
  let seasonPanelOpen = $state(false);
  let statsPanelOpen = $state(false);
  let soundEnabled = $derived(soundTheme !== "off");
  let vibrateEnabled = $state(false);
  let audioCtx: AudioContext | null = null;
  let masterOut: GainNode | null = null;
  let recDest: MediaStreamAudioDestinationNode | null = null;
  let lastSoundTime = 0;
  const SOUND_DEBOUNCE_MS = 180;
  let activeSounds = 0;
  const MAX_CONCURRENT_SOUNDS = 3;
  let noiseBuffer: AudioBuffer | null = null;

  function ensureAudioCtx() {
    if (!audioCtx) {
      audioCtx = new AudioContext();
      const compressor = audioCtx.createDynamicsCompressor();
      compressor.threshold.value = -12;
      compressor.knee.value = 10;
      compressor.ratio.value = 4;
      compressor.attack.value = 0.003;
      compressor.release.value = 0.15;
      compressor.connect(audioCtx.destination);
      masterOut = audioCtx.createGain();
      masterOut.gain.value = 0.8;
      masterOut.connect(compressor);
    }
    if (audioCtx.state === "suspended") {
      audioCtx.resume();
    }
    if (!noiseBuffer) {
      const len = Math.ceil(audioCtx.sampleRate * 0.05);
      noiseBuffer = audioCtx.createBuffer(1, len, audioCtx.sampleRate);
      const data = noiseBuffer.getChannelData(0);
      for (let i = 0; i < len; i++) {
        data[i] = Math.random() * 2 - 1;
      }
    }
    return audioCtx;
  }

  function playSound() {
    if (soundTheme === "off") return;
    const now = performance.now();
    if (now - lastSoundTime < SOUND_DEBOUNCE_MS) return;
    if (activeSounds >= MAX_CONCURRENT_SOUNDS) return;
    lastSoundTime = now;
    activeSounds++;

    const dur = soundTheme === "chimes" ? 500 : soundTheme === "underwater" ? 200 : 250;
    setTimeout(() => { activeSounds = Math.max(0, activeSounds - 1); }, dur);

    switch (soundTheme) {
      case "plasma": playCrackle(); break;
      case "birds": playBirdChirp(); break;
      case "underwater": playUnderwater(); break;
      case "chimes": playChime(); break;
      case "heartbeat": playHeartbeat(); break;
    }
  }

  // --- Plasma Crackle: electrical discharge / Knistern ---
  function playCrackle() {
    const ctx = ensureAudioCtx();
    const t = ctx.currentTime;
    const duration = 0.004 + Math.random() * 0.014;
    const volume = 0.08 + Math.random() * 0.12;

    const noise = ctx.createBufferSource();
    noise.buffer = noiseBuffer!;
    const bp = ctx.createBiquadFilter();
    bp.type = "bandpass";
    bp.frequency.value = 2500 + Math.random() * 5500;
    bp.Q.value = 0.8 + Math.random() * 2.5;
    const hp = ctx.createBiquadFilter();
    hp.type = "highpass";
    hp.frequency.value = 800 + Math.random() * 1200;
    const gain = ctx.createGain();
    gain.gain.setValueAtTime(volume, t);
    gain.gain.exponentialRampToValueAtTime(0.001, t + duration);
    noise.connect(bp); bp.connect(hp); hp.connect(gain); gain.connect(masterOut!);
    noise.start(t, Math.random() * 0.03, duration + 0.01);

    if (Math.random() < 0.25) {
      const osc = ctx.createOscillator();
      osc.type = "sine";
      const startFreq = 2000 + Math.random() * 5000;
      osc.frequency.setValueAtTime(startFreq, t);
      osc.frequency.exponentialRampToValueAtTime(150 + Math.random() * 300, t + 0.012);
      const oscGain = ctx.createGain();
      oscGain.gain.setValueAtTime(volume * 0.35, t);
      oscGain.gain.exponentialRampToValueAtTime(0.001, t + 0.012);
      osc.connect(oscGain); oscGain.connect(masterOut!);
      osc.start(t); osc.stop(t + 0.015);
    }
    if (Math.random() < 0.15) {
      const noise2 = ctx.createBufferSource();
      noise2.buffer = noiseBuffer!;
      const bp2 = ctx.createBiquadFilter();
      bp2.type = "bandpass";
      bp2.frequency.value = 4000 + Math.random() * 4000;
      bp2.Q.value = 1 + Math.random() * 3;
      const gain2 = ctx.createGain();
      const d2 = 0.002 + Math.random() * 0.006;
      gain2.gain.setValueAtTime(volume * 0.6, t + 0.005);
      gain2.gain.exponentialRampToValueAtTime(0.001, t + 0.005 + d2);
      noise2.connect(bp2); bp2.connect(gain2); gain2.connect(masterOut!);
      noise2.start(t + 0.005, Math.random() * 0.03, d2 + 0.01);
    }
  }

  // --- Bird Song: FM-synthesized chirps and warbles ---
  function playBirdChirp() {
    const ctx = ensureAudioCtx();
    const t = ctx.currentTime;
    const volume = 0.10 + Math.random() * 0.12;
    const chirps = Math.random() < 0.3 ? (2 + Math.floor(Math.random() * 2)) : 1;

    for (let i = 0; i < chirps; i++) {
      const offset = i * (0.06 + Math.random() * 0.04);
      const baseFreq = 1800 + Math.random() * 2800;
      const chirpDur = 0.04 + Math.random() * 0.06;

      const carrier = ctx.createOscillator();
      carrier.type = "sine";
      carrier.frequency.setValueAtTime(baseFreq * 0.7, t + offset);
      carrier.frequency.linearRampToValueAtTime(baseFreq, t + offset + chirpDur * 0.3);
      carrier.frequency.exponentialRampToValueAtTime(baseFreq * (0.5 + Math.random() * 0.3), t + offset + chirpDur);

      const modulator = ctx.createOscillator();
      modulator.type = "sine";
      modulator.frequency.value = 30 + Math.random() * 50;
      const modGain = ctx.createGain();
      modGain.gain.value = baseFreq * (0.02 + Math.random() * 0.04);
      modulator.connect(modGain);
      modGain.connect(carrier.frequency);

      const env = ctx.createGain();
      env.gain.setValueAtTime(0.001, t + offset);
      env.gain.linearRampToValueAtTime(volume, t + offset + chirpDur * 0.15);
      env.gain.setValueAtTime(volume, t + offset + chirpDur * 0.5);
      env.gain.exponentialRampToValueAtTime(0.001, t + offset + chirpDur);

      carrier.connect(env); env.connect(masterOut!);
      carrier.start(t + offset); carrier.stop(t + offset + chirpDur + 0.01);
      modulator.start(t + offset); modulator.stop(t + offset + chirpDur + 0.01);
    }
  }

  // --- Underwater: single clean bubble blub ---
  function playUnderwater() {
    const ctx = ensureAudioCtx();
    const t = ctx.currentTime;

    // One clean sine bubble — pitch drops like a rising bubble
    const freq = 300 + Math.random() * 200;
    const dur = 0.06 + Math.random() * 0.04;

    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.setValueAtTime(freq, t);
    osc.frequency.exponentialRampToValueAtTime(freq * 0.5, t + dur);

    const env = ctx.createGain();
    env.gain.setValueAtTime(0, t);
    env.gain.linearRampToValueAtTime(0.10, t + 0.005);
    env.gain.exponentialRampToValueAtTime(0.001, t + dur);

    osc.connect(env);
    env.connect(masterOut!);
    osc.start(t);
    osc.stop(t + dur + 0.01);
  }

  // --- Wind Chimes: gentle pentatonic metallic tones ---
  function playChime() {
    const ctx = ensureAudioCtx();
    const t = ctx.currentTime;
    const volume = 0.08 + Math.random() * 0.10;
    const pentatonic = [261.6, 293.7, 329.6, 392.0, 440.0, 523.3, 587.3, 659.3, 784.0, 880.0];
    const baseFreq = pentatonic[Math.floor(Math.random() * pentatonic.length)];
    const detune = (Math.random() - 0.5) * 10;
    const decay = 0.3 + Math.random() * 0.3;

    const osc = ctx.createOscillator();
    osc.type = "sine";
    osc.frequency.value = baseFreq;
    osc.detune.value = detune;
    const env = ctx.createGain();
    env.gain.setValueAtTime(volume, t);
    env.gain.exponentialRampToValueAtTime(0.001, t + decay);
    osc.connect(env); env.connect(masterOut!);
    osc.start(t); osc.stop(t + decay + 0.02);

    const harm2 = ctx.createOscillator();
    harm2.type = "sine";
    harm2.frequency.value = baseFreq * 2.01;
    harm2.detune.value = detune + (Math.random() - 0.5) * 6;
    const env2 = ctx.createGain();
    env2.gain.setValueAtTime(volume * 0.3, t);
    env2.gain.exponentialRampToValueAtTime(0.001, t + decay * 0.7);
    harm2.connect(env2); env2.connect(masterOut!);
    harm2.start(t); harm2.stop(t + decay * 0.7 + 0.02);

    if (Math.random() < 0.5) {
      const harm3 = ctx.createOscillator();
      harm3.type = "sine";
      harm3.frequency.value = baseFreq * 3.02;
      const env3 = ctx.createGain();
      env3.gain.setValueAtTime(volume * 0.12, t);
      env3.gain.exponentialRampToValueAtTime(0.001, t + decay * 0.4);
      harm3.connect(env3); env3.connect(masterOut!);
      harm3.start(t); harm3.stop(t + decay * 0.4 + 0.02);
    }
  }

  // --- Heartbeat: warm double-pulse bass ---
  function playHeartbeat() {
    const ctx = ensureAudioCtx();
    const t = ctx.currentTime;
    const volume = 0.15 + Math.random() * 0.10;
    const baseFreq = 50 + Math.random() * 20;

    for (let i = 0; i < 2; i++) {
      const offset = i * (0.08 + Math.random() * 0.03);
      const dur = i === 0 ? 0.08 : 0.06;
      const vol = i === 0 ? volume : volume * 0.7;
      const osc = ctx.createOscillator();
      osc.type = "sine";
      osc.frequency.setValueAtTime(baseFreq, t + offset);
      osc.frequency.exponentialRampToValueAtTime(baseFreq * 0.6, t + offset + dur);
      const env = ctx.createGain();
      env.gain.setValueAtTime(0.001, t + offset);
      env.gain.linearRampToValueAtTime(vol, t + offset + 0.008);
      env.gain.exponentialRampToValueAtTime(0.001, t + offset + dur);
      osc.connect(env); env.connect(masterOut!);
      osc.start(t + offset); osc.stop(t + offset + dur + 0.02);
    }
  }

  function toggleSound() {
    const idx = SOUND_THEMES.indexOf(soundTheme);
    soundTheme = SOUND_THEMES[(idx + 1) % SOUND_THEMES.length];
    if (soundTheme !== "off") ensureAudioCtx();
  }

  // Set of nodes to highlight (hovered node + all connected neighbors)
  let highlightedNodes = new Set<string>();

  // Collect all descendant nodes (children) from a given node
  // In our graph structure: user -> sensors -> attributes
  function collectDescendants(nodeId: string, collected: Set<string>) {
    if (!graph) return;

    // Get all outgoing edges (children)
    const outEdges = graph.outEdges(nodeId);
    for (const edge of outEdges) {
      const target = graph.target(edge);
      if (!collected.has(target)) {
        collected.add(target);
        collectDescendants(target, collected);
      }
    }

    // Also collect parent nodes going upward (for context)
    const inEdges = graph.inEdges(nodeId);
    for (const edge of inEdges) {
      const source = graph.source(edge);
      if (!collected.has(source)) {
        collected.add(source);
      }
    }
  }

  // ── Season Color Theme System ───────────────────────────────────────
  type Season = "spring" | "summer" | "autumn" | "winter" | "rainbow";

  interface SeasonTheme {
    name: string;
    icon: string;
    nodes: { room: string; user: string; sensor: string; attribute: string };
    attrs: { heartrate: string; battery: string; location: string; imu: string };
    glow: {
      data: { core: [number,number,number]; mid: [number,number,number]; wisp: [number,number,number] };
      attention: { core: [number,number,number]; mid: [number,number,number]; wisp: [number,number,number] };
      heartbeat: { core: [number,number,number]; mid: [number,number,number]; wisp: [number,number,number] };
      connect: { core: [number,number,number]; mid: [number,number,number]; wisp: [number,number,number] };
      disconnect: { core: [number,number,number]; mid: [number,number,number]; wisp: [number,number,number] };
    };
    heatmap: [string, string, string, string, string]; // idle, low, medium, high, intense
    attention_levels: [string, string, string, string]; // high, medium, low, none
    selectedEdge: string;
  }

  const SEASON_THEMES: Record<Season, SeasonTheme> = {
    spring: {
      name: "Spring", icon: "🌸",
      nodes: { room: "#2d8a4e", user: "#a8e6a0", sensor: "#ff69b4", attribute: "#7ecf7e" },
      attrs: { heartrate: "#ff4d88", battery: "#ffe040", location: "#3cb371", imu: "#da70d6" },
      glow: {
        data:       { core: [140, 255, 160], mid: [80, 230, 110], wisp: [110, 245, 135] },
        attention:  { core: [255, 200, 230], mid: [255, 150, 200], wisp: [255, 175, 215] },
        heartbeat:  { core: [255, 120, 180], mid: [240, 80, 150], wisp: [250, 100, 165] },
        connect:    { core: [100, 255, 150], mid: [50, 230, 100], wisp: [75, 245, 125] },
        disconnect: { core: [255, 240, 100], mid: [245, 220, 60], wisp: [250, 230, 80] },
      },
      heatmap: ["#1a3a2a", "#2d8a4e", "#5cc870", "#ff69b4", "#ff1493"],
      attention_levels: ["#ff69b4", "#5cc870", "#2d8a4e", "#1a3a2a"],
      selectedEdge: "#90ee90",
    },
    summer: {
      name: "Summer", icon: "☀️",
      nodes: { room: "#2d8a8a", user: "#e8d5a0", sensor: "#f09030", attribute: "#6cb4d8" },
      attrs: { heartrate: "#e84040", battery: "#f5c030", location: "#20b2aa", imu: "#9370db" },
      glow: {
        data:       { core: [255, 240, 200], mid: [250, 210, 150], wisp: [255, 225, 175] },
        attention:  { core: [255, 250, 230], mid: [255, 235, 195], wisp: [255, 242, 210] },
        heartbeat:  { core: [255, 140, 140], mid: [240, 90, 90],   wisp: [250, 115, 115] },
        connect:    { core: [150, 240, 220], mid: [50, 210, 190],  wisp: [100, 225, 205] },
        disconnect: { core: [255, 220, 130], mid: [245, 185, 60],  wisp: [250, 200, 100] },
      },
      heatmap: ["#334155", "#2d8a8a", "#d4a030", "#f09030", "#e84040"],
      attention_levels: ["#f5c030", "#d4a030", "#2d8a8a", "#374151"],
      selectedEdge: "#fcd9a0",
    },
    autumn: {
      name: "Autumn", icon: "🍂",
      nodes: { room: "#8b5e3c", user: "#d4a870", sensor: "#cc6633", attribute: "#a07050" },
      attrs: { heartrate: "#c44040", battery: "#d4a030", location: "#6b8e6b", imu: "#8b6090" },
      glow: {
        data:       { core: [255, 210, 160], mid: [230, 170, 110], wisp: [245, 190, 135] },
        attention:  { core: [255, 235, 200], mid: [240, 210, 165], wisp: [248, 222, 180] },
        heartbeat:  { core: [230, 140, 120], mid: [210, 100, 80],  wisp: [220, 120, 100] },
        connect:    { core: [160, 210, 160], mid: [100, 180, 110], wisp: [130, 195, 135] },
        disconnect: { core: [230, 190, 120], mid: [210, 160, 70],  wisp: [220, 175, 95] },
      },
      heatmap: ["#334155", "#6b5b3c", "#a07040", "#cc6633", "#c44040"],
      attention_levels: ["#d4a030", "#b08030", "#6b5b3c", "#374151"],
      selectedEdge: "#e8c090",
    },
    winter: {
      name: "Winter", icon: "❄️",
      nodes: { room: "#5a7d9a", user: "#c8d8e4", sensor: "#4ca6c9", attribute: "#7b9ab8" },
      attrs: { heartrate: "#d47090", battery: "#c8b870", location: "#50b0a0", imu: "#8080c0" },
      glow: {
        data:       { core: [200, 230, 255], mid: [160, 205, 250], wisp: [180, 218, 252] },
        attention:  { core: [230, 245, 255], mid: [200, 225, 250], wisp: [215, 235, 252] },
        heartbeat:  { core: [220, 160, 190], mid: [200, 120, 160], wisp: [210, 140, 175] },
        connect:    { core: [170, 230, 220], mid: [110, 210, 200], wisp: [140, 220, 210] },
        disconnect: { core: [210, 210, 230], mid: [180, 180, 210], wisp: [195, 195, 220] },
      },
      heatmap: ["#334155", "#4a6a8a", "#5090b0", "#4ca6c9", "#d47090"],
      attention_levels: ["#4ca6c9", "#5a7d9a", "#4a5a6a", "#374151"],
      selectedEdge: "#a0d0e8",
    },
    rainbow: {
      name: "Rainbow", icon: "🌈",
      nodes: { room: "#3b82f6", user: "#22c55e", sensor: "#f97316", attribute: "#8b5cf6" },
      attrs: { heartrate: "#ef4444", battery: "#eab308", location: "#06b6d4", imu: "#a78bfa" },
      glow: {
        data:       { core: [180, 255, 210], mid: [34, 197, 94],   wisp: [120, 230, 170] },
        attention:  { core: [255, 220, 180], mid: [250, 180, 120], wisp: [252, 200, 150] },
        heartbeat:  { core: [255, 100, 100], mid: [239, 68, 68],   wisp: [248, 84, 84] },
        connect:    { core: [100, 220, 255], mid: [6, 182, 212],   wisp: [50, 200, 235] },
        disconnect: { core: [255, 200, 80],  mid: [234, 179, 8],   wisp: [245, 190, 44] },
      },
      heatmap: ["#334155", "#22c55e", "#eab308", "#f97316", "#ef4444"],
      attention_levels: ["#ef4444", "#eab308", "#22c55e", "#374151"],
      selectedEdge: "#34d399",
    },
  };

  function detectCETSeason(): Season {
    // CET/CEST timezone month determines season
    const cetDate = new Date(new Date().toLocaleString("en-US", { timeZone: "Europe/Berlin" }));
    const month = cetDate.getMonth(); // 0-11
    if (month >= 2 && month <= 4) return "spring";
    if (month >= 5 && month <= 7) return "summer";
    if (month >= 8 && month <= 10) return "autumn";
    return "winter";
  }

  function loadSavedSeason(): Season {
    try {
      const saved = localStorage.getItem("sensocto_graph_season");
      if (saved && saved in SEASON_THEMES) return saved as Season;
    } catch (_) {}
    return detectCETSeason();
  }

  let currentSeason = $state<Season>(loadSavedSeason());
  function getTheme(): SeasonTheme { return SEASON_THEMES[currentSeason]; }

  // Reactive nodeColors that updates with season
  let nodeColors = $derived(getTheme().nodes);

  function getAttrColor(attrType: string | undefined, attrId: string | undefined): string {
    const t = getTheme().attrs;
    if (attrType === "heartrate" || attrId?.includes("heart")) return t.heartrate;
    if (attrType === "battery") return t.battery;
    if (attrType === "location" || attrId?.includes("geo")) return t.location;
    if (attrType === "imu" || attrId?.includes("accelero")) return t.imu;
    return getTheme().nodes.attribute;
  }

  function switchSeason(season: Season) {
    currentSeason = season;
    try { localStorage.setItem("sensocto_graph_season", season); } catch (_) {}
    // Recolor all nodes in the graph
    if (!graph) return;
    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "attribute") {
        graph.setNodeAttribute(node, "color", getAttrColor(attrs.data?.attribute_type, attrs.data?.attribute_id));
      } else if (attrs.nodeType) {
        const nc = getTheme().nodes;
        graph.setNodeAttribute(node, "color", nc[attrs.nodeType as keyof typeof nc] || "#6b7280");
      }
    });
    scheduleRefresh();
  }

  // Base node sizes (will be scaled based on graph size)
  const baseNodeSizes = {
    room: 16,
    user: 12,
    sensor: 8,
    attribute: 4
  };

  let scaledNodeSizes = $state({ ...baseNodeSizes });

  function calculateNodeScale(nodeCount: number): number {
    if (nodeCount <= 30) return 1.4;
    if (nodeCount <= 80) return 1.1;
    if (nodeCount <= 200) return 0.85;
    if (nodeCount <= 500) return 0.7;
    if (nodeCount <= 1000) return 0.55;
    return 0.4;
  }

  // Slight random variation for organic feel (±15%)
  function jitterSize(base: number): number {
    return base * (0.85 + Math.random() * 0.3);
  }

  // Random curvature for organic edge feel
  function randomCurvature(): number {
    const sign = Math.random() > 0.5 ? 1 : -1;
    return sign * (0.15 + Math.random() * 0.35);
  }

  function buildGraph() {
    graph = new Graph();

    // First, estimate total node count to calculate scale
    let estimatedNodeCount = rooms.length + users.length;
    for (const sensor of Object.values(sensors)) {
      estimatedNodeCount += 1; // sensor node
      estimatedNodeCount += Object.keys(sensor.attributes || {}).length; // attribute nodes
    }

    // Calculate and apply scale factor
    const scale = calculateNodeScale(estimatedNodeCount);
    scaledNodeSizes = {
      room: baseNodeSizes.room * scale,
      user: baseNodeSizes.user * scale,
      sensor: baseNodeSizes.sensor * scale,
      attribute: baseNodeSizes.attribute * scale
    };

    // Add room nodes
    for (const room of rooms) {
      graph.addNode(`room:${room.id}`, {
        label: room.name,
        size: jitterSize(scaledNodeSizes.room),
        color: nodeColors.room,
        nodeType: "room",
        data: room,
        x: Math.random() * 100,
        y: Math.random() * 100
      });
    }

    // Add user/connector nodes
    for (const user of users) {
      graph.addNode(`user:${user.connector_id}`, {
        label: user.connector_name,
        size: jitterSize(scaledNodeSizes.user + Math.min(user.sensor_count * scale, 8 * scale)),
        color: nodeColors.user,
        nodeType: "user",
        data: user,
        x: Math.random() * 100,
        y: Math.random() * 100
      });
    }

    // Add sensor nodes and edges
    for (const [sensorId, sensor] of Object.entries(sensors)) {
      const sensorNodeId = `sensor:${sensorId}`;
      const attrCount = Object.keys(sensor.attributes || {}).length;

      graph.addNode(sensorNodeId, {
        label: sensor.sensor_name || sensorId.substring(0, 12),
        size: jitterSize(scaledNodeSizes.sensor + Math.min(attrCount * 1.5 * scale, 6 * scale)),
        color: nodeColors.sensor,
        nodeType: "sensor",
        data: sensor,
        x: Math.random() * 100,
        y: Math.random() * 100
      });

      // Connect sensor to its user/connector
      const userNodeId = `user:${sensor.connector_id}`;
      if (graph.hasNode(userNodeId)) {
        graph.addEdge(userNodeId, sensorNodeId, {
          size: Math.max(0.3, 0.7 * scale),
          color: "rgba(55, 65, 81, 0.35)",
          curvature: randomCurvature()
        });
      }

      // Add attribute nodes
      for (const [attrId, attr] of Object.entries(sensor.attributes || {})) {
        const attrNodeId = `attr:${sensorId}:${attrId}`;
        const attrLabel = attr.attribute_name || attr.attribute_id;

        // Color attributes by type
        const attrColor = getAttrColor(attr.attribute_type, attr.attribute_id);

        graph.addNode(attrNodeId, {
          label: attrLabel,
          size: jitterSize(scaledNodeSizes.attribute),
          color: attrColor,
          nodeType: "attribute",
          data: { ...attr, sensor_id: sensorId },
          x: Math.random() * 100,
          y: Math.random() * 100
        });

        graph.addEdge(sensorNodeId, attrNodeId, {
          size: Math.max(0.2, 0.4 * scale),
          color: "rgba(55, 65, 81, 0.25)",
          curvature: randomCurvature()
        });
      }
    }

    // Connect rooms to sensors if we have room data with sensor connections
    // (This would require additional data from the backend)
  }

  function zoomToRandomDetail() {
    if (!sigma || !graph || graph.order === 0) return;
    const camera = sigma.getCamera();
    const nodes = graph.nodes();
    const target = nodes[Math.floor(Math.random() * nodes.length)];
    const pos = sigma.getNodeDisplayData(target);
    if (!pos) return;
    const center = sigma.viewportToFramedGraph(sigma.graphToViewport(pos));
    camera.setState({ x: center.x, y: center.y, ratio: 0.35, angle: 0 });
  }

  function runLayout() {
    if (!graph || graph.order === 0) return;

    const nodeCount = graph.order;

    // For small graphs or when worker isn't available, use sync fallback
    if (nodeCount < 50) {
      runLayoutSync();
      return;
    }

    // Stop any existing worker
    if (fa2Worker) {
      fa2Worker.stop();
      fa2Worker.kill();
      fa2Worker = null;
    }

    isLayoutRunning = true;

    try {
      fa2Worker = new FA2Layout(graph, {
        settings: {
          gravity: 0.3,
          scalingRatio: nodeCount > 300 ? 20 : 12,
          strongGravityMode: false,
          barnesHutOptimize: nodeCount > 100,
          barnesHutTheta: 0.6,
          linLogMode: true,
          adjustSizes: true,
          edgeWeightInfluence: 1,
          slowDown: 2
        }
      });

      fa2Worker.start();

      // Auto-stop after a duration proportional to graph size
      const duration = nodeCount > 500 ? 3000 : nodeCount > 200 ? 2000 : 1500;
      setTimeout(() => {
        if (fa2Worker) {
          fa2Worker.stop();
          fa2Worker.kill();
          fa2Worker = null;
        }
        isLayoutRunning = false;
        sigma?.refresh();
        if (compact) {
          setTimeout(() => zoomToRandomDetail(), 50);
        }
      }, duration);
    } catch (e) {
      console.warn("FA2 Worker failed, falling back to sync:", e);
      runLayoutSync();
    }
  }

  // Synchronous fallback for small graphs or when worker fails
  function runLayoutSync() {
    if (!graph || graph.order === 0) return;
    isLayoutRunning = true;

    const nodeCount = graph.order;
    const iterations = nodeCount > 500 ? 200 : nodeCount > 200 ? 150 : 120;

    forceAtlas2.assign(graph, {
      iterations,
      settings: {
        gravity: 0.3,
        scalingRatio: nodeCount > 300 ? 20 : 12,
        strongGravityMode: false,
        barnesHutOptimize: nodeCount > 100,
        barnesHutTheta: 0.6,
        linLogMode: true,
        adjustSizes: true,
        edgeWeightInfluence: 1,
        slowDown: 2
      }
    });

    sigma?.refresh();
    if (compact) {
      setTimeout(() => zoomToRandomDetail(), 50);
    }
    isLayoutRunning = false;
  }

  function initSigma() {
    if (!container || !graph) return;

    // Clear any existing sigma instance
    if (sigma) {
      sigma.kill();
    }

    // Calculate scale-aware settings
    const scale = scaledNodeSizes.sensor / baseNodeSizes.sensor;
    const labelThreshold = Math.max(2, 4 * scale);
    const labelSize = Math.max(8, Math.round(12 * scale));

    // Temporarily inject preserveDrawingBuffer:true for export support
    const origGetContext = HTMLCanvasElement.prototype.getContext;
    HTMLCanvasElement.prototype.getContext = function(type: string, opts?: any) {
      if (type === "webgl2" || type === "webgl" || type === "experimental-webgl") {
        opts = { ...opts, preserveDrawingBuffer: true };
      }
      return origGetContext.call(this, type, opts);
    } as any;

    sigma = new Sigma(graph, container, {
      renderLabels: !compact,
      labelRenderedSizeThreshold: labelThreshold,
      labelFont: "Inter, system-ui, sans-serif",
      labelSize: labelSize,
      labelWeight: "500",
      labelColor: { color: "#e5e7eb" },
      defaultNodeColor: "#6b7280",
      defaultEdgeColor: "rgba(55, 65, 81, 0.3)",
      defaultEdgeType: "curved",
      edgeProgramClasses: {
        curved: EdgeCurveProgram
      },
      allowInvalidContainer: true,
      labelDensity: scale < 0.7 ? 0.5 : 1,
      minCameraRatio: 0.1,
      maxCameraRatio: 10,
      // Node reducer: LOD + highlight dimming
      nodeReducer: (node, data) => {
        // LOD: hide attribute nodes when zoomed out
        if (!lodAttributesVisible && data.nodeType === "attribute") {
          return { ...data, hidden: true };
        }
        if (highlightedNodes.size === 0) {
          return data;
        }
        if (highlightedNodes.has(node)) {
          return { ...data, zIndex: 1 };
        }
        return {
          ...data,
          color: "rgba(45, 55, 72, 0.3)",
          zIndex: 0
        };
      },
      edgeReducer: (edge, data) => {
        // LOD: hide edges to hidden attribute nodes
        if (!lodAttributesVisible) {
          const target = graph.target(edge);
          const targetAttrs = graph.getNodeAttributes(target);
          if (targetAttrs.nodeType === "attribute") {
            return { ...data, hidden: true };
          }
        }
        if (highlightedNodes.size === 0) {
          return data;
        }
        const source = graph.source(edge);
        const target = graph.target(edge);
        if (highlightedNodes.has(source) && highlightedNodes.has(target)) {
          return { ...data, color: getTheme().selectedEdge, size: (data.size || 0.5) * 1.5, zIndex: 1 };
        }
        return {
          ...data,
          color: "rgba(55, 65, 81, 0.4)",
          zIndex: 0
        };
      }
    });

    // Restore original getContext
    HTMLCanvasElement.prototype.getContext = origGetContext;

    // Track mouse position for hover tooltip
    container.addEventListener("mousemove", (e: MouseEvent) => {
      mouseX = e.clientX;
      mouseY = e.clientY;
    });

    // Handle node hover - highlight connected subgraph + boost attention
    sigma.on("enterNode", ({ node }) => {
      hoveredNode = node;
      const attrs = graph.getNodeAttributes(node);
      hoverDetails = {
        id: node,
        label: attrs.label,
        type: attrs.nodeType,
        data: attrs.data
      };
      document.body.style.cursor = "pointer";

      highlightedNodes = new Set([node]);
      collectDescendants(node, highlightedNodes);
      sigma?.refresh();

      // Boost attention for hovered sensor (or parent sensor of attribute)
      const sensorId = attrs.nodeType === "sensor" ? attrs.data?.sensor_id
        : attrs.nodeType === "attribute" ? attrs.data?.sensor_id : null;
      if (sensorId) {
        window.dispatchEvent(new CustomEvent("graph-hover-sensor", {
          detail: { sensor_id: sensorId, action: "enter" }
        }));
      }
    });

    sigma.on("leaveNode", ({ node }) => {
      const attrs = graph.getNodeAttributes(node);
      document.body.style.cursor = "default";
      hoveredNode = null;
      hoverDetails = null;

      if (selectedNode) {
        highlightedNodes = new Set([selectedNode]);
        collectDescendants(selectedNode, highlightedNodes);
      } else {
        highlightedNodes = new Set();
      }
      sigma?.refresh();

      // Release attention boost
      const sensorId = attrs.nodeType === "sensor" ? attrs.data?.sensor_id
        : attrs.nodeType === "attribute" ? attrs.data?.sensor_id : null;
      if (sensorId) {
        window.dispatchEvent(new CustomEvent("graph-hover-sensor", {
          detail: { sensor_id: sensorId, action: "leave" }
        }));
      }
    });

    // Handle node click - persist selection in bottom bar
    sigma.on("clickNode", ({ node }) => {
      if (selectedNode === node) {
        selectedNode = null;
        selectedDetails = null;
        highlightedNodes = new Set();
      } else {
        selectedNode = node;
        const attrs = graph.getNodeAttributes(node);
        selectedDetails = {
          id: node,
          label: attrs.label,
          type: attrs.nodeType,
          data: attrs.data
        };
        highlightedNodes = new Set([node]);
        collectDescendants(node, highlightedNodes);
      }
      sigma?.refresh();
    });

    // Handle background click to deselect and close mobile controls
    sigma.on("clickStage", () => {
      selectedNode = null;
      selectedDetails = null;
      highlightedNodes = new Set();
      leftBarOpen = false;
      rightBarOpen = false;
      sigma?.refresh();
    });

    // LOD: toggle attribute visibility based on zoom level
    sigma.getCamera().on("updated", (state) => {
      const shouldShow = graph.order < LOD_MIN_NODES || state.ratio < LOD_ZOOM_THRESHOLD;
      if (shouldShow !== lodAttributesVisible) {
        lodAttributesVisible = shouldShow;
        sigma?.refresh();
      }
    });

    // Run initial layout
    runLayout();
  }

  function handleZoomIn() {
    if (sigma) {
      const camera = sigma.getCamera();
      camera.animatedZoom({ duration: 200 });
    }
  }

  function handleZoomOut() {
    if (sigma) {
      const camera = sigma.getCamera();
      camera.animatedUnzoom({ duration: 200 });
    }
  }

  function handleRelayout() {
    handleRelayoutForMode();
  }

  function handleFullscreen() {
    isFullscreen = !isFullscreen;
    setTimeout(() => sigma?.refresh(), 50);
  }

  // ── Mode Switching ──────────────────────────────────────────────

  // Smoothly animate all node positions from current to target over duration ms
  function animateNodePositions(targetPositions: Map<string, {x: number; y: number}>, duration: number = 400) {
    if (!graph || !sigma) return;

    const startPositions = new Map<string, {x: number; y: number}>();
    graph.forEachNode((node) => {
      startPositions.set(node, {
        x: graph.getNodeAttribute(node, "x"),
        y: graph.getNodeAttribute(node, "y")
      });
    });

    const startTime = performance.now();

    function tick() {
      const elapsed = performance.now() - startTime;
      const progress = Math.min(elapsed / duration, 1);
      // Ease-out cubic for smooth deceleration
      const t = 1 - Math.pow(1 - progress, 3);

      graph.forEachNode((node) => {
        const start = startPositions.get(node);
        const target = targetPositions.get(node);
        if (start && target) {
          graph.setNodeAttribute(node, "x", start.x + (target.x - start.x) * t);
          graph.setNodeAttribute(node, "y", start.y + (target.y - start.y) * t);
        }
      });

      sigma?.refresh();

      if (progress < 1) {
        requestAnimationFrame(tick);
      }
    }

    requestAnimationFrame(tick);
  }

  // Capture all current node positions from the graph
  function capturePositions(): Map<string, {x: number; y: number}> {
    const positions = new Map<string, {x: number; y: number}>();
    if (!graph) return positions;
    graph.forEachNode((node) => {
      positions.set(node, {
        x: graph.getNodeAttribute(node, "x"),
        y: graph.getNodeAttribute(node, "y")
      });
    });
    return positions;
  }

  function switchViewMode(newMode: ViewMode) {
    if (viewMode === newMode || isTransitioning) return;

    isTransitioning = true;
    const oldMode = viewMode;
    viewMode = newMode;

    // Cleanup old mode's timers/animations
    cleanupMode(oldMode);

    // Track which layout was last applied
    if (layoutModes.includes(newMode)) {
      lastLayoutMode = newMode;
    }

    // For visual modes, re-apply the last layout first to get clean positions
    if (visualModes.includes(newMode) && visualModes.includes(oldMode)) {
      applyLayout(lastLayoutMode);
    }

    // For layout mode switches, animate the transition
    if (layoutModes.includes(newMode)) {
      applyLayout(newMode, true);
    } else {
      applyViewMode(newMode);
    }

    setTimeout(() => { isTransitioning = false; }, 600);
  }

  function applyLayout(mode: ViewMode, animate: boolean = false) {
    if (!graph || graph.order === 0) return;

    const oldPositions = animate ? capturePositions() : null;

    switch (mode) {
      // Use sync layout when animating so positions are available immediately
      case "topology":     animate ? runLayoutSync() : runLayout(); break;
      case "per-user":     layoutPerUser(); break;
      case "per-type":     layoutPerType(); break;
      case "radial":       layoutRadialTree(); break;
      case "constellation": layoutConstellation(); break;
      case "flower":        layoutFlower(); break;
    }

    if (animate && oldPositions) {
      const targetPositions = capturePositions();
      // Restore old positions, then animate to new
      for (const [node, pos] of oldPositions) {
        if (graph.hasNode(node)) {
          graph.setNodeAttribute(node, "x", pos.x);
          graph.setNodeAttribute(node, "y", pos.y);
        }
      }
      animateNodePositions(targetPositions, 500);
    }
  }

  function applyViewMode(mode: ViewMode) {
    if (!graph) return;

    if (layoutModes.includes(mode)) {
      applyLayout(mode);
    }

    // Start overlay-specific systems
    switch (mode) {
      case "heatmap":    startActivityHeatmap(); break;
      case "freshness":  startFreshnessDecay(); break;
      case "heartbeat":  startHeartbeatSync(); break;
      case "river":      startDataRiver(); break;
      case "attention":  startAttentionRadar(); break;
    }

    // Restore normal appearance for layout-only modes
    if (layoutModes.includes(mode)) {
      restoreNodeAppearances();
    }

    sigma?.refresh();
  }

  function cleanupMode(mode: ViewMode) {
    switch (mode) {
      case "heatmap":    stopActivityHeatmap(); break;
      case "freshness":  stopFreshnessDecay(); break;
      case "heartbeat":  stopHeartbeatSync(); break;
      case "river":      stopDataRiver(); break;
      case "attention":  stopAttentionRadar(); break;
    }
  }

  function restoreNodeAppearances() {
    if (!graph) return;
    graph.forEachNode((node, attrs) => {
      const type = attrs.nodeType as keyof typeof nodeColors;
      const originalColor = getOriginalNodeColor(attrs);
      const baseSize = scaledNodeSizes[type] || 4;
      graph.setNodeAttribute(node, "color", originalColor);
      graph.setNodeAttribute(node, "size", jitterSize(baseSize));
    });
  }

  function getOriginalNodeColor(attrs: any): string {
    if (attrs.nodeType === "attribute") {
      return getAttrColor(attrs.data?.attribute_type, attrs.data?.attribute_id);
    }
    return nodeColors[attrs.nodeType as keyof typeof nodeColors] || "#6b7280";
  }

  // ── Layout: Per User Clusters ─────────────────────────────────

  function layoutPerUser() {
    if (!graph || graph.order === 0) return;
    isLayoutRunning = true;

    const userNodes: string[] = [];
    const sensorsByUser = new Map<string, string[]>();
    const attributesBySensor = new Map<string, string[]>();

    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "user") { userNodes.push(node); sensorsByUser.set(node, []); }
    });
    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "sensor") {
        const userNode = `user:${attrs.data.connector_id}`;
        sensorsByUser.get(userNode)?.push(node);
        attributesBySensor.set(node, []);
      }
    });
    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "attribute") {
        const sensorNode = `sensor:${attrs.data.sensor_id}`;
        attributesBySensor.get(sensorNode)?.push(node);
      }
    });

    const userCount = Math.max(userNodes.length, 1);
    const userRingR = Math.max(30, 20 * Math.sqrt(userCount));
    const cx = 50, cy = 50;

    userNodes.forEach((userNode, i) => {
      const angle = (i / userCount) * 2 * Math.PI - Math.PI / 2;
      const ux = cx + userRingR * Math.cos(angle);
      const uy = cy + userRingR * Math.sin(angle);
      graph.setNodeAttribute(userNode, "x", ux);
      graph.setNodeAttribute(userNode, "y", uy);

      const sensors = sensorsByUser.get(userNode) || [];
      const sCount = Math.max(sensors.length, 1);
      const sRingR = Math.max(6, 4 * Math.sqrt(sCount));

      sensors.forEach((sNode, si) => {
        const sAngle = (si / sCount) * 2 * Math.PI;
        const sx = ux + sRingR * Math.cos(sAngle);
        const sy = uy + sRingR * Math.sin(sAngle);
        graph.setNodeAttribute(sNode, "x", sx);
        graph.setNodeAttribute(sNode, "y", sy);

        const attrs = attributesBySensor.get(sNode) || [];
        const aCount = Math.max(attrs.length, 1);
        const aRingR = Math.max(2, 1.5 * Math.sqrt(aCount));

        attrs.forEach((aNode, ai) => {
          const aAngle = (ai / aCount) * 2 * Math.PI;
          graph.setNodeAttribute(aNode, "x", sx + aRingR * Math.cos(aAngle));
          graph.setNodeAttribute(aNode, "y", sy + aRingR * Math.sin(aAngle));
        });
      });
    });

    isLayoutRunning = false;
    sigma?.refresh();
  }

  // ── Layout: Per Attribute Type ────────────────────────────────

  function layoutPerType() {
    if (!graph || graph.order === 0) return;
    isLayoutRunning = true;

    const typeGroups = new Map<string, { sensors: Set<string>; attributes: string[] }>();
    const userNodes: string[] = [];

    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "user") userNodes.push(node);
      if (attrs.nodeType === "attribute") {
        const type = attrs.data?.attribute_type || "other";
        if (!typeGroups.has(type)) typeGroups.set(type, { sensors: new Set(), attributes: [] });
        typeGroups.get(type)!.attributes.push(node);
        typeGroups.get(type)!.sensors.add(`sensor:${attrs.data.sensor_id}`);
      }
    });

    const types = Array.from(typeGroups.keys()).sort();
    const colCount = Math.max(types.length, 1);
    const colWidth = 100 / (colCount + 1);

    // Users across top
    userNodes.forEach((node, i) => {
      graph.setNodeAttribute(node, "x", ((i + 1) / (userNodes.length + 1)) * 100);
      graph.setNodeAttribute(node, "y", 8);
    });

    // Each type in its column
    types.forEach((type, colIdx) => {
      const group = typeGroups.get(type)!;
      const colX = (colIdx + 1) * colWidth;
      const sensors = Array.from(group.sensors);

      sensors.forEach((sNode, si) => {
        if (graph.hasNode(sNode)) {
          graph.setNodeAttribute(sNode, "x", colX + (Math.random() - 0.5) * 4);
          graph.setNodeAttribute(sNode, "y", 25 + (si / Math.max(sensors.length, 1)) * 40);
        }
      });

      group.attributes.forEach((aNode, ai) => {
        graph.setNodeAttribute(aNode, "x", colX + (Math.random() - 0.5) * 6);
        graph.setNodeAttribute(aNode, "y", 30 + (ai / Math.max(group.attributes.length, 1)) * 55);
      });
    });

    isLayoutRunning = false;
    sigma?.refresh();
  }

  // ── Layout: Radial Tree ───────────────────────────────────────

  function layoutRadialTree() {
    if (!graph || graph.order === 0) return;
    isLayoutRunning = true;

    const cx = 50, cy = 50;
    const rings = { user: 15, sensor: 35, attribute: 55 };
    const nodesByType: Record<string, string[]> = { user: [], sensor: [], attribute: [] };

    graph.forEachNode((node, attrs) => {
      const t = attrs.nodeType;
      if (t && nodesByType[t]) nodesByType[t].push(node);
    });

    // Users in inner ring
    const uCount = Math.max(nodesByType.user.length, 1);
    nodesByType.user.forEach((node, i) => {
      const a = (i / uCount) * 2 * Math.PI - Math.PI / 2;
      graph.setNodeAttribute(node, "x", cx + rings.user * Math.cos(a));
      graph.setNodeAttribute(node, "y", cy + rings.user * Math.sin(a));
    });

    // Sensors in middle ring — angular position near parent user
    // Group sensors by user to distribute evenly within each user's arc
    const sensorsByUser = new Map<string, string[]>();
    nodesByType.sensor.forEach(node => {
      const attrs = graph.getNodeAttributes(node);
      const uKey = `user:${attrs.data.connector_id}`;
      if (!sensorsByUser.has(uKey)) sensorsByUser.set(uKey, []);
      sensorsByUser.get(uKey)!.push(node);
    });

    let sensorIdx = 0;
    const totalSensors = nodesByType.sensor.length || 1;
    sensorsByUser.forEach((sensors, userNode) => {
      let userAngle = 0;
      if (graph.hasNode(userNode)) {
        const ua = graph.getNodeAttributes(userNode);
        userAngle = Math.atan2(ua.y - cy, ua.x - cx);
      }
      const arcSpan = (sensors.length / totalSensors) * 2 * Math.PI;
      sensors.forEach((sNode, si) => {
        const a = userAngle - arcSpan / 2 + (si / Math.max(sensors.length, 1)) * arcSpan;
        graph.setNodeAttribute(sNode, "x", cx + rings.sensor * Math.cos(a));
        graph.setNodeAttribute(sNode, "y", cy + rings.sensor * Math.sin(a));
        sensorIdx++;
      });
    });

    // Attributes in outer ring — near parent sensor
    const attrsBySensor = new Map<string, string[]>();
    nodesByType.attribute.forEach(node => {
      const attrs = graph.getNodeAttributes(node);
      const sKey = `sensor:${attrs.data.sensor_id}`;
      if (!attrsBySensor.has(sKey)) attrsBySensor.set(sKey, []);
      attrsBySensor.get(sKey)!.push(node);
    });

    attrsBySensor.forEach((attrs, sensorNode) => {
      let sAngle = 0;
      if (graph.hasNode(sensorNode)) {
        const sa = graph.getNodeAttributes(sensorNode);
        sAngle = Math.atan2(sa.y - cy, sa.x - cx);
      }
      const spread = Math.min(0.3, (attrs.length / 20) * Math.PI);
      attrs.forEach((aNode, ai) => {
        const a = sAngle - spread / 2 + (ai / Math.max(attrs.length, 1)) * spread;
        graph.setNodeAttribute(aNode, "x", cx + rings.attribute * Math.cos(a));
        graph.setNodeAttribute(aNode, "y", cy + rings.attribute * Math.sin(a));
      });
    });

    isLayoutRunning = false;
    sigma?.refresh();
  }

  // ── Layout: Constellation ─────────────────────────────────────

  function layoutConstellation() {
    if (!graph || graph.order === 0) return;
    isLayoutRunning = true;

    const userEntries: Array<{node: string; sensors: string[]}> = [];
    const attrsBySensor = new Map<string, string[]>();

    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "user") userEntries.push({node, sensors: []});
    });
    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "sensor") {
        const entry = userEntries.find(u => u.node === `user:${attrs.data.connector_id}`);
        if (entry) entry.sensors.push(node);
        attrsBySensor.set(node, []);
      }
    });
    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "attribute") {
        const sNode = `sensor:${attrs.data.sensor_id}`;
        attrsBySensor.get(sNode)?.push(node);
      }
    });

    const gridSize = Math.max(1, Math.ceil(Math.sqrt(userEntries.length)));
    const cellW = 100 / gridSize;
    const cellH = 100 / gridSize;

    userEntries.forEach((entry, idx) => {
      const row = Math.floor(idx / gridSize);
      const col = idx % gridSize;
      const cx = (col + 0.5) * cellW;
      const cy = (row + 0.5) * cellH;

      graph.setNodeAttribute(entry.node, "x", cx);
      graph.setNodeAttribute(entry.node, "y", cy);

      const sCount = Math.max(entry.sensors.length, 1);
      const polyR = Math.min(cellW, cellH) * 0.3;

      entry.sensors.forEach((sNode, si) => {
        const angle = (si / sCount) * 2 * Math.PI - Math.PI / 2;
        const sx = cx + polyR * Math.cos(angle);
        const sy = cy + polyR * Math.sin(angle);
        graph.setNodeAttribute(sNode, "x", sx);
        graph.setNodeAttribute(sNode, "y", sy);

        const attrs = attrsBySensor.get(sNode) || [];
        const aR = polyR * 0.25;
        attrs.forEach((aNode, ai) => {
          const aAngle = (ai / Math.max(attrs.length, 1)) * 2 * Math.PI;
          graph.setNodeAttribute(aNode, "x", sx + aR * Math.cos(aAngle));
          graph.setNodeAttribute(aNode, "y", sy + aR * Math.sin(aAngle));
        });
      });
    });

    isLayoutRunning = false;
    sigma?.refresh();
  }

  // ── Layout: Flower (Rose Curve) ─────────────────────────────────

  function layoutFlower() {
    if (!graph || graph.order === 0) return;
    isLayoutRunning = true;

    const cx = 50, cy = 50;
    const maxR = 42;

    // Collect all nodes by type
    const userNodes: string[] = [];
    const sensorNodes: string[] = [];
    const attrNodes: string[] = [];
    const attrsBySensor = new Map<string, string[]>();

    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "user") userNodes.push(node);
      else if (attrs.nodeType === "sensor") { sensorNodes.push(node); attrsBySensor.set(node, []); }
      else if (attrs.nodeType === "attribute") attrNodes.push(node);
    });
    graph.forEachNode((node, attrs) => {
      if (attrs.nodeType === "attribute") {
        const sKey = `sensor:${attrs.data.sensor_id}`;
        attrsBySensor.get(sKey)?.push(node);
      }
    });

    // Flatten: each "item" is a sensor + its attributes (one unit per petal slot)
    type Item = { sensor: string; attrs: string[] };
    const items: Item[] = sensorNodes.map(s => ({ sensor: s, attrs: attrsBySensor.get(s) || [] }));

    // Choose petal count: use number of users (min 5, max 12) for visual balance
    const petalCount = Math.max(5, Math.min(12, userNodes.length || 5));
    const petalAngle = (2 * Math.PI) / petalCount;

    // Distribute items evenly across petals (round-robin)
    const petals: Item[][] = Array.from({length: petalCount}, () => []);
    items.forEach((item, i) => {
      petals[i % petalCount].push(item);
    });

    // Find the max items in any petal (all petals will use this for spacing)
    const maxPerPetal = Math.max(1, ...petals.map(p => p.length));

    // Place user nodes at the flower center
    const userR = Math.min(5, maxR * 0.1);
    userNodes.forEach((node, i) => {
      const a = (i / Math.max(userNodes.length, 1)) * 2 * Math.PI - Math.PI / 2;
      graph.setNodeAttribute(node, "x", cx + userR * Math.cos(a));
      graph.setNodeAttribute(node, "y", cy + userR * Math.sin(a));
    });

    // Place items in each petal — identical geometry per petal
    for (let pi = 0; pi < petalCount; pi++) {
      const petal = petals[pi];
      if (petal.length === 0) continue;

      // Petal center angle
      const pa = pi * petalAngle - Math.PI / 2;
      const cosA = Math.cos(pa);
      const sinA = Math.sin(pa);

      // Place sensors along the petal spine at evenly spaced radii
      // Use maxPerPetal for spacing so all petals have identical slot positions
      for (let si = 0; si < petal.length; si++) {
        const item = petal[si];
        // t ranges from ~0.25 to ~0.9 along the petal
        const t = (si + 1) / (maxPerPetal + 1);
        const r = maxR * (0.18 + 0.75 * t);

        // Petal width at this t: sine envelope, widest at t≈0.5
        const width = maxR * 0.08 * Math.sin(t * Math.PI);
        // Alternate left/right of spine for visual fullness
        const side = si % 2 === 0 ? 1 : -1;
        const offset = petal.length > 1 ? side * width * 0.5 : 0;

        const sx = cx + r * cosA - offset * sinA;
        const sy = cy + r * sinA + offset * cosA;
        graph.setNodeAttribute(item.sensor, "x", sx);
        graph.setNodeAttribute(item.sensor, "y", sy);

        // Attributes: small arc pointing outward from center
        const aCount = item.attrs.length;
        if (aCount === 0) continue;
        const attrR = Math.max(1.2, 1.5 * Math.sqrt(aCount));
        for (let ai = 0; ai < aCount; ai++) {
          // Fan in a semicircle facing outward
          const spread = Math.min(Math.PI, (aCount / 3) * Math.PI * 0.5);
          const baseAngle = pa;
          const aAngle = baseAngle - spread / 2 + (aCount === 1 ? spread / 2 : (ai / (aCount - 1)) * spread);
          graph.setNodeAttribute(item.attrs[ai], "x", sx + attrR * Math.cos(aAngle));
          graph.setNodeAttribute(item.attrs[ai], "y", sy + attrR * Math.sin(aAngle));
        }
      }
    }

    isLayoutRunning = false;
    sigma?.refresh();
  }

  // ── Visual: Activity Heatmap ──────────────────────────────────

  function startActivityHeatmap() {
    // Apply heatmap coloring to current layout positions
    applyLayout(lastLayoutMode);
    if (graph) {
      graph.forEachNode(node => {
        activityCounts.set(node, 0);
        updateHeatmapNode(node);
      });
    }
  }

  function stopActivityHeatmap() {
    activityDecayTimers.forEach(t => clearTimeout(t));
    activityDecayTimers = [];
    activityCounts.clear();
  }

  function trackActivity(nodeId: string) {
    const cur = (activityCounts.get(nodeId) || 0) + 1;
    activityCounts.set(nodeId, cur);
    updateHeatmapNode(nodeId);
    vibrateNode(nodeId);

    const timer = setTimeout(() => {
      const c = activityCounts.get(nodeId) || 0;
      if (c > 0) activityCounts.set(nodeId, c - 1);
      if (viewMode === "heatmap") updateHeatmapNode(nodeId);
      scheduleRefresh();
    }, ACTIVITY_WINDOW_MS);
    activityDecayTimers.push(timer);
  }

  function updateHeatmapNode(nodeId: string) {
    if (!graph || !graph.hasNode(nodeId)) return;
    const count = activityCounts.get(nodeId) || 0;
    const attrs = graph.getNodeAttributes(nodeId);
    const baseSize = scaledNodeSizes[attrs.nodeType as keyof typeof scaledNodeSizes] || 4;

    let color: string;
    const hm = getTheme().heatmap;
    if (count === 0)      color = hm[0];
    else if (count <= 2)  color = hm[1];
    else if (count <= 5)  color = hm[2];
    else if (count <= 10) color = hm[3];
    else                  color = hm[4];

    const sizeMult = 1.0 + Math.min(count * 0.08, 0.8);
    graph.setNodeAttribute(nodeId, "color", color);
    graph.setNodeAttribute(nodeId, "size", baseSize * sizeMult);
    scheduleRefresh();
  }

  // ── Visual: Freshness Decay ───────────────────────────────────

  function startFreshnessDecay() {
    applyLayout(lastLayoutMode);
    const now = Date.now();
    if (graph) {
      graph.forEachNode(node => nodeFreshness.set(node, now));
    }
    freshnessTimer = setInterval(updateFreshnessAppearances, FRESHNESS_INTERVAL_MS);
  }

  function stopFreshnessDecay() {
    if (freshnessTimer) { clearInterval(freshnessTimer); freshnessTimer = null; }
    nodeFreshness.clear();
  }

  function hexToRgba(hex: string, alpha: number): string {
    const c = hex.replace("#", "");
    return `rgba(${parseInt(c.slice(0,2),16)},${parseInt(c.slice(2,4),16)},${parseInt(c.slice(4,6),16)},${alpha})`;
  }

  // Convert any CSS color to "r,g,b" string for safe rgba() construction
  function colorToRgb(color: string): string {
    if (color.startsWith("rgb")) {
      const m = color.match(/(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
      if (m) return `${m[1]},${m[2]},${m[3]}`;
    }
    if (color.startsWith("#")) {
      const c = color.replace("#", "");
      return `${parseInt(c.slice(0,2),16)},${parseInt(c.slice(2,4),16)},${parseInt(c.slice(4,6),16)}`;
    }
    return "139,92,246"; // fallback purple
  }

  function updateFreshnessAppearances() {
    if (!graph || viewMode !== "freshness") return;
    const now = Date.now();

    graph.forEachNode((node, attrs) => {
      const last = nodeFreshness.get(node) || now;
      const stale = (now - last) / 1000;
      const baseSize = scaledNodeSizes[attrs.nodeType as keyof typeof scaledNodeSizes] || 4;
      const origColor = getOriginalNodeColor(attrs);

      let opacity: number, sizeFactor: number;
      if (stale < 2)       { opacity = 1.0; sizeFactor = 1.0; }
      else if (stale < 10) { opacity = 0.8; sizeFactor = 0.95; }
      else if (stale < 30) { opacity = 0.5; sizeFactor = 0.85; }
      else if (stale < 120){ opacity = 0.3; sizeFactor = 0.7; }
      else                 { opacity = 0.1; sizeFactor = 0.5; }

      graph.setNodeAttribute(node, "color", hexToRgba(origColor, opacity));
      graph.setNodeAttribute(node, "size", baseSize * sizeFactor);
    });
    scheduleRefresh();
  }

  function markNodeFresh(nodeId: string) {
    nodeFreshness.set(nodeId, Date.now());
    if (viewMode !== "freshness" || !graph || !graph.hasNode(nodeId)) return;
    const attrs = graph.getNodeAttributes(nodeId);
    const origColor = getOriginalNodeColor(attrs);
    graph.setNodeAttribute(nodeId, "color", lightenColor(origColor, 0.6));
    vibrateNode(nodeId);
    setTimeout(() => {
      if (graph?.hasNode(nodeId)) {
        graph.setNodeAttribute(nodeId, "color", origColor);
        scheduleRefresh();
      }
    }, 200);
    scheduleRefresh();
  }

  // ── Visual: Heartbeat Sync ────────────────────────────────────

  function extractBPM(lastvalue: any): number | null {
    if (!lastvalue?.payload) return null;
    const p = lastvalue.payload;
    if (typeof p === "number" && p > 20 && p < 250) return p;
    if (p?.bpm && typeof p.bpm === "number") return p.bpm;
    if (p?.heart_rate && typeof p.heart_rate === "number") return p.heart_rate;
    if (p?.heartRate && typeof p.heartRate === "number") return p.heartRate;
    return null;
  }

  function startHeartbeatSync() {
    applyLayout(lastLayoutMode);
    heartbeatStartTime = performance.now();
    heartbeatBPMs.clear();

    if (graph) {
      graph.forEachNode((node, attrs) => {
        if (attrs.nodeType === "attribute" &&
            (attrs.data?.attribute_type === "heartrate" || attrs.data?.attribute_type === "hr" ||
             attrs.data?.attribute_id?.includes("heart"))) {
          const bpm = extractBPM(attrs.data?.lastvalue);
          if (bpm) heartbeatBPMs.set(node, bpm);
        }
      });
    }
    heartbeatAnimFrame = requestAnimationFrame(animateHeartbeat);
  }

  function stopHeartbeatSync() {
    if (heartbeatAnimFrame) { cancelAnimationFrame(heartbeatAnimFrame); heartbeatAnimFrame = null; }
    heartbeatBPMs.clear();
    heartbeatStartTime = null;
  }

  function animateHeartbeat() {
    if (!sigma || !graph || viewMode !== "heartbeat") { heartbeatAnimFrame = null; return; }

    const now = performance.now();
    const elapsed = heartbeatStartTime ? now - heartbeatStartTime : 0;

    const bpms = Array.from(heartbeatBPMs.values());
    const avgBPM = bpms.length > 0 ? bpms.reduce((s, b) => s + b, 0) / bpms.length : 60;
    const globalPhase = (elapsed / 1000) * (avgBPM / 60) * 2 * Math.PI;
    const globalScale = 1.0 + Math.sin(globalPhase) * 0.03;

    graph.forEachNode((node, attrs) => {
      const baseSize = scaledNodeSizes[attrs.nodeType as keyof typeof scaledNodeSizes] || 4;

      if (heartbeatBPMs.has(node)) {
        const nodeBPM = heartbeatBPMs.get(node)!;
        const nodePhase = (elapsed / 1000) * (nodeBPM / 60) * 2 * Math.PI;
        const nodeScale = 1.0 + Math.sin(nodePhase) * 0.2;
        graph.setNodeAttribute(node, "size", baseSize * nodeScale);

        // Glow at peak
        if (Math.sin(nodePhase) > 0.95 && isNodeInViewport(node)) {
          activeGlows.set(node, { start: now, kind: "heartbeat" });
          startGlowLoop();
        }
        // Color heartbeat nodes red at peak, pink otherwise
        const intensity = (Math.sin(nodePhase) + 1) / 2;
        const r = Math.round(200 + intensity * 55);
        graph.setNodeAttribute(node, "color", `rgb(${r}, ${Math.round(60 - intensity * 30)}, ${Math.round(80 - intensity * 40)})`);
      } else {
        graph.setNodeAttribute(node, "size", baseSize * globalScale);
      }
    });

    sigma.refresh();
    heartbeatAnimFrame = requestAnimationFrame(animateHeartbeat);
  }

  // ── Visual: Data River ────────────────────────────────────────

  function startDataRiver() {
    applyLayout(lastLayoutMode);
    riverParticles = [];
    riverAnimFrame = requestAnimationFrame(animateDataRiver);
  }

  function stopDataRiver() {
    if (riverAnimFrame) { cancelAnimationFrame(riverAnimFrame); riverAnimFrame = null; }
    riverParticles = [];
    // Clear glow canvas
    if (glowCtx && glowCanvas) {
      glowCtx.clearRect(0, 0, glowCanvas.clientWidth, glowCanvas.clientHeight);
    }
  }

  function spawnParticle(sensorId: string, attributeId: string) {
    if (viewMode !== "river" || !graph || !sigma) return;

    const sensorNodeId = `sensor:${sensorId}`;
    const attrNodeId = `attr:${sensorId}:${attributeId}`;
    if (!graph.hasNode(sensorNodeId) || !graph.hasNode(attrNodeId)) return;

    const userNodeId = `user:${graph.getNodeAttribute(sensorNodeId, "data").connector_id}`;
    const path: Array<{x: number; y: number}> = [];

    if (graph.hasNode(userNodeId)) {
      const ua = graph.getNodeAttributes(userNodeId);
      path.push({x: ua.x, y: ua.y});
    }
    const sa = graph.getNodeAttributes(sensorNodeId);
    path.push({x: sa.x, y: sa.y});
    const aa = graph.getNodeAttributes(attrNodeId);
    path.push({x: aa.x, y: aa.y});

    if (path.length < 2) return;

    const color = graph.getNodeAttribute(attrNodeId, "color") || getTheme().nodes.attribute;
    riverParticles.push({ path, progress: 0, speed: 0.012 + Math.random() * 0.008, color, size: 1.5 + Math.random() });

    if (riverParticles.length > 300) riverParticles.splice(0, riverParticles.length - 300);

    vibrateNode(attrNodeId);
  }

  function animateDataRiver() {
    if (viewMode !== "river") { riverAnimFrame = null; return; }

    // Update particles
    riverParticles = riverParticles.filter(p => { p.progress += p.speed; return p.progress < 1.0; });

    // Render on glow canvas
    if (!glowCanvas || !sigma) { riverAnimFrame = requestAnimationFrame(animateDataRiver); return; }
    if (!glowCtx) glowCtx = glowCanvas.getContext("2d");
    if (!glowCtx) { riverAnimFrame = requestAnimationFrame(animateDataRiver); return; }

    const w = glowCanvas.clientWidth;
    const h = glowCanvas.clientHeight;
    const dpr = window.devicePixelRatio || 1;
    if (glowCanvas.width !== w * dpr || glowCanvas.height !== h * dpr) {
      glowCanvas.width = w * dpr;
      glowCanvas.height = h * dpr;
      glowCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    // Fade trail instead of full clear
    glowCtx.fillStyle = "rgba(15, 23, 42, 0.3)";
    glowCtx.fillRect(0, 0, w, h);

    for (const p of riverParticles) {
      const pos = interpolatePath(p.path, p.progress);
      if (!pos) continue;
      const vp = sigma.graphToViewport(pos);

      const grad = glowCtx.createRadialGradient(vp.x, vp.y, 0, vp.x, vp.y, p.size * 4);
      const rgb = colorToRgb(p.color);
      grad.addColorStop(0, `rgba(${rgb},1)`);
      grad.addColorStop(0.4, `rgba(${rgb},0.53)`);
      grad.addColorStop(1, `rgba(${rgb},0)`);
      glowCtx.fillStyle = grad;
      glowCtx.beginPath();
      glowCtx.arc(vp.x, vp.y, p.size * 4, 0, Math.PI * 2);
      glowCtx.fill();
    }

    riverAnimFrame = requestAnimationFrame(animateDataRiver);
  }

  function interpolatePath(path: Array<{x: number; y: number}>, progress: number): {x: number; y: number} | null {
    if (path.length < 2) return null;
    const segs = path.length - 1;
    const segLen = 1.0 / segs;
    const segIdx = Math.min(Math.floor(progress / segLen), segs - 1);
    const t = (progress - segIdx * segLen) / segLen;
    const a = path[segIdx], b = path[segIdx + 1];
    return { x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t };
  }

  // ── Visual: Attention Radar ───────────────────────────────────

  function startAttentionRadar() {
    applyLayout(lastLayoutMode);
    if (graph) {
      graph.forEachNode((node, attrs) => {
        if (attrs.nodeType === "sensor") {
          const level = sensorAttentionLevels.get(attrs.data?.sensor_id) || attrs.data?.attention_level || "none";
          applyAttentionAppearance(node, level);
        } else if (attrs.nodeType === "attribute") {
          const sLevel = sensorAttentionLevels.get(attrs.data?.sensor_id) || "none";
          applyAttentionAppearance(node, sLevel);
        }
      });
    }
    sigma?.refresh();
  }

  function stopAttentionRadar() {
    // appearances restored by restoreNodeAppearances in next mode switch
  }

  function applyAttentionAppearance(nodeId: string, level: string) {
    if (!graph || !graph.hasNode(nodeId)) return;
    const attrs = graph.getNodeAttributes(nodeId);
    const baseSize = scaledNodeSizes[attrs.nodeType as keyof typeof scaledNodeSizes] || 4;

    let color: string, sizeMult: number;
    const al = getTheme().attention_levels;
    switch (level) {
      case "high":   color = al[0]; sizeMult = 1.5; break;
      case "medium": color = al[1]; sizeMult = 1.2; break;
      case "low":    color = al[2]; sizeMult = 0.9; break;
      default:       color = al[3]; sizeMult = 0.6; break;
    }

    graph.setNodeAttribute(nodeId, "color", color);
    graph.setNodeAttribute(nodeId, "size", baseSize * sizeMult);

    if (level === "high") {
      activeGlows.set(nodeId, { start: performance.now(), kind: "attention" });
      startGlowLoop();
    }
  }

  function handleAttentionChanged(event: CustomEvent) {
    const { sensor_id, level } = event.detail;
    sensorAttentionLevels.set(sensor_id, level);

    if (viewMode !== "attention") return;
    const sNodeId = `sensor:${sensor_id}`;
    if (graph?.hasNode(sNodeId)) {
      applyAttentionAppearance(sNodeId, level);
      vibrateNode(sNodeId);
      graph.forEachNode((node, attrs) => {
        if (attrs.nodeType === "attribute" && attrs.data?.sensor_id === sensor_id) {
          applyAttentionAppearance(node, level);
          vibrateNode(node);
        }
      });
      scheduleRefresh();
    }
  }

  // ── Mode-specific label for re-layout button ──────────────────
  function handleRelayoutForMode() {
    if (layoutModes.includes(viewMode)) {
      applyLayout(viewMode, true);
    } else {
      applyLayout(lastLayoutMode, true);
    }
  }

  function onKeydown(e: KeyboardEvent) {
    if (e.key === "Escape") {
      if (isRecording) {
        stopRecording();
      } else if (showExportModal) {
        showExportModal = false;
      } else if (isFullscreen) {
        isFullscreen = false;
        setTimeout(() => sigma?.refresh(), 50);
      }
    }
  }

  function exportGraph() {
    if (!sigma || !container) return;
    isExporting = true;

    try {
      // Force synchronous re-render so WebGL buffers are filled
      sigma.refresh();

      const canvases = container.querySelectorAll("canvas");
      if (canvases.length === 0) { isExporting = false; return; }

      const baseWidth = container.offsetWidth;
      const baseHeight = container.offsetHeight;
      const width = Math.round(baseWidth * exportScale);
      const height = Math.round(baseHeight * exportScale);

      const offscreen = document.createElement("canvas");
      offscreen.width = width;
      offscreen.height = height;
      const ctx = offscreen.getContext("2d");
      if (!ctx) { isExporting = false; return; }

      if (exportBackground) {
        const grad = ctx.createLinearGradient(0, 0, width, height);
        grad.addColorStop(0, "#0f172a");
        grad.addColorStop(1, "#1e293b");
        ctx.fillStyle = grad;
        ctx.fillRect(0, 0, width, height);
      }

      // Capture immediately after render — WebGL buffer is still filled
      canvases.forEach(canvas => {
        ctx.drawImage(canvas, 0, 0, width, height);
      });

      // Composite glow overlay
      if (glowCanvas && glowCanvas.width > 0) {
        ctx.drawImage(glowCanvas, 0, 0, width, height);
      }

      const mimeType = exportFormat === "jpeg" ? "image/jpeg" : "image/png";
      const quality = exportFormat === "jpeg" ? 0.95 : undefined;

      offscreen.toBlob((blob) => {
        if (!blob) { isExporting = false; return; }
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = `sensocto-graph-${width}x${height}.${exportFormat}`;
        document.body.appendChild(a);
        a.click();
        document.body.removeChild(a);
        URL.revokeObjectURL(url);
        showExportModal = false;
        isExporting = false;
      }, mimeType, quality);
    } catch (err) {
      console.error("Export failed:", err);
      isExporting = false;
    }
  }

  function startRecording() {
    if (!container) return;

    const canvases = container.querySelectorAll("canvas");
    if (canvases.length === 0) return;

    const w = container.offsetWidth;
    const h = container.offsetHeight;

    recordingCanvas = document.createElement("canvas");
    recordingCanvas.width = w;
    recordingCanvas.height = h;
    const ctx = recordingCanvas.getContext("2d");
    if (!ctx) return;

    // Composite loop at ~30fps
    function drawFrame() {
      if (!ctx || !recordingCanvas) return;
      // Draw background
      const grad = ctx.createLinearGradient(0, 0, recordingCanvas.width, recordingCanvas.height);
      grad.addColorStop(0, "#0f172a");
      grad.addColorStop(1, "#1e293b");
      ctx.fillStyle = grad;
      ctx.fillRect(0, 0, recordingCanvas.width, recordingCanvas.height);
      // Composite sigma canvases
      canvases.forEach(c => {
        ctx.drawImage(c, 0, 0, recordingCanvas!.width, recordingCanvas!.height);
      });
      // Composite glow overlay
      if (glowCanvas && glowCanvas.width > 0) {
        ctx.drawImage(glowCanvas, 0, 0, recordingCanvas!.width, recordingCanvas!.height);
      }
      recordingRaf = requestAnimationFrame(drawFrame);
    }

    drawFrame();

    const stream = recordingCanvas.captureStream(30);

    // Pipe audio from the sound engine into the recording stream
    if (soundEnabled && audioCtx && masterOut) {
      recDest = audioCtx.createMediaStreamDestination();
      masterOut.connect(recDest);
      recDest.stream.getAudioTracks().forEach(track => stream.addTrack(track));
    }

    const mimeType = MediaRecorder.isTypeSupported("video/webm;codecs=vp9")
      ? "video/webm;codecs=vp9"
      : "video/webm";

    recordedChunks = [];
    mediaRecorder = new MediaRecorder(stream, {
      mimeType,
      videoBitsPerSecond: 8_000_000,
      audioBitsPerSecond: 128_000
    });

    mediaRecorder.ondataavailable = (e) => {
      if (e.data.size > 0) recordedChunks.push(e.data);
    };

    mediaRecorder.onstop = () => {
      const blob = new Blob(recordedChunks, { type: mimeType });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = `sensocto-graph-${w}x${h}.webm`;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
      recordedChunks = [];
    };

    mediaRecorder.start(100); // collect data every 100ms
    isRecording = true;
    recordingSeconds = 0;
    recordingTimer = setInterval(() => { recordingSeconds += 1; }, 1000);
  }

  function stopRecording() {
    if (mediaRecorder && mediaRecorder.state !== "inactive") {
      mediaRecorder.stop();
    }
    if (recDest && masterOut) {
      try { masterOut.disconnect(recDest); } catch (_) {}
      recDest = null;
    }
    if (recordingRaf !== null) {
      cancelAnimationFrame(recordingRaf);
      recordingRaf = null;
    }
    if (recordingTimer !== null) {
      clearInterval(recordingTimer);
      recordingTimer = null;
    }
    recordingCanvas = null;
    mediaRecorder = null;
    isRecording = false;
    recordingSeconds = 0;
  }

  function toggleRecording() {
    if (isRecording) stopRecording();
    else startRecording();
  }

  function formatRecordingTime(seconds: number): string {
    const m = Math.floor(seconds / 60);
    const s = seconds % 60;
    return `${m}:${s.toString().padStart(2, "0")}`;
  }

  function getNodeTypeIcon(type: string): string {
    switch (type) {
      case "room": return "🏠";
      case "user": return "👤";
      case "sensor": return "📡";
      case "attribute": return "📊";
      default: return "•";
    }
  }

  function formatAttributeValue(data: any): string {
    if (!data?.lastvalue?.payload) return "No data";
    const payload = data.lastvalue.payload;
    if (typeof payload === "object") {
      return JSON.stringify(payload, null, 2);
    }
    return String(payload);
  }

  function getHoverSummary(details: any): string {
    if (!details) return "";
    switch (details.type) {
      case "user":
        return `${details.data.sensor_count} sensors`;
      case "sensor":
        return `${Object.keys(details.data.attributes || {}).length} attrs`;
      case "attribute": {
        const val = details.data?.lastvalue?.payload;
        if (val == null) return details.data.attribute_type;
        const short = typeof val === "object" ? JSON.stringify(val) : String(val);
        return short.length > 30 ? short.slice(0, 27) + "..." : short;
      }
      case "room":
        return `${details.data.sensor_count} sensors`;
      default:
        return "";
    }
  }

  // Track active pulsation animations: nodeId => {timeout, baseSize, originalColor}
  // Store original values to prevent compounding growth from rapid events
  let activePulsations = new Map<string, {timeout: number, baseSize: number, originalColor: string}>();

  // Standalone vibration tracking — shared across all view modes
  let activeVibrations = new Map<string, {timeouts: number[], offset: {dx: number, dy: number}}>();

  // Vibrate a node with a subtle, scale-aware positional jitter.
  // Can be called from any view mode — purely positional, doesn't touch size/color.
  function vibrateNode(nodeId: string) {
    if (!vibrateEnabled || !sigma || !graph || !graph.hasNode(nodeId)) return;
    if (!isNodeInViewport(nodeId)) return;

    const existing = activeVibrations.get(nodeId);
    if (existing) {
      for (const vt of existing.timeouts) clearTimeout(vt);
      if (existing.offset.dx !== 0 || existing.offset.dy !== 0) {
        graph.setNodeAttribute(nodeId, "x", graph.getNodeAttribute(nodeId, "x") - existing.offset.dx);
        graph.setNodeAttribute(nodeId, "y", graph.getNodeAttribute(nodeId, "y") - existing.offset.dy);
      }
    }

    const ratio = sigma.getCamera().ratio || 1;
    const amp = (0.3 + Math.random() * 0.2) * ratio;
    const timeouts: number[] = [];
    const offset = { dx: 0, dy: 0 };

    const steps = 2;
    for (let i = 0; i < steps; i++) {
      const vt = setTimeout(() => {
        if (!graph || !graph.hasNode(nodeId)) return;
        const prevDx = offset.dx;
        const prevDy = offset.dy;
        const angle = Math.random() * Math.PI * 2;
        const r = amp * (1 - i / steps);
        const newDx = Math.cos(angle) * r;
        const newDy = Math.sin(angle) * r;
        graph.setNodeAttribute(nodeId, "x", graph.getNodeAttribute(nodeId, "x") - prevDx + newDx);
        graph.setNodeAttribute(nodeId, "y", graph.getNodeAttribute(nodeId, "y") - prevDy + newDy);
        offset.dx = newDx;
        offset.dy = newDy;
      }, i * 40);
      timeouts.push(vt);
    }
    const resetVt = setTimeout(() => {
      if (!graph || !graph.hasNode(nodeId)) return;
      graph.setNodeAttribute(nodeId, "x", graph.getNodeAttribute(nodeId, "x") - offset.dx);
      graph.setNodeAttribute(nodeId, "y", graph.getNodeAttribute(nodeId, "y") - offset.dy);
      offset.dx = 0;
      offset.dy = 0;
      activeVibrations.delete(nodeId);
    }, 100);
    timeouts.push(resetVt);

    activeVibrations.set(nodeId, { timeouts, offset });
  }

  // Glow overlay system — electric plasma halo on pulsating nodes
  let glowCanvas: HTMLCanvasElement;
  let glowCtx: CanvasRenderingContext2D | null = null;
  let glowRaf: number | null = null;
  type GlowKind = "data" | "attention" | "heartbeat" | "connect" | "disconnect";
  interface GlowColors { core: [number, number, number]; mid: [number, number, number]; wisp: [number, number, number]; }
  function getGlowPalettes(): Record<GlowKind, GlowColors> { return getTheme().glow; }
  interface GlowEntry { start: number; kind: GlowKind; frozenPos?: { x: number; y: number }; frozenSize?: number; }
  let activeGlows = new Map<string, GlowEntry>();
  const GLOW_DURATION_MS = 350;

  function startGlowLoop() {
    if (glowRaf !== null) return;
    function tick() {
      renderGlows();
      if (activeGlows.size > 0) {
        glowRaf = requestAnimationFrame(tick);
      } else {
        glowRaf = null;
      }
    }
    glowRaf = requestAnimationFrame(tick);
  }

  function renderGlows() {
    if (!glowCanvas || !sigma || !graph) return;
    if (!glowCtx) glowCtx = glowCanvas.getContext("2d");
    if (!glowCtx) return;

    const w = glowCanvas.clientWidth;
    const h = glowCanvas.clientHeight;
    const dpr = window.devicePixelRatio || 1;
    if (glowCanvas.width !== w * dpr || glowCanvas.height !== h * dpr) {
      glowCanvas.width = w * dpr;
      glowCanvas.height = h * dpr;
      glowCtx.setTransform(dpr, 0, 0, dpr, 0, 0);
    }

    glowCtx.clearRect(0, 0, w, h);
    const now = performance.now();

    for (const [nodeId, glow] of activeGlows) {
      const elapsed = now - glow.start;
      if (elapsed > GLOW_DURATION_MS) {
        activeGlows.delete(nodeId);
        continue;
      }

      // For nodes that no longer exist, use frozen position if available (disconnect glow)
      let viewPos: { x: number; y: number };
      let displaySize: number;

      if (!graph.hasNode(nodeId)) {
        if (glow.frozenPos) {
          viewPos = glow.frozenPos;
          displaySize = glow.frozenSize || 8;
        } else {
          activeGlows.delete(nodeId);
          continue;
        }
      } else {
        if (!isNodeInViewport(nodeId)) continue;
        const nodeAttrs = graph.getNodeAttributes(nodeId);
        viewPos = sigma.graphToViewport({ x: nodeAttrs.x, y: nodeAttrs.y });
        const baseSize = nodeAttrs.size || 4;
        const ratio = sigma.getCamera().ratio || 1;
        displaySize = (baseSize / ratio) * 2;
      }

      const palettes = getGlowPalettes();
      const palette = palettes[glow.kind] || palettes.data;
      const [cR, cG, cB] = palette.core;
      const [mR, mG, mB] = palette.mid;
      const [wR, wG, wB] = palette.wisp;

      const progress = elapsed / GLOW_DURATION_MS;
      const alpha = 0.5 * (1 - progress * progress);
      const glowRadius = displaySize * (2.0 + progress * 1.0);

      const hash = nodeId.charCodeAt(0) + (nodeId.charCodeAt(1) || 0) * 7;
      const angle1 = (hash % 6.28);
      const angle2 = angle1 + 2.1;
      const drift = displaySize * 0.3;

      // Layer 1: core glow
      const g1 = glowCtx.createRadialGradient(
        viewPos.x, viewPos.y, displaySize * 0.2,
        viewPos.x, viewPos.y, glowRadius * 0.7
      );
      g1.addColorStop(0, `rgba(${cR}, ${cG}, ${cB}, ${alpha * 0.9})`);
      g1.addColorStop(0.4, `rgba(${mR}, ${mG}, ${mB}, ${alpha * 0.4})`);
      g1.addColorStop(1, `rgba(${mR}, ${mG}, ${mB}, 0)`);

      glowCtx.fillStyle = g1;
      glowCtx.beginPath();
      glowCtx.arc(viewPos.x, viewPos.y, glowRadius * 0.7, 0, Math.PI * 2);
      glowCtx.fill();

      // Layer 2 & 3: offset wisps
      const offsets = [
        { x: Math.cos(angle1) * drift, y: Math.sin(angle1) * drift },
        { x: Math.cos(angle2) * drift, y: Math.sin(angle2) * drift },
      ];

      for (const off of offsets) {
        const cx = viewPos.x + off.x;
        const cy = viewPos.y + off.y;
        const r = glowRadius * 0.5;
        const g = glowCtx.createRadialGradient(cx, cy, 0, cx, cy, r);
        g.addColorStop(0, `rgba(${wR}, ${wG}, ${wB}, ${alpha * 0.5})`);
        g.addColorStop(0.5, `rgba(${mR}, ${mG}, ${mB}, ${alpha * 0.2})`);
        g.addColorStop(1, `rgba(${mR}, ${mG}, ${mB}, 0)`);
        glowCtx.fillStyle = g;
        glowCtx.beginPath();
        glowCtx.arc(cx, cy, r, 0, Math.PI * 2);
        glowCtx.fill();
      }
    }
  }

  // Throttle sigma.refresh() to at most once per animation frame
  let refreshScheduled = false;
  function scheduleRefresh() {
    if (refreshScheduled) return;
    refreshScheduled = true;
    requestAnimationFrame(() => {
      refreshScheduled = false;
      if (sigma) {
        sigma.refresh();
      }
    });
  }

  // Lighten a hex color by mixing with white
  function lightenColor(hex: string, amount: number = 0.3): string {
    // Remove # if present
    const color = hex.replace('#', '');
    const r = parseInt(color.substring(0, 2), 16);
    const g = parseInt(color.substring(2, 4), 16);
    const b = parseInt(color.substring(4, 6), 16);

    // Mix with white
    const newR = Math.min(255, Math.round(r + (255 - r) * amount));
    const newG = Math.min(255, Math.round(g + (255 - g) * amount));
    const newB = Math.min(255, Math.round(b + (255 - b) * amount));

    return `#${newR.toString(16).padStart(2, '0')}${newG.toString(16).padStart(2, '0')}${newB.toString(16).padStart(2, '0')}`;
  }

  // Check if a graph node is currently visible in the camera viewport.
  // Uses Sigma's graphToViewport to project node coords, then tests
  // against the canvas bounds with a generous margin for glow radius.
  function isNodeInViewport(nodeId: string): boolean {
    if (!sigma || !graph || !graph.hasNode(nodeId)) return false;
    const attrs = graph.getNodeAttributes(nodeId);
    const vp = sigma.graphToViewport({ x: attrs.x, y: attrs.y });
    const w = container?.offsetWidth || 0;
    const h = container?.offsetHeight || 0;
    const margin = 80;
    return vp.x >= -margin && vp.x <= w + margin && vp.y >= -margin && vp.y <= h + margin;
  }

  // Pulsate a node with subtle animation + optional render-only vibration
  function pulsateNode(nodeId: string) {
    if (!graph || !graph.hasNode(nodeId)) return;

    const existing = activePulsations.get(nodeId);

    let baseSize: number;
    let originalColor: string;

    if (existing) {
      clearTimeout(existing.timeout);
      baseSize = existing.baseSize;
      originalColor = existing.originalColor;
    } else {
      baseSize = graph.getNodeAttribute(nodeId, "size");
      originalColor = graph.getNodeAttribute(nodeId, "color");
    }

    // Subtle size increase (20% larger)
    graph.setNodeAttribute(nodeId, "size", baseSize * 1.2);

    // Lighten the node's color
    graph.setNodeAttribute(nodeId, "color", lightenColor(originalColor, 0.4));

    // Delegate vibration to standalone function
    vibrateNode(nodeId);

    // Contract back after animation
    const timeout = setTimeout(() => {
      if (graph && graph.hasNode(nodeId)) {
        graph.setNodeAttribute(nodeId, "size", baseSize);
        graph.setNodeAttribute(nodeId, "color", originalColor);
        activePulsations.delete(nodeId);
        scheduleRefresh();
      }
    }, 250);

    activePulsations.set(nodeId, {timeout, baseSize, originalColor});

    activeGlows.set(nodeId, { start: performance.now(), kind: "data" });
    startGlowLoop();

    scheduleRefresh();
  }

  // Handle graph activity events - pulsate sensor nodes (viewport-aware)
  function handleGraphActivity(event: CustomEvent) {
    const { sensor_id, attribute_ids } = event.detail;
    const sensorNodeId = `sensor:${sensor_id}`;
    let anyVisible = false;

    // Mode-specific handling
    if (viewMode === "heatmap") {
      if (graph?.hasNode(sensorNodeId)) trackActivity(sensorNodeId);
      if (attribute_ids && Array.isArray(attribute_ids)) {
        for (const attrId of attribute_ids) {
          const attrNodeId = `attr:${sensor_id}:${attrId}`;
          if (graph?.hasNode(attrNodeId)) trackActivity(attrNodeId);
        }
      }
      return;
    }

    if (viewMode === "river") {
      if (attribute_ids && Array.isArray(attribute_ids)) {
        for (const attrId of attribute_ids) {
          spawnParticle(sensor_id, attrId);
        }
      }
    }

    if (viewMode === "freshness") {
      if (graph?.hasNode(sensorNodeId)) markNodeFresh(sensorNodeId);
      if (attribute_ids && Array.isArray(attribute_ids)) {
        for (const attrId of attribute_ids) {
          const attrNodeId = `attr:${sensor_id}:${attrId}`;
          if (graph?.hasNode(attrNodeId)) markNodeFresh(attrNodeId);
        }
      }
    }

    // Pulsation for topology and layout modes
    if (layoutModes.includes(viewMode)) {
      if (graph && graph.hasNode(sensorNodeId) && isNodeInViewport(sensorNodeId)) {
        pulsateNode(sensorNodeId);
        anyVisible = true;
      }
      if (attribute_ids && Array.isArray(attribute_ids)) {
        for (const attrId of attribute_ids) {
          const attrNodeId = `attr:${sensor_id}:${attrId}`;
          if (graph && graph.hasNode(attrNodeId) && isNodeInViewport(attrNodeId)) {
            pulsateNode(attrNodeId);
            anyVisible = true;
          }
        }
      }
    }

    if (anyVisible) playSound();
  }

  // Handle composite measurement events for real-time updates (viewport-aware)
  function handleCompositeMeasurement(event: CustomEvent) {
    const { sensor_id, attribute_id, payload } = event.detail;
    const attrNodeId = `attr:${sensor_id}:${attribute_id}`;

    if (graph && graph.hasNode(attrNodeId)) {
      // Always update data
      const attrs = graph.getNodeAttributes(attrNodeId);
      if (attrs.data) {
        attrs.data.lastvalue = { payload, timestamp: Date.now() };
      }

      // Mode-specific handling
      if (viewMode === "freshness") {
        markNodeFresh(attrNodeId);
        markNodeFresh(`sensor:${sensor_id}`);
      }
      if (viewMode === "heartbeat") {
        const bpm = extractBPM({ payload });
        if (bpm) {
          heartbeatBPMs.set(attrNodeId, bpm);
          vibrateNode(attrNodeId);
        }
      }
      if (viewMode === "river") {
        spawnParticle(sensor_id, attribute_id);
      }
      if (viewMode === "heatmap") {
        trackActivity(attrNodeId);
        trackActivity(`sensor:${sensor_id}`);
      }

      // Pulsation for layout modes
      if (layoutModes.includes(viewMode) && isNodeInViewport(attrNodeId)) {
        pulsateNode(attrNodeId);
        const sensorNodeId = `sensor:${sensor_id}`;
        if (graph.hasNode(sensorNodeId) && isNodeInViewport(sensorNodeId)) {
          pulsateNode(sensorNodeId);
        }
      }
    }
  }

  // Track previous topology to avoid unnecessary rebuilds
  let prevSensorSet = new Set<string>();
  let prevUserSet = new Set<string>();
  let rebuildTimer: ReturnType<typeof setTimeout> | null = null;
  let isInitialBuild = true;

  // Incremental graph updates: add/remove only changed nodes instead of full rebuild
  $effect(() => {
    // Access reactive deps
    const currentRooms = rooms;
    const currentUsers = users;
    const currentSensors = sensors;

    const currentSensorSet = new Set(Object.keys(currentSensors || {}));
    const currentUserSet = new Set((currentUsers || []).map(u => u.connector_id));

    // Check for actual topology changes
    const sensorsEqual = currentSensorSet.size === prevSensorSet.size &&
      [...currentSensorSet].every(s => prevSensorSet.has(s));
    const usersEqual = currentUserSet.size === prevUserSet.size &&
      [...currentUserSet].every(u => prevUserSet.has(u));

    if (sensorsEqual && usersEqual && !isInitialBuild) {
      return;
    }

    if (rebuildTimer) clearTimeout(rebuildTimer);
    rebuildTimer = setTimeout(() => {
      // First build: full rebuild needed (no graph or sigma yet)
      if (isInitialBuild || !graph || !sigma) {
        isInitialBuild = false;
        prevSensorSet = currentSensorSet;
        prevUserSet = currentUserSet;
        buildGraph();
        if (container) {
          initSigma();
          applyViewMode(viewMode);
        }
        return;
      }

      // Incremental: compute diff
      const addedSensors = [...currentSensorSet].filter(s => !prevSensorSet.has(s));
      const removedSensors = [...prevSensorSet].filter(s => !currentSensorSet.has(s));
      const addedUsers = [...currentUserSet].filter(u => !prevUserSet.has(u));
      const removedUsers = [...prevUserSet].filter(u => !currentUserSet.has(u));

      prevSensorSet = currentSensorSet;
      prevUserSet = currentUserSet;

      // If too many changes (>30% of graph), do full rebuild
      const changeCount = addedSensors.length + removedSensors.length + addedUsers.length + removedUsers.length;
      const totalNodes = graph.order;
      if (changeCount > totalNodes * 0.3 || changeCount > 50) {
        buildGraph();
        if (container) {
          initSigma();
          applyViewMode(viewMode);
        }
        return;
      }

      // Calculate scale for new nodes
      const scale = scaledNodeSizes.sensor / baseNodeSizes.sensor;

      // Remove departed sensors (and their attributes + edges)
      for (const sensorId of removedSensors) {
        const sensorNodeId = `sensor:${sensorId}`;
        if (graph.hasNode(sensorNodeId)) {
          // Freeze position for amber disconnect glow, then drop the node
          const attrs = graph.getNodeAttributes(sensorNodeId);
          const frozenPos = sigma ? sigma.graphToViewport({ x: attrs.x, y: attrs.y }) : null;
          const ratio = sigma ? (sigma.getCamera().ratio || 1) : 1;
          const frozenSize = ((attrs.size || 4) / ratio) * 2;
          if (frozenPos) {
            activeGlows.set(sensorNodeId, { start: performance.now(), kind: "disconnect", frozenPos, frozenSize });
            startGlowLoop();
          }
          // Remove attribute nodes first
          const edges = graph.edges(sensorNodeId);
          for (const edge of edges) {
            const target = graph.target(edge);
            const targetAttrs = graph.getNodeAttributes(target);
            if (targetAttrs.nodeType === "attribute") {
              graph.dropNode(target);
            }
          }
          graph.dropNode(sensorNodeId);
        }
      }

      // Remove departed users
      for (const userId of removedUsers) {
        const userNodeId = `user:${userId}`;
        if (graph.hasNode(userNodeId)) {
          graph.dropNode(userNodeId);
        }
      }

      // Add new users
      for (const userId of addedUsers) {
        const user = (currentUsers || []).find(u => u.connector_id === userId);
        if (!user) continue;
        const userNodeId = `user:${userId}`;
        if (!graph.hasNode(userNodeId)) {
          graph.addNode(userNodeId, {
            label: user.connector_name,
            size: jitterSize(scaledNodeSizes.user + Math.min(user.sensor_count * scale, 8 * scale)),
            color: nodeColors.user,
            nodeType: "user",
            data: user,
            x: 50 + (Math.random() - 0.5) * 20,
            y: 50 + (Math.random() - 0.5) * 20
          });
        }
      }

      // Add new sensors (with attributes + edges)
      for (const sensorId of addedSensors) {
        const sensor = currentSensors[sensorId];
        if (!sensor) continue;

        const sensorNodeId = `sensor:${sensorId}`;
        const attrCount = Object.keys(sensor.attributes || {}).length;

        // Position near the parent user for visual continuity
        const userNodeId = `user:${sensor.connector_id}`;
        let startX = 50 + (Math.random() - 0.5) * 30;
        let startY = 50 + (Math.random() - 0.5) * 30;
        if (graph.hasNode(userNodeId)) {
          startX = graph.getNodeAttribute(userNodeId, "x") + (Math.random() - 0.5) * 10;
          startY = graph.getNodeAttribute(userNodeId, "y") + (Math.random() - 0.5) * 10;
        }

        if (!graph.hasNode(sensorNodeId)) {
          graph.addNode(sensorNodeId, {
            label: sensor.sensor_name || sensorId.substring(0, 12),
            size: jitterSize(scaledNodeSizes.sensor + Math.min(attrCount * 1.5 * scale, 6 * scale)),
            color: nodeColors.sensor,
            nodeType: "sensor",
            data: sensor,
            x: startX,
            y: startY
          });
          // Emerald connect glow for newly appearing sensors
          activeGlows.set(sensorNodeId, { start: performance.now(), kind: "connect" });
          startGlowLoop();
        }

        // Edge to user
        if (graph.hasNode(userNodeId) && !graph.hasEdge(userNodeId, sensorNodeId)) {
          graph.addEdge(userNodeId, sensorNodeId, {
            size: Math.max(0.3, 0.7 * scale),
            color: "rgba(55, 65, 81, 0.35)",
            curvature: randomCurvature()
          });
        }

        // Attribute nodes
        for (const [attrId, attr] of Object.entries(sensor.attributes || {})) {
          const attrNodeId = `attr:${sensorId}:${attrId}`;
          const attrColor = getAttrColor((attr as any).attribute_type, attrId);

          if (!graph.hasNode(attrNodeId)) {
            graph.addNode(attrNodeId, {
              label: (attr as any).attribute_name || (attr as any).attribute_id,
              size: jitterSize(scaledNodeSizes.attribute),
              color: attrColor,
              nodeType: "attribute",
              data: { ...(attr as any), sensor_id: sensorId },
              x: startX + (Math.random() - 0.5) * 5,
              y: startY + (Math.random() - 0.5) * 5
            });
          }

          if (!graph.hasEdge(sensorNodeId, attrNodeId)) {
            graph.addEdge(sensorNodeId, attrNodeId, {
              size: Math.max(0.2, 0.4 * scale),
              color: "rgba(55, 65, 81, 0.25)",
              curvature: randomCurvature()
            });
          }
        }
      }

      // Re-run layout to integrate new nodes smoothly
      if (addedSensors.length > 0 || addedUsers.length > 0) {
        runLayout();
      }
      sigma?.refresh();
    }, 500);
  });

  onMount(() => {
    // Initial build is handled by the $effect when props arrive.
    // Only set up event listeners here.
    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.addEventListener("graph-activity-event", handleGraphActivity as EventListener);
    window.addEventListener("attention-changed-event", handleAttentionChanged as EventListener);
    window.addEventListener("keydown", onKeydown);
  });

  onDestroy(() => {
    if (isRecording) stopRecording();
    if (glowRaf !== null) { cancelAnimationFrame(glowRaf); glowRaf = null; }
    activeGlows.clear();
    cleanupMode(viewMode);
    if (fa2Worker) {
      fa2Worker.stop();
      fa2Worker.kill();
      fa2Worker = null;
    }
    if (audioCtx) {
      audioCtx.close();
      audioCtx = null;
    }
    window.removeEventListener("keydown", onKeydown);
    if (rebuildTimer) clearTimeout(rebuildTimer);
    if (sigma) {
      sigma.kill();
      sigma = null;
    }
    for (const pulsation of activePulsations.values()) {
      clearTimeout(pulsation.timeout);
    }
    activePulsations.clear();
    for (const vib of activeVibrations.values()) {
      for (const vt of vib.timeouts) clearTimeout(vt);
    }
    activeVibrations.clear();
    window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.removeEventListener("graph-activity-event", handleGraphActivity as EventListener);
    window.removeEventListener("attention-changed-event", handleAttentionChanged as EventListener);
  });
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="lobby-graph" class:fullscreen={isFullscreen} class:compact={compact} bind:this={graphRoot}
  onclick={() => { seasonPanelOpen = false; statsPanelOpen = false; }}>
  <div bind:this={container} class="graph-container"></div>

  <!-- Glow overlay canvas for plasma discharge halos -->
  <canvas bind:this={glowCanvas} class="glow-overlay"></canvas>

  <!-- Right Sidebar: Tools/Controls -->
  <div class="sidebar sidebar-right" class:sidebar-open={rightBarOpen}>
    <button class="sidebar-trigger" aria-label="Toggle tools" onclick={() => rightBarOpen = !rightBarOpen}>
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 011.37.49l1.296 2.247a1.125 1.125 0 01-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 010 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 01-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 01-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 01-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 01-1.369-.49l-1.297-2.247a1.125 1.125 0 01.26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 010-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 01-.26-1.43l1.297-2.247a1.125 1.125 0 011.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.086.22-.128.332-.183.582-.495.644-.869l.214-1.28z" />
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" />
      </svg>
    </button>
    <div class="sidebar-panel">
      <button onclick={handleZoomIn} data-tooltip="Zoom In" class="control-btn tooltip-left">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM10 7v6m3-3H7" />
        </svg>
      </button>
      <button onclick={handleZoomOut} data-tooltip="Zoom Out" class="control-btn tooltip-left">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 21l-6-6m2-5a7 7 0 11-14 0 7 7 0 0114 0zM13 10H7" />
        </svg>
      </button>
      <button onclick={handleRelayout} data-tooltip="Re-layout — Recompute node positions" class="control-btn tooltip-left" disabled={isLayoutRunning}>
        <svg class="w-5 h-5" class:animate-spin={isLayoutRunning} fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
        </svg>
      </button>
      <div class="control-divider"></div>
      <button onclick={handleFullscreen} data-tooltip={isFullscreen ? "Exit Fullscreen" : "Fullscreen — Expand graph to fill screen"} class="control-btn tooltip-left">
        {#if isFullscreen}
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 9V4.5M9 9H4.5M9 9L3.75 3.75M9 15v4.5M9 15H4.5M9 15l-5.25 5.25M15 9h4.5M15 9V4.5M15 9l5.25-5.25M15 15h4.5M15 15v4.5m0-4.5l5.25 5.25" />
          </svg>
        {:else}
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.75 3.75v4.5m0-4.5h4.5m-4.5 0L9 9M3.75 20.25v-4.5m0 4.5h4.5m-4.5 0L9 15M20.25 3.75h-4.5m4.5 0v4.5m0-4.5L15 9m5.25 11.25h-4.5m4.5 0v-4.5m0 4.5L15 15" />
          </svg>
        {/if}
      </button>
      <button onclick={() => showExportModal = true} data-tooltip="Export — Save as PNG or JPEG at up to 8x resolution" class="control-btn tooltip-left">
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 16.5v2.25A2.25 2.25 0 005.25 21h13.5A2.25 2.25 0 0021 18.75V16.5M16.5 12L12 16.5m0 0L7.5 12m4.5 4.5V3" />
        </svg>
      </button>
      <button onclick={toggleRecording} data-tooltip={isRecording ? "Stop Recording" : `Record — Capture graph as WebM${soundEnabled ? " + audio" : ""}`} class="control-btn tooltip-left" class:recording={isRecording}>
        {#if isRecording}
          <svg class="w-5 h-5" fill="currentColor" viewBox="0 0 24 24">
            <rect x="6" y="6" width="12" height="12" rx="1" />
          </svg>
        {:else}
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <circle cx="12" cy="12" r="8" stroke-width="2" />
            <circle cx="12" cy="12" r="4" fill="currentColor" />
          </svg>
        {/if}
      </button>
      <div class="control-divider"></div>
      <button onclick={toggleSound} data-tooltip={THEME_LABELS[soundTheme]} class="control-btn tooltip-left" class:sound-active={soundEnabled}>
        {#if soundEnabled}
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19.114 5.636a9 9 0 010 12.728M16.463 8.288a5.25 5.25 0 010 7.424M6.75 8.25l4.72-4.72a.75.75 0 011.28.53v15.88a.75.75 0 01-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 012.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75z" />
          </svg>
        {:else}
          <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17.25 9.75L19.5 12m0 0l2.25 2.25M19.5 12l2.25-2.25M19.5 12l-2.25 2.25m-10.5-6l4.72-4.72a.75.75 0 011.28.53v15.88a.75.75 0 01-1.28.53l-4.72-4.72H4.51c-.88 0-1.704-.507-1.938-1.354A9.009 9.009 0 012.25 12c0-.83.112-1.633.322-2.396C2.806 8.756 3.63 8.25 4.51 8.25H6.75z" />
          </svg>
        {/if}
      </button>
      <button onclick={() => vibrateEnabled = !vibrateEnabled} data-tooltip={vibrateEnabled ? "Vibrate On" : "Vibrate Off"} class="control-btn tooltip-left" class:sound-active={vibrateEnabled}>
        <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          {#if vibrateEnabled}
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12" />
            <circle cx="18" cy="17.25" r="2" fill="currentColor" stroke="none" />
            <path stroke-linecap="round" stroke-width="1.5" d="M21.5 15.5a3 3 0 010 3.5M15 15.5a3 3 0 000 3.5" />
          {:else}
            <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25h16.5" />
          {/if}
        </svg>
      </button>
    </div>
  </div>

  <div class="sidebar sidebar-left" class:sidebar-open={leftBarOpen}>
    <button class="sidebar-trigger" aria-label="Toggle view modes" onclick={() => leftBarOpen = !leftBarOpen}>
      <svg class="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6.429 9.75L2.25 12l4.179 2.25m0-4.5l5.571 3 5.571-3m-11.142 0L2.25 7.5 12 2.25l9.75 5.25-4.179 2.25m0 0l4.179 2.25L12 17.25 2.25 12l4.179-2.25m11.142 0l-5.571 3-5.571-3m11.142 4.5L21.75 12l-4.179 2.25m0 0l-5.571 3-5.571-3" />
      </svg>
    </button>
    <div class="sidebar-panel">
      <span class="sidebar-group-label">Layout</span>
      <button onclick={() => switchViewMode("topology")} class="mode-btn tooltip-right" class:active={viewMode === "topology"} class:layout-active={lastLayoutMode === "topology" && visualModes.includes(viewMode)} data-tooltip="Topology — Force-directed clustering">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M7.5 21L3 16.5m0 0L7.5 12M3 16.5h13.5m0-13.5L21 7.5m0 0L16.5 12M21 7.5H7.5" /></svg>
      </button>
      <button onclick={() => switchViewMode("per-type")} class="mode-btn tooltip-right" class:active={viewMode === "per-type"} class:layout-active={lastLayoutMode === "per-type" && visualModes.includes(viewMode)} data-tooltip="Per Type — Lanes by attribute">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3.75 6.75h16.5M3.75 12h16.5m-16.5 5.25H12" /></svg>
      </button>
      <button onclick={() => switchViewMode("radial")} class="mode-btn tooltip-right" class:active={viewMode === "radial"} class:layout-active={lastLayoutMode === "radial" && visualModes.includes(viewMode)} data-tooltip="Radial — Concentric rings">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" stroke-width="2" /><circle cx="12" cy="12" r="5" stroke-width="2" /><circle cx="12" cy="12" r="1.5" fill="currentColor" /></svg>
      </button>
      <button onclick={() => switchViewMode("flower")} class="mode-btn tooltip-right" class:active={viewMode === "flower"} class:layout-active={lastLayoutMode === "flower" && visualModes.includes(viewMode)} data-tooltip="Flower — Rose-curve petals">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 2C12 2 14.5 5.5 14.5 8.5C14.5 10.5 13.4 12 12 12C10.6 12 9.5 10.5 9.5 8.5C9.5 5.5 12 2 12 2Z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M22 12C22 12 18.5 14.5 15.5 14.5C13.5 14.5 12 13.4 12 12C12 10.6 13.5 9.5 15.5 9.5C18.5 9.5 22 12 22 12Z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M12 22C12 22 9.5 18.5 9.5 15.5C9.5 13.5 10.6 12 12 12C13.4 12 14.5 13.5 14.5 15.5C14.5 18.5 12 22 12 22Z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="1.5" d="M2 12C2 12 5.5 9.5 8.5 9.5C10.5 9.5 12 10.6 12 12C12 13.4 10.5 14.5 8.5 14.5C5.5 14.5 2 12 2 12Z" /><circle cx="12" cy="12" r="2" fill="currentColor" /></svg>
      </button>
      <button onclick={() => switchViewMode("per-user")} class="mode-btn tooltip-right" class:active={viewMode === "per-user"} class:layout-active={lastLayoutMode === "per-user" && visualModes.includes(viewMode)} data-tooltip="Per User — Sensors orbit owner">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 19.128a9.38 9.38 0 002.625.372 9.337 9.337 0 004.121-.952 4.125 4.125 0 00-7.533-2.493M15 19.128v-.003c0-1.113-.285-2.16-.786-3.07M15 19.128v.106A12.318 12.318 0 018.624 21c-2.331 0-4.512-.645-6.374-1.766l-.001-.109a6.375 6.375 0 0111.964-3.07M12 6.375a3.375 3.375 0 11-6.75 0 3.375 3.375 0 016.75 0zm8.25 2.25a2.625 2.625 0 11-5.25 0 2.625 2.625 0 015.25 0z" /></svg>
      </button>
      <button onclick={() => switchViewMode("constellation")} class="mode-btn tooltip-right" class:active={viewMode === "constellation"} class:layout-active={lastLayoutMode === "constellation" && visualModes.includes(viewMode)} data-tooltip="Constellation — Star patterns">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11.48 3.499a.562.562 0 011.04 0l2.125 5.111a.563.563 0 00.475.345l5.518.442c.499.04.701.663.321.988l-4.204 3.602a.563.563 0 00-.182.557l1.285 5.385a.562.562 0 01-.84.61l-4.725-2.885a.563.563 0 00-.586 0L6.982 20.54a.562.562 0 01-.84-.61l1.285-5.386a.562.562 0 00-.182-.557l-4.204-3.602a.563.563 0 01.321-.988l5.518-.442a.563.563 0 00.475-.345L11.48 3.5z" /></svg>
      </button>
      <div class="control-divider"></div>
      <span class="sidebar-group-label">Visual</span>
      <button onclick={() => switchViewMode("heatmap")} class="mode-btn tooltip-right" class:active={viewMode === "heatmap"} data-tooltip="Heatmap — Data frequency colors">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15.362 5.214A8.252 8.252 0 0112 21 8.25 8.25 0 016.038 7.048 8.287 8.287 0 009 9.6a8.983 8.983 0 013.361-6.867 8.21 8.21 0 003 2.48z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 18a3.75 3.75 0 00.495-7.467 5.99 5.99 0 00-1.925 3.546 5.974 5.974 0 01-2.133-1A3.75 3.75 0 0012 18z" /></svg>
      </button>
      <button onclick={() => switchViewMode("freshness")} class="mode-btn tooltip-right" class:active={viewMode === "freshness"} data-tooltip="Freshness — Fade over time">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 6v6h4.5m4.5 0a9 9 0 11-18 0 9 9 0 0118 0z" /></svg>
      </button>
      <button onclick={() => switchViewMode("heartbeat")} class="mode-btn tooltip-right" class:active={viewMode === "heartbeat"} data-tooltip="Heartbeat — Pulse at BPM">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M21 8.25c0-2.485-2.099-4.5-4.688-4.5-1.935 0-3.597 1.126-4.312 2.733-.715-1.607-2.377-2.733-4.313-2.733C5.1 3.75 3 5.765 3 8.25c0 7.22 9 12 9 12s9-4.78 9-12z" /></svg>
      </button>
      <button onclick={() => switchViewMode("river")} class="mode-btn tooltip-right" class:active={viewMode === "river"} data-tooltip="Data River — Flowing particles">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M3 7.5L7.5 3m0 0L12 7.5M7.5 3v13.5m13.5 0L16.5 21m0 0L12 16.5m4.5 4.5V7.5" /></svg>
      </button>
      <button onclick={() => switchViewMode("attention")} class="mode-btn tooltip-right" class:active={viewMode === "attention"} data-tooltip="Attention — Who's watching">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24"><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M2.036 12.322a1.012 1.012 0 010-.639C3.423 7.51 7.36 4.5 12 4.5c4.638 0 8.573 3.007 9.963 7.178.07.207.07.431 0 .639C20.577 16.49 16.64 19.5 12 19.5c-4.638 0-8.573-3.007-9.963-7.178z" /><path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M15 12a3 3 0 11-6 0 3 3 0 016 0z" /></svg>
      </button>
    </div>
  </div>

  <!-- Season selector — bottom-left, tap/hover to expand -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="bottom-overlay bottom-left" class:open={seasonPanelOpen}
    onclick={(e) => { e.stopPropagation(); seasonPanelOpen = !seasonPanelOpen; statsPanelOpen = false; }}>
    <span class="bottom-trigger">{SEASON_THEMES[currentSeason].icon}</span>
    <div class="bottom-panel">
      {#each (["spring", "summer", "autumn", "winter", "rainbow"] as Season[]) as season}
        <button
          onclick={(e) => { e.stopPropagation(); switchSeason(season); seasonPanelOpen = false; }}
          class="season-btn"
          class:active={currentSeason === season}
          title={SEASON_THEMES[season].name}
        >
          {SEASON_THEMES[season].icon}
        </button>
      {/each}
    </div>
  </div>

  <!-- Recording indicator -->
  {#if isRecording}
    <div class="recording-indicator">
      <span class="rec-dot"></span>
      <span class="rec-label">REC</span>
      <span class="rec-time">{formatRecordingTime(recordingSeconds)}</span>
    </div>
  {/if}

  <!-- Export Modal -->
  {#if showExportModal}
    <div class="export-overlay" onclick={() => showExportModal = false}>
      <div class="export-modal" onclick={(e) => e.stopPropagation()}>
        <div class="export-header">
          <span class="export-title">Export Graph</span>
          <button class="export-close" onclick={() => showExportModal = false}>
            <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
            </svg>
          </button>
        </div>

        <div class="export-body">
          <div class="export-field">
            <label class="export-label">Format</label>
            <div class="export-options">
              <button class="export-option" class:active={exportFormat === "png"} onclick={() => exportFormat = "png"}>PNG</button>
              <button class="export-option" class:active={exportFormat === "jpeg"} onclick={() => exportFormat = "jpeg"}>JPEG</button>
            </div>
          </div>

          <div class="export-field">
            <label class="export-label">Resolution</label>
            <div class="export-options">
              {#each [1, 2, 4, 8] as scale}
                <button class="export-option" class:active={exportScale === scale} onclick={() => exportScale = scale}>
                  {scale}x
                </button>
              {/each}
            </div>
            <span class="export-hint">
              {Math.round((container?.offsetWidth || 1920) * exportScale)} x {Math.round((container?.offsetHeight || 1080) * exportScale)} px
            </span>
          </div>

          <div class="export-field">
            <label class="export-label">Background</label>
            <div class="export-options">
              <button class="export-option" class:active={exportBackground} onclick={() => exportBackground = true}>Dark</button>
              <button class="export-option" class:active={!exportBackground} onclick={() => exportBackground = false}>Transparent</button>
            </div>
            {#if !exportBackground && exportFormat === "jpeg"}
              <span class="export-hint export-warn">JPEG doesn't support transparency - will be black</span>
            {/if}
          </div>
        </div>

        <div class="export-footer">
          <button class="export-cancel" onclick={() => showExportModal = false}>Cancel</button>
          <button class="export-submit" onclick={exportGraph} disabled={isExporting}>
            {isExporting ? "Exporting..." : "Download"}
          </button>
        </div>
      </div>
    </div>
  {/if}


  <!-- Compact Hover Tooltip (follows cursor) -->
  {#if hoverDetails && !selectedNode}
    <div class="hover-tooltip" style="left: {mouseX + 14}px; top: {mouseY - 10}px;">
      <span class="hover-icon" style="color: {nodeColors[hoverDetails.type] || '#9ca3af'}">{getNodeTypeIcon(hoverDetails.type)}</span>
      <span class="hover-label">{hoverDetails.label}</span>
      <span class="hover-meta">{getHoverSummary(hoverDetails)}</span>
    </div>
  {/if}

  <!-- Selected Node Bottom Bar -->
  {#if selectedDetails}
    <div class="bottom-bar">
      <div class="bottom-bar-main">
        <span class="bottom-bar-icon" style="color: {nodeColors[selectedDetails.type] || '#9ca3af'}">{getNodeTypeIcon(selectedDetails.type)}</span>
        <span class="bottom-bar-type">{selectedDetails.type}</span>
        <span class="bottom-bar-label">{selectedDetails.label}</span>
        <span class="bottom-bar-sep">|</span>

        {#if selectedDetails.type === "user"}
          <span class="bottom-bar-detail">Connector: {selectedDetails.data.connector_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Sensors: {selectedDetails.data.sensor_count}</span>
          {#if selectedDetails.data.attributes_summary?.length > 0}
            <span class="bottom-bar-sep">|</span>
            {#each selectedDetails.data.attributes_summary as attr}
              <span class="bottom-bar-tag">{attr.type}: {attr.count}</span>
            {/each}
          {/if}
        {:else if selectedDetails.type === "sensor"}
          <span class="bottom-bar-detail">ID: {selectedDetails.data.sensor_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Connector: {selectedDetails.data.connector_name}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Attrs: {Object.keys(selectedDetails.data.attributes || {}).length}</span>
        {:else if selectedDetails.type === "attribute"}
          <span class="bottom-bar-detail">ID: {selectedDetails.data.attribute_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Type: {selectedDetails.data.attribute_type}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Sensor: {selectedDetails.data.sensor_id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-value">{formatAttributeValue(selectedDetails.data)}</span>
        {:else if selectedDetails.type === "room"}
          <span class="bottom-bar-detail">ID: {selectedDetails.data.id}</span>
          <span class="bottom-bar-sep">|</span>
          <span class="bottom-bar-detail">Sensors: {selectedDetails.data.sensor_count}</span>
        {/if}
      </div>

      <button onclick={() => { selectedNode = null; selectedDetails = null; highlightedNodes = new Set(); sigma?.refresh(); }} class="bottom-bar-close" data-tooltip="Deselect node" data-tooltip-pos="above">
        <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M6 18L18 6M6 6l12 12" />
        </svg>
      </button>
    </div>
  {/if}

  <!-- Stats — bottom-right, tap/hover to expand -->
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div class="bottom-overlay bottom-right" class:open={statsPanelOpen}
    onclick={(e) => { e.stopPropagation(); statsPanelOpen = !statsPanelOpen; seasonPanelOpen = false; }}>
    <span class="bottom-trigger stats-trigger">{graph?.order || 0}</span>
    <div class="bottom-panel">
      <span>Nodes: {graph?.order || 0}{!lodAttributesVisible ? " (LOD)" : ""}</span>
      <span>Edges: {graph?.size || 0}</span>
      <span>Scale: {(scaledNodeSizes.sensor / baseNodeSizes.sensor).toFixed(2)}x</span>
    </div>
  </div>
</div>

<style>
  .lobby-graph {
    position: relative;
    width: 100%;
    height: 100%;
    background: linear-gradient(135deg, #0f172a 0%, #1e293b 100%);
  }

  .lobby-graph.fullscreen {
    position: fixed;
    inset: 0;
    z-index: 9999;
    min-height: unset;
  }

  .lobby-graph.compact {
    min-height: unset;
    height: 100%;
  }

  .lobby-graph.compact .sidebar,
  .lobby-graph.compact .bottom-overlay,
  .lobby-graph.compact .export-modal {
    display: none;
  }

  .graph-container {
    position: absolute;
    inset: 0;
  }

  .glow-overlay {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    z-index: 1;
  }

  /* ── Sidebars ──────────────────────────────────────── */

  .sidebar {
    position: absolute;
    top: 1rem;
    display: flex;
    flex-direction: column;
    align-items: center;
    z-index: 10;
  }

  .sidebar-left {
    left: 1rem;
  }

  .sidebar-right {
    right: 1rem;
  }

  .sidebar-trigger {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2.5rem;
    height: 2.5rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    color: #d1d5db;
    cursor: pointer;
    transition: all 0.15s ease;
    touch-action: manipulation;
    flex-shrink: 0;
  }

  .sidebar-trigger:hover {
    background: rgba(55, 65, 81, 0.9);
    color: #ffffff;
  }

  .sidebar-panel {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 0.375rem;
    margin-top: 0.5rem;
    padding: 0.5rem;
    background: rgba(31, 41, 55, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.625rem;
    backdrop-filter: blur(8px);
    opacity: 0;
    visibility: hidden;
    transform: translateY(-8px);
    transition: opacity 0.2s ease, transform 0.2s ease, visibility 0.2s;
    position: relative;
  }

  .sidebar-panel::before {
    content: '';
    position: absolute;
    top: -0.5rem;
    left: 0;
    right: 0;
    height: 0.5rem;
  }

  @media (hover: hover) and (pointer: fine) {
    .sidebar:hover .sidebar-panel {
      opacity: 1;
      visibility: visible;
      transform: translateY(0);
    }
  }

  .sidebar.sidebar-open .sidebar-panel {
    opacity: 1;
    visibility: visible;
    transform: translateY(0);
  }

  .sidebar-group-label {
    font-size: 0.55rem;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: #6b7280;
    font-weight: 600;
    white-space: nowrap;
    margin-top: 0.25rem;
    margin-bottom: 0.125rem;
  }

  .sidebar-left .mode-btn {
    width: 2.25rem;
    height: 2.25rem;
  }

  .sidebar-left .mode-btn :global(svg) {
    width: 1.125rem;
    height: 1.125rem;
  }

  .control-divider {
    width: 100%;
    height: 1px;
    background: rgba(75, 85, 99, 0.4);
  }

  .control-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 2.5rem;
    height: 2.5rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    color: #d1d5db;
    cursor: pointer;
    transition: all 0.15s ease;
    touch-action: manipulation;
  }

  .control-btn:hover:not(:disabled) {
    background: rgba(55, 65, 81, 0.9);
    color: #ffffff;
  }

  .control-btn:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* ── CSS Tooltips ─────────────────────────────────────── */

  [data-tooltip] {
    position: relative;
  }

  [data-tooltip]::after {
    content: attr(data-tooltip);
    position: absolute;
    white-space: normal;
    max-width: 220px;
    width: max-content;
    padding: 0.4rem 0.6rem;
    background: rgba(17, 24, 39, 0.97);
    border: 1px solid rgba(75, 85, 99, 0.6);
    border-radius: 0.375rem;
    font-size: 0.7rem;
    line-height: 1.35;
    font-weight: 400;
    color: #e5e7eb;
    letter-spacing: 0;
    text-transform: none;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.45);
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.15s ease, transform 0.15s ease;
    z-index: 100;
  }

  [data-tooltip]:hover::after {
    opacity: 1;
  }

  /* Left-side tooltips (for the right-side controls panel) */
  .tooltip-left[data-tooltip]::after {
    right: calc(100% + 8px);
    top: 50%;
    transform: translateY(-50%) translateX(4px);
  }

  .tooltip-left[data-tooltip]:hover::after {
    transform: translateY(-50%) translateX(0);
  }

  /* Right-side tooltips (for the left-side mode toolbar) */
  .tooltip-right[data-tooltip]::after {
    left: calc(100% + 8px);
    top: 50%;
    transform: translateY(-50%) translateX(-4px);
  }

  .tooltip-right[data-tooltip]:hover::after {
    transform: translateY(-50%) translateX(0);
  }

  /* Below tooltips (for the top mode selector) */
  .tooltip-below[data-tooltip]::after {
    top: calc(100% + 8px);
    left: 50%;
    transform: translateX(-50%) translateY(-4px);
  }

  .tooltip-below[data-tooltip]:hover::after {
    transform: translateX(-50%) translateY(0);
  }

  /* Above tooltips (e.g. for bottom bar close) */
  [data-tooltip-pos="above"][data-tooltip]::after {
    bottom: calc(100% + 8px);
    top: auto;
    left: 50%;
    transform: translateX(-50%) translateY(4px);
  }

  [data-tooltip-pos="above"][data-tooltip]:hover::after {
    transform: translateX(-50%) translateY(0);
  }

  .mode-btn {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.75rem;
    height: 1.75rem;
    background: rgba(31, 41, 55, 0.6);
    border: 1px solid rgba(75, 85, 99, 0.3);
    border-radius: 0.375rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
    padding: 0;
    touch-action: manipulation;
  }

  .mode-btn:hover {
    background: rgba(55, 65, 81, 0.8);
    border-color: rgba(107, 114, 128, 0.5);
    color: #d1d5db;
  }

  .mode-btn.active {
    background: rgba(6, 182, 212, 0.2);
    border-color: rgba(6, 182, 212, 0.6);
    color: #22d3ee;
    box-shadow: 0 0 10px rgba(6, 182, 212, 0.25);
  }

  .mode-btn.layout-active {
    border-color: rgba(6, 182, 212, 0.35);
    color: rgba(34, 211, 238, 0.55);
  }

  .mode-btn :global(svg) {
    width: 1rem;
    height: 1rem;
  }

  /* ── Bottom overlays (hover to expand) ─────────────── */

  .bottom-overlay {
    position: absolute;
    bottom: 1rem;
    z-index: 10;
  }

  .bottom-left { left: 1rem; }
  .bottom-right { right: 1rem; }

  .bottom-trigger {
    display: flex;
    align-items: center;
    justify-content: center;
    min-width: 2.5rem;
    height: 2.5rem;
    padding: 0 0.5rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    color: #d1d5db;
    font-size: 1rem;
    cursor: default;
  }

  .stats-trigger {
    font-size: 0.7rem;
    color: #9ca3af;
    font-variant-numeric: tabular-nums;
  }

  .bottom-panel {
    display: flex;
    gap: 0.5rem;
    padding: 0.5rem 0.75rem;
    margin-top: 0.375rem;
    background: rgba(31, 41, 55, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    backdrop-filter: blur(8px);
    opacity: 0;
    visibility: hidden;
    transform: translateY(8px);
    transition: opacity 0.2s ease, transform 0.2s ease, visibility 0.2s;
    position: absolute;
    bottom: 100%;
    white-space: nowrap;
    font-size: 0.7rem;
    color: #9ca3af;
  }

  .bottom-left .bottom-panel { left: 0; }
  .bottom-right .bottom-panel { right: 0; }

  .bottom-panel::after {
    content: '';
    position: absolute;
    bottom: -0.375rem;
    left: 0;
    right: 0;
    height: 0.375rem;
  }

  .bottom-overlay.open .bottom-panel {
    opacity: 1;
    visibility: visible;
    transform: translateY(0);
  }

  @media (hover: hover) and (pointer: fine) {
    .bottom-overlay:hover .bottom-panel {
      opacity: 1;
      visibility: visible;
      transform: translateY(0);
    }
  }

  /* Compact hover tooltip - follows cursor */
  .hover-tooltip {
    position: fixed;
    display: flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.375rem 0.625rem;
    background: rgba(17, 24, 39, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.6);
    border-radius: 0.375rem;
    z-index: 30;
    pointer-events: none;
    white-space: nowrap;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
  }

  .hover-icon {
    font-size: 0.8rem;
  }

  .hover-label {
    font-size: 0.75rem;
    font-weight: 600;
    color: #f3f4f6;
  }

  .hover-meta {
    font-size: 0.7rem;
    color: #9ca3af;
  }

  /* Selected node bottom bar */
  .bottom-bar {
    position: absolute;
    bottom: 3.5rem;
    left: 50%;
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: 0.5rem;
    max-width: calc(100% - 2rem);
    padding: 0.5rem 0.75rem;
    background: rgba(17, 24, 39, 0.95);
    border: 1px solid rgba(75, 85, 99, 0.5);
    border-radius: 0.5rem;
    z-index: 20;
    box-shadow: 0 -4px 16px rgba(0, 0, 0, 0.3);
  }

  .bottom-bar-main {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    overflow-x: auto;
    white-space: nowrap;
    scrollbar-width: none;
  }

  .bottom-bar-main::-webkit-scrollbar {
    display: none;
  }

  .bottom-bar-icon {
    font-size: 0.9rem;
    flex-shrink: 0;
  }

  .bottom-bar-type {
    font-size: 0.65rem;
    text-transform: uppercase;
    letter-spacing: 0.04em;
    color: #6b7280;
    flex-shrink: 0;
  }

  .bottom-bar-label {
    font-size: 0.8rem;
    font-weight: 600;
    color: #f3f4f6;
    flex-shrink: 0;
  }

  .bottom-bar-sep {
    color: #374151;
    font-size: 0.7rem;
    flex-shrink: 0;
  }

  .bottom-bar-detail {
    font-size: 0.75rem;
    color: #d1d5db;
    flex-shrink: 0;
  }

  .bottom-bar-tag {
    font-size: 0.65rem;
    padding: 0.125rem 0.375rem;
    background: rgba(75, 85, 99, 0.4);
    border-radius: 0.25rem;
    color: #d1d5db;
    flex-shrink: 0;
  }

  .bottom-bar-value {
    font-size: 0.7rem;
    font-family: monospace;
    color: #a5f3fc;
    max-width: 200px;
    overflow: hidden;
    text-overflow: ellipsis;
    flex-shrink: 0;
  }

  .bottom-bar-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.25rem;
    height: 1.25rem;
    background: rgba(55, 65, 81, 0.5);
    border: none;
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    flex-shrink: 0;
  }

  .bottom-bar-close:hover {
    background: rgba(75, 85, 99, 0.5);
    color: #d1d5db;
  }

  /* Export modal */
  .export-overlay {
    position: fixed;
    inset: 0;
    background: rgba(0, 0, 0, 0.6);
    display: flex;
    align-items: center;
    justify-content: center;
    z-index: 10000;
    backdrop-filter: blur(4px);
  }

  .export-modal {
    background: #1f2937;
    border: 1px solid rgba(75, 85, 99, 0.6);
    border-radius: 0.75rem;
    width: 22rem;
    box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
  }

  .export-header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 1rem 1.25rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.3);
  }

  .export-title {
    font-size: 0.95rem;
    font-weight: 600;
    color: #f3f4f6;
  }

  .export-close {
    display: flex;
    align-items: center;
    justify-content: center;
    width: 1.5rem;
    height: 1.5rem;
    background: none;
    border: none;
    color: #9ca3af;
    cursor: pointer;
    border-radius: 0.25rem;
  }

  .export-close:hover {
    background: rgba(75, 85, 99, 0.4);
    color: #d1d5db;
  }

  .export-body {
    padding: 1.25rem;
    display: flex;
    flex-direction: column;
    gap: 1.25rem;
  }

  .export-field {
    display: flex;
    flex-direction: column;
    gap: 0.5rem;
  }

  .export-label {
    font-size: 0.75rem;
    font-weight: 500;
    color: #9ca3af;
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .export-options {
    display: flex;
    gap: 0.375rem;
  }

  .export-option {
    flex: 1;
    padding: 0.5rem 0.75rem;
    background: rgba(31, 41, 55, 0.8);
    border: 1px solid rgba(75, 85, 99, 0.4);
    border-radius: 0.375rem;
    color: #d1d5db;
    font-size: 0.8rem;
    font-weight: 500;
    cursor: pointer;
    transition: all 0.15s;
    text-align: center;
  }

  .export-option:hover {
    background: rgba(55, 65, 81, 0.6);
    border-color: rgba(107, 114, 128, 0.6);
  }

  .export-option.active {
    background: rgba(6, 182, 212, 0.15);
    border-color: rgba(6, 182, 212, 0.5);
    color: #22d3ee;
  }

  .export-hint {
    font-size: 0.7rem;
    color: #6b7280;
  }

  .export-warn {
    color: #f59e0b;
  }

  .export-footer {
    display: flex;
    gap: 0.5rem;
    padding: 1rem 1.25rem;
    border-top: 1px solid rgba(75, 85, 99, 0.3);
    justify-content: flex-end;
  }

  .export-cancel {
    padding: 0.5rem 1rem;
    background: none;
    border: 1px solid rgba(75, 85, 99, 0.4);
    border-radius: 0.375rem;
    color: #9ca3af;
    font-size: 0.8rem;
    cursor: pointer;
  }

  .export-cancel:hover {
    background: rgba(55, 65, 81, 0.4);
    color: #d1d5db;
  }

  .export-submit {
    padding: 0.5rem 1.25rem;
    background: #0891b2;
    border: none;
    border-radius: 0.375rem;
    color: white;
    font-size: 0.8rem;
    font-weight: 500;
    cursor: pointer;
    transition: background 0.15s;
  }

  .export-submit:hover:not(:disabled) {
    background: #06b6d4;
  }

  .export-submit:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }

  /* Recording */
  .control-btn.recording {
    background: rgba(220, 38, 38, 0.3);
    border-color: rgba(239, 68, 68, 0.6);
    color: #fca5a5;
  }

  .control-btn.recording:hover {
    background: rgba(220, 38, 38, 0.5);
    border-color: rgba(239, 68, 68, 0.8);
  }

  .control-btn.sound-active {
    background: rgba(16, 185, 129, 0.2);
    border-color: rgba(52, 211, 153, 0.5);
    color: #6ee7b7;
  }

  .control-btn.sound-active:hover {
    background: rgba(16, 185, 129, 0.35);
    border-color: rgba(52, 211, 153, 0.7);
  }

  .season-btn {
    width: 2rem;
    height: 2rem;
    display: flex;
    align-items: center;
    justify-content: center;
    border: none;
    background: transparent;
    border-radius: 0.375rem;
    cursor: pointer;
    font-size: 0.875rem;
    color: #d1d5db;
    opacity: 0.5;
    transition: all 0.15s ease;
    touch-action: manipulation;
  }

  .season-btn:hover {
    opacity: 0.8;
    background: rgba(55, 65, 81, 0.9);
  }

  .season-btn.active {
    opacity: 1;
    background: rgba(75, 85, 99, 0.5);
  }

  .recording-indicator {
    position: absolute;
    top: 1rem;
    left: 4rem;
    display: flex;
    align-items: center;
    gap: 0.5rem;
    padding: 0.4rem 0.75rem;
    background: rgba(31, 41, 55, 0.9);
    border: 1px solid rgba(239, 68, 68, 0.5);
    border-radius: 0.5rem;
    z-index: 10;
    font-size: 0.75rem;
    font-weight: 600;
  }

  .rec-dot {
    width: 0.5rem;
    height: 0.5rem;
    border-radius: 50%;
    background: #ef4444;
    animation: rec-blink 1s ease-in-out infinite;
  }

  .rec-label {
    color: #ef4444;
    letter-spacing: 0.08em;
  }

  .rec-time {
    color: #d1d5db;
    font-variant-numeric: tabular-nums;
  }

  @keyframes rec-blink {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  @keyframes spin {
    from { transform: rotate(0deg); }
    to { transform: rotate(360deg); }
  }

  .animate-spin {
    animation: spin 1s linear infinite;
  }

  /* ── Mobile Responsive ─────────────────────────────── */

  @media (max-width: 767px) {
    .sidebar-trigger {
      width: 2.25rem;
      height: 2.25rem;
    }

    .sidebar-left .mode-btn {
      width: 2.5rem;
      height: 2.5rem;
    }

    .recording-indicator {
      left: 3.75rem;
    }

    .legend {
      bottom: 0.5rem;
      left: 0.5rem;
      padding: 0.375rem 0.5rem;
      gap: 0.5rem;
      font-size: 0.625rem;
    }

    .legend-dot {
      width: 7px;
      height: 7px;
    }

    .stats {
      bottom: 0.5rem;
      right: 0.5rem;
      padding: 0.25rem 0.5rem;
      gap: 0.5rem;
      font-size: 0.6rem;
    }

    [data-tooltip]::after {
      display: none;
    }

    .bottom-bar {
      bottom: 3.5rem;
    }
  }
</style>

<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors = [] }: {
    sensors: Array<{
      sensor_id: string;
      sensor_name?: string;
      gaze_x: number;
      gaze_y: number;
      confidence: number;
      aperture_left: number;
      aperture_right: number;
      blinking: number;
      worn: number;
    }>;
  } = $props();

  // ─── Types ─────────────────────────────────────────────
  type GazeViewMode = "faces" | "heatmap" | "scanpath" | "stats";

  interface GazePoint { x: number; y: number; timestamp: number; confidence: number; }

  interface SensorState {
    sensor_id: string;
    sensor_name: string;
    gazeX: number;
    gazeY: number;
    targetGazeX: number;
    targetGazeY: number;
    confidence: number;
    apertureLeft: number;
    apertureRight: number;
    targetApertureLeft: number;
    targetApertureRight: number;
    blinking: boolean;
    worn: boolean;
    lastUpdate: number;
    mustacheIndex: number;
    colorIndex: number;
    gazeHistory: GazePoint[];
    fixations: Array<{ x: number; y: number; duration: number; timestamp: number }>;
    saccadeCount: number;
    blinkCount: number;
    startTime: number;
    inFixation: boolean;
    fixationStart: number;
    fixationCenterX: number;
    fixationCenterY: number;
  }

  interface StatsRow {
    sensor_id: string;
    sensor_name: string;
    fixationCount: number;
    avgFixationDuration: number;
    saccadeCount: number;
    blinkRate: number;
    avgConfidence: number;
    worn: boolean;
  }

  // ─── State ─────────────────────────────────────────────
  let viewMode = $state<GazeViewMode>("faces");
  let sensorStates: Map<string, SensorState> = new Map();
  let sensorList = $state<SensorState[]>([]);
  let activeSensorCount = $state(0);
  let totalSensorCount = $state(0);
  let statsData = $state<StatsRow[]>([]);
  let rafId: number | null = null;

  // Heatmap
  let heatmapCanvas: HTMLCanvasElement;
  let heatmapCtx: CanvasRenderingContext2D | null = null;
  let heatmapGrid = new Float32Array(100 * 100);
  const HEATMAP_RES = 100;
  const HEATMAP_DECAY = 0.99995;

  // Scanpath
  let scanpathCanvas: HTMLCanvasElement;
  let scanpathCtx: CanvasRenderingContext2D | null = null;

  // Constants
  const LERP_FACTOR = 0.12;
  const APERTURE_LERP = 0.15;
  const STALE_THRESHOLD_MS = 5000;
  const MAX_HISTORY = 1000;
  const MAX_FIXATIONS = 100;
  const TRAIL_DURATION_MS = 5000;
  const FIXATION_DIST_THRESHOLD = 0.03;
  const FIXATION_MIN_MS = 120;
  const STATS_INTERVAL_MS = 500;
  let lastStatsUpdate = 0;

  const SENSOR_COLORS = Array.from({ length: 60 }, (_, i) =>
    `hsl(${(i * 137.508) % 360}, 70%, 60%)`
  );

  // ─── Hash + helpers ────────────────────────────────────
  function hashString(str: string): number {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      hash = ((hash << 5) - hash) + str.charCodeAt(i);
      hash |= 0;
    }
    return Math.abs(hash);
  }

  let nextColorIndex = 0;

  function getOrCreateSensor(sensor_id: string, sensor_name?: string): SensorState {
    let state = sensorStates.get(sensor_id);
    if (!state) {
      state = {
        sensor_id,
        sensor_name: sensor_name || sensor_id,
        gazeX: 0.5, gazeY: 0.5,
        targetGazeX: 0.5, targetGazeY: 0.5,
        confidence: 0,
        apertureLeft: 15, apertureRight: 15,
        targetApertureLeft: 15, targetApertureRight: 15,
        blinking: false, worn: true,
        lastUpdate: Date.now(),
        mustacheIndex: hashString(sensor_id) % 4,
        colorIndex: nextColorIndex++,
        gazeHistory: [],
        fixations: [],
        saccadeCount: 0,
        blinkCount: 0,
        startTime: Date.now(),
        inFixation: false,
        fixationStart: 0,
        fixationCenterX: 0.5,
        fixationCenterY: 0.5,
      };
      sensorStates.set(sensor_id, state);
    }
    return state;
  }

  function initFromProps() {
    sensors.forEach((s) => {
      const state = getOrCreateSensor(s.sensor_id, s.sensor_name);
      state.targetGazeX = s.gaze_x ?? 0.5;
      state.targetGazeY = s.gaze_y ?? 0.5;
      state.confidence = s.confidence ?? 0;
      state.targetApertureLeft = s.aperture_left ?? 15;
      state.targetApertureRight = s.aperture_right ?? 15;
      state.blinking = (s.blinking ?? 0) > 0.5;
      state.worn = (s.worn ?? 1) > 0.5;
      state.lastUpdate = Date.now();
    });
    rebuildSensorList();
  }

  function rebuildSensorList() {
    sensorList = Array.from(sensorStates.values());
    totalSensorCount = sensorList.length;
    const now = Date.now();
    activeSensorCount = sensorList.filter(s => (now - s.lastUpdate) < STALE_THRESHOLD_MS).length;
  }

  // ─── Fixation detection ────────────────────────────────
  function processGazeForScience(state: SensorState, x: number, y: number, confidence: number) {
    const now = Date.now();

    // Add to history
    state.gazeHistory.push({ x, y, timestamp: now, confidence });
    if (state.gazeHistory.length > MAX_HISTORY) state.gazeHistory.shift();

    // Heatmap: accumulate regardless of active view
    if (confidence > 0.5) {
      const gx = Math.min(HEATMAP_RES - 1, Math.max(0, Math.floor(x * HEATMAP_RES)));
      const gy = Math.min(HEATMAP_RES - 1, Math.max(0, Math.floor(y * HEATMAP_RES)));
      // Gaussian splat: center + 4 neighbors
      const idx = gy * HEATMAP_RES + gx;
      heatmapGrid[idx] += confidence * 0.15;
      if (gx > 0) heatmapGrid[idx - 1] += confidence * 0.05;
      if (gx < HEATMAP_RES - 1) heatmapGrid[idx + 1] += confidence * 0.05;
      if (gy > 0) heatmapGrid[idx - HEATMAP_RES] += confidence * 0.05;
      if (gy < HEATMAP_RES - 1) heatmapGrid[idx + HEATMAP_RES] += confidence * 0.05;
    }

    // Fixation detection: is gaze clustered?
    if (state.inFixation) {
      const dist = Math.sqrt((x - state.fixationCenterX) ** 2 + (y - state.fixationCenterY) ** 2);
      if (dist > FIXATION_DIST_THRESHOLD) {
        // End fixation
        const duration = now - state.fixationStart;
        if (duration >= FIXATION_MIN_MS) {
          state.fixations.push({
            x: state.fixationCenterX, y: state.fixationCenterY,
            duration, timestamp: state.fixationStart
          });
          if (state.fixations.length > MAX_FIXATIONS) state.fixations.shift();
        }
        state.inFixation = false;
        state.saccadeCount++;
      } else {
        // Update running center
        state.fixationCenterX = state.fixationCenterX * 0.95 + x * 0.05;
        state.fixationCenterY = state.fixationCenterY * 0.95 + y * 0.05;
      }
    } else {
      // Start new fixation candidate
      state.inFixation = true;
      state.fixationStart = now;
      state.fixationCenterX = x;
      state.fixationCenterY = y;
    }
  }

  // ─── RAF loop ──────────────────────────────────────────
  function rafLoop() {
    const now = Date.now();

    // Lerp faces
    let needsFacesUpdate = false;
    sensorStates.forEach((s) => {
      const dx = s.targetGazeX - s.gazeX;
      const dy = s.targetGazeY - s.gazeY;
      const dl = s.targetApertureLeft - s.apertureLeft;
      const dr = s.targetApertureRight - s.apertureRight;
      if (Math.abs(dx) > 0.001 || Math.abs(dy) > 0.001 || Math.abs(dl) > 0.01 || Math.abs(dr) > 0.01) {
        s.gazeX += dx * LERP_FACTOR;
        s.gazeY += dy * LERP_FACTOR;
        s.apertureLeft += dl * APERTURE_LERP;
        s.apertureRight += dr * APERTURE_LERP;
        needsFacesUpdate = true;
      }
    });

    if (viewMode === "faces" && needsFacesUpdate) {
      sensorList = Array.from(sensorStates.values());
    }

    // Render active canvas
    if (viewMode === "heatmap") renderHeatmap();
    if (viewMode === "scanpath") renderScanpath();

    // Throttled stats
    if (viewMode === "stats" && now - lastStatsUpdate > STATS_INTERVAL_MS) {
      updateStats();
      lastStatsUpdate = now;
    }

    // Periodic active count
    if (now % 1000 < 17) {
      activeSensorCount = Array.from(sensorStates.values()).filter(s => (now - s.lastUpdate) < STALE_THRESHOLD_MS).length;
    }

    rafId = requestAnimationFrame(rafLoop);
  }

  // ─── Heatmap rendering ─────────────────────────────────
  function renderHeatmap() {
    if (!heatmapCtx) {
      if (heatmapCanvas) heatmapCtx = heatmapCanvas.getContext("2d");
      if (!heatmapCtx) return;
    }
    const w = heatmapCanvas.width;
    const h = heatmapCanvas.height;
    const imageData = heatmapCtx.createImageData(w, h);
    const data = imageData.data;
    const cellW = w / HEATMAP_RES;
    const cellH = h / HEATMAP_RES;

    // Decay
    for (let i = 0; i < heatmapGrid.length; i++) heatmapGrid[i] *= HEATMAP_DECAY;

    // Find max
    let maxVal = 0.001;
    for (let i = 0; i < heatmapGrid.length; i++) {
      if (heatmapGrid[i] > maxVal) maxVal = heatmapGrid[i];
    }

    // Draw pixels
    for (let gy = 0; gy < HEATMAP_RES; gy++) {
      for (let gx = 0; gx < HEATMAP_RES; gx++) {
        const v = Math.min(1, heatmapGrid[gy * HEATMAP_RES + gx] / maxVal);
        const startX = Math.floor(gx * cellW);
        const endX = Math.floor((gx + 1) * cellW);
        const startY = Math.floor(gy * cellH);
        const endY = Math.floor((gy + 1) * cellH);

        let r: number, g: number, b: number, a: number;
        if (v < 0.01) { r = 15; g = 23; b = 42; a = 255; }
        else if (v < 0.25) { const t = v / 0.25; r = 15; g = 23; b = Math.floor(42 + 213 * t); a = 255; }
        else if (v < 0.5) { const t = (v - 0.25) / 0.25; r = 0; g = Math.floor(255 * t); b = Math.floor(255 * (1 - t)); a = 255; }
        else if (v < 0.75) { const t = (v - 0.5) / 0.25; r = Math.floor(255 * t); g = 255; b = 0; a = 255; }
        else { const t = (v - 0.75) / 0.25; r = 255; g = Math.floor(255 * (1 - t)); b = 0; a = 255; }

        for (let py = startY; py < endY; py++) {
          for (let px = startX; px < endX; px++) {
            const idx = (py * w + px) * 4;
            data[idx] = r; data[idx + 1] = g; data[idx + 2] = b; data[idx + 3] = a;
          }
        }
      }
    }
    heatmapCtx.putImageData(imageData, 0, 0);

    // Draw axis labels
    heatmapCtx.fillStyle = "#94a3b8";
    heatmapCtx.font = "11px monospace";
    heatmapCtx.fillText("0.0", 2, h - 2);
    heatmapCtx.fillText("1.0", w - 24, h - 2);
    heatmapCtx.fillText("0.0", 2, 12);
    heatmapCtx.fillText("X →", w / 2 - 10, h - 2);
    heatmapCtx.save();
    heatmapCtx.translate(10, h / 2 + 8);
    heatmapCtx.rotate(-Math.PI / 2);
    heatmapCtx.fillText("Y →", 0, 0);
    heatmapCtx.restore();
  }

  // ─── Scanpath rendering ────────────────────────────────
  function renderScanpath() {
    if (!scanpathCtx) {
      if (scanpathCanvas) scanpathCtx = scanpathCanvas.getContext("2d");
      if (!scanpathCtx) return;
    }
    const w = scanpathCanvas.width;
    const h = scanpathCanvas.height;
    const now = Date.now();
    const cutoff = now - TRAIL_DURATION_MS;

    scanpathCtx.fillStyle = "#0f172a";
    scanpathCtx.fillRect(0, 0, w, h);

    // Grid lines
    scanpathCtx.strokeStyle = "rgba(75, 85, 99, 0.2)";
    scanpathCtx.lineWidth = 0.5;
    for (let i = 0; i <= 10; i++) {
      const x = (i / 10) * w;
      const y = (i / 10) * h;
      scanpathCtx.beginPath(); scanpathCtx.moveTo(x, 0); scanpathCtx.lineTo(x, h); scanpathCtx.stroke();
      scanpathCtx.beginPath(); scanpathCtx.moveTo(0, y); scanpathCtx.lineTo(w, y); scanpathCtx.stroke();
    }

    sensorStates.forEach((state) => {
      const color = SENSOR_COLORS[state.colorIndex % SENSOR_COLORS.length];
      const history = state.gazeHistory.filter(p => p.timestamp > cutoff);
      if (history.length < 2) return;

      // Draw trail
      scanpathCtx!.lineWidth = 1.5;
      scanpathCtx!.lineCap = "round";
      scanpathCtx!.lineJoin = "round";

      for (let i = 1; i < history.length; i++) {
        const p0 = history[i - 1];
        const p1 = history[i];
        const alpha = Math.max(0.05, 1 - (now - p1.timestamp) / TRAIL_DURATION_MS);
        scanpathCtx!.strokeStyle = color;
        scanpathCtx!.globalAlpha = alpha * 0.6;
        scanpathCtx!.beginPath();
        scanpathCtx!.moveTo(p0.x * w, p0.y * h);
        scanpathCtx!.lineTo(p1.x * w, p1.y * h);
        scanpathCtx!.stroke();
      }

      // Draw fixations as circles
      state.fixations.forEach(fix => {
        if (fix.timestamp + fix.duration < cutoff) return;
        const radius = Math.min(30, Math.sqrt(fix.duration / 5));
        scanpathCtx!.globalAlpha = 0.25;
        scanpathCtx!.fillStyle = color;
        scanpathCtx!.beginPath();
        scanpathCtx!.arc(fix.x * w, fix.y * h, radius, 0, Math.PI * 2);
        scanpathCtx!.fill();
        scanpathCtx!.globalAlpha = 0.7;
        scanpathCtx!.strokeStyle = color;
        scanpathCtx!.lineWidth = 1.5;
        scanpathCtx!.stroke();
      });

      // Current position dot
      const last = history[history.length - 1];
      scanpathCtx!.globalAlpha = 1;
      scanpathCtx!.fillStyle = color;
      scanpathCtx!.beginPath();
      scanpathCtx!.arc(last.x * w, last.y * h, 4, 0, Math.PI * 2);
      scanpathCtx!.fill();
      scanpathCtx!.strokeStyle = "#fff";
      scanpathCtx!.lineWidth = 1;
      scanpathCtx!.stroke();
    });

    scanpathCtx.globalAlpha = 1;

    // Axis labels
    scanpathCtx.fillStyle = "#64748b";
    scanpathCtx.font = "11px monospace";
    scanpathCtx.fillText("(0,0)", 2, 12);
    scanpathCtx.fillText("(1,1)", w - 32, h - 4);
  }

  // ─── Stats ─────────────────────────────────────────────
  function updateStats() {
    const now = Date.now();
    const rows: StatsRow[] = [];
    sensorStates.forEach((state) => {
      const uptimeS = Math.max(1, (now - state.startTime) / 1000);
      const blinkRate = (state.blinkCount / uptimeS) * 60;
      const totalFixDur = state.fixations.reduce((s, f) => s + f.duration, 0);
      const avgFix = state.fixations.length > 0 ? totalFixDur / state.fixations.length : 0;
      rows.push({
        sensor_id: state.sensor_id,
        sensor_name: state.sensor_name,
        fixationCount: state.fixations.length,
        avgFixationDuration: Math.round(avgFix),
        saccadeCount: state.saccadeCount,
        blinkRate: Math.round(blinkRate * 10) / 10,
        avgConfidence: state.confidence,
        worn: state.worn,
      });
    });
    rows.sort((a, b) => b.fixationCount - a.fixationCount);
    statsData = rows;
  }

  // ─── Helpers ───────────────────────────────────────────
  function apertureToOpenness(degrees: number): number {
    return Math.max(0, Math.min(1, degrees / 25));
  }

  function gazeToPupilOffset(gaze: number, range: number): number {
    return (gaze - 0.5) * range * 2;
  }

  function confidenceColor(c: number): string {
    if (c > 0.8) return "#22c55e";
    if (c > 0.5) return "#eab308";
    return "#ef4444";
  }

  const MUSTACHES = [
    { path: "M50,62 C50,62 45,58 38,60 C31,62 28,67 25,68 C22,69 18,66 18,66 C18,66 22,72 28,70 C34,68 38,66 42,64 C46,62 50,65 50,65 C50,65 54,62 58,64 C62,66 66,68 72,70 C78,72 82,66 82,66 C82,66 78,69 75,68 C72,67 69,62 62,60 C55,58 50,62 50,62 Z", color: "#8B4513", name: "Handlebar" },
    { path: "M50,60 C50,60 42,56 35,62 C30,66 30,70 30,70 C30,70 33,66 38,63 C43,60 48,62 50,63 C52,62 57,60 62,63 C67,66 70,70 70,70 C70,70 70,66 65,62 C58,56 50,60 50,60 Z", color: "#5C3317", name: "Chevron" },
    { path: "M32,64 C32,64 38,62 44,62 C48,62 50,63 50,63 C50,63 52,62 56,62 C62,62 68,64 68,64 C68,64 68,66 68,66 C68,66 62,64 56,64 C52,64 50,65 50,65 C50,65 48,64 44,64 C38,64 32,66 32,66 C32,66 32,64 32,64 Z", color: "#374151", name: "Pencil" },
    { path: "M50,61 C50,61 44,58 36,61 C28,64 25,70 24,74 C23,76 26,76 27,74 C28,72 30,67 36,64 C42,61 48,63 50,64 C52,63 58,61 64,64 C70,67 72,72 73,74 C74,76 77,76 76,74 C75,70 72,64 64,61 C56,58 50,61 50,61 Z", color: "#78716C", name: "Walrus" },
  ];

  // Reset canvas contexts when switching tabs (canvas DOM elements get destroyed/recreated by {#if})
  $effect(() => {
    viewMode;
    heatmapCtx = null;
    scanpathCtx = null;
  });

  // ─── Lifecycle ─────────────────────────────────────────
  onMount(() => {
    initFromProps();
    rafId = requestAnimationFrame(rafLoop);

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload } = e.detail;
      const state = getOrCreateSensor(sensor_id);
      state.lastUpdate = Date.now();

      switch (attribute_id) {
        case "eye_gaze": {
          if (payload && typeof payload === "object") {
            const x = payload.x ?? payload["x"];
            const y = payload.y ?? payload["y"];
            const conf = payload.confidence ?? payload["confidence"];
            if (typeof x === "number") state.targetGazeX = x;
            if (typeof y === "number") state.targetGazeY = y;
            if (typeof conf === "number") state.confidence = conf;
            if (typeof x === "number" && typeof y === "number") {
              processGazeForScience(state, x, y, conf ?? 0);
            }
          }
          break;
        }
        case "eye_aperture": {
          if (payload && typeof payload === "object") {
            const left = payload.left ?? payload["left"];
            const right = payload.right ?? payload["right"];
            if (typeof left === "number") state.targetApertureLeft = left;
            if (typeof right === "number") state.targetApertureRight = right;
          }
          break;
        }
        case "eye_blink": {
          const val = typeof payload === "number" ? payload : 0;
          const wasBlink = state.blinking;
          state.blinking = val > 0.5;
          if (state.blinking && !wasBlink) state.blinkCount++;
          break;
        }
        case "eye_worn": {
          const val = typeof payload === "number" ? payload : 1;
          state.worn = val > 0.5;
          break;
        }
      }

      if (sensorStates.size !== sensorList.length) rebuildSensorList();
    };

    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.dispatchEvent(new CustomEvent("composite-component-ready"));

    return () => {
      window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    };
  });

  onDestroy(() => {
    if (rafId) { cancelAnimationFrame(rafId); rafId = null; }
  });
</script>

<div class="gaze-container">
  <div class="gaze-header">
    <h2>Eye Tracking</h2>
    <span class="sensor-count">{totalSensorCount} tracker{totalSensorCount !== 1 ? 's' : ''}</span>
    <span class="active-count" class:active={activeSensorCount > 0}>
      {activeSensorCount} active
    </span>

    <div class="mode-selector">
      <button class="mode-btn" class:active={viewMode === "faces"} onclick={() => viewMode = "faces"} title="Faces — Googly eyes view">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="9" cy="10" r="1.5"/><circle cx="15" cy="10" r="1.5"/><path d="M8 15c1.5 2 6.5 2 8 0"/><circle cx="12" cy="12" r="10"/></svg>
      </button>
      <button class="mode-btn" class:active={viewMode === "heatmap"} onclick={() => viewMode = "heatmap"} title="Heatmap — Aggregated gaze density">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect x="3" y="3" width="7" height="7" rx="1"/><rect x="14" y="3" width="7" height="7" rx="1"/><rect x="3" y="14" width="7" height="7" rx="1"/><rect x="14" y="14" width="7" height="7" rx="1"/></svg>
      </button>
      <button class="mode-btn" class:active={viewMode === "scanpath"} onclick={() => viewMode = "scanpath"} title="Scanpath — Gaze trajectories with fixations">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 17l4-4 4 4 4-8 6 8"/><circle cx="7" cy="13" r="1.5" fill="currentColor"/><circle cx="15" cy="9" r="2" fill="currentColor" opacity="0.5"/></svg>
      </button>
      <button class="mode-btn" class:active={viewMode === "stats"} onclick={() => { viewMode = "stats"; updateStats(); }} title="Stats — Real-time metrics table">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M3 10h18M3 14h18M3 6h18M3 18h18"/><path d="M8 6v12"/></svg>
      </button>
    </div>
  </div>

  <!-- Faces View -->
  {#if viewMode === "faces"}
    <div class="gaze-grid">
      {#each sensorList as sensor (sensor.sensor_id)}
        {@const leftOpenness = sensor.blinking ? 0 : apertureToOpenness(sensor.apertureLeft)}
        {@const rightOpenness = sensor.blinking ? 0 : apertureToOpenness(sensor.apertureRight)}
        {@const pupilOffsetX = gazeToPupilOffset(sensor.gazeX, 12)}
        {@const pupilOffsetY = gazeToPupilOffset(sensor.gazeY, 8)}
        {@const mustache = MUSTACHES[sensor.mustacheIndex]}
        {@const isStale = (Date.now() - sensor.lastUpdate) > STALE_THRESHOLD_MS}

        <div class="face-card" class:stale={isStale}>
          <div class="face-name">{sensor.sensor_name}</div>
          <div class="face-mustache-label">{mustache.name}</div>
          <svg viewBox="0 0 100 100" class="face-svg">
            <ellipse cx="50" cy="48" rx="38" ry="42" fill="#1e293b" stroke="#475569" stroke-width="0.8" />
            <g transform="translate(35, 38)">
              {#if !sensor.worn}
                <line x1="-6" y1="-6" x2="6" y2="6" stroke="#ef4444" stroke-width="2" stroke-linecap="round" />
                <line x1="6" y1="-6" x2="-6" y2="6" stroke="#ef4444" stroke-width="2" stroke-linecap="round" />
              {:else}
                <ellipse cx="0" cy="0" rx="10" ry={10 * leftOpenness} fill="white" stroke="#94a3b8" stroke-width="0.5" />
                {#if leftOpenness > 0.05}
                  <circle cx={pupilOffsetX * leftOpenness} cy={pupilOffsetY * leftOpenness} r={5 * Math.min(leftOpenness, 1)} fill="#1e3a5f" />
                  <circle cx={pupilOffsetX * leftOpenness} cy={pupilOffsetY * leftOpenness} r={2.5 * Math.min(leftOpenness, 1)} fill="#0f172a" />
                  <circle cx={pupilOffsetX * leftOpenness - 1.5} cy={pupilOffsetY * leftOpenness - 1.5} r={1.2 * Math.min(leftOpenness, 1)} fill="white" opacity="0.7" />
                {/if}
                {#if leftOpenness < 0.95}
                  <ellipse cx="0" cy={-10 * leftOpenness} rx="10.5" ry={10 * (1 - leftOpenness)} fill="#1e293b" />
                {/if}
              {/if}
            </g>
            <g transform="translate(65, 38)">
              {#if !sensor.worn}
                <line x1="-6" y1="-6" x2="6" y2="6" stroke="#ef4444" stroke-width="2" stroke-linecap="round" />
                <line x1="6" y1="-6" x2="-6" y2="6" stroke="#ef4444" stroke-width="2" stroke-linecap="round" />
              {:else}
                <ellipse cx="0" cy="0" rx="10" ry={10 * rightOpenness} fill="white" stroke="#94a3b8" stroke-width="0.5" />
                {#if rightOpenness > 0.05}
                  <circle cx={pupilOffsetX * rightOpenness} cy={pupilOffsetY * rightOpenness} r={5 * Math.min(rightOpenness, 1)} fill="#1e3a5f" />
                  <circle cx={pupilOffsetX * rightOpenness} cy={pupilOffsetY * rightOpenness} r={2.5 * Math.min(rightOpenness, 1)} fill="#0f172a" />
                  <circle cx={pupilOffsetX * rightOpenness - 1.5} cy={pupilOffsetY * rightOpenness - 1.5} r={1.2 * Math.min(rightOpenness, 1)} fill="white" opacity="0.7" />
                {/if}
                {#if rightOpenness < 0.95}
                  <ellipse cx="0" cy={-10 * rightOpenness} rx="10.5" ry={10 * (1 - rightOpenness)} fill="#1e293b" />
                {/if}
              {/if}
            </g>
            <path d="M48,48 Q50,54 52,48" fill="none" stroke="#475569" stroke-width="0.6" />
            <path d={mustache.path} fill={mustache.color} opacity="0.9" />
          </svg>
          <div class="confidence-bar">
            <div class="confidence-fill" style="width: {sensor.confidence * 100}%; background-color: {confidenceColor(sensor.confidence)}"></div>
          </div>
          <div class="confidence-label">
            {#if !sensor.worn}<span class="not-worn">Not worn</span>
            {:else if sensor.blinking}<span class="blinking">Blinking</span>
            {:else}Confidence: {(sensor.confidence * 100).toFixed(0)}%{/if}
          </div>
        </div>
      {/each}
    </div>
  {/if}

  <!-- Heatmap View -->
  {#if viewMode === "heatmap"}
    <div class="canvas-container">
      <canvas bind:this={heatmapCanvas} width="600" height="600" class="viz-canvas"></canvas>
      <div class="heatmap-legend">
        <span class="legend-label">Cold</span>
        <div class="legend-gradient"></div>
        <span class="legend-label">Hot</span>
      </div>
      <div class="canvas-info">Aggregated gaze density across all {totalSensorCount} trackers. Decays over time.</div>
    </div>
  {/if}

  <!-- Scanpath View -->
  {#if viewMode === "scanpath"}
    <div class="canvas-container">
      <canvas bind:this={scanpathCanvas} width="900" height="600" class="viz-canvas wide"></canvas>
      <div class="scanpath-legend">
        {#each Array.from(sensorStates.values()).slice(0, 12) as sensor}
          <div class="legend-item">
            <div class="legend-dot" style="background: {SENSOR_COLORS[sensor.colorIndex % SENSOR_COLORS.length]}"></div>
            <span>{sensor.sensor_name}</span>
          </div>
        {/each}
        {#if sensorStates.size > 12}
          <span class="legend-more">+{sensorStates.size - 12} more</span>
        {/if}
      </div>
      <div class="canvas-info">Gaze trails (last 5s). Circles = fixations (size = duration). Dots = current gaze.</div>
    </div>
  {/if}

  <!-- Stats View -->
  {#if viewMode === "stats"}
    <div class="stats-container">
      <div class="stats-summary">
        <div class="stat-card">
          <div class="stat-value">{statsData.length}</div>
          <div class="stat-label">Trackers</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">{statsData.reduce((s, r) => s + r.fixationCount, 0)}</div>
          <div class="stat-label">Total Fixations</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">
            {statsData.length > 0 ? Math.round(statsData.reduce((s, r) => s + r.avgFixationDuration, 0) / statsData.length) : 0}ms
          </div>
          <div class="stat-label">Avg Fixation</div>
        </div>
        <div class="stat-card">
          <div class="stat-value">
            {statsData.length > 0 ? (statsData.reduce((s, r) => s + r.avgConfidence, 0) / statsData.length * 100).toFixed(0) : 0}%
          </div>
          <div class="stat-label">Avg Confidence</div>
        </div>
      </div>
      <div class="stats-table-wrap">
        <table class="stats-table">
          <thead>
            <tr>
              <th>Sensor</th>
              <th>Fixations</th>
              <th>Avg Fix (ms)</th>
              <th>Saccades</th>
              <th>Blinks/min</th>
              <th>Confidence</th>
              <th>Status</th>
            </tr>
          </thead>
          <tbody>
            {#each statsData as row (row.sensor_id)}
              <tr>
                <td class="sensor-name-cell">{row.sensor_name}</td>
                <td>{row.fixationCount}</td>
                <td>{row.avgFixationDuration}</td>
                <td>{row.saccadeCount}</td>
                <td>{row.blinkRate}</td>
                <td>
                  <span class="conf-badge" style="background: {confidenceColor(row.avgConfidence)}">{(row.avgConfidence * 100).toFixed(0)}%</span>
                </td>
                <td>
                  {#if !row.worn}<span class="not-worn">Off</span>
                  {:else}<span class="status-ok">Active</span>{/if}
                </td>
              </tr>
            {/each}
          </tbody>
        </table>
      </div>
    </div>
  {/if}
</div>

<style>
  .gaze-container { padding: 1rem; }

  .gaze-header {
    display: flex;
    align-items: center;
    gap: 0.75rem;
    margin-bottom: 1rem;
    flex-wrap: wrap;
  }
  .gaze-header h2 { font-size: 1.1rem; font-weight: 600; color: #e2e8f0; margin: 0; }

  .sensor-count, .active-count {
    font-size: 0.75rem; color: #94a3b8; background: #1e293b;
    padding: 0.15rem 0.5rem; border-radius: 9999px;
  }
  .active-count.active { color: #22c55e; background: rgba(34, 197, 94, 0.1); }

  .mode-selector {
    display: flex; gap: 0.35rem; margin-left: auto;
    background: rgba(31, 41, 55, 0.7); padding: 0.25rem;
    border-radius: 0.5rem; border: 1px solid rgba(75, 85, 99, 0.3);
  }
  .mode-btn {
    display: flex; align-items: center; justify-content: center;
    width: 2rem; height: 2rem; background: transparent;
    border: 1px solid transparent; border-radius: 0.375rem;
    color: #9ca3af; cursor: pointer; transition: all 0.15s; padding: 0.25rem;
  }
  .mode-btn:hover { background: rgba(55, 65, 81, 0.8); color: #d1d5db; }
  .mode-btn.active {
    background: rgba(6, 182, 212, 0.2); border-color: rgba(6, 182, 212, 0.6);
    color: #22d3ee; box-shadow: 0 0 8px rgba(6, 182, 212, 0.25);
  }
  .mode-btn :global(svg) { width: 1rem; height: 1rem; }

  /* ─── Faces ───────────────────────── */
  .gaze-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
    gap: 0.75rem;
  }
  .face-card {
    background: #0f172a; border: 1px solid #334155; border-radius: 0.75rem;
    padding: 0.5rem; text-align: center; transition: border-color 0.3s;
  }
  .face-card:hover { border-color: #06b6d4; }
  .face-card.stale { opacity: 0.5; border-color: #1e293b; }
  .face-name { font-size: 0.7rem; font-weight: 500; color: #e2e8f0; margin-bottom: 0.1rem; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .face-mustache-label { font-size: 0.6rem; color: #64748b; margin-bottom: 0.15rem; }
  .face-svg { width: 100%; max-width: 140px; margin: 0 auto; display: block; }
  .confidence-bar { height: 2px; background: #1e293b; border-radius: 2px; margin-top: 0.35rem; overflow: hidden; }
  .confidence-fill { height: 100%; border-radius: 2px; transition: width 0.3s ease; }
  .confidence-label { font-size: 0.6rem; color: #64748b; margin-top: 0.15rem; }
  .not-worn { color: #ef4444; }
  .blinking { color: #eab308; }

  /* ─── Canvas views ────────────────── */
  .canvas-container { display: flex; flex-direction: column; align-items: center; gap: 0.75rem; }
  .viz-canvas {
    width: 100%; max-width: 600px; aspect-ratio: 1;
    border: 1px solid #334155; border-radius: 0.5rem;
    image-rendering: pixelated;
  }
  .viz-canvas.wide { max-width: 900px; aspect-ratio: 3/2; image-rendering: auto; }
  .canvas-info { font-size: 0.7rem; color: #64748b; text-align: center; }

  /* ─── Heatmap legend ──────────────── */
  .heatmap-legend { display: flex; align-items: center; gap: 0.5rem; }
  .legend-label { font-size: 0.7rem; color: #94a3b8; }
  .legend-gradient {
    width: 200px; height: 10px; border-radius: 5px;
    background: linear-gradient(to right, #0f172a, #1e40af, #22c55e, #eab308, #ef4444);
    border: 1px solid #334155;
  }

  /* ─── Scanpath legend ─────────────── */
  .scanpath-legend { display: flex; flex-wrap: wrap; gap: 0.5rem; justify-content: center; max-width: 900px; }
  .legend-item { display: flex; align-items: center; gap: 0.25rem; }
  .legend-dot { width: 8px; height: 8px; border-radius: 50%; flex-shrink: 0; }
  .legend-item span { font-size: 0.65rem; color: #94a3b8; }
  .legend-more { font-size: 0.65rem; color: #64748b; font-style: italic; }

  /* ─── Stats ───────────────────────── */
  .stats-container { display: flex; flex-direction: column; gap: 1rem; }
  .stats-summary { display: grid; grid-template-columns: repeat(auto-fit, minmax(120px, 1fr)); gap: 0.75rem; }
  .stat-card {
    background: #0f172a; border: 1px solid #334155; border-radius: 0.5rem;
    padding: 0.75rem; text-align: center;
  }
  .stat-value { font-size: 1.5rem; font-weight: 700; color: #e2e8f0; font-variant-numeric: tabular-nums; }
  .stat-label { font-size: 0.7rem; color: #64748b; margin-top: 0.25rem; }

  .stats-table-wrap { overflow-x: auto; }
  .stats-table {
    width: 100%; border-collapse: collapse; font-size: 0.75rem;
    font-variant-numeric: tabular-nums;
  }
  .stats-table th {
    text-align: left; padding: 0.5rem 0.75rem; color: #94a3b8;
    border-bottom: 1px solid #334155; font-weight: 500; white-space: nowrap;
  }
  .stats-table td {
    padding: 0.4rem 0.75rem; border-bottom: 1px solid rgba(51, 65, 85, 0.4); color: #e2e8f0;
  }
  .stats-table tbody tr:hover { background: rgba(6, 182, 212, 0.05); }
  .sensor-name-cell { font-weight: 500; white-space: nowrap; max-width: 180px; overflow: hidden; text-overflow: ellipsis; }
  .conf-badge {
    display: inline-block; padding: 0.1rem 0.4rem; border-radius: 9999px;
    font-size: 0.65rem; color: #fff; font-weight: 600;
  }
  .status-ok { color: #22c55e; }
</style>

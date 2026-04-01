<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; value: number }>;
  } = $props();

  let tracesCanvas: HTMLCanvasElement;

  const COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#06b6d4',
    '#3b82f6', '#8b5cf6', '#ec4899', '#14b8a6', '#f59e0b',
    '#6366f1', '#10b981', '#f43f5e', '#0ea5e9', '#a855f7',
    '#84cc16', '#e879f9', '#fb923c', '#2dd4bf', '#818cf8'
  ];

  const MAX_DATA_POINTS = 5000;
  const UPDATE_INTERVAL_MS = 32; // ~30fps for smooth trace rendering
  const PHASE_BUFFER_SIZE = 100; // ECG at 100Hz, ~1s window

  // Time windows — also define sample budget for continuous strip chart
  // At 100Hz: 3s=300, 10s=1000, 30s=3000 samples
  const TIME_WINDOWS = [
    { label: '3s', ms: 3 * 1000, samples: 300 },
    { label: '10s', ms: 10 * 1000, samples: 1000 },
    { label: '30s', ms: 30 * 1000, samples: 3000 }
  ];
  let selectedSamples = $state(TIME_WINDOWS[0].samples);

  type ViewMode = 'traces' | 'grid' | 'morphology' | 'sync';
  let viewMode = $state<ViewMode>('traces');
  let selectedWindowMs = $state(TIME_WINDOWS[0].ms);

  let sensorData: Map<string, Array<{ x: number; y: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();
  let sensorNames: Map<string, string> = new Map();
  let pendingUpdates: Map<string, Array<{ x: number; y: number }>> = new Map();
  let rafId: number | null = null;
  let lastUpdateTime = 0;
  let lastExtremesUpdate = 0;
  let latestDataTimestamp = 0;
  let dirtySeriesIds: Set<string> = new Set();

  // Traces interactivity: highlight + show/hide
  let hiddenSensors: Set<string> = new Set();
  let highlightedSensor = $state<string | null>(null);
  let legendSensorIds = $state<string[]>([]);

  // Phase sync (for sync heatmap)
  let phaseBuffers: Map<string, number[]> = new Map();
  let pairwiseSyncMatrix: Map<string, number> = new Map();
  let heatmapSensorIds = $state<string[]>([]);
  let heatmapData = $state<number[][]>([]);
  const PAIRWISE_SMOOTHING = 0.75;

  // Grid view: per-sensor canvas sparklines
  let gridSensorIds = $state<string[]>([]);
  let gridCanvases: Map<string, HTMLCanvasElement> = new Map();

  // Morphology view: mean beat extraction
  let morphologyCanvas: HTMLCanvasElement;
  let meanBeatData = $state<{ mean: number[]; upper: number[]; lower: number[]; outlierIds: string[] }>({
    mean: [], upper: [], lower: [], outlierIds: []
  });

  function getDisplayName(sensorId: string): string {
    return sensorNames.get(sensorId) || (sensorId.length > 12 ? sensorId.slice(-8) : sensorId);
  }

  function addToPhaseBuffer(sensorId: string, value: number) {
    let buffer = phaseBuffers.get(sensorId);
    if (!buffer) {
      buffer = [];
      phaseBuffers.set(sensorId, buffer);
    }
    buffer.push(value);
    if (buffer.length > PHASE_BUFFER_SIZE) {
      buffer.splice(0, buffer.length - PHASE_BUFFER_SIZE);
    }
  }

  // ── Pairwise Sync (reused from HRV/Breathing) ──
  function computePairwiseSync() {
    if (viewMode !== 'sync') return;

    const sensorPhases: Array<{ id: string; phase: number }> = [];
    phaseBuffers.forEach((buffer, sensorId) => {
      if (buffer.length < 10) return;
      const n = buffer.length;
      let min = buffer[0], max = buffer[0];
      for (let i = 1; i < n; i++) {
        if (buffer[i] < min) min = buffer[i];
        if (buffer[i] > max) max = buffer[i];
      }
      const range = max - min;
      if (range < 0.005) return; // ECG values are in mV, range ~0.3-1.2

      const current = buffer[n - 1];
      const norm = Math.max(0, Math.min(1, (current - min) / range));
      const lookback = Math.min(10, n - 1);
      const derivative = buffer[n - 1] - buffer[n - 1 - lookback];
      const baseAngle = Math.acos(1 - 2 * norm);
      const phase = derivative >= 0 ? baseAngle : (2 * Math.PI - baseAngle);
      sensorPhases.push({ id: sensorId, phase });
    });

    if (sensorPhases.length < 2) return;
    sensorPhases.sort((a, b) => a.id.localeCompare(b.id));

    const ids = sensorPhases.map(s => s.id);
    const n = ids.length;
    const matrix: number[][] = Array.from({ length: n }, () => new Array(n).fill(1));

    for (let i = 0; i < n; i++) {
      for (let j = i + 1; j < n; j++) {
        const phaseDiff = sensorPhases[i].phase - sensorPhases[j].phase;
        const instantPlv = (Math.cos(phaseDiff) + 1) / 2;
        const key = `${ids[i]}|${ids[j]}`;
        const prev = pairwiseSyncMatrix.get(key);
        const smoothed = prev !== undefined
          ? PAIRWISE_SMOOTHING * prev + (1 - PAIRWISE_SMOOTHING) * instantPlv
          : instantPlv;
        pairwiseSyncMatrix.set(key, smoothed);
        matrix[i][j] = smoothed;
        matrix[j][i] = smoothed;
      }
    }
    heatmapSensorIds = ids;
    heatmapData = matrix;
  }

  function getHeatmapColor(value: number): string {
    if (value >= 0.75) {
      const t = (value - 0.75) / 0.25;
      return `rgb(34, ${Math.round(180 + t * 17)}, 94)`;
    } else if (value >= 0.5) {
      const t = (value - 0.5) / 0.25;
      return `rgb(${Math.round(234 - t * 200)}, ${Math.round(179 + t * 18)}, ${Math.round(8 + t * 86)})`;
    } else if (value >= 0.25) {
      const t = (value - 0.25) / 0.25;
      return `rgb(${Math.round(249 - t * 15)}, ${Math.round(115 + t * 64)}, ${Math.round(22 - t * 14)})`;
    } else {
      const t = value / 0.25;
      return `rgb(${Math.round(239 + t * 10)}, ${Math.round(68 + t * 47)}, ${Math.round(68 - t * 46)})`;
    }
  }

  // ── Grid View: Canvas sparklines ──
  function updateGridView() {
    if (viewMode !== 'grid') return;

    const ids = Array.from(sensorData.keys()).sort();
    if (JSON.stringify(ids) !== JSON.stringify(gridSensorIds)) {
      gridSensorIds = ids;
    }

    // Draw sparklines on next frame after DOM update
    requestAnimationFrame(() => {
      gridSensorIds.forEach(sensorId => {
        const canvas = document.getElementById(`grid-canvas-${sensorId}`) as HTMLCanvasElement;
        if (!canvas) return;

        const ctx = canvas.getContext('2d');
        if (!ctx) return;

        const dpr = window.devicePixelRatio || 1;
        const rect = canvas.getBoundingClientRect();
        canvas.width = rect.width * dpr;
        canvas.height = rect.height * dpr;
        ctx.scale(dpr, dpr);

        const data = sensorData.get(sensorId) || [];
        const now = latestDataTimestamp || Date.now();
        const windowMs = 3000; // 3s window for sparklines
        const cutoff = now - windowMs;
        const visible = data.filter(d => d.x >= cutoff);

        if (visible.length < 2) {
          ctx.clearRect(0, 0, rect.width, rect.height);
          return;
        }

        let min = visible[0].y, max = visible[0].y;
        for (const d of visible) {
          if (d.y < min) min = d.y;
          if (d.y > max) max = d.y;
        }
        const range = max - min || 1;
        const pad = 2;

        ctx.fillStyle = '#0a0f14';
        ctx.fillRect(0, 0, rect.width, rect.height);

        const color = sensorColors.get(sensorId) || '#4ade80';
        ctx.strokeStyle = color;
        ctx.lineWidth = 1.2;
        ctx.beginPath();

        for (let i = 0; i < visible.length; i++) {
          const x = ((visible[i].x - cutoff) / windowMs) * rect.width;
          const y = pad + (1 - (visible[i].y - min) / range) * (rect.height - 2 * pad);
          if (i === 0) ctx.moveTo(x, y);
          else ctx.lineTo(x, y);
        }
        ctx.stroke();
      });
    });
  }

  // ── Morphology View: Compute mean beat ──
  function updateMorphologyView() {
    if (viewMode !== 'morphology') return;

    const canvas = document.getElementById('morphology-canvas') as HTMLCanvasElement;
    if (!canvas) return;
    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const w = rect.width;
    const h = rect.height;

    ctx.fillStyle = '#0a0f14';
    ctx.fillRect(0, 0, w, h);

    // Collect last ~1s of data from each sensor, resample to 100 points
    const RESAMPLE = 100;
    const windowMs = 1000;
    const now = latestDataTimestamp || Date.now();
    const cutoff = now - windowMs;
    const sensorTraces: number[][] = [];
    const sensorIds: string[] = [];

    sensorData.forEach((data, sensorId) => {
      const visible = data.filter(d => d.x >= cutoff);
      if (visible.length < 10) return;

      // Resample to fixed length
      const resampled: number[] = new Array(RESAMPLE);
      for (let i = 0; i < RESAMPLE; i++) {
        const t = cutoff + (i / RESAMPLE) * windowMs;
        // Find nearest point
        let best = 0;
        let bestDist = Infinity;
        for (let j = 0; j < visible.length; j++) {
          const dist = Math.abs(visible[j].x - t);
          if (dist < bestDist) { bestDist = dist; best = j; }
        }
        resampled[i] = visible[best].y;
      }
      sensorTraces.push(resampled);
      sensorIds.push(sensorId);
    });

    if (sensorTraces.length < 1) return;

    // Compute mean, std, upper/lower bounds
    const mean: number[] = new Array(RESAMPLE).fill(0);
    const std: number[] = new Array(RESAMPLE).fill(0);

    for (let i = 0; i < RESAMPLE; i++) {
      let sum = 0;
      for (const trace of sensorTraces) sum += trace[i];
      mean[i] = sum / sensorTraces.length;
    }

    for (let i = 0; i < RESAMPLE; i++) {
      let sumSq = 0;
      for (const trace of sensorTraces) sumSq += (trace[i] - mean[i]) ** 2;
      std[i] = Math.sqrt(sumSq / sensorTraces.length);
    }

    // Find overall range for scaling
    let globalMin = Infinity, globalMax = -Infinity;
    for (const trace of sensorTraces) {
      for (const v of trace) {
        if (v < globalMin) globalMin = v;
        if (v > globalMax) globalMax = v;
      }
    }
    const range = globalMax - globalMin || 1;
    const pad = 20;

    const toX = (i: number) => pad + (i / RESAMPLE) * (w - 2 * pad);
    const toY = (v: number) => pad + (1 - (v - globalMin) / range) * (h - 2 * pad);

    // Draw confidence band (±1 std)
    ctx.fillStyle = 'rgba(74, 222, 128, 0.1)';
    ctx.beginPath();
    for (let i = 0; i < RESAMPLE; i++) {
      const x = toX(i);
      const y = toY(mean[i] + std[i]);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    for (let i = RESAMPLE - 1; i >= 0; i--) {
      ctx.lineTo(toX(i), toY(mean[i] - std[i]));
    }
    ctx.closePath();
    ctx.fill();

    // Draw individual traces (faded)
    const outlierIds: string[] = [];
    for (let t = 0; t < sensorTraces.length; t++) {
      const trace = sensorTraces[t];
      // Compute deviation from mean
      let totalDev = 0;
      for (let i = 0; i < RESAMPLE; i++) {
        totalDev += Math.abs(trace[i] - mean[i]);
      }
      const avgDev = totalDev / RESAMPLE;
      const avgStd = std.reduce((a, b) => a + b, 0) / RESAMPLE;
      const isOutlier = avgDev > avgStd * 1.5;

      if (isOutlier) outlierIds.push(sensorIds[t]);

      const color = sensorColors.get(sensorIds[t]) || '#4ade80';
      ctx.strokeStyle = isOutlier ? color : 'rgba(74, 222, 128, 0.15)';
      ctx.lineWidth = isOutlier ? 1.5 : 0.5;
      ctx.beginPath();
      for (let i = 0; i < RESAMPLE; i++) {
        const x = toX(i);
        const y = toY(trace[i]);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }

    // Draw mean beat (bold green)
    ctx.strokeStyle = '#4ade80';
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    for (let i = 0; i < RESAMPLE; i++) {
      const x = toX(i);
      const y = toY(mean[i]);
      if (i === 0) ctx.moveTo(x, y);
      else ctx.lineTo(x, y);
    }
    ctx.stroke();

    // Labels
    ctx.fillStyle = '#4ade80';
    ctx.font = '11px monospace';
    ctx.fillText(`Mean Beat (${sensorTraces.length} sensors)`, pad, 14);
    if (outlierIds.length > 0) {
      ctx.fillStyle = '#f97316';
      ctx.fillText(`Outliers: ${outlierIds.map(id => getDisplayName(id)).join(', ')}`, pad, 28);
    }

    // Y-axis labels
    ctx.fillStyle = 'rgba(74, 222, 128, 0.5)';
    ctx.font = '9px monospace';
    ctx.fillText(`${globalMax.toFixed(2)} mV`, 2, pad + 4);
    ctx.fillText(`${globalMin.toFixed(2)} mV`, 2, h - pad + 12);

    meanBeatData = { mean, upper: mean.map((v, i) => v + std[i]), lower: mean.map((v, i) => v - std[i]), outlierIds };
  }

  function initializeSensorData() {
    sensors.forEach((sensor, index) => {
      if (!sensorData.has(sensor.sensor_id)) {
        sensorData.set(sensor.sensor_id, []);
        sensorColors.set(sensor.sensor_id, COLORS[index % COLORS.length]);
      }
      if (sensor.sensor_name) {
        sensorNames.set(sensor.sensor_id, sensor.sensor_name);
      }
    });
  }

  function addDataPoint(sensorId: string, value: number, timestamp?: number) {
    const ts = timestamp || Date.now();
    const pending = pendingUpdates.get(sensorId) || [];
    pending.push({ x: ts, y: value });
    pendingUpdates.set(sensorId, pending);
    if (ts > latestDataTimestamp) latestDataTimestamp = ts;
    addToPhaseBuffer(sensorId, value);
  }

  function processPendingUpdates(): boolean {
    if (pendingUpdates.size === 0) return false;
    pendingUpdates.forEach((points, sensorId) => {
      let data = sensorData.get(sensorId) || [];
      data.push(...points);
      if (data.length > MAX_DATA_POINTS) {
        data = data.slice(data.length - MAX_DATA_POINTS);
      }
      sensorData.set(sensorId, data);
      dirtySeriesIds.add(sensorId);
    });
    pendingUpdates.clear();
    return true;
  }

  function rafLoop(timestamp: number) {
    try {
      if (timestamp - lastUpdateTime >= UPDATE_INTERVAL_MS) {
        const hadData = processPendingUpdates();
        if (viewMode === 'traces') {
          updateTracesCanvas(hadData, timestamp);
        } else if (viewMode === 'grid' && hadData) {
          updateGridView();
        } else if (viewMode === 'morphology' && hadData) {
          updateMorphologyView();
        } else if (viewMode === 'sync') {
          computePairwiseSync();
        }
        lastUpdateTime = timestamp;
      }
    } catch (e) {
      console.warn("[CompositeECG] RAF error, recovering:", e);
    }
    rafId = requestAnimationFrame(rafLoop);
  }

  // ── Canvas-based Traces renderer (replaces Highcharts SVG for crisp rendering) ──
  const TRACES_MARGIN = { top: 10, right: 10, bottom: 20, left: 45 };

  function binarySearchCutoff(data: Array<{ x: number; y: number }>, cutoff: number): number {
    let lo = 0, hi = data.length;
    while (lo < hi) {
      const mid = (lo + hi) >>> 1;
      if (data[mid].x < cutoff) lo = mid + 1;
      else hi = mid;
    }
    return lo;
  }

  function updateTracesCanvas(hadData: boolean, timestamp: number) {
    if (!tracesCanvas) return;
    if (!hadData && timestamp - lastExtremesUpdate < 500) return;

    const ctx = tracesCanvas.getContext('2d');
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = tracesCanvas.getBoundingClientRect();
    const cw = rect.width;
    const ch = rect.height;

    // Resize canvas buffer to match display size (retina-aware)
    if (tracesCanvas.width !== Math.round(cw * dpr) || tracesCanvas.height !== Math.round(ch * dpr)) {
      tracesCanvas.width = Math.round(cw * dpr);
      tracesCanvas.height = Math.round(ch * dpr);
    }

    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);

    const plotW = cw - TRACES_MARGIN.left - TRACES_MARGIN.right;
    const plotH = ch - TRACES_MARGIN.top - TRACES_MARGIN.bottom;
    const N = selectedSamples; // number of samples to show

    // Update legend sensor list
    const currentIds = Array.from(sensorData.keys()).sort();
    if (currentIds.length !== legendSensorIds.length || currentIds.some((id, i) => id !== legendSensorIds[i])) {
      legendSensorIds = currentIds;
    }

    // Take the last N samples per sensor (sequential strip chart — no time gaps)
    // Compute global Y range across visible sensors
    let globalMin = Infinity, globalMax = -Infinity;
    sensorData.forEach((data, sensorId) => {
      if (hiddenSensors.has(sensorId)) return;
      const start = Math.max(0, data.length - N);
      for (let i = start; i < data.length; i++) {
        if (data[i].y < globalMin) globalMin = data[i].y;
        if (data[i].y > globalMax) globalMax = data[i].y;
      }
    });
    if (!isFinite(globalMin)) { globalMin = -1; globalMax = 1; }
    const yRange = globalMax - globalMin || 1;
    const yPad = yRange * 0.08;
    const yMin = globalMin - yPad;
    const yMax = globalMax + yPad;

    // Clear
    ctx.fillStyle = '#0a0f14';
    ctx.fillRect(0, 0, cw, ch);

    // Draw grid lines
    ctx.strokeStyle = 'rgba(74, 222, 128, 0.12)';
    ctx.lineWidth = 0.5;

    // Y grid + labels
    const yTicks = 5;
    ctx.fillStyle = 'rgba(74, 222, 128, 0.7)';
    ctx.font = '9px monospace';
    ctx.textAlign = 'right';
    ctx.textBaseline = 'middle';
    for (let i = 0; i <= yTicks; i++) {
      const frac = i / yTicks;
      const yVal = yMax - frac * (yMax - yMin);
      const py = TRACES_MARGIN.top + frac * plotH;
      ctx.beginPath();
      ctx.moveTo(TRACES_MARGIN.left, py);
      ctx.lineTo(TRACES_MARGIN.left + plotW, py);
      ctx.stroke();
      ctx.fillText(yVal.toFixed(1), TRACES_MARGIN.left - 4, py);
    }

    // X grid — show elapsed seconds (strip chart style)
    const windowSec = selectedWindowMs / 1000;
    const xTickCount = selectedWindowMs <= 3000 ? 6 : selectedWindowMs <= 10000 ? 10 : 6;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'top';
    for (let i = 0; i <= xTickCount; i++) {
      const frac = i / xTickCount;
      const px = TRACES_MARGIN.left + frac * plotW;
      const secAgo = windowSec * (1 - frac);
      const label = secAgo === 0 ? 'now' : `-${secAgo.toFixed(1)}s`;
      ctx.beginPath();
      ctx.moveTo(px, TRACES_MARGIN.top);
      ctx.lineTo(px, TRACES_MARGIN.top + plotH);
      ctx.stroke();
      ctx.fillText(label, px, TRACES_MARGIN.top + plotH + 4);
    }

    // Y-axis label
    ctx.save();
    ctx.fillStyle = 'rgba(74, 222, 128, 0.7)';
    ctx.font = '10px monospace';
    ctx.textAlign = 'center';
    ctx.translate(12, TRACES_MARGIN.top + plotH / 2);
    ctx.rotate(-Math.PI / 2);
    ctx.fillText('mV', 0, 0);
    ctx.restore();

    // Draw traces — sequential strip chart (x = sample index, not timestamp)
    // Each sample maps to an evenly-spaced x position → no gaps ever
    ctx.save();
    ctx.beginPath();
    ctx.rect(TRACES_MARGIN.left, TRACES_MARGIN.top, plotW, plotH);
    ctx.clip();

    const hasHighlight = highlightedSensor !== null;

    function drawSensorTrace(data: Array<{ x: number; y: number }>, color: string, lineWidth: number, alpha: number) {
      const count = Math.min(data.length, N);
      if (count < 2) return;
      const start = data.length - count;
      const xStep = plotW / (N - 1); // evenly spaced across the plot width

      ctx.globalAlpha = alpha;
      ctx.strokeStyle = color;
      ctx.lineWidth = lineWidth;
      ctx.beginPath();
      ctx.moveTo(
        TRACES_MARGIN.left + 0 * xStep,
        TRACES_MARGIN.top + ((yMax - data[start].y) / (yMax - yMin)) * plotH
      );
      for (let i = 1; i < count; i++) {
        ctx.lineTo(
          TRACES_MARGIN.left + i * xStep,
          TRACES_MARGIN.top + ((yMax - data[start + i].y) / (yMax - yMin)) * plotH
        );
      }
      ctx.stroke();
    }

    // First pass: draw non-highlighted (dimmed if something is highlighted)
    sensorData.forEach((data, sensorId) => {
      if (hiddenSensors.has(sensorId)) return;
      if (sensorId === highlightedSensor) return;
      const color = sensorColors.get(sensorId) || '#4ade80';
      drawSensorTrace(data, color, 1.0, hasHighlight ? 0.2 : 1.0);
    });

    // Second pass: draw highlighted sensor on top
    if (highlightedSensor && !hiddenSensors.has(highlightedSensor)) {
      const data = sensorData.get(highlightedSensor);
      if (data) {
        const color = sensorColors.get(highlightedSensor) || '#4ade80';
        drawSensorTrace(data, color, 2.5, 1.0);
      }
    }

    ctx.globalAlpha = 1.0;
    ctx.restore();

    lastExtremesUpdate = timestamp;
    dirtySeriesIds.clear();
  }

  function setTimeWindow(window: { ms: number; samples: number }) {
    selectedWindowMs = window.ms;
    selectedSamples = window.samples;
    // Canvas will redraw on next RAF with new window
  }

  function toggleSensorVisibility(sensorId: string) {
    if (hiddenSensors.has(sensorId)) {
      hiddenSensors.delete(sensorId);
    } else {
      hiddenSensors.add(sensorId);
      // If we hid the highlighted one, clear highlight
      if (highlightedSensor === sensorId) highlightedSensor = null;
    }
    hiddenSensors = new Set(hiddenSensors); // trigger reactivity
  }

  function toggleHighlight(sensorId: string) {
    if (hiddenSensors.has(sensorId)) return; // can't highlight a hidden sensor
    highlightedSensor = highlightedSensor === sensorId ? null : sensorId;
  }

  function switchMode(mode: ViewMode) {
    viewMode = mode;
    if (mode === 'traces') {
      // Canvas will be drawn on next RAF
    } else if (mode === 'grid') {
      setTimeout(() => updateGridView(), 150);
    } else if (mode === 'morphology') {
      setTimeout(() => updateMorphologyView(), 150);
    }
  }

  onMount(() => {
    initializeSensorData();
    // Start RAF loop immediately — it handles all view modes
    rafId = requestAnimationFrame(rafLoop);
    // Canvas traces will be drawn on first RAF frame

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload, timestamp } = e.detail;
      if (attribute_id === "ecg") {
        const value = typeof payload === "number" ? payload : null;
        if (value !== null) {
          if (!sensorData.has(sensor_id)) {
            const index = sensorData.size;
            sensorColors.set(sensor_id, COLORS[index % COLORS.length]);
            sensorData.set(sensor_id, []);
          }
          addDataPoint(sensor_id, value, timestamp);
        }
      }
    };

    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;
      if (attributeId === "ecg") {
        const data = e?.detail?.data;
        if (Array.isArray(data) && data.length > 0) {
          if (!sensorData.has(eventSensorId)) {
            const index = sensorData.size;
            sensorColors.set(eventSensorId, COLORS[index % COLORS.length]);
            sensorData.set(eventSensorId, []);
          }
          data.forEach((measurement: any) => {
            const value = measurement?.payload;
            const timestamp = measurement?.timestamp;
            if (typeof value === "number") {
              addDataPoint(eventSensorId, value, timestamp);
            }
          });
        } else if (data?.payload !== undefined) {
          const value = data.payload;
          if (typeof value === "number") {
            if (!sensorData.has(eventSensorId)) {
              const index = sensorData.size;
              sensorColors.set(eventSensorId, COLORS[index % COLORS.length]);
              sensorData.set(eventSensorId, []);
            }
            addDataPoint(eventSensorId, value, data.timestamp);
          }
        }
      }
    };

    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.addEventListener("accumulator-data-event", handleAccumulatorEvent as EventListener);

    return () => {
      window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
      window.removeEventListener("accumulator-data-event", handleAccumulatorEvent as EventListener);
    };
  });

  onDestroy(() => {
    if (rafId) cancelAnimationFrame(rafId);
  });
</script>

<div class="composite-chart-container">
  <div class="chart-header">
    <div class="header-left">
      <h2>ECG Overview</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
    </div>
    <div class="header-controls">
      <div class="view-mode-selector">
        <button class="mode-btn" class:active={viewMode === 'traces'} onclick={() => switchMode('traces')} title="Overlaid ECG traces">
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.5"><polyline points="1,12 4,8 7,10 10,4 13,6 15,2"/></svg>
          Traces
        </button>
        <button class="mode-btn" class:active={viewMode === 'grid'} onclick={() => switchMode('grid')} title="Sparkline grid — one per person">
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.5"><rect x="1" y="1" width="6" height="6" rx="0.5"/><rect x="9" y="1" width="6" height="6" rx="0.5"/><rect x="1" y="9" width="6" height="6" rx="0.5"/><rect x="9" y="9" width="6" height="6" rx="0.5"/></svg>
          Grid
        </button>
        <button class="mode-btn" class:active={viewMode === 'morphology'} onclick={() => switchMode('morphology')} title="Mean beat morphology with outlier detection">
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.5"><path d="M1,10 Q4,10 5,10 Q6,10 7,3 Q8,10 9,10 Q10,10 11,8 Q12,10 15,10"/></svg>
          Morphology
        </button>
        <button class="mode-btn" class:active={viewMode === 'sync'} onclick={() => switchMode('sync')} title="Pairwise synchronization heatmap">
          <svg viewBox="0 0 16 16" width="10" height="10" fill="currentColor"><rect x="1" y="1" width="4" height="4" rx="0.5" opacity="0.9"/><rect x="6" y="1" width="4" height="4" rx="0.5" opacity="0.5"/><rect x="11" y="1" width="4" height="4" rx="0.5" opacity="0.2"/><rect x="1" y="6" width="4" height="4" rx="0.5" opacity="0.5"/><rect x="6" y="6" width="4" height="4" rx="0.5" opacity="0.9"/><rect x="11" y="6" width="4" height="4" rx="0.5" opacity="0.4"/><rect x="1" y="11" width="4" height="4" rx="0.5" opacity="0.2"/><rect x="6" y="11" width="4" height="4" rx="0.5" opacity="0.4"/><rect x="11" y="11" width="4" height="4" rx="0.5" opacity="0.9"/></svg>
          Sync
        </button>
      </div>
      {#if viewMode === 'traces'}
        <div class="time-window-selector">
          {#each TIME_WINDOWS as window}
            <button class="mode-btn" class:active={selectedWindowMs === window.ms} onclick={() => setTimeWindow(window)}>
              {window.label}
            </button>
          {/each}
        </div>
      {/if}
    </div>
  </div>

  <!-- TRACES VIEW (Canvas-based for crisp rendering) -->
  {#if viewMode === 'traces'}
    <div class="chart-wrapper">
      <canvas class="traces-canvas" bind:this={tracesCanvas}></canvas>
    </div>
    <div class="traces-legend">
      {#each legendSensorIds as sensorId}
        {@const color = sensorColors.get(sensorId) || '#4ade80'}
        {@const isHidden = hiddenSensors.has(sensorId)}
        {@const isHighlighted = highlightedSensor === sensorId}
        <button
          class="legend-item"
          class:hidden-sensor={isHidden}
          class:highlighted-sensor={isHighlighted}
          onclick={() => toggleHighlight(sensorId)}
          oncontextmenu={(e) => { e.preventDefault(); toggleSensorVisibility(sensorId); }}
          title="Click: highlight · Right-click: show/hide"
        >
          <span class="legend-line" style="background: {isHidden ? '#555' : color}"></span>
          <span class="legend-name">{getDisplayName(sensorId)}</span>
        </button>
      {/each}
    </div>

  <!-- GRID VIEW: Sparkline per person -->
  {:else if viewMode === 'grid'}
    <div class="grid-container">
      {#each gridSensorIds as sensorId}
        <div class="grid-cell">
          <div class="grid-label" style="color: {sensorColors.get(sensorId) || '#4ade80'}">{getDisplayName(sensorId)}</div>
          <canvas id="grid-canvas-{sensorId}" class="grid-canvas"></canvas>
        </div>
      {/each}
      {#if gridSensorIds.length === 0}
        <div class="empty-msg">Waiting for ECG data...</div>
      {/if}
    </div>

  <!-- MORPHOLOGY VIEW: Mean beat + outliers -->
  {:else if viewMode === 'morphology'}
    <div class="morphology-container">
      <canvas id="morphology-canvas" class="morphology-canvas"></canvas>
      {#if meanBeatData.outlierIds.length > 0}
        <div class="outlier-bar">
          <span class="outlier-label">Outliers:</span>
          {#each meanBeatData.outlierIds as id}
            <span class="outlier-tag" style="border-color: {sensorColors.get(id) || '#f97316'}">{getDisplayName(id)}</span>
          {/each}
        </div>
      {/if}
    </div>

  <!-- SYNC VIEW: Pairwise heatmap -->
  {:else if viewMode === 'sync'}
    <div class="heatmap-section">
      <div class="heatmap-header">
        <span class="heatmap-title">Pairwise ECG Synchronization</span>
        <div class="heatmap-legend">
          <span class="legend-label">Low</span>
          <div class="legend-gradient"></div>
          <span class="legend-label">High</span>
        </div>
      </div>
      {#if heatmapSensorIds.length >= 2}
        {@const n = heatmapSensorIds.length}
        {@const cellSize = Math.max(18, Math.min(32, 300 / n))}
        {@const labelWidth = 56}
        {@const headerHeight = 60}
        {@const gridWidth = n * cellSize}
        {@const svgWidth = labelWidth + gridWidth + 2}
        {@const svgHeight = headerHeight + gridWidth + 2}
        <div class="heatmap-scroll">
          <svg width={svgWidth} height={svgHeight} viewBox="0 0 {svgWidth} {svgHeight}" class="heatmap-svg">
            {#each heatmapSensorIds as id, i}
              {@const cx = labelWidth + i * cellSize + cellSize / 2}
              {@const cy = headerHeight - 6}
              <text x={cx} y={cy} text-anchor="start" transform="rotate(-45, {cx}, {cy})" class="heatmap-label">{getDisplayName(id)}</text>
            {/each}
            {#each heatmapSensorIds as rowId, i}
              <text x={labelWidth - 6} y={headerHeight + i * cellSize + cellSize / 2 + 3} text-anchor="end" class="heatmap-label">{getDisplayName(rowId)}</text>
              {#each heatmapSensorIds as _colId, j}
                {@const value = heatmapData[i]?.[j] ?? 0}
                <rect x={labelWidth + j * cellSize + 1} y={headerHeight + i * cellSize + 1} width={cellSize - 2} height={cellSize - 2} rx="2"
                  fill={i === j ? 'rgba(74, 222, 128, 0.15)' : getHeatmapColor(value)} opacity={i === j ? 1 : 0.85}>
                  <title>{i === j ? getDisplayName(rowId) : `${getDisplayName(rowId)} ↔ ${getDisplayName(_colId)}: ${Math.round(value * 100)}%`}</title>
                </rect>
                {#if i === j}
                  <circle cx={labelWidth + j * cellSize + cellSize / 2} cy={headerHeight + i * cellSize + cellSize / 2} r={Math.min(8, cellSize / 3.5)} fill={sensorColors.get(rowId) || '#4ade80'} />
                {:else if cellSize >= 20}
                  <text x={labelWidth + j * cellSize + cellSize / 2} y={headerHeight + i * cellSize + cellSize / 2 + 3} text-anchor="middle" class="cell-value">{Math.round(value * 100)}</text>
                {/if}
              {/each}
            {/each}
          </svg>
        </div>
      {:else}
        <div class="empty-msg">Waiting for ≥2 sensors with ECG phase data...</div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .composite-chart-container {
    background: #0a0f14;
    border-radius: 0.5rem;
    border: 1px solid rgba(74, 222, 128, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: 260px;
    display: flex;
    flex-direction: column;
    box-shadow: 0 0 20px rgba(0, 255, 0, 0.05), inset 0 0 60px rgba(0, 0, 0, 0.5);
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
    padding: 0.2rem 0.5rem;
    background: rgba(74, 222, 128, 0.05);
    border-radius: 0.25rem;
    border: 1px solid rgba(74, 222, 128, 0.2);
    gap: 0.5rem;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    min-width: 0;
  }

  .chart-header h2 {
    font-size: 0.75rem;
    font-weight: 600;
    color: #4ade80;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    white-space: nowrap;
  }

  .sensor-count {
    font-size: 0.65rem;
    color: #4ade80;
    font-family: monospace;
    opacity: 0.7;
    white-space: nowrap;
  }

  .header-controls {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .view-mode-selector, .time-window-selector {
    display: flex;
    gap: 0.15rem;
  }

  .mode-btn {
    display: flex;
    align-items: center;
    gap: 0.2rem;
    padding: 0.2rem 0.4rem;
    font-size: 0.7rem;
    font-family: monospace;
    background: rgba(74, 222, 128, 0.1);
    border: 1px solid rgba(74, 222, 128, 0.3);
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
    white-space: nowrap;
  }

  .mode-btn:hover {
    background: rgba(74, 222, 128, 0.2);
    color: #4ade80;
  }

  .mode-btn.active {
    background: rgba(74, 222, 128, 0.3);
    border-color: #4ade80;
    color: #4ade80;
    box-shadow: 0 0 8px rgba(74, 222, 128, 0.3);
  }

  .chart-wrapper {
    flex: 1;
    min-height: 200px;
    border-radius: 0.25rem;
    position: relative;
  }

  .traces-canvas {
    width: 100%;
    height: 100%;
    border-radius: 0.25rem;
    display: block;
  }

  .traces-legend {
    display: flex;
    flex-wrap: wrap;
    gap: 2px 4px;
    padding: 4px 6px;
    justify-content: center;
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 1px 6px;
    font-size: 0.6rem;
    font-family: monospace;
    background: transparent;
    border: 1px solid transparent;
    border-radius: 3px;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.1s ease;
    user-select: none;
  }

  .legend-item:hover {
    background: rgba(74, 222, 128, 0.1);
    border-color: rgba(74, 222, 128, 0.2);
  }

  .legend-item.highlighted-sensor {
    background: rgba(74, 222, 128, 0.15);
    border-color: rgba(74, 222, 128, 0.4);
    color: #e5e7eb;
  }

  .legend-item.hidden-sensor {
    opacity: 0.4;
    text-decoration: line-through;
  }

  .legend-line {
    display: inline-block;
    width: 14px;
    height: 2px;
    border-radius: 1px;
    flex-shrink: 0;
  }

  .legend-name {
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    max-width: 100px;
  }

  /* ── Grid View ── */
  .grid-container {
    flex: 1;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
    gap: 4px;
    padding: 4px;
    overflow-y: auto;
    min-height: 200px;
  }

  .grid-cell {
    background: rgba(74, 222, 128, 0.03);
    border: 1px solid rgba(74, 222, 128, 0.15);
    border-radius: 4px;
    padding: 2px 4px;
    display: flex;
    flex-direction: column;
    min-height: 60px;
  }

  .grid-label {
    font-size: 0.6rem;
    font-family: monospace;
    font-weight: 600;
    margin-bottom: 1px;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .grid-canvas {
    flex: 1;
    width: 100%;
    min-height: 40px;
    border-radius: 2px;
  }

  /* ── Morphology View ── */
  .morphology-container {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 200px;
  }

  .morphology-canvas {
    flex: 1;
    width: 100%;
    min-height: 200px;
    border-radius: 4px;
  }

  .outlier-bar {
    display: flex;
    align-items: center;
    gap: 0.3rem;
    padding: 0.25rem 0.5rem;
    flex-wrap: wrap;
  }

  .outlier-label {
    font-size: 0.65rem;
    font-family: monospace;
    color: #f97316;
    font-weight: 600;
  }

  .outlier-tag {
    font-size: 0.6rem;
    font-family: monospace;
    color: #e5e7eb;
    padding: 0.1rem 0.3rem;
    border: 1px solid;
    border-radius: 3px;
    background: rgba(249, 115, 22, 0.1);
  }

  /* ── Sync Heatmap ── */
  .heatmap-section {
    flex: 1;
    min-height: 0;
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .heatmap-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 0 0.25rem;
    margin-bottom: 0.25rem;
  }

  .heatmap-title {
    font-size: 0.65rem;
    font-family: monospace;
    color: #4ade80;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.8;
  }

  .heatmap-legend {
    display: flex;
    align-items: center;
    gap: 0.3rem;
  }

  .legend-label {
    font-size: 0.55rem;
    font-family: monospace;
    color: #9ca3af;
  }

  .legend-gradient {
    width: 60px;
    height: 6px;
    border-radius: 3px;
    background: linear-gradient(to right, #ef4444, #f97316, #eab308, #84cc16, #22c55e);
  }

  .heatmap-scroll {
    flex: 1;
    overflow: auto;
    display: flex;
    justify-content: center;
    align-items: center;
    padding: 0.5rem;
  }

  .heatmap-svg {
    flex-shrink: 0;
  }

  .heatmap-label {
    font-size: 10px;
    font-family: monospace;
    fill: #9ca3af;
  }

  .cell-value {
    font-size: 9px;
    font-family: monospace;
    fill: rgba(255, 255, 255, 0.85);
    pointer-events: none;
  }

  .empty-msg {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    font-family: monospace;
    color: #9ca3af;
    opacity: 0.6;
  }

  @media (max-width: 480px) {
    .composite-chart-container { padding: 0.15rem; }
    .chart-header { flex-wrap: nowrap; gap: 0.2rem; padding: 0.1rem 0.2rem; }
    .chart-header h2 { font-size: 0.55rem; }
    .sensor-count { display: none; }
    .mode-btn { padding: 0.1rem 0.2rem; font-size: 0.5rem; }
    .mode-btn svg { display: none; }
    .grid-container { grid-template-columns: repeat(auto-fill, minmax(120px, 1fr)); }
  }
</style>

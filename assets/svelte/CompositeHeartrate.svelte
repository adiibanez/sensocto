<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors: initialSensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; bpm: number }>;
  } = $props();

  type ViewMode = 'pills' | 'beeswarm' | 'ranking' | 'timeline';
  let viewMode = $state<ViewMode>('pills');

  let sensorsState = $state<Array<{ sensor_id: string; sensor_name?: string; bpm: number }>>([]);

  $effect(() => { sensorsState = [...initialSensors]; });

  const validSensors = $derived(sensorsState.filter(s => s.bpm > 0));
  const avgBpm = $derived(validSensors.length > 0 ? Math.round(validSensors.reduce((sum, s) => sum + s.bpm, 0) / validSensors.length) : 0);
  const minBpm = $derived(validSensors.length > 0 ? Math.min(...validSensors.map(s => s.bpm)) : 0);
  const maxBpm = $derived(validSensors.length > 0 ? Math.max(...validSensors.map(s => s.bpm)) : 0);
  const sortedSensors = $derived([...sensorsState].sort((a, b) => b.bpm - a.bpm));

  // Timeline heatmap: rolling BPM history per sensor
  // Each entry: { timestamp, bpm }
  const HISTORY_WINDOW_MS = 5 * 60 * 1000; // 5 minutes
  const HISTORY_BUCKET_MS = 10 * 1000; // 10-second buckets
  let bpmHistory: Map<string, Array<{ t: number; bpm: number }>> = new Map();

  function getBpmColor(bpm: number): string {
    if (bpm <= 0) return '#6b7280';
    if (bpm < 60) return '#3b82f6';
    if (bpm < 100) return '#22c55e';
    if (bpm < 120) return '#eab308';
    return '#ef4444';
  }

  function getBpmZone(bpm: number): string {
    if (bpm <= 0) return 'No data';
    if (bpm < 60) return 'Low';
    if (bpm < 100) return 'Normal';
    if (bpm < 120) return 'Elevated';
    return 'High';
  }

  function getDisplayName(sensor: { sensor_id: string; sensor_name?: string }): string {
    return sensor.sensor_name || sensor.sensor_id.substring(0, 12);
  }

  function getDisplayNameById(sensorId: string): string {
    const s = sensorsState.find(s => s.sensor_id === sensorId);
    return s ? getDisplayName(s) : sensorId.substring(0, 12);
  }

  // Record BPM to history for timeline heatmap
  function recordHistory(sensorId: string, bpm: number) {
    let history = bpmHistory.get(sensorId);
    if (!history) {
      history = [];
      bpmHistory.set(sensorId, history);
    }
    history.push({ t: Date.now(), bpm });
    // Prune old entries
    const cutoff = Date.now() - HISTORY_WINDOW_MS - 30000;
    while (history.length > 0 && history[0].t < cutoff) {
      history.shift();
    }
  }

  function handleCompositeMeasurement(event: CustomEvent) {
    const { sensor_id, attribute_id, payload } = event.detail;
    if (attribute_id !== "heartrate") return;

    let bpm = 0;
    try {
      const data = typeof payload === "string" ? JSON.parse(payload) : payload;
      bpm = data?.bpm ?? data?.heartRate ?? data ?? 0;
      if (typeof bpm !== "number") bpm = 0;
    } catch { return; }

    // Record to history
    recordHistory(sensor_id, bpm);

    const existingIndex = sensorsState.findIndex(s => s.sensor_id === sensor_id);
    if (existingIndex >= 0) {
      sensorsState[existingIndex] = { ...sensorsState[existingIndex], bpm };
    } else {
      sensorsState = [...sensorsState, { sensor_id, bpm }];
    }
  }

  // ── Beeswarm: compute non-overlapping dot positions ──
  const BEESWARM_RANGE = [40, 180]; // BPM axis range
  const DOT_RADIUS = 8;

  function computeBeeswarm(sensors: typeof validSensors, height: number): Array<{ id: string; name: string; bpm: number; x: number; y: number; color: string }> {
    if (sensors.length === 0 || height === 0) return [];
    const dots: Array<{ id: string; name: string; bpm: number; x: number; y: number; color: string }> = [];
    const pad = 20;

    // Map BPM to y position
    const bpmToY = (bpm: number) => pad + ((BEESWARM_RANGE[1] - bpm) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (height - 2 * pad);

    // Sort by BPM for stable placement
    const sorted = [...sensors].sort((a, b) => a.bpm - b.bpm);

    for (const sensor of sorted) {
      const y = bpmToY(Math.max(BEESWARM_RANGE[0], Math.min(BEESWARM_RANGE[1], sensor.bpm)));
      let x = 0; // start at center

      // Jitter: push right if overlapping with existing dots
      let placed = false;
      for (let attempt = 0; attempt < 50; attempt++) {
        const testX = (attempt % 2 === 0 ? 1 : -1) * Math.ceil(attempt / 2) * (DOT_RADIUS * 2.2);
        let overlaps = false;
        for (const d of dots) {
          const dx = testX - d.x;
          const dy = y - d.y;
          if (Math.sqrt(dx * dx + dy * dy) < DOT_RADIUS * 2.1) {
            overlaps = true;
            break;
          }
        }
        if (!overlaps) {
          x = testX;
          placed = true;
          break;
        }
      }
      if (!placed) x = dots.length * DOT_RADIUS * 0.5;

      dots.push({ id: sensor.sensor_id, name: getDisplayName(sensor), bpm: sensor.bpm, x, y, color: getBpmColor(sensor.bpm) });
    }
    return dots;
  }

  // ── Timeline heatmap data ──
  function getTimelineData(): { sensorIds: string[]; buckets: number; matrix: number[][] } {
    const now = Date.now();
    const buckets = Math.floor(HISTORY_WINDOW_MS / HISTORY_BUCKET_MS);
    const sensorIds = sortedSensors.map(s => s.sensor_id);
    const matrix: number[][] = [];

    for (const sid of sensorIds) {
      const history = bpmHistory.get(sid) || [];
      const row: number[] = new Array(buckets).fill(0);
      for (let b = 0; b < buckets; b++) {
        const bucketStart = now - HISTORY_WINDOW_MS + b * HISTORY_BUCKET_MS;
        const bucketEnd = bucketStart + HISTORY_BUCKET_MS;
        const inBucket = history.filter(h => h.t >= bucketStart && h.t < bucketEnd);
        if (inBucket.length > 0) {
          row[b] = Math.round(inBucket.reduce((s, h) => s + h.bpm, 0) / inBucket.length);
        }
      }
      matrix.push(row);
    }
    return { sensorIds, buckets, matrix };
  }

  // Reactive beeswarm data
  let beeswarmHeight = $state(400);
  const beeswarmDots = $derived(viewMode === 'beeswarm' ? computeBeeswarm(validSensors, beeswarmHeight) : []);

  // Timeline: recompute on each render when in timeline mode
  let timelineData = $state<{ sensorIds: string[]; buckets: number; matrix: number[][] }>({ sensorIds: [], buckets: 0, matrix: [] });
  let timelineInterval: ReturnType<typeof setInterval> | null = null;

  function startTimelineUpdates() {
    if (timelineInterval) return;
    timelineInterval = setInterval(() => {
      if (viewMode === 'timeline') {
        timelineData = getTimelineData();
      }
    }, 2000);
  }

  function stopTimelineUpdates() {
    if (timelineInterval) { clearInterval(timelineInterval); timelineInterval = null; }
  }

  // Beeswarm container resize observer
  let beeswarmContainer: HTMLDivElement;

  onMount(() => {
    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    startTimelineUpdates();
  });

  onDestroy(() => {
    window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    stopTimelineUpdates();
  });
</script>

<div class="composite-hr">
  <!-- Header with mode selector -->
  <div class="hr-header">
    <div class="stats-bar">
      <div class="stat">
        <span class="stat-label">Avg</span>
        <span class="stat-value" style="color: {getBpmColor(avgBpm)}">{avgBpm}</span>
        <span class="stat-unit">bpm</span>
      </div>
      <div class="stat-divider"></div>
      <div class="stat">
        <span class="stat-label">Min</span>
        <span class="stat-value" style="color: {getBpmColor(minBpm)}">{minBpm}</span>
      </div>
      <div class="stat-divider"></div>
      <div class="stat">
        <span class="stat-label">Max</span>
        <span class="stat-value" style="color: {getBpmColor(maxBpm)}">{maxBpm}</span>
      </div>
      <div class="stat-divider"></div>
      <div class="stat">
        <span class="stat-value text-white">{validSensors.length}</span>
        <span class="stat-unit">sensors</span>
      </div>
    </div>
    <div class="view-mode-selector">
      <button class="mode-btn" class:active={viewMode === 'pills'} onclick={() => viewMode = 'pills'}>Pills</button>
      <button class="mode-btn" class:active={viewMode === 'beeswarm'} onclick={() => viewMode = 'beeswarm'}>Swarm</button>
      <button class="mode-btn" class:active={viewMode === 'ranking'} onclick={() => viewMode = 'ranking'}>Ranking</button>
      <button class="mode-btn" class:active={viewMode === 'timeline'} onclick={() => { viewMode = 'timeline'; timelineData = getTimelineData(); }}>Timeline</button>
    </div>
  </div>

  <!-- PILLS VIEW (original) -->
  {#if viewMode === 'pills'}
    <div class="sensor-grid">
      {#each sortedSensors as sensor (sensor.sensor_id)}
        <div class="sensor-pill" style="border-color: {getBpmColor(sensor.bpm)}"
          title="{getDisplayName(sensor)}: {sensor.bpm > 0 ? sensor.bpm + ' bpm (' + getBpmZone(sensor.bpm) + ')' : 'No data'}">
          <span class="sensor-name">{getDisplayName(sensor)}</span>
          <span class="sensor-bpm" style="color: {getBpmColor(sensor.bpm)}">{sensor.bpm > 0 ? sensor.bpm : '—'}</span>
        </div>
      {/each}
    </div>

  <!-- BEESWARM VIEW -->
  {:else if viewMode === 'beeswarm'}
    {@const h = 400}
    {@const pad = 20}
    {@const zoneLines = [60, 100, 120]}
    <div class="beeswarm-container" bind:this={beeswarmContainer}>
      <svg class="beeswarm-svg" viewBox="-200 0 400 {h}" preserveAspectRatio="xMidYMid meet">
        <!-- Zone bands -->
        <rect x="-200" y={pad} width="400" height={((BEESWARM_RANGE[1] - 120) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          fill="rgba(239, 68, 68, 0.08)" />
        <rect x="-200" y={pad + ((BEESWARM_RANGE[1] - 120) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          width="400" height={((120 - 100) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          fill="rgba(234, 179, 8, 0.06)" />
        <rect x="-200" y={pad + ((BEESWARM_RANGE[1] - 100) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          width="400" height={((100 - 60) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          fill="rgba(34, 197, 94, 0.06)" />
        <rect x="-200" y={pad + ((BEESWARM_RANGE[1] - 60) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          width="400" height={((60 - BEESWARM_RANGE[0]) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          fill="rgba(59, 130, 246, 0.06)" />

        <!-- Zone lines -->
        {#each zoneLines as bpm}
          {@const y = pad + ((BEESWARM_RANGE[1] - bpm) / (BEESWARM_RANGE[1] - BEESWARM_RANGE[0])) * (h - 2 * pad)}
          <line x1="-200" y1={y} x2="200" y2={y} stroke="rgba(156, 163, 175, 0.2)" stroke-width="1" stroke-dasharray="4,4" />
          <text x="-195" y={y - 3} class="zone-label" fill={getBpmColor(bpm)}>{bpm} bpm</text>
        {/each}

        <!-- Dots -->
        {#each beeswarmDots as dot}
          <circle cx={dot.x} cy={dot.y} r={DOT_RADIUS} fill={dot.color} opacity="0.85" stroke="rgba(0,0,0,0.3)" stroke-width="0.5">
            <title>{dot.name}: {dot.bpm} bpm ({getBpmZone(dot.bpm)})</title>
          </circle>
          {#if DOT_RADIUS >= 7}
            <text x={dot.x} y={dot.y + 3} text-anchor="middle" class="dot-label">{Math.round(dot.bpm)}</text>
          {/if}
        {/each}
      </svg>
    </div>

  <!-- RANKING VIEW -->
  {:else if viewMode === 'ranking'}
    <div class="ranking-container">
      {#each sortedSensors as sensor, i (sensor.sensor_id)}
        {@const pct = sensor.bpm > 0 ? Math.min(100, (sensor.bpm / 180) * 100) : 0}
        <div class="ranking-row">
          <span class="ranking-rank">#{i + 1}</span>
          <span class="ranking-name">{getDisplayName(sensor)}</span>
          <div class="ranking-bar-bg">
            <div class="ranking-bar" style="width: {pct}%; background: {getBpmColor(sensor.bpm)}"></div>
          </div>
          <span class="ranking-bpm" style="color: {getBpmColor(sensor.bpm)}">{sensor.bpm > 0 ? sensor.bpm : '—'}</span>
        </div>
      {/each}
    </div>

  <!-- TIMELINE HEATMAP VIEW -->
  {:else if viewMode === 'timeline'}
    <div class="timeline-container">
      {#if timelineData.sensorIds.length > 0 && timelineData.buckets > 0}
        {@const cellW = Math.max(4, Math.min(16, 800 / timelineData.buckets))}
        {@const cellH = Math.max(14, Math.min(24, 500 / timelineData.sensorIds.length))}
        {@const labelW = 85}
        {@const svgW = labelW + timelineData.buckets * cellW + 2}
        {@const svgH = 20 + timelineData.sensorIds.length * cellH + 2}
        <div class="timeline-scroll">
          <svg viewBox="0 0 {svgW} {svgH}" class="timeline-svg" preserveAspectRatio="xMidYMid meet">
            <!-- Time labels (top) -->
            {#each [0, Math.floor(timelineData.buckets / 4), Math.floor(timelineData.buckets / 2), Math.floor(3 * timelineData.buckets / 4), timelineData.buckets - 1] as b}
              {@const minutesAgo = Math.round((timelineData.buckets - b) * HISTORY_BUCKET_MS / 60000)}
              <text x={labelW + b * cellW + cellW / 2} y="12" text-anchor="middle" class="time-label">
                {minutesAgo > 0 ? `-${minutesAgo}m` : 'now'}
              </text>
            {/each}

            <!-- Rows -->
            {#each timelineData.sensorIds as sid, i}
              <text x={labelW - 4} y={20 + i * cellH + cellH / 2 + 3} text-anchor="end" class="row-label">{getDisplayNameById(sid)}</text>
              {#each timelineData.matrix[i] as bpm, j}
                <rect x={labelW + j * cellW} y={20 + i * cellH} width={cellW - 1} height={cellH - 1} rx="1"
                  fill={bpm > 0 ? getBpmColor(bpm) : 'rgba(75, 85, 99, 0.15)'} opacity={bpm > 0 ? 0.8 : 0.3}>
                  <title>{getDisplayNameById(sid)}: {bpm > 0 ? bpm + ' bpm' : 'no data'}</title>
                </rect>
              {/each}
            {/each}
          </svg>
        </div>
      {:else}
        <div class="empty-msg">Collecting heart rate history...</div>
      {/if}
    </div>
  {/if}

  <!-- Legend (shown in all views) -->
  <div class="legend">
    <div class="legend-item"><span class="legend-dot" style="background: #3b82f6"></span><span>&lt;60 Low</span></div>
    <div class="legend-item"><span class="legend-dot" style="background: #22c55e"></span><span>60-99 Normal</span></div>
    <div class="legend-item"><span class="legend-dot" style="background: #eab308"></span><span>100-119 Elevated</span></div>
    <div class="legend-item"><span class="legend-dot" style="background: #ef4444"></span><span>120+ High</span></div>
  </div>
</div>

<style>
  .composite-hr {
    background: rgba(31, 41, 55, 0.6);
    border-radius: 0.5rem;
    padding: 0.5rem;
    height: 100%;
    display: flex;
    flex-direction: column;
  }

  .hr-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.5rem;
    gap: 0.5rem;
    flex-wrap: wrap;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    gap: 0.6rem;
    padding: 0.3rem 0.6rem;
    background: rgba(17, 24, 39, 0.5);
    border-radius: 0.375rem;
  }

  .stat { display: flex; align-items: baseline; gap: 0.2rem; }
  .stat-label { font-size: 0.6rem; color: #9ca3af; text-transform: uppercase; letter-spacing: 0.05em; }
  .stat-value { font-size: 1rem; font-weight: 700; font-variant-numeric: tabular-nums; }
  .stat-unit { font-size: 0.55rem; color: #6b7280; }
  .stat-divider { width: 1px; height: 1.2rem; background: rgba(75, 85, 99, 0.5); }
  .text-white { color: #ffffff; }

  .view-mode-selector { display: flex; gap: 0.15rem; }
  .mode-btn {
    padding: 0.2rem 0.45rem;
    font-size: 0.65rem;
    font-family: monospace;
    background: rgba(75, 85, 99, 0.2);
    border: 1px solid rgba(75, 85, 99, 0.4);
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
  }
  .mode-btn:hover { background: rgba(75, 85, 99, 0.4); color: #e5e7eb; }
  .mode-btn.active { background: rgba(239, 68, 68, 0.15); border-color: #ef4444; color: #f87171; box-shadow: 0 0 6px rgba(239, 68, 68, 0.2); }

  /* ── Pills View ── */
  .sensor-grid { display: flex; flex-wrap: wrap; gap: 0.375rem; flex: 1; align-content: flex-start; overflow-y: auto; }
  .sensor-pill {
    display: flex; align-items: center; gap: 0.375rem;
    padding: 0.25rem 0.5rem;
    background: rgba(17, 24, 39, 0.6);
    border: 1px solid; border-radius: 9999px;
    font-size: 0.75rem;
  }
  .sensor-pill:hover { background: rgba(17, 24, 39, 0.8); }
  .sensor-name { color: #d1d5db; max-width: 80px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sensor-bpm { font-weight: 600; font-variant-numeric: tabular-nums; }

  /* ── Beeswarm View ── */
  .beeswarm-container {
    flex: 1;
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 200px;
    overflow: hidden;
  }
  .beeswarm-svg { width: 100%; height: 100%; max-height: 500px; }
  .zone-label { font-size: 8px; font-family: monospace; }
  .dot-label { font-size: 6px; font-family: monospace; fill: rgba(0,0,0,0.7); pointer-events: none; font-weight: 600; }

  /* ── Ranking View ── */
  .ranking-container {
    flex: 1;
    overflow-y: auto;
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 0.25rem;
  }
  .ranking-row {
    display: flex;
    align-items: center;
    gap: 0.4rem;
    padding: 0.15rem 0.3rem;
    background: rgba(17, 24, 39, 0.3);
    border-radius: 0.25rem;
  }
  .ranking-rank { font-size: 0.6rem; color: #6b7280; font-family: monospace; min-width: 20px; }
  .ranking-name { font-size: 0.65rem; color: #d1d5db; min-width: 70px; max-width: 90px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: monospace; }
  .ranking-bar-bg { flex: 1; height: 10px; background: rgba(75, 85, 99, 0.2); border-radius: 5px; overflow: hidden; }
  .ranking-bar { height: 100%; border-radius: 5px; transition: width 0.3s ease; }
  .ranking-bpm { font-size: 0.7rem; font-weight: 600; font-family: monospace; font-variant-numeric: tabular-nums; min-width: 30px; text-align: right; }

  /* ── Timeline Heatmap ── */
  .timeline-container {
    flex: 1;
    display: flex;
    flex-direction: column;
    min-height: 200px;
    overflow: hidden;
  }
  .timeline-scroll {
    flex: 1;
    overflow: auto;
    display: flex;
    justify-content: center;
    align-items: flex-start;
    padding: 0.25rem;
  }
  .timeline-svg { max-width: 100%; max-height: 100%; }
  .time-label { font-size: 8px; font-family: monospace; fill: #9ca3af; }
  .row-label { font-size: 9px; font-family: monospace; fill: #9ca3af; }
  .empty-msg {
    flex: 1; display: flex; align-items: center; justify-content: center;
    font-size: 0.7rem; font-family: monospace; color: #9ca3af; opacity: 0.6;
  }

  /* ── Legend ── */
  .legend {
    display: flex; justify-content: center; gap: 0.75rem;
    padding-top: 0.4rem; border-top: 1px solid rgba(75, 85, 99, 0.3);
    margin-top: 0.4rem; flex-shrink: 0;
  }
  .legend-item { display: flex; align-items: center; gap: 0.25rem; font-size: 0.6rem; color: #9ca3af; }
  .legend-dot { width: 6px; height: 6px; border-radius: 50%; }

  @media (max-width: 480px) {
    .hr-header { flex-direction: column; align-items: stretch; }
    .stats-bar { justify-content: center; }
    .view-mode-selector { justify-content: center; }
    .mode-btn { font-size: 0.55rem; padding: 0.15rem 0.3rem; }
  }
</style>

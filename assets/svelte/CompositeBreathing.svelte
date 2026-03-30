<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Highcharts from "highcharts";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; value: number }>;
  } = $props();

  let chartContainer: HTMLDivElement;
  let chart: Highcharts.Chart | null = null;

  const COLORS = [
    '#ef4444', // Red
    '#f97316', // Orange
    '#eab308', // Yellow
    '#22c55e', // Green
    '#06b6d4', // Cyan
    '#3b82f6', // Blue
    '#8b5cf6', // Violet
    '#ec4899', // Pink
    '#14b8a6', // Teal
    '#f59e0b', // Amber
    '#6366f1', // Indigo
    '#10b981', // Emerald
    '#f43f5e', // Rose
    '#0ea5e9', // Sky
    '#a855f7', // Purple
    '#84cc16', // Lime
    '#e879f9', // Fuchsia
    '#fb923c', // Light orange
    '#2dd4bf', // Light teal
    '#818cf8'  // Light indigo
  ];

  const MAX_DATA_POINTS = 5000;
  const UPDATE_INTERVAL_MS = 100;
  const PHASE_BUFFER_SIZE = 50; // ~5 seconds at 10Hz

  const TIME_WINDOWS = [
    { label: '10s', ms: 10 * 1000 },
    { label: '30s', ms: 30 * 1000 },
    { label: '1min', ms: 60 * 1000 }
  ];

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
  let syncDirty = false;

  // Breathing state counts - updated imperatively in the RAF loop
  let latestValues: Map<string, number> = new Map();
  let inhalingCount = $state(0);
  let exhalingCount = $state(0);
  let holdingCount = $state(0);

  // Phase synchronization (Kuramoto order parameter)
  let phaseBuffers: Map<string, number[]> = new Map();
  let phaseSync = $state(0);
  let smoothedSync = 0;

  // Sync history for chart visualization
  let syncHistory: Array<{ x: number; y: number }> = [];
  const SYNC_SERIES_NAME = 'Phase Sync';

  // Pairwise synchronization heatmap
  let viewMode = $state<'chart' | 'heatmap'>('chart');
  let pairwiseSyncMatrix: Map<string, number> = new Map();
  let heatmapSensorIds = $state<string[]>([]);
  let heatmapData = $state<number[][]>([]);
  const PAIRWISE_SMOOTHING = 0.7; // breathing is faster than HRV, react quicker

  function updateBreathingStates() {
    let inhaling = 0, exhaling = 0, holding = 0;

    phaseBuffers.forEach((buffer) => {
      if (buffer.length < 10) return;
      const n = buffer.length;
      const lookback = Math.min(5, n - 1);
      const derivative = buffer[n - 1] - buffer[n - 1 - lookback];
      const threshold = 1.5;

      if (derivative > threshold) inhaling++;
      else if (derivative < -threshold) exhaling++;
      else holding++;
    });

    inhalingCount = inhaling;
    exhalingCount = exhaling;
    holdingCount = holding;
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

  // Estimate instantaneous breathing phase for each sensor,
  // then compute the Kuramoto order parameter R = |mean(e^(i*theta))|.
  // R ranges from 0 (random phases) to 1 (perfect synchrony).
  // Being a circular mean, a few outliers only moderately reduce R.
  function computePhaseSync() {
    const phases: number[] = [];

    phaseBuffers.forEach((buffer) => {
      if (buffer.length < 15) return;

      const n = buffer.length;
      let min = buffer[0], max = buffer[0];
      for (let i = 1; i < n; i++) {
        if (buffer[i] < min) min = buffer[i];
        if (buffer[i] > max) max = buffer[i];
      }
      const range = max - min;
      if (range < 2) return;

      const current = buffer[n - 1];
      const norm = Math.max(0, Math.min(1, (current - min) / range));

      // Derivative from last 5 samples for stable sign estimation
      const lookback = Math.min(5, n - 1);
      const derivative = buffer[n - 1] - buffer[n - 1 - lookback];
      const rising = derivative >= 0;

      // Map normalized value + direction to phase angle [0, 2pi]
      // Rising (inhale):  min→max maps to 0→pi
      // Falling (exhale): max→min maps to pi→2pi
      const baseAngle = Math.acos(1 - 2 * norm);
      const phase = rising ? baseAngle : (2 * Math.PI - baseAngle);
      phases.push(phase);
    });

    if (phases.length < 2) return;

    // Kuramoto order parameter
    let sumCos = 0, sumSin = 0;
    for (const theta of phases) {
      sumCos += Math.cos(theta);
      sumSin += Math.sin(theta);
    }
    const R = Math.sqrt(
      (sumCos / phases.length) ** 2 +
      (sumSin / phases.length) ** 2
    );

    // Exponential moving average for smooth display
    smoothedSync = smoothedSync === 0 ? R : 0.85 * smoothedSync + 0.15 * R;
    phaseSync = Math.round(smoothedSync * 100);

    // Record to history
    syncHistory.push({ x: Date.now(), y: phaseSync });
    if (syncHistory.length > MAX_DATA_POINTS) {
      syncHistory = syncHistory.slice(syncHistory.length - MAX_DATA_POINTS);
    }
    syncDirty = true;
  }

  function getSyncColor(pct: number): string {
    if (pct >= 80) return '#22c55e';
    if (pct >= 60) return '#84cc16';
    if (pct >= 40) return '#eab308';
    if (pct >= 20) return '#f97316';
    return '#ef4444';
  }

  function getSyncLabel(pct: number): string {
    if (pct >= 80) return 'Excellent';
    if (pct >= 60) return 'Good';
    if (pct >= 40) return 'Partial';
    if (pct >= 20) return 'Low';
    return 'None';
  }

  function computePairwiseSync() {
    if (viewMode !== 'heatmap') return;

    const sensorPhases: Array<{ id: string; phase: number }> = [];

    phaseBuffers.forEach((buffer, sensorId) => {
      if (buffer.length < 15) return;
      const n = buffer.length;
      let min = buffer[0], max = buffer[0];
      for (let i = 1; i < n; i++) {
        if (buffer[i] < min) min = buffer[i];
        if (buffer[i] > max) max = buffer[i];
      }
      const range = max - min;
      if (range < 2) return;

      const current = buffer[n - 1];
      const norm = Math.max(0, Math.min(1, (current - min) / range));
      const lookback = Math.min(5, n - 1);
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

  function getDisplayName(sensorId: string): string {
    return sensorNames.get(sensorId) || (sensorId.length > 12 ? sensorId.slice(-8) : sensorId);
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
    latestValues.set(sensorId, value);
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
        updateChart(hadData, timestamp);
        if (hadData) {
          updateBreathingStates();
          computePhaseSync();
          computePairwiseSync();
        }
        lastUpdateTime = timestamp;
      }
    } catch (e) {
      console.warn("[CompositeBreathing] RAF error, recovering:", e);
      if (!chart && chartContainer) createChart();
    }
    rafId = requestAnimationFrame(rafLoop);
  }

  function createChart() {
    if (!chartContainer) return;
    if (chart) {
      chart.destroy();
    }

    const series: Highcharts.SeriesOptionsType[] = Array.from(sensorData.entries()).map(([sensorId, data]) => ({
      type: 'line' as const,
      id: `sensor-${sensorId}`,
      name: getDisplayName(sensorId),
      data: data.map(d => [d.x, d.y]),
      color: sensorColors.get(sensorId) || '#06b6d4',
      lineWidth: 1.5,
      yAxis: 0,
      marker: { enabled: false },
      animation: false,
      states: {
        hover: {
          lineWidth: 2.5
        }
      }
    }));

    // Add sync history as colored area at bottom
    series.push({
      type: 'area' as const,
      name: SYNC_SERIES_NAME,
      data: syncHistory.map(d => [d.x, d.y]),
      yAxis: 1,
      lineWidth: 0,
      marker: { enabled: false },
      animation: false,
      fillOpacity: 0.6,
      enableMouseTracking: true,
      showInLegend: false,
      tooltip: {
        pointFormatter: function() {
          const c = this.y < 20 ? '#ef4444' : this.y < 40 ? '#f97316' : this.y < 60 ? '#eab308' : this.y < 80 ? '#84cc16' : '#22c55e';
          return `<span style="color:${c}">\u25CF</span> Phase Sync: <b>${Math.round(this.y)}%</b><br/>`;
        }
      },
      zones: [
        { value: 20, color: '#ef4444' },
        { value: 40, color: '#f97316' },
        { value: 60, color: '#eab308' },
        { value: 80, color: '#84cc16' },
        { color: '#22c55e' }
      ]
    });

    chart = Highcharts.chart(chartContainer, {
      chart: {
        type: 'line',
        backgroundColor: '#0a0f14',
        animation: false,
        style: {
          fontFamily: 'monospace'
        },
        spacingTop: 5,
        spacingRight: 5,
        spacingBottom: 5,
        spacingLeft: 5,
        zooming: {
          type: 'x'
        }
      },
      title: {
        text: undefined
      },
      credits: {
        enabled: false
      },
      xAxis: {
        type: 'datetime',
        title: {
          text: undefined
        },
        labels: {
          style: {
            color: '#22d3ee',
            fontSize: '9px'
          },
          format: '{value:%H:%M:%S}'
        },
        crosshair: {
          width: 1,
          color: 'rgba(34, 211, 238, 0.4)',
          dashStyle: 'Dot'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(34, 211, 238, 0.15)',
        minorGridLineWidth: 0,
        lineColor: 'rgba(34, 211, 238, 0.3)',
        tickColor: 'rgba(34, 211, 238, 0.3)'
      },
      yAxis: [{
        // Primary: Breathing values
        title: {
          text: '%',
          style: {
            color: '#22d3ee',
            fontSize: '10px'
          },
          margin: 5
        },
        min: 40,
        max: 105,
        height: '85%',
        labels: {
          style: {
            color: '#22d3ee',
            fontSize: '9px'
          },
          format: '{value:.0f}'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(34, 211, 238, 0.15)',
        minorGridLineWidth: 0,
        plotBands: [{
          from: 50,
          to: 100,
          color: 'rgba(6, 182, 212, 0.03)',
          label: {
            text: 'Normal range',
            style: { color: 'rgba(34, 211, 238, 0.3)', fontSize: '9px' },
            align: 'right'
          }
        }]
      }, {
        // Secondary: Sync percentage (bottom strip)
        title: { text: undefined },
        min: 0,
        max: 100,
        top: '88%',
        height: '12%',
        offset: 0,
        labels: { enabled: false },
        gridLineWidth: 0
      }],
      legend: {
        enabled: true,
        align: 'center',
        verticalAlign: 'bottom',
        layout: 'horizontal',
        floating: false,
        backgroundColor: 'transparent',
        borderWidth: 0,
        itemStyle: {
          color: '#9ca3af',
          fontSize: '9px'
        },
        itemHoverStyle: {
          color: '#ffffff'
        },
        itemMarginTop: 2,
        itemMarginBottom: 0,
        margin: 5,
        padding: 0
      },
      tooltip: {
        backgroundColor: 'rgba(10, 15, 20, 0.95)',
        borderColor: 'rgba(34, 211, 238, 0.5)',
        borderWidth: 1,
        style: {
          color: '#22d3ee',
          fontSize: '11px'
        },
        xDateFormat: '%H:%M:%S.%L',
        valueDecimals: 1,
        valueSuffix: '%',
        shared: true
      },
      plotOptions: {
        line: {
          animation: false,
          lineWidth: 1.5
        },
        series: {
          animation: false,
          turboThreshold: 10000,
          states: {
            hover: {
              lineWidthPlus: 1
            }
          }
        }
      },
      series: series
    });
  }

  function getFilteredData(data: Array<{ x: number; y: number }>, cutoff: number): Array<[number, number]> {
    // Binary search for the first point >= cutoff
    let lo = 0, hi = data.length;
    while (lo < hi) {
      const mid = (lo + hi) >>> 1;
      if (data[mid].x < cutoff) lo = mid + 1;
      else hi = mid;
    }
    const result: Array<[number, number]> = new Array(data.length - lo);
    for (let i = lo; i < data.length; i++) {
      result[i - lo] = [data[i].x, data[i].y];
    }
    return result;
  }

  function updateChart(hadData: boolean, timestamp: number) {
    if (!chart) {
      if (chartContainer && sensorData.size > 0) createChart();
      return;
    }

    if (!chart.container || !chartContainer?.isConnected) {
      chart = null;
      return;
    }

    // If no new data, only update xAxis extremes every 500ms for window scrolling
    if (!hadData) {
      if (timestamp - lastExtremesUpdate >= 500) {
        const now = latestDataTimestamp > 0 ? latestDataTimestamp : Date.now();
        chart.xAxis[0].setExtremes(now - selectedWindowMs, now, true, false);
        lastExtremesUpdate = timestamp;
      }
      return;
    }

    const now = latestDataTimestamp > 0 ? latestDataTimestamp : Date.now();
    const cutoff = now - selectedWindowMs;
    let needsRedraw = false;

    // Only update series that have new data
    dirtySeriesIds.forEach((sensorId) => {
      const seriesId = `sensor-${sensorId}`;
      const data = sensorData.get(sensorId);
      if (!data) return;

      const existingSeries = chart!.get(seriesId) as Highcharts.Series | null;
      const filteredData = getFilteredData(data, cutoff);

      if (existingSeries) {
        existingSeries.setData(filteredData, false, false, false);
        needsRedraw = true;
      } else {
        const index = Array.from(sensorData.keys()).indexOf(sensorId);
        chart!.addSeries({
          type: 'line',
          id: seriesId,
          name: getDisplayName(sensorId),
          data: filteredData,
          yAxis: 0,
          color: sensorColors.get(sensorId) || COLORS[index % COLORS.length],
          lineWidth: 1.5,
          marker: { enabled: false },
          animation: false
        }, false);
        needsRedraw = true;
      }
    });
    dirtySeriesIds.clear();

    // Update sync history series only when dirty
    if (syncDirty) {
      const syncSeries = chart.series.find(s => s.name === SYNC_SERIES_NAME);
      const filteredSync = getFilteredData(syncHistory, cutoff);
      if (syncSeries) {
        syncSeries.setData(filteredSync, false, false, false);
        needsRedraw = true;
      } else if (filteredSync.length > 0) {
        chart.addSeries({
          type: 'area',
          name: SYNC_SERIES_NAME,
          data: filteredSync,
          yAxis: 1,
          lineWidth: 0,
          marker: { enabled: false },
          animation: false,
          fillOpacity: 0.6,
          enableMouseTracking: true,
          showInLegend: false,
          tooltip: {
            pointFormatter: function() {
              const c = this.y < 20 ? '#ef4444' : this.y < 40 ? '#f97316' : this.y < 60 ? '#eab308' : this.y < 80 ? '#84cc16' : '#22c55e';
              return `<span style="color:${c}">\u25CF</span> Phase Sync: <b>${Math.round(this.y)}%</b><br/>`;
            }
          },
          zones: [
            { value: 20, color: '#ef4444' },
            { value: 40, color: '#f97316' },
            { value: 60, color: '#eab308' },
            { value: 80, color: '#84cc16' },
            { color: '#22c55e' }
          ]
        }, false);
        needsRedraw = true;
      }
      syncDirty = false;
    }

    if (needsRedraw) {
      chart.xAxis[0].setExtremes(now - selectedWindowMs, now, false);
      chart.redraw(false);
      lastExtremesUpdate = timestamp;
    }
  }

  function setTimeWindow(ms: number) {
    selectedWindowMs = ms;
    // Force full redraw with all series dirty
    sensorData.forEach((_data, sensorId) => dirtySeriesIds.add(sensorId));
    syncDirty = true;
    updateChart(true, performance.now());
  }

  function consumeSeedBuffer(): boolean {
    const seedBuffer = (window as any).__compositeSeedBuffer;
    if (!Array.isArray(seedBuffer) || seedBuffer.length === 0) return false;

    let consumed = 0;
    seedBuffer.forEach((event: any) => {
      if (event.attribute_id === "respiration" && Array.isArray(event.data)) {
        const sid = event.sensor_id;
        if (!sensorData.has(sid)) {
          const index = sensorData.size;
          sensorColors.set(sid, COLORS[index % COLORS.length]);
          sensorData.set(sid, []);
        }
        event.data.forEach((m: any) => {
          if (typeof m?.payload === "number") {
            addDataPoint(sid, m.payload, m.timestamp);
          }
        });
        consumed++;
      } else if (event.attribute_id === "breathing_sync" && Array.isArray(event.data)) {
        event.data.forEach((m: any) => {
          if (typeof m?.payload === "number") {
            syncHistory.push({ x: m.timestamp, y: m.payload });
          }
        });
        syncDirty = true;
        consumed++;
      }
    });
    (window as any).__compositeSeedBuffer = [];
    if (consumed > 0) processPendingUpdates();
    return consumed > 0;
  }

  onMount(() => {
    initializeSensorData();
    createChart();
    rafId = requestAnimationFrame(rafLoop);

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload, timestamp } = e.detail;

      if (attribute_id === "respiration") {
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
      if (attributeId === "respiration") {
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
      } else if (attributeId === "breathing_sync") {
        const data = e?.detail?.data;
        if (Array.isArray(data) && data.length > 0) {
          data.forEach((m: any) => {
            if (typeof m?.payload === "number") {
              syncHistory.push({ x: m.timestamp, y: m.payload });
            }
          });
          syncDirty = true;
        }
      }
    };

    window.addEventListener(
      "composite-measurement-event",
      handleCompositeMeasurement as EventListener
    );

    window.addEventListener(
      "accumulator-data-event",
      handleAccumulatorEvent as EventListener
    );

    // Signal readiness - the hook will replay any buffered seed data
    if (consumeSeedBuffer()) {
      sensorData.forEach((_data, sensorId) => dirtySeriesIds.add(sensorId));
      syncDirty = true;
      updateChart(true, performance.now());
    }
    window.dispatchEvent(new CustomEvent('composite-component-ready'));

    return () => {
      window.removeEventListener(
        "composite-measurement-event",
        handleCompositeMeasurement as EventListener
      );
      window.removeEventListener(
        "accumulator-data-event",
        handleAccumulatorEvent as EventListener
      );
    };
  });

  onDestroy(() => {
    if (rafId) {
      cancelAnimationFrame(rafId);
    }
    if (chart) {
      chart.destroy();
    }
  });
</script>

<div class="composite-chart-container">
  <div class="chart-header">
    <div class="header-left">
      <h2>Breathing Overview</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
    </div>
    <div class="stats-bar">
      <span class="breath-state has-tooltip" data-tooltip="Inhaling — participants currently breathing in (rising torso expansion)">
        <svg class="breath-svg inhale" viewBox="0 0 16 16" width="12" height="12">
          <path d="M8 2 C5 2 3 5 3 8 C3 11 5 14 8 14 C11 14 13 11 13 8 C13 5 11 2 8 2" fill="none" stroke="currentColor" stroke-width="1.5"/>
          <path d="M5 8 L8 4 L11 8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        {inhalingCount}
      </span>
      <span class="breath-state has-tooltip" data-tooltip="Exhaling — participants currently breathing out (falling torso expansion)">
        <svg class="breath-svg exhale" viewBox="0 0 16 16" width="12" height="12">
          <path d="M8 2 C5 2 3 5 3 8 C3 11 5 14 8 14 C11 14 13 11 13 8 C13 5 11 2 8 2" fill="none" stroke="currentColor" stroke-width="1.5"/>
          <path d="M5 8 L8 12 L11 8" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
        </svg>
        {exhalingCount}
      </span>
      <span class="breath-state has-tooltip" data-tooltip="Holding — participants in a breath hold (neither inhaling nor exhaling)">
        <svg class="breath-svg hold" viewBox="0 0 16 16" width="12" height="12">
          <path d="M8 2 C5 2 3 5 3 8 C3 11 5 14 8 14 C11 14 13 11 13 8 C13 5 11 2 8 2" fill="none" stroke="currentColor" stroke-width="1.5"/>
          <line x1="5" y1="8" x2="11" y2="8" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/>
        </svg>
        {holdingCount}
      </span>
      <span class="stat-divider"></span>
      <span class="sync-value has-tooltip" data-tooltip="Phase Sync (Kuramoto) — how synchronized breathing is across participants. 0% = random, 100% = perfectly in sync" style="color: {getSyncColor(phaseSync)}">{phaseSync}%</span>
    </div>
    <div class="header-controls">
      <div class="view-mode-selector">
        <button
          class="time-btn"
          class:active={viewMode === 'chart'}
          onclick={() => { viewMode = 'chart'; if (chart) setTimeout(() => chart?.reflow(), 50); }}
          title="Kuramoto time-series chart"
        >
          <svg viewBox="0 0 16 16" width="10" height="10" fill="none" stroke="currentColor" stroke-width="1.5">
            <polyline points="1,12 4,8 7,10 10,4 13,6 15,2"/>
          </svg>
          Chart
        </button>
        <button
          class="time-btn"
          class:active={viewMode === 'heatmap'}
          onclick={() => { viewMode = 'heatmap'; }}
          title="Pairwise synchronization heatmap"
        >
          <svg viewBox="0 0 16 16" width="10" height="10" fill="currentColor">
            <rect x="1" y="1" width="4" height="4" rx="0.5" opacity="0.9"/>
            <rect x="6" y="1" width="4" height="4" rx="0.5" opacity="0.5"/>
            <rect x="11" y="1" width="4" height="4" rx="0.5" opacity="0.2"/>
            <rect x="1" y="6" width="4" height="4" rx="0.5" opacity="0.5"/>
            <rect x="6" y="6" width="4" height="4" rx="0.5" opacity="0.9"/>
            <rect x="11" y="6" width="4" height="4" rx="0.5" opacity="0.4"/>
            <rect x="1" y="11" width="4" height="4" rx="0.5" opacity="0.2"/>
            <rect x="6" y="11" width="4" height="4" rx="0.5" opacity="0.4"/>
            <rect x="11" y="11" width="4" height="4" rx="0.5" opacity="0.9"/>
          </svg>
          Heatmap
        </button>
      </div>
      {#if viewMode === 'chart'}
        <div class="time-window-selector">
          {#each TIME_WINDOWS as window}
            <button
              class="time-btn"
              class:active={selectedWindowMs === window.ms}
              onclick={() => setTimeWindow(window.ms)}
            >
              {window.label}
            </button>
          {/each}
        </div>
      {/if}
    </div>
  </div>
  <div class="sync-bar">
    <div
      class="sync-bar-fill"
      style="width: {phaseSync}%; background: {getSyncColor(phaseSync)}"
    ></div>
  </div>
  {#if viewMode === 'chart'}
    <div class="chart-wrapper" bind:this={chartContainer}></div>
  {:else}
    <div class="heatmap-section">
      <div class="heatmap-header">
        <span class="heatmap-title">Pairwise Breathing Synchronization</span>
        <div class="heatmap-legend">
          <span class="legend-label">Low</span>
          <div class="legend-gradient"></div>
          <span class="legend-label">High</span>
        </div>
      </div>
      {#if heatmapSensorIds.length >= 2}
        {@const n = heatmapSensorIds.length}
        {@const cellSize = Math.max(28, Math.min(56, 500 / n))}
        {@const labelWidth = 80}
        {@const headerHeight = 100}
        {@const gridWidth = n * cellSize}
        {@const svgWidth = labelWidth + gridWidth + 2}
        {@const svgHeight = headerHeight + gridWidth + 2}
        <div class="heatmap-scroll">
          <svg
            viewBox="0 0 {svgWidth} {svgHeight}"
            class="heatmap-svg"
            preserveAspectRatio="xMidYMid meet"
          >
            {#each heatmapSensorIds as id, i}
              {@const cx = labelWidth + i * cellSize + cellSize / 2}
              {@const cy = headerHeight - 6}
              <text
                x={cx}
                y={cy}
                text-anchor="start"
                transform="rotate(-45, {cx}, {cy})"
                class="heatmap-label"
              >{getDisplayName(id)}</text>
            {/each}

            {#each heatmapSensorIds as rowId, i}
              <text
                x={labelWidth - 6}
                y={headerHeight + i * cellSize + cellSize / 2 + 3}
                text-anchor="end"
                class="heatmap-label"
              >{getDisplayName(rowId)}</text>

              {#each heatmapSensorIds as _colId, j}
                {@const value = heatmapData[i]?.[j] ?? 0}
                <rect
                  x={labelWidth + j * cellSize + 1}
                  y={headerHeight + i * cellSize + 1}
                  width={cellSize - 2}
                  height={cellSize - 2}
                  rx="2"
                  fill={i === j ? 'rgba(34, 211, 238, 0.15)' : getHeatmapColor(value)}
                  opacity={i === j ? 1 : 0.85}
                >
                  <title>{i === j ? getDisplayName(rowId) : `${getDisplayName(rowId)} ↔ ${getDisplayName(_colId)}: ${Math.round(value * 100)}%`}</title>
                </rect>
                {#if i === j}
                  <circle
                    cx={labelWidth + j * cellSize + cellSize / 2}
                    cy={headerHeight + i * cellSize + cellSize / 2}
                    r={Math.min(8, cellSize / 3.5)}
                    fill={sensorColors.get(rowId) || '#22d3ee'}
                  />
                {:else if cellSize >= 28}
                  <text
                    x={labelWidth + j * cellSize + cellSize / 2}
                    y={headerHeight + i * cellSize + cellSize / 2 + 4}
                    text-anchor="middle"
                    class="cell-value"
                  >{Math.round(value * 100)}</text>
                {/if}
              {/each}
            {/each}
          </svg>
        </div>
      {:else}
        <div class="heatmap-empty">
          Waiting for ≥2 sensors with breathing phase data...
        </div>
      {/if}
    </div>
  {/if}
</div>

<style>
  .composite-chart-container {
    background: #0a0f14;
    border-radius: 0.5rem;
    border: 1px solid rgba(34, 211, 238, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: 260px;
    display: flex;
    flex-direction: column;
    box-shadow:
      0 0 20px rgba(6, 182, 212, 0.05),
      inset 0 0 60px rgba(0, 0, 0, 0.5);
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
    padding: 0.2rem 0.5rem;
    background: rgba(34, 211, 238, 0.05);
    border-radius: 0.25rem;
    border: 1px solid rgba(34, 211, 238, 0.2);
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
    color: #22d3ee;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    white-space: nowrap;
  }

  .sensor-count {
    font-size: 0.65rem;
    color: #22d3ee;
    font-family: monospace;
    opacity: 0.7;
    white-space: nowrap;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .breath-state {
    display: flex;
    align-items: center;
    gap: 0.15rem;
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    color: #22d3ee;
    font-variant-numeric: tabular-nums;
  }

  .breath-svg {
    flex-shrink: 0;
  }

  .breath-svg.inhale { color: #22c55e; }
  .breath-svg.exhale { color: #f97316; }
  .breath-svg.hold { color: #9ca3af; }

  .stat-divider {
    width: 1px;
    height: 0.8rem;
    background: rgba(34, 211, 238, 0.2);
  }

  .sync-value {
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    font-variant-numeric: tabular-nums;
  }

  .has-tooltip {
    position: relative;
    cursor: help;
  }

  .has-tooltip::after {
    content: attr(data-tooltip);
    position: absolute;
    bottom: calc(100% + 6px);
    left: 50%;
    transform: translateX(-50%);
    background: rgba(10, 15, 20, 0.95);
    color: #e5e7eb;
    font-size: 0.65rem;
    font-weight: 400;
    font-family: system-ui, sans-serif;
    line-height: 1.4;
    padding: 0.35rem 0.5rem;
    border-radius: 0.25rem;
    border: 1px solid rgba(34, 211, 238, 0.3);
    white-space: normal;
    width: max-content;
    max-width: 220px;
    pointer-events: none;
    opacity: 0;
    transition: opacity 0.15s ease;
    z-index: 100;
    box-shadow: 0 4px 12px rgba(0, 0, 0, 0.4);
  }

  .has-tooltip:hover::after {
    opacity: 1;
  }

  @media (max-width: 480px) {
    .composite-chart-container { padding: 0.15rem; }
    .chart-header { flex-wrap: nowrap; gap: 0.2rem; padding: 0.1rem 0.2rem; margin-bottom: 0.1rem; }
    .header-left { gap: 0.2rem; flex-shrink: 0; }
    .chart-header h2 { font-size: 0.55rem; letter-spacing: 0; }
    .sensor-count { display: none; }
    .stats-bar { gap: 0.25rem; }
    .breath-state { font-size: 0.6rem; }
    .breath-svg { width: 10px; height: 10px; }
    .sync-value { font-size: 0.6rem; }
    .stat-divider { height: 0.6rem; }
    .sync-bar { height: 2px; margin-bottom: 0.1rem; }
    .time-window-selector { gap: 0.1rem; flex-shrink: 0; }
    .time-btn { padding: 0.1rem 0.2rem; font-size: 0.5rem; }
    .heatmap-section { min-height: 100px; }
    .heatmap-title { font-size: 0.55rem; }
    .view-mode-selector .time-btn svg { display: none; }
  }

  .sync-bar {
    height: 3px;
    background: rgba(34, 211, 238, 0.1);
    border-radius: 2px;
    margin-bottom: 0.25rem;
    overflow: hidden;
  }

  .sync-bar-fill {
    height: 100%;
    border-radius: 2px;
    transition: width 0.3s ease, background 0.3s ease;
    box-shadow: 0 0 6px currentColor;
  }

  .time-window-selector {
    display: flex;
    gap: 0.25rem;
  }

  .time-btn {
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    font-family: monospace;
    background: rgba(34, 211, 238, 0.1);
    border: 1px solid rgba(34, 211, 238, 0.3);
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .time-btn:hover {
    background: rgba(34, 211, 238, 0.2);
    color: #22d3ee;
  }

  .time-btn.active {
    background: rgba(34, 211, 238, 0.3);
    border-color: #22d3ee;
    color: #22d3ee;
    box-shadow: 0 0 8px rgba(34, 211, 238, 0.3);
  }

  .header-controls {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .view-mode-selector {
    display: flex;
    gap: 0.15rem;
  }

  .view-mode-selector .time-btn {
    display: flex;
    align-items: center;
    gap: 0.2rem;
  }

  .heatmap-section {
    flex: 1;
    min-height: 200px;
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
    color: #22d3ee;
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
    max-width: 100%;
    max-height: 100%;
    width: auto;
    height: auto;
  }

  .heatmap-label {
    font-size: 13px;
    font-family: monospace;
    fill: #9ca3af;
  }

  .cell-value {
    font-size: 12px;
    font-family: monospace;
    fill: rgba(255, 255, 255, 0.85);
    pointer-events: none;
  }

  .heatmap-empty {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 0.7rem;
    font-family: monospace;
    color: #9ca3af;
    opacity: 0.6;
  }

  .chart-wrapper {
    flex: 1;
    min-height: 200px;
    background:
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 19px,
        rgba(34, 211, 238, 0.03) 19px,
        rgba(34, 211, 238, 0.03) 20px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 19px,
        rgba(34, 211, 238, 0.03) 19px,
        rgba(34, 211, 238, 0.03) 20px
      ),
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 99px,
        rgba(34, 211, 238, 0.08) 99px,
        rgba(34, 211, 238, 0.08) 100px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 99px,
        rgba(34, 211, 238, 0.08) 99px,
        rgba(34, 211, 238, 0.08) 100px
      );
    border-radius: 0.25rem;
  }
</style>

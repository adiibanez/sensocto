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
  const PHASE_BUFFER_SIZE = 20; // HRV data at ~0.2Hz, 20 samples = ~100s of context

  const TIME_WINDOWS = [
    { label: '5min', ms: 5 * 60 * 1000 },
    { label: '15min', ms: 15 * 60 * 1000 },
    { label: '1h', ms: 60 * 60 * 1000 }
  ];

  let selectedWindowMs = $state(TIME_WINDOWS[0].ms);
  let sensorData: Map<string, Array<{ x: number; y: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();
  let sensorNames: Map<string, string> = new Map();
  let pendingUpdates: Map<string, Array<{ x: number; y: number }>> = new Map();
  let rafId: number | null = null;
  let lastUpdateTime = 0;

  // HRV stress state counts - updated imperatively in the RAF loop
  let latestValues: Map<string, number> = new Map();
  let stressedCount = $state(0);
  let moderateCount = $state(0);
  let relaxedCount = $state(0);
  let groupMeanRmssd = $state(0);

  // Phase synchronization (Kuramoto order parameter)
  let phaseBuffers: Map<string, number[]> = new Map();
  let phaseSync = $state(0);
  let smoothedSync = 0;

  // Sync history for chart visualization
  let syncHistory: Array<{ x: number; y: number }> = [];
  const SYNC_SERIES_NAME = 'Phase Sync';

  function updateHrvStates() {
    let stressed = 0, moderate = 0, relaxed = 0;
    let sum = 0, count = 0;

    latestValues.forEach((value) => {
      if (value < 20) stressed++;
      else if (value <= 50) moderate++;
      else relaxed++;
      sum += value;
      count++;
    });

    stressedCount = stressed;
    moderateCount = moderate;
    relaxedCount = relaxed;
    groupMeanRmssd = count > 0 ? Math.round(sum / count) : 0;
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

  // Estimate instantaneous HRV phase for each sensor,
  // then compute the Kuramoto order parameter R = |mean(e^(i*theta))|.
  // R ranges from 0 (random phases) to 1 (perfect synchrony).
  // Being a circular mean, a few outliers only moderately reduce R.
  function computePhaseSync() {
    const phases: number[] = [];

    phaseBuffers.forEach((buffer) => {
      if (buffer.length < 8) return;

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
      // Rising:  min->max maps to 0->pi
      // Falling: max->min maps to pi->2pi
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
    const pending = pendingUpdates.get(sensorId) || [];
    pending.push({ x: timestamp || Date.now(), y: value });
    pendingUpdates.set(sensorId, pending);
    latestValues.set(sensorId, value);
    addToPhaseBuffer(sensorId, value);
  }

  function processPendingUpdates() {
    if (pendingUpdates.size === 0) return;

    pendingUpdates.forEach((points, sensorId) => {
      let data = sensorData.get(sensorId) || [];
      data.push(...points);
      if (data.length > MAX_DATA_POINTS) {
        data = data.slice(data.length - MAX_DATA_POINTS);
      }
      sensorData.set(sensorId, data);
    });

    pendingUpdates.clear();
  }

  function rafLoop(timestamp: number) {
    try {
      if (timestamp - lastUpdateTime >= UPDATE_INTERVAL_MS) {
        processPendingUpdates();
        updateChart();
        updateHrvStates();
        computePhaseSync();
        lastUpdateTime = timestamp;
      }
    } catch (e) {
      console.warn("[CompositeHRV] RAF error, recovering:", e);
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
      color: sensorColors.get(sensorId) || '#f97316',
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
            color: '#f97316',
            fontSize: '9px'
          },
          format: '{value:%H:%M:%S}'
        },
        crosshair: {
          width: 1,
          color: 'rgba(249, 115, 22, 0.4)',
          dashStyle: 'Dot'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(249, 115, 22, 0.15)',
        minorGridLineWidth: 0,
        lineColor: 'rgba(249, 115, 22, 0.3)',
        tickColor: 'rgba(249, 115, 22, 0.3)'
      },
      yAxis: [{
        // Primary: RMSSD values
        title: {
          text: 'ms',
          style: {
            color: '#f97316',
            fontSize: '10px'
          },
          margin: 5
        },
        min: 0,
        max: 120,
        height: '85%',
        labels: {
          style: {
            color: '#f97316',
            fontSize: '9px'
          },
          format: '{value:.0f}'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(249, 115, 22, 0.15)',
        minorGridLineWidth: 0,
        plotBands: [{
          from: 20,
          to: 80,
          color: 'rgba(249, 115, 22, 0.03)',
          label: {
            text: 'Normal range',
            style: { color: 'rgba(249, 115, 22, 0.3)', fontSize: '9px' },
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
        borderColor: 'rgba(249, 115, 22, 0.5)',
        borderWidth: 1,
        style: {
          color: '#f97316',
          fontSize: '11px'
        },
        xDateFormat: '%H:%M:%S.%L',
        valueDecimals: 1,
        valueSuffix: 'ms',
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
    let start = 0;
    for (let i = 0; i < data.length; i++) {
      if (data[i].x >= cutoff) {
        start = i;
        break;
      }
      start = i + 1;
    }
    const result: Array<[number, number]> = new Array(data.length - start);
    for (let i = start; i < data.length; i++) {
      result[i - start] = [data[i].x, data[i].y];
    }
    return result;
  }

  function updateChart() {
    if (!chart) {
      if (chartContainer && sensorData.size > 0) createChart();
      return;
    }

    // Guard against destroyed/detached chart
    if (!chart.container || !chartContainer?.isConnected) {
      chart = null;
      return;
    }

    const now = Date.now();
    const cutoff = now - selectedWindowMs;
    let needsRedraw = false;

    Array.from(sensorData.entries()).forEach(([sensorId, data], index) => {
      const seriesId = `sensor-${sensorId}`;
      const existingSeries = chart!.get(seriesId) as Highcharts.Series | null;
      const filteredData = getFilteredData(data, cutoff);

      if (existingSeries) {
        existingSeries.setData(filteredData, false, false, false);
        needsRedraw = true;
      } else {
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

    // Update sync history series
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

    if (needsRedraw) {
      chart.xAxis[0].setExtremes(now - selectedWindowMs, now, false);
      chart.redraw(false);
    }
  }

  function setTimeWindow(ms: number) {
    selectedWindowMs = ms;
    updateChart();
  }

  function consumeSeedBuffer(): boolean {
    const seedBuffer = (window as any).__compositeSeedBuffer;
    if (!Array.isArray(seedBuffer) || seedBuffer.length === 0) return false;

    let consumed = 0;
    seedBuffer.forEach((event: any) => {
      if (event.attribute_id === "hrv" && Array.isArray(event.data)) {
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
      } else if (event.attribute_id === "hrv_sync" && Array.isArray(event.data)) {
        event.data.forEach((m: any) => {
          if (typeof m?.payload === "number") {
            syncHistory.push({ x: m.timestamp, y: m.payload });
          }
        });
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

      if (attribute_id === "hrv") {
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
      if (attributeId === "hrv") {
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
      } else if (attributeId === "hrv_sync") {
        const data = e?.detail?.data;
        if (Array.isArray(data) && data.length > 0) {
          data.forEach((m: any) => {
            if (typeof m?.payload === "number") {
              syncHistory.push({ x: m.timestamp, y: m.payload });
            }
          });
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
    if (consumeSeedBuffer()) updateChart();
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
      <h2>HRV Overview</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
    </div>
    <div class="stats-bar">
      <span class="hrv-state has-tooltip" data-tooltip="Stressed — RMSSD below 20ms. High sympathetic (fight-or-flight) activity">
        <svg class="hrv-svg stressed" viewBox="0 0 16 16" width="12" height="12">
          <path d="M3 4 L8 12 L13 4 Z" fill="currentColor" opacity="0.8"/>
        </svg>
        {stressedCount}
      </span>
      <span class="hrv-state has-tooltip" data-tooltip="Moderate — RMSSD 20-50ms. Balanced autonomic nervous system activity">
        <svg class="hrv-svg moderate" viewBox="0 0 16 16" width="12" height="12">
          <rect x="2" y="6" width="12" height="4" rx="1" fill="currentColor" opacity="0.8"/>
        </svg>
        {moderateCount}
      </span>
      <span class="hrv-state has-tooltip" data-tooltip="Relaxed — RMSSD above 50ms. High parasympathetic (rest-and-digest) activity">
        <svg class="hrv-svg relaxed" viewBox="0 0 16 16" width="12" height="12">
          <path d="M3 12 L8 4 L13 12 Z" fill="currentColor" opacity="0.8"/>
        </svg>
        {relaxedCount}
      </span>
      <span class="stat-divider"></span>
      <span class="hrv-mean has-tooltip" data-tooltip="Group Mean RMSSD — average of successive RR-interval differences across all participants. Higher = greater vagal tone / relaxation">x&#x0304; {groupMeanRmssd}<span class="hrv-unit">ms</span></span>
      <span class="stat-divider"></span>
      <span class="sync-value has-tooltip" data-tooltip="Phase Sync (Kuramoto) — how synchronized HRV oscillations are across participants. 0% = random, 100% = perfectly in sync" style="color: {getSyncColor(phaseSync)}">{phaseSync}%</span>
    </div>
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
  </div>
  <div class="sync-bar">
    <div
      class="sync-bar-fill"
      style="width: {phaseSync}%; background: {getSyncColor(phaseSync)}"
    ></div>
  </div>
  <div class="chart-wrapper" bind:this={chartContainer}></div>
</div>

<style>
  .composite-chart-container {
    background: #0a0f14;
    border-radius: 0.5rem;
    border: 1px solid rgba(249, 115, 22, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: 260px;
    display: flex;
    flex-direction: column;
    box-shadow:
      0 0 20px rgba(249, 115, 22, 0.05),
      inset 0 0 60px rgba(0, 0, 0, 0.5);
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
    padding: 0.2rem 0.5rem;
    background: rgba(249, 115, 22, 0.05);
    border-radius: 0.25rem;
    border: 1px solid rgba(249, 115, 22, 0.2);
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
    color: #f97316;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    white-space: nowrap;
  }

  .sensor-count {
    font-size: 0.65rem;
    color: #f97316;
    font-family: monospace;
    opacity: 0.7;
    white-space: nowrap;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    gap: 0.4rem;
  }

  .hrv-state {
    display: flex;
    align-items: center;
    gap: 0.15rem;
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    color: #f97316;
    font-variant-numeric: tabular-nums;
  }

  .hrv-svg {
    flex-shrink: 0;
  }

  .hrv-svg.stressed { color: #ef4444; }
  .hrv-svg.moderate { color: #eab308; }
  .hrv-svg.relaxed { color: #22c55e; }

  .hrv-mean {
    font-size: 0.7rem;
    font-weight: 600;
    font-family: monospace;
    color: #f97316;
    font-variant-numeric: tabular-nums;
  }

  .hrv-unit {
    font-size: 0.55rem;
    opacity: 0.6;
    margin-left: 1px;
  }

  .stat-divider {
    width: 1px;
    height: 0.8rem;
    background: rgba(249, 115, 22, 0.2);
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
    border: 1px solid rgba(249, 115, 22, 0.3);
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
    .hrv-state { font-size: 0.6rem; }
    .hrv-svg { width: 10px; height: 10px; }
    .hrv-mean { font-size: 0.6rem; }
    .sync-value { font-size: 0.6rem; }
    .stat-divider { height: 0.6rem; }
    .sync-bar { height: 2px; margin-bottom: 0.1rem; }
    .time-window-selector { gap: 0.1rem; flex-shrink: 0; }
    .time-btn { padding: 0.1rem 0.2rem; font-size: 0.5rem; }
  }

  .sync-bar {
    height: 3px;
    background: rgba(249, 115, 22, 0.1);
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
    background: rgba(249, 115, 22, 0.1);
    border: 1px solid rgba(249, 115, 22, 0.3);
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .time-btn:hover {
    background: rgba(249, 115, 22, 0.2);
    color: #f97316;
  }

  .time-btn.active {
    background: rgba(249, 115, 22, 0.3);
    border-color: #f97316;
    color: #f97316;
    box-shadow: 0 0 8px rgba(249, 115, 22, 0.3);
  }

  .chart-wrapper {
    flex: 1;
    min-height: 200px;
    background:
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 19px,
        rgba(249, 115, 22, 0.03) 19px,
        rgba(249, 115, 22, 0.03) 20px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 19px,
        rgba(249, 115, 22, 0.03) 19px,
        rgba(249, 115, 22, 0.03) 20px
      ),
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 99px,
        rgba(249, 115, 22, 0.08) 99px,
        rgba(249, 115, 22, 0.08) 100px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 99px,
        rgba(249, 115, 22, 0.08) 99px,
        rgba(249, 115, 22, 0.08) 100px
      );
    border-radius: 0.25rem;
  }
</style>

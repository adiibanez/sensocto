<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Highcharts from "highcharts";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; value: number }>;
  } = $props();

  let chartContainer: HTMLDivElement;
  let chart: Highcharts.Chart | null = null;

  const COLORS = [
    '#06b6d4', // Cyan
    '#22d3ee', // Light cyan
    '#67e8f9', // Lighter cyan
    '#0891b2', // Dark cyan
    '#2dd4bf', // Teal
    '#5eead4', // Light teal
    '#14b8a6', // Medium teal
    '#99f6e4', // Pale teal
    '#0d9488', // Deep teal
    '#a5f3fc'  // Ice cyan
  ];

  const MAX_DATA_POINTS = 5000;
  const UPDATE_INTERVAL_MS = 100;
  const PHASE_BUFFER_SIZE = 50; // ~5 seconds at 10Hz

  const TIME_WINDOWS = [
    { label: '10s', ms: 10 * 1000 },
    { label: '2min', ms: 2 * 60 * 1000 },
    { label: '10min', ms: 10 * 60 * 1000 }
  ];

  let selectedWindowMs = $state(TIME_WINDOWS[0].ms);
  let sensorData: Map<string, Array<{ x: number; y: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();
  let pendingUpdates: Map<string, Array<{ x: number; y: number }>> = new Map();
  let rafId: number | null = null;
  let lastUpdateTime = 0;

  // Stats - updated imperatively in the RAF loop
  let latestValues: Map<string, number> = new Map();
  let avgExpansion = $state(0);
  let minExpansion = $state(0);
  let maxExpansion = $state(0);

  // Phase synchronization (Kuramoto order parameter)
  let phaseBuffers: Map<string, number[]> = new Map();
  let phaseSync = $state(0);
  let smoothedSync = 0;

  function updateStats() {
    const vals = Array.from(latestValues.values()).filter(v => v > 0);
    if (vals.length > 0) {
      avgExpansion = Math.round(vals.reduce((sum, v) => sum + v, 0) / vals.length);
      minExpansion = Math.round(Math.min(...vals));
      maxExpansion = Math.round(Math.max(...vals));
    }
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

  function initializeSensorData() {
    sensors.forEach((sensor, index) => {
      if (!sensorData.has(sensor.sensor_id)) {
        sensorData.set(sensor.sensor_id, []);
        sensorColors.set(sensor.sensor_id, COLORS[index % COLORS.length]);
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
    if (timestamp - lastUpdateTime >= UPDATE_INTERVAL_MS) {
      processPendingUpdates();
      updateChart();
      updateStats();
      computePhaseSync();
      lastUpdateTime = timestamp;
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
      name: sensorId.length > 12 ? sensorId.slice(-8) : sensorId,
      data: data.map(d => [d.x, d.y]),
      color: sensorColors.get(sensorId) || '#06b6d4',
      lineWidth: 1.5,
      marker: { enabled: false },
      animation: false,
      states: {
        hover: {
          lineWidth: 2
        }
      }
    }));

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
        gridLineWidth: 1,
        gridLineColor: 'rgba(34, 211, 238, 0.15)',
        minorGridLineWidth: 0,
        lineColor: 'rgba(34, 211, 238, 0.3)',
        tickColor: 'rgba(34, 211, 238, 0.3)'
      },
      yAxis: {
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
      },
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
          enableMouseTracking: false,
          lineWidth: 1.5
        },
        series: {
          animation: false,
          turboThreshold: 10000,
          states: {
            hover: {
              enabled: false
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
    if (!chart) return;

    const now = Date.now();
    const cutoff = now - selectedWindowMs;
    let needsRedraw = false;

    Array.from(sensorData.entries()).forEach(([sensorId, data], index) => {
      const displayName = sensorId.length > 12 ? sensorId.slice(-8) : sensorId;
      const existingSeries = chart!.series.find(s => s.name === displayName);
      const filteredData = getFilteredData(data, cutoff);

      if (existingSeries) {
        existingSeries.setData(filteredData, false, false, false);
        needsRedraw = true;
      } else if (filteredData.length > 0) {
        chart!.addSeries({
          type: 'line',
          name: displayName,
          data: filteredData,
          color: sensorColors.get(sensorId) || COLORS[index % COLORS.length],
          lineWidth: 1.5,
          marker: { enabled: false },
          animation: false
        }, false);
        needsRedraw = true;
      }
    });

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
      <h2>Breathing Overview</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
    </div>
    <div class="stats-bar">
      <div class="stat">
        <span class="stat-label">Avg</span>
        <span class="stat-value">{avgExpansion}%</span>
      </div>
      <div class="stat">
        <span class="stat-label">Min</span>
        <span class="stat-value">{minExpansion}%</span>
      </div>
      <div class="stat">
        <span class="stat-label">Max</span>
        <span class="stat-value">{maxExpansion}%</span>
      </div>
      <div class="stat-divider"></div>
      <div class="stat sync-stat">
        <span class="stat-label">In Phase</span>
        <span class="stat-value" style="color: {getSyncColor(phaseSync)}">{phaseSync}%</span>
        <span class="sync-label" style="color: {getSyncColor(phaseSync)}">{getSyncLabel(phaseSync)}</span>
      </div>
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
    border: 1px solid rgba(34, 211, 238, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: 260px;
    box-shadow:
      0 0 20px rgba(6, 182, 212, 0.05),
      inset 0 0 60px rgba(0, 0, 0, 0.5);
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
    padding: 0.25rem 0.5rem;
    background: rgba(34, 211, 238, 0.05);
    border-radius: 0.25rem;
    border: 1px solid rgba(34, 211, 238, 0.2);
    flex-wrap: wrap;
    gap: 0.5rem;
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .chart-header h2 {
    font-size: 0.75rem;
    font-weight: 600;
    color: #22d3ee;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .sensor-count {
    font-size: 0.65rem;
    color: #22d3ee;
    font-family: monospace;
    opacity: 0.7;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .stat {
    display: flex;
    align-items: baseline;
    gap: 0.25rem;
  }

  .stat-label {
    font-size: 0.6rem;
    color: #9ca3af;
    text-transform: uppercase;
    font-family: monospace;
  }

  .stat-value {
    font-size: 0.8rem;
    font-weight: 600;
    color: #22d3ee;
    font-family: monospace;
    font-variant-numeric: tabular-nums;
  }

  .stat-divider {
    width: 1px;
    height: 1.2rem;
    background: rgba(34, 211, 238, 0.2);
  }

  .sync-stat {
    gap: 0.35rem;
  }

  .sync-label {
    font-size: 0.55rem;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    opacity: 0.8;
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

  .chart-wrapper {
    height: calc(100% - 2.5rem);
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

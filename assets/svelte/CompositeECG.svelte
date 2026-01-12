<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Highcharts from "highcharts";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; value: number }>;
  } = $props();

  let chartContainer: HTMLDivElement;
  let chart: Highcharts.Chart | null = null;

  // ECG-appropriate colors - medical monitor style
  const COLORS = [
    '#00ff00', // Classic ECG green
    '#00ffff', // Cyan
    '#ffff00', // Yellow
    '#ff6600', // Orange
    '#ff00ff', // Magenta
    '#00ff99', // Teal green
    '#66ccff', // Light blue
    '#ff9999', // Light red
    '#99ff99', // Light green
    '#ffcc00'  // Gold
  ];

  const MAX_DATA_POINTS = 5000;
  const UPDATE_INTERVAL_MS = 100;

  // Time window options in milliseconds
  const TIME_WINDOWS = [
    { label: '10s', ms: 10 * 1000 },
    { label: '2min', ms: 2 * 60 * 1000 },
    { label: '10min', ms: 10 * 60 * 1000 }
  ];

  let selectedWindowMs = $state(TIME_WINDOWS[0].ms);
  let sensorData: Map<string, Array<{ x: number; y: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();
  let pendingUpdates: Map<string, Array<{ x: number; y: number }>> = new Map();
  let updateTimer: ReturnType<typeof setInterval> | null = null;
  let rafId: number | null = null;
  let lastUpdateTime = 0;

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
  }

  function processPendingUpdates() {
    if (pendingUpdates.size === 0) return;

    pendingUpdates.forEach((points, sensorId) => {
      let data = sensorData.get(sensorId) || [];
      // Append new points (already in order from server)
      data.push(...points);
      // Trim from start efficiently using slice instead of shift loop
      if (data.length > MAX_DATA_POINTS) {
        data = data.slice(data.length - MAX_DATA_POINTS);
      }
      sensorData.set(sensorId, data);
    });

    pendingUpdates.clear();
  }

  function rafLoop(timestamp: number) {
    // Throttle updates to UPDATE_INTERVAL_MS
    if (timestamp - lastUpdateTime >= UPDATE_INTERVAL_MS) {
      processPendingUpdates();
      updateChart();
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
      color: sensorColors.get(sensorId) || '#00ff00',
      lineWidth: 1,
      marker: { enabled: false },
      animation: false,
      states: {
        hover: {
          lineWidth: 1.5
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
            color: '#4ade80',
            fontSize: '9px'
          },
          format: '{value:%H:%M:%S}'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(74, 222, 128, 0.15)',
        minorGridLineWidth: 0,
        lineColor: 'rgba(74, 222, 128, 0.3)',
        tickColor: 'rgba(74, 222, 128, 0.3)'
      },
      yAxis: {
        title: {
          text: 'mV',
          style: {
            color: '#4ade80',
            fontSize: '10px'
          },
          margin: 5
        },
        labels: {
          style: {
            color: '#4ade80',
            fontSize: '9px'
          },
          format: '{value:.1f}'
        },
        gridLineWidth: 1,
        gridLineColor: 'rgba(74, 222, 128, 0.15)',
        minorGridLineWidth: 0,
        minPadding: 0.05,
        maxPadding: 0.05
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
        borderColor: 'rgba(74, 222, 128, 0.5)',
        borderWidth: 1,
        style: {
          color: '#4ade80',
          fontSize: '11px'
        },
        xDateFormat: '%H:%M:%S.%L',
        valueDecimals: 3,
        valueSuffix: ' mV',
        shared: true
      },
      plotOptions: {
        line: {
          animation: false,
          enableMouseTracking: false,
          lineWidth: 1
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
    // Binary search for cutoff point since data is sorted by time
    let start = 0;
    let end = data.length;
    while (start < end) {
      const mid = (start + end) >> 1;
      if (data[mid].x < cutoff) {
        start = mid + 1;
      } else {
        end = mid;
      }
    }
    // Single pass: slice and transform
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
          lineWidth: 1,
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

  onMount(() => {
    initializeSensorData();

    setTimeout(() => {
      createChart();
      // Start the animation loop after chart is created
      rafId = requestAnimationFrame(rafLoop);
    }, 100);

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

    window.addEventListener(
      "composite-measurement-event",
      handleCompositeMeasurement as EventListener
    );

    window.addEventListener(
      "accumulator-data-event",
      handleAccumulatorEvent as EventListener
    );

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
      <h2>ECG Overview</h2>
      <span class="sensor-count">{sensors.length} sensors</span>
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
  <div class="chart-wrapper" bind:this={chartContainer}></div>
</div>

<style>
  .composite-chart-container {
    background: #0a0f14;
    border-radius: 0.5rem;
    border: 1px solid rgba(74, 222, 128, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: 260px;
    box-shadow:
      0 0 20px rgba(0, 255, 0, 0.05),
      inset 0 0 60px rgba(0, 0, 0, 0.5);
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 0.25rem;
    padding: 0.25rem 0.5rem;
    background: rgba(74, 222, 128, 0.05);
    border-radius: 0.25rem;
    border: 1px solid rgba(74, 222, 128, 0.2);
  }

  .header-left {
    display: flex;
    align-items: center;
    gap: 0.75rem;
  }

  .chart-header h2 {
    font-size: 0.75rem;
    font-weight: 600;
    color: #4ade80;
    margin: 0;
    font-family: monospace;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .sensor-count {
    font-size: 0.65rem;
    color: #4ade80;
    font-family: monospace;
    opacity: 0.7;
  }

  .time-window-selector {
    display: flex;
    gap: 0.25rem;
  }

  .time-btn {
    padding: 0.25rem 0.5rem;
    font-size: 0.75rem;
    font-family: monospace;
    background: rgba(74, 222, 128, 0.1);
    border: 1px solid rgba(74, 222, 128, 0.3);
    border-radius: 0.25rem;
    color: #9ca3af;
    cursor: pointer;
    transition: all 0.15s ease;
  }

  .time-btn:hover {
    background: rgba(74, 222, 128, 0.2);
    color: #4ade80;
  }

  .time-btn.active {
    background: rgba(74, 222, 128, 0.3);
    border-color: #4ade80;
    color: #4ade80;
    box-shadow: 0 0 8px rgba(74, 222, 128, 0.3);
  }

  .chart-wrapper {
    height: calc(100% - 2.5rem);
    min-height: 200px;
    background:
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 19px,
        rgba(74, 222, 128, 0.03) 19px,
        rgba(74, 222, 128, 0.03) 20px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 19px,
        rgba(74, 222, 128, 0.03) 19px,
        rgba(74, 222, 128, 0.03) 20px
      ),
      repeating-linear-gradient(
        0deg,
        transparent,
        transparent 99px,
        rgba(74, 222, 128, 0.08) 99px,
        rgba(74, 222, 128, 0.08) 100px
      ),
      repeating-linear-gradient(
        90deg,
        transparent,
        transparent 99px,
        rgba(74, 222, 128, 0.08) 99px,
        rgba(74, 222, 128, 0.08) 100px
      );
    border-radius: 0.25rem;
  }
</style>

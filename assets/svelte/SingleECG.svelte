<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Highcharts from "highcharts";

  // Props - can be passed from parent or set via attributes on the custom element
  let {
    sensor_id = "",
    attribute_id = "ecg",
    color = "#00ff00",
    title = "",
    showHeader = true,
    minHeight = "260px"
  }: {
    sensor_id: string;
    attribute_id?: string;
    color?: string;
    title?: string;
    showHeader?: boolean;
    minHeight?: string;
  } = $props();

  let chartContainer: HTMLDivElement;
  let chart: Highcharts.Chart | null = null;

  const MAX_DATA_POINTS = 5000;
  const UPDATE_INTERVAL_MS = 100;

  // Time window options in milliseconds
  const TIME_WINDOWS = [
    { label: '10s', ms: 10 * 1000 },
    { label: '2min', ms: 2 * 60 * 1000 },
    { label: '10min', ms: 10 * 60 * 1000 }
  ];

  let selectedWindowMs = $state(TIME_WINDOWS[0].ms);
  let dataPoints: Array<{ x: number; y: number }> = [];
  let pendingUpdates: Array<{ x: number; y: number }> = [];
  let rafId: number | null = null;
  let lastUpdateTime = 0;

  function addDataPoint(value: number, timestamp?: number) {
    pendingUpdates.push({ x: timestamp || Date.now(), y: value });
  }

  function processPendingUpdates() {
    if (pendingUpdates.length === 0) return;

    // Append new points - data arrives in order from server
    dataPoints.push(...pendingUpdates);

    // Trim from start efficiently using slice
    if (dataPoints.length > MAX_DATA_POINTS) {
      dataPoints = dataPoints.slice(dataPoints.length - MAX_DATA_POINTS);
    }

    pendingUpdates = [];
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
        enabled: false
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
        valueSuffix: ' mV'
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
      series: [{
        type: 'line' as const,
        name: 'ECG',
        data: [],
        color: color,
        lineWidth: 1.5,
        marker: { enabled: false },
        animation: false
      }]
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
    if (!chart || !chart.series[0]) return;

    const now = Date.now();
    const cutoff = now - selectedWindowMs;
    const filteredData = getFilteredData(dataPoints, cutoff);

    chart.series[0].setData(filteredData, false, false, false);
    chart.xAxis[0].setExtremes(now - selectedWindowMs, now, false);
    chart.redraw(false);
  }

  function setTimeWindow(ms: number) {
    selectedWindowMs = ms;
    updateChart();
  }

  onMount(() => {
    setTimeout(() => {
      createChart();
      rafId = requestAnimationFrame(rafLoop);
    }, 100);

    // Handle real-time measurement events (from composite view)
    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id: eventSensorId, attribute_id: eventAttrId, payload, timestamp } = e.detail;

      // Only process events for this sensor and attribute
      if (eventSensorId === sensor_id && eventAttrId === attribute_id) {
        const value = typeof payload === "number" ? payload : null;
        if (value !== null) {
          addDataPoint(value, timestamp);
        }
      }
    };

    // Handle accumulator/batch events
    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const eventAttrId = e?.detail?.attribute_id;

      // Only process events for this sensor and attribute
      if (eventSensorId === sensor_id && eventAttrId === attribute_id) {
        const data = e?.detail?.data;

        if (Array.isArray(data) && data.length > 0) {
          data.forEach((measurement: any) => {
            const value = measurement?.payload;
            const timestamp = measurement?.timestamp;
            if (typeof value === "number") {
              addDataPoint(value, timestamp);
            }
          });
        } else if (data?.payload !== undefined) {
          const value = data.payload;
          if (typeof value === "number") {
            addDataPoint(value, data.timestamp);
          }
        }
      }
    };

    // Handle storage worker events (historical data)
    const handleStorageWorkerEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const eventAttrId = e?.detail?.attribute_id;

      if (eventSensorId === sensor_id && eventAttrId === attribute_id) {
        const data = e?.detail?.data;
        if (Array.isArray(data)) {
          data.forEach((measurement: any) => {
            const value = measurement?.payload;
            const timestamp = measurement?.timestamp;
            if (typeof value === "number") {
              addDataPoint(value, timestamp);
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

    window.addEventListener(
      "storage-worker-event",
      handleStorageWorkerEvent as EventListener
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
      window.removeEventListener(
        "storage-worker-event",
        handleStorageWorkerEvent as EventListener
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

<div class="single-ecg-container" style="--min-height: {minHeight}">
  {#if showHeader}
    <div class="chart-header">
      <div class="header-left">
        <h2>{title || 'ECG Waveform'}</h2>
        {#if sensor_id}
          <span class="sensor-id">{sensor_id.length > 12 ? sensor_id.slice(-8) : sensor_id}</span>
        {/if}
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
  {/if}
  <div class="chart-wrapper" bind:this={chartContainer}></div>
</div>

<style>
  .single-ecg-container {
    background: #0a0f14;
    border-radius: 0.5rem;
    border: 1px solid rgba(74, 222, 128, 0.3);
    padding: 0.5rem;
    height: 100%;
    min-height: var(--min-height, 260px);
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

  .sensor-id {
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

  /* When no header, chart-wrapper takes full height */
  .single-ecg-container:not(:has(.chart-header)) .chart-wrapper {
    height: 100%;
  }
</style>

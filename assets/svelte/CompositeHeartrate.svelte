<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Chart from "chart.js/auto";
  import "chartjs-adapter-date-fns";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; bpm: number }>;
  } = $props();

  let canvas: HTMLCanvasElement;
  let chart: Chart | null = null;

  const COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#0ea5e9', '#6366f1', '#a855f7', '#ec4899', '#f43f5e',
    '#84cc16', '#06b6d4', '#8b5cf6', '#d946ef', '#fb7185'
  ];

  const MAX_DATA_POINTS = 60;

  let sensorData: Map<string, Array<{ timestamp: number; value: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();

  function initializeSensorData() {
    sensors.forEach((sensor, index) => {
      if (!sensorData.has(sensor.sensor_id)) {
        sensorData.set(sensor.sensor_id, []);
        sensorColors.set(sensor.sensor_id, COLORS[index % COLORS.length]);
      }
      if (sensor.bpm > 0) {
        addDataPoint(sensor.sensor_id, sensor.bpm);
      }
    });
  }

  function addDataPoint(sensorId: string, value: number) {
    const data = sensorData.get(sensorId) || [];
    data.push({ timestamp: Date.now(), value });
    if (data.length > MAX_DATA_POINTS) {
      data.shift();
    }
    sensorData.set(sensorId, data);
  }

  function createChart() {
    if (!canvas) return;
    if (chart) {
      chart.destroy();
    }

    const datasets = Array.from(sensorData.entries()).map(([sensorId, data]) => ({
      label: sensorId,
      data: data.map(d => ({ x: d.timestamp, y: d.value })),
      borderColor: sensorColors.get(sensorId) || '#ffffff',
      backgroundColor: 'transparent',
      borderWidth: 2,
      pointRadius: 0,
      tension: 0.3,
      fill: false
    }));

    chart = new Chart(canvas, {
      type: 'line',
      data: { datasets },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        animation: { duration: 0 },
        interaction: {
          mode: 'nearest',
          axis: 'x',
          intersect: false
        },
        scales: {
          x: {
            type: 'time',
            time: {
              unit: 'second',
              displayFormats: { second: 'HH:mm:ss' }
            },
            display: true,
            title: { display: true, text: 'Time', color: '#9ca3af' },
            ticks: { color: '#9ca3af' },
            grid: { color: 'rgba(75, 85, 99, 0.3)' }
          },
          y: {
            display: true,
            title: { display: true, text: 'BPM', color: '#9ca3af' },
            suggestedMin: 40,
            suggestedMax: 120,
            ticks: { color: '#9ca3af' },
            grid: { color: 'rgba(75, 85, 99, 0.3)' }
          }
        },
        plugins: {
          legend: {
            display: true,
            position: 'bottom',
            labels: {
              color: '#9ca3af',
              usePointStyle: true,
              padding: 15
            }
          },
          tooltip: {
            backgroundColor: 'rgba(17, 24, 39, 0.9)',
            titleColor: '#ffffff',
            bodyColor: '#9ca3af',
            borderColor: 'rgba(75, 85, 99, 0.5)',
            borderWidth: 1,
            callbacks: {
              label: (context) => `${context.dataset.label}: ${context.parsed.y.toFixed(1)} BPM`
            }
          }
        }
      }
    });
  }

  function updateChart() {
    if (!chart) return;

    chart.data.datasets = Array.from(sensorData.entries()).map(([sensorId, data]) => ({
      label: sensorId,
      data: data.map(d => ({ x: d.timestamp, y: d.value })),
      borderColor: sensorColors.get(sensorId) || '#ffffff',
      backgroundColor: 'transparent',
      borderWidth: 2,
      pointRadius: 0,
      tension: 0.3,
      fill: false
    }));

    chart.update('none');
  }

  onMount(() => {
    initializeSensorData();

    setTimeout(() => {
      createChart();
    }, 100);

    // Handler for composite measurement events from server via hook
    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload, timestamp } = e.detail;

      if (attribute_id === "heartrate" || attribute_id === "hr") {
        const value = typeof payload === "number" ? payload : null;

        if (value !== null && value > 0) {
          if (!sensorData.has(sensor_id)) {
            const index = sensorData.size;
            sensorColors.set(sensor_id, COLORS[index % COLORS.length]);
            sensorData.set(sensor_id, []);
          }
          addDataPoint(sensor_id, value);
          updateChart();
        }
      }
    };

    // Handler for accumulator events (legacy, from sensor tiles)
    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;

      if (attributeId === "heartrate" || attributeId === "hr") {
        const data = e?.detail?.data;
        let value: number | null = null;

        if (Array.isArray(data) && data.length > 0) {
          const lastMeasurement = data[data.length - 1];
          value = lastMeasurement?.payload;
        } else if (data?.payload !== undefined) {
          value = data.payload;
        }

        if (typeof value === "number" && value > 0) {
          if (!sensorData.has(eventSensorId)) {
            const index = sensorData.size;
            sensorColors.set(eventSensorId, COLORS[index % COLORS.length]);
            sensorData.set(eventSensorId, []);
          }
          addDataPoint(eventSensorId, value);
          updateChart();
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
    if (chart) {
      chart.destroy();
    }
  });
</script>

<div class="composite-chart-container">
  <div class="chart-header">
    <h2>Heartrate Overview</h2>
    <span class="sensor-count">{sensors.length} sensors</span>
  </div>
  <div class="chart-wrapper">
    <canvas bind:this={canvas}></canvas>
  </div>
</div>

<style>
  .composite-chart-container {
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    padding: 1rem;
    height: 100%;
    min-height: 400px;
  }

  .chart-header {
    display: flex;
    justify-content: space-between;
    align-items: center;
    margin-bottom: 1rem;
    padding-bottom: 0.75rem;
    border-bottom: 1px solid rgba(75, 85, 99, 0.5);
  }

  .chart-header h2 {
    font-size: 1rem;
    font-weight: 600;
    color: #ffffff;
    margin: 0;
  }

  .sensor-count {
    font-size: 0.75rem;
    color: #9ca3af;
  }

  .chart-wrapper {
    height: calc(100% - 3rem);
    min-height: 320px;
  }

  .chart-wrapper canvas {
    width: 100% !important;
    height: 100% !important;
  }
</style>

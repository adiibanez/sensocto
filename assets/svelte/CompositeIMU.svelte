<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Chart from "chart.js/auto";
  import "chartjs-adapter-date-fns";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; orientation: any }>;
  } = $props();

  let canvas: HTMLCanvasElement;
  let chart: Chart | null = null;

  const COLORS = [
    '#ef4444', '#f97316', '#eab308', '#22c55e', '#14b8a6',
    '#0ea5e9', '#6366f1', '#a855f7', '#ec4899', '#f43f5e',
    '#84cc16', '#06b6d4', '#8b5cf6', '#d946ef', '#fb7185'
  ];

  const MAX_DATA_POINTS = 60;

  type AxisData = { timestamp: number; x: number; y: number; z: number };
  let sensorData: Map<string, Array<AxisData>> = new Map();
  let sensorColors: Map<string, { x: string; y: string; z: string }> = new Map();

  function getColorVariants(baseColor: string): { x: string; y: string; z: string } {
    return {
      x: baseColor,
      y: adjustBrightness(baseColor, 0.7),
      z: adjustBrightness(baseColor, 0.4)
    };
  }

  function adjustBrightness(hex: string, factor: number): string {
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    const nr = Math.round(r + (255 - r) * (1 - factor));
    const ng = Math.round(g + (255 - g) * (1 - factor));
    const nb = Math.round(b + (255 - b) * (1 - factor));
    return `#${nr.toString(16).padStart(2, '0')}${ng.toString(16).padStart(2, '0')}${nb.toString(16).padStart(2, '0')}`;
  }

  function initializeSensorData() {
    sensors.forEach((sensor, index) => {
      if (!sensorData.has(sensor.sensor_id)) {
        sensorData.set(sensor.sensor_id, []);
        sensorColors.set(sensor.sensor_id, getColorVariants(COLORS[index % COLORS.length]));
      }
      if (sensor.orientation && typeof sensor.orientation === 'object') {
        addDataPoint(sensor.sensor_id, sensor.orientation);
      }
    });
  }

  function addDataPoint(sensorId: string, orientation: any) {
    const data = sensorData.get(sensorId) || [];
    let x = 0, y = 0, z = 0;

    if ('x' in orientation && 'y' in orientation && 'z' in orientation) {
      x = orientation.x || 0;
      y = orientation.y || 0;
      z = orientation.z || 0;
    } else if ('alpha' in orientation || 'beta' in orientation || 'gamma' in orientation) {
      x = orientation.alpha || 0;
      y = orientation.beta || 0;
      z = orientation.gamma || 0;
    }

    data.push({ timestamp: Date.now(), x, y, z });
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

    const datasets: any[] = [];

    Array.from(sensorData.entries()).forEach(([sensorId, data]) => {
      const colors = sensorColors.get(sensorId)!;
      datasets.push(
        {
          label: `${sensorId} (X)`,
          data: data.map(d => ({ x: d.timestamp, y: d.x })),
          borderColor: colors.x,
          backgroundColor: 'transparent',
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
          fill: false
        },
        {
          label: `${sensorId} (Y)`,
          data: data.map(d => ({ x: d.timestamp, y: d.y })),
          borderColor: colors.y,
          backgroundColor: 'transparent',
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
          borderDash: [5, 5],
          fill: false
        },
        {
          label: `${sensorId} (Z)`,
          data: data.map(d => ({ x: d.timestamp, y: d.z })),
          borderColor: colors.z,
          backgroundColor: 'transparent',
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
          borderDash: [2, 2],
          fill: false
        }
      );
    });

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
            title: { display: true, text: 'Orientation (degrees)', color: '#9ca3af' },
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
              padding: 10,
              font: { size: 10 }
            }
          },
          tooltip: {
            backgroundColor: 'rgba(17, 24, 39, 0.9)',
            titleColor: '#ffffff',
            bodyColor: '#9ca3af',
            borderColor: 'rgba(75, 85, 99, 0.5)',
            borderWidth: 1,
            callbacks: {
              label: (context) => `${context.dataset.label}: ${context.parsed.y.toFixed(2)}°`
            }
          }
        }
      }
    });
  }

  function updateChart() {
    if (!chart) return;

    const datasets: any[] = [];

    Array.from(sensorData.entries()).forEach(([sensorId, data]) => {
      const colors = sensorColors.get(sensorId)!;
      datasets.push(
        {
          label: `${sensorId} (X)`,
          data: data.map(d => ({ x: d.timestamp, y: d.x })),
          borderColor: colors.x,
          backgroundColor: 'transparent',
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
          fill: false
        },
        {
          label: `${sensorId} (Y)`,
          data: data.map(d => ({ x: d.timestamp, y: d.y })),
          borderColor: colors.y,
          backgroundColor: 'transparent',
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
          borderDash: [5, 5],
          fill: false
        },
        {
          label: `${sensorId} (Z)`,
          data: data.map(d => ({ x: d.timestamp, y: d.z })),
          borderColor: colors.z,
          backgroundColor: 'transparent',
          borderWidth: 2,
          pointRadius: 0,
          tension: 0.3,
          borderDash: [2, 2],
          fill: false
        }
      );
    });

    chart.data.datasets = datasets;
    chart.update('none');
  }

  onMount(() => {
    initializeSensorData();

    setTimeout(() => {
      createChart();
    }, 100);

    // Handler for composite measurement events from server via hook
    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload } = e.detail;

      if (attribute_id === "imu") {
        const orientation = payload;

        if (orientation && typeof orientation === 'object') {
          if (!sensorData.has(sensor_id)) {
            const index = sensorData.size;
            sensorColors.set(sensor_id, getColorVariants(COLORS[index % COLORS.length]));
            sensorData.set(sensor_id, []);
          }
          addDataPoint(sensor_id, orientation);
          updateChart();
        }
      }
    };

    // Handler for accumulator events (legacy, from sensor tiles)
    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;

      if (attributeId === "imu") {
        const data = e?.detail?.data;
        let orientation: any = null;

        if (Array.isArray(data) && data.length > 0) {
          const lastMeasurement = data[data.length - 1];
          orientation = lastMeasurement?.payload;
        } else if (data?.payload !== undefined) {
          orientation = data.payload;
        }

        if (orientation && typeof orientation === 'object') {
          if (!sensorData.has(eventSensorId)) {
            const index = sensorData.size;
            sensorColors.set(eventSensorId, getColorVariants(COLORS[index % COLORS.length]));
            sensorData.set(eventSensorId, []);
          }
          addDataPoint(eventSensorId, orientation);
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
    <h2>IMU Orientation Overview</h2>
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

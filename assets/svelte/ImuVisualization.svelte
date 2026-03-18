<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Chart from "chart.js/auto";
  import "chartjs-adapter-date-fns";

  export let identifier: string = "";
  export let sensorId: string = "";
  export let attributeId: string = "imu";

  let accelCanvas: HTMLCanvasElement;
  let gyroCanvas: HTMLCanvasElement;
  let accelChart: Chart | null = null;
  let gyroChart: Chart | null = null;

  const MAX_DATA_POINTS = 120;

  type Sample = { timestamp: number; ax: number; ay: number; az: number; rx: number; ry: number; rz: number; pitch: number; roll: number; yaw: number; heading: number };
  let samples: Sample[] = [];

  let currentValues: Sample = { timestamp: 0, ax: 0, ay: 0, az: 0, rx: 0, ry: 0, rz: 0, pitch: 0, roll: 0, yaw: 0, heading: 0 };

  function parsePayload(payload: any): Sample | null {
    const ts = Date.now();

    if (typeof payload === "string" && payload.includes(",")) {
      const tokens = payload.split(",").map(Number);
      if (tokens.length >= 7) {
        return {
          timestamp: ts,
          ax: tokens[1] || 0, ay: tokens[2] || 0, az: tokens[3] || 0,
          rx: tokens[4] || 0, ry: tokens[5] || 0, rz: tokens[6] || 0,
          pitch: 0, roll: 0, yaw: 0, heading: 0
        };
      }
    }

    if (payload && typeof payload === "object") {
      if ("accelerometer" in payload && "gyroscope" in payload) {
        const a = payload.accelerometer || {};
        const g = payload.gyroscope || {};
        return {
          timestamp: ts,
          ax: a.x || 0, ay: a.y || 0, az: a.z || 0,
          rx: g.x || 0, ry: g.y || 0, rz: g.z || 0,
          pitch: payload.pitch || 0, roll: payload.roll || 0, yaw: payload.yaw || 0,
          heading: payload.heading || 0
        };
      }

      if ("acc" in payload && "gyro" in payload) {
        const a = payload.acc || {};
        const g = payload.gyro || {};
        return {
          timestamp: ts,
          ax: a.x || 0, ay: a.y || 0, az: a.z || 0,
          rx: g.x || 0, ry: g.y || 0, rz: g.z || 0,
          pitch: payload.pitch || 0, roll: payload.roll || 0, yaw: payload.yaw || 0,
          heading: payload.heading || 0
        };
      }

      if ("x" in payload && "y" in payload && "z" in payload) {
        return {
          timestamp: ts,
          ax: payload.x || 0, ay: payload.y || 0, az: payload.z || 0,
          rx: 0, ry: 0, rz: 0,
          pitch: payload.pitch || 0, roll: payload.roll || 0, yaw: payload.yaw || 0,
          heading: payload.heading || 0
        };
      }

      if ("roll" in payload || "pitch" in payload || "yaw" in payload) {
        return {
          timestamp: ts,
          ax: 0, ay: 0, az: 0,
          rx: 0, ry: 0, rz: 0,
          pitch: payload.pitch || 0, roll: payload.roll || 0, yaw: payload.yaw || 0,
          heading: payload.heading || 0
        };
      }

      if ("alpha" in payload || "beta" in payload || "gamma" in payload) {
        return {
          timestamp: ts,
          ax: 0, ay: 0, az: 0,
          rx: 0, ry: 0, rz: 0,
          pitch: payload.beta || 0, roll: payload.gamma || 0, yaw: payload.alpha || 0,
          heading: payload.alpha || 0
        };
      }
    }

    return null;
  }

  function addSample(sample: Sample) {
    samples.push(sample);
    if (samples.length > MAX_DATA_POINTS) samples.shift();
    currentValues = sample;
  }

  function createCharts() {
    if (accelCanvas) {
      accelChart = new Chart(accelCanvas, {
        type: "line",
        data: {
          datasets: [
            { label: "X", data: [], borderColor: "#ef4444", borderWidth: 1.5, pointRadius: 0, tension: 0.3, fill: false },
            { label: "Y", data: [], borderColor: "#22c55e", borderWidth: 1.5, pointRadius: 0, tension: 0.3, fill: false },
            { label: "Z", data: [], borderColor: "#3b82f6", borderWidth: 1.5, pointRadius: 0, tension: 0.3, fill: false }
          ]
        },
        options: chartOptions("Acceleration (m/s²)")
      });
    }

    if (gyroCanvas) {
      gyroChart = new Chart(gyroCanvas, {
        type: "line",
        data: {
          datasets: [
            { label: "X", data: [], borderColor: "#f97316", borderWidth: 1.5, pointRadius: 0, tension: 0.3, fill: false },
            { label: "Y", data: [], borderColor: "#a855f7", borderWidth: 1.5, pointRadius: 0, tension: 0.3, fill: false },
            { label: "Z", data: [], borderColor: "#06b6d4", borderWidth: 1.5, pointRadius: 0, tension: 0.3, fill: false }
          ]
        },
        options: chartOptions("Gyroscope (°/s)")
      });
    }
  }

  function chartOptions(yLabel: string): any {
    return {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 0 },
      interaction: { mode: "nearest", axis: "x", intersect: false },
      scales: {
        x: {
          type: "time",
          time: { unit: "second", displayFormats: { second: "HH:mm:ss" } },
          display: true,
          ticks: { color: "#6b7280", maxTicksLimit: 5 },
          grid: { color: "rgba(75, 85, 99, 0.2)" }
        },
        y: {
          display: true,
          title: { display: true, text: yLabel, color: "#9ca3af", font: { size: 11 } },
          ticks: { color: "#6b7280" },
          grid: { color: "rgba(75, 85, 99, 0.2)" }
        }
      },
      plugins: {
        legend: {
          display: true,
          position: "bottom",
          labels: { color: "#9ca3af", usePointStyle: true, padding: 8, font: { size: 10 } }
        },
        tooltip: {
          backgroundColor: "rgba(17, 24, 39, 0.9)",
          titleColor: "#fff",
          bodyColor: "#9ca3af",
          borderColor: "rgba(75, 85, 99, 0.5)",
          borderWidth: 1
        }
      }
    };
  }

  function updateCharts() {
    if (accelChart) {
      accelChart.data.datasets[0].data = samples.map(s => ({ x: s.timestamp, y: s.ax }));
      accelChart.data.datasets[1].data = samples.map(s => ({ x: s.timestamp, y: s.ay }));
      accelChart.data.datasets[2].data = samples.map(s => ({ x: s.timestamp, y: s.az }));
      accelChart.update("none");
    }
    if (gyroChart) {
      gyroChart.data.datasets[0].data = samples.map(s => ({ x: s.timestamp, y: s.rx }));
      gyroChart.data.datasets[1].data = samples.map(s => ({ x: s.timestamp, y: s.ry }));
      gyroChart.data.datasets[2].data = samples.map(s => ({ x: s.timestamp, y: s.rz }));
      gyroChart.update("none");
    }
  }

  let listeners: Array<() => void> = [];

  onMount(() => {
    setTimeout(() => createCharts(), 100);

    const handleComposite = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload } = e.detail;
      if (sensor_id === sensorId && attribute_id === attributeId) {
        const sample = parsePayload(payload);
        if (sample) {
          addSample(sample);
          updateCharts();
        }
      }
    };

    const handleAccumulator = (e: CustomEvent) => {
      const { sensor_id, attribute_id, data } = e.detail;
      if (sensor_id === sensorId && attribute_id === attributeId) {
        let payload: any = null;
        if (Array.isArray(data) && data.length > 0) {
          payload = data[data.length - 1]?.payload;
        } else if (data?.payload !== undefined) {
          payload = data.payload;
        }
        if (payload) {
          const sample = parsePayload(payload);
          if (sample) {
            addSample(sample);
            updateCharts();
          }
        }
      }
    };

    window.addEventListener("composite-measurement-event", handleComposite as EventListener);
    window.addEventListener("accumulator-data-event", handleAccumulator as EventListener);

    listeners = [
      () => window.removeEventListener("composite-measurement-event", handleComposite as EventListener),
      () => window.removeEventListener("accumulator-data-event", handleAccumulator as EventListener)
    ];
  });

  onDestroy(() => {
    listeners.forEach(fn => fn());
    if (accelChart) accelChart.destroy();
    if (gyroChart) gyroChart.destroy();
  });

  function fmt(v: number): string {
    return v.toFixed(2);
  }

  function accelMag(): number {
    return Math.sqrt(currentValues.ax ** 2 + currentValues.ay ** 2 + currentValues.az ** 2);
  }
</script>

<div class="imu-viz" id={identifier}>
  <div class="imu-grid">
    <div class="chart-panel">
      <canvas bind:this={accelCanvas}></canvas>
    </div>
    <div class="chart-panel">
      <canvas bind:this={gyroCanvas}></canvas>
    </div>
  </div>

  <div class="values-panel">
    <div class="value-group">
      <span class="group-label">Accel</span>
      <span class="val" style="color: #ef4444">X {fmt(currentValues.ax)}</span>
      <span class="val" style="color: #22c55e">Y {fmt(currentValues.ay)}</span>
      <span class="val" style="color: #3b82f6">Z {fmt(currentValues.az)}</span>
      <span class="val mag">|a| {fmt(accelMag())} m/s²</span>
    </div>
    <div class="value-group">
      <span class="group-label">Gyro</span>
      <span class="val" style="color: #f97316">X {fmt(currentValues.rx)}</span>
      <span class="val" style="color: #a855f7">Y {fmt(currentValues.ry)}</span>
      <span class="val" style="color: #06b6d4">Z {fmt(currentValues.rz)}</span>
    </div>
    <div class="value-group">
      <span class="group-label">Orient</span>
      <span class="val">P {fmt(currentValues.pitch)}°</span>
      <span class="val">R {fmt(currentValues.roll)}°</span>
      <span class="val">Y {fmt(currentValues.yaw)}°</span>
    </div>
  </div>
</div>

<style>
  .imu-viz {
    display: flex;
    flex-direction: column;
    height: 100%;
    gap: 0.5rem;
    background: rgba(31, 41, 55, 0.5);
    border-radius: 0.5rem;
    padding: 0.75rem;
  }

  .imu-grid {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 0.5rem;
    flex: 1;
    min-height: 0;
  }

  .chart-panel {
    position: relative;
    min-height: 140px;
  }

  .chart-panel canvas {
    width: 100% !important;
    height: 100% !important;
  }

  .values-panel {
    display: flex;
    gap: 1rem;
    justify-content: center;
    flex-wrap: wrap;
    padding: 0.5rem;
    background: rgba(17, 24, 39, 0.5);
    border-radius: 0.375rem;
  }

  .value-group {
    display: flex;
    align-items: center;
    gap: 0.5rem;
    font-size: 0.7rem;
    font-family: monospace;
  }

  .group-label {
    color: #9ca3af;
    font-weight: 600;
    text-transform: uppercase;
    font-size: 0.6rem;
    min-width: 2.5rem;
  }

  .val {
    color: #d1d5db;
  }

  .mag {
    color: #fbbf24;
    font-weight: 600;
  }
</style>

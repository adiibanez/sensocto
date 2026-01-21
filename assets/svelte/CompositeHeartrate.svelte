<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors: initialSensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; bpm: number }>;
  } = $props();

  // Local state for realtime updates - starts with initial props
  let sensorsState = $state<Array<{ sensor_id: string; sensor_name?: string; bpm: number }>>(initialSensors);

  // Update local state when props change (e.g., on initial load or reconnect)
  $effect(() => {
    if (initialSensors.length > 0) {
      sensorsState = [...initialSensors];
    }
  });

  // Compute stats from current sensor data
  const validSensors = $derived(sensorsState.filter(s => s.bpm > 0));
  const avgBpm = $derived(
    validSensors.length > 0
      ? Math.round(validSensors.reduce((sum, s) => sum + s.bpm, 0) / validSensors.length)
      : 0
  );
  const minBpm = $derived(
    validSensors.length > 0
      ? Math.min(...validSensors.map(s => s.bpm))
      : 0
  );
  const maxBpm = $derived(
    validSensors.length > 0
      ? Math.max(...validSensors.map(s => s.bpm))
      : 0
  );

  // Heart rate zones for color coding
  function getBpmColor(bpm: number): string {
    if (bpm <= 0) return '#6b7280'; // gray for no data
    if (bpm < 60) return '#3b82f6'; // blue - bradycardia
    if (bpm < 100) return '#22c55e'; // green - normal
    if (bpm < 120) return '#eab308'; // yellow - elevated
    return '#ef4444'; // red - high
  }

  function getBpmZone(bpm: number): string {
    if (bpm <= 0) return 'No data';
    if (bpm < 60) return 'Low';
    if (bpm < 100) return 'Normal';
    if (bpm < 120) return 'Elevated';
    return 'High';
  }

  // Sort sensors by BPM descending (highest first) for attention
  const sortedSensors = $derived(
    [...sensorsState].sort((a, b) => b.bpm - a.bpm)
  );

  function getDisplayName(sensor: { sensor_id: string; sensor_name?: string }): string {
    return sensor.sensor_name || sensor.sensor_id.substring(0, 12);
  }

  // Handle realtime composite measurement events
  function handleCompositeMeasurement(event: CustomEvent) {
    const { sensor_id, attribute_id, payload } = event.detail;
    console.log("[CompositeHeartrate] Received event:", { sensor_id, attribute_id, payload });

    // Only handle heartrate attribute (note: "heartrate" not "heart_rate")
    if (attribute_id !== "heartrate") return;
    console.log("[CompositeHeartrate] Processing heartrate for:", sensor_id);

    // Parse BPM from payload
    let bpm = 0;
    try {
      const data = typeof payload === "string" ? JSON.parse(payload) : payload;
      bpm = data?.bpm ?? data?.heartRate ?? data ?? 0;
      if (typeof bpm !== "number") bpm = 0;
    } catch {
      return;
    }

    // Update or add sensor in state
    const existingIndex = sensorsState.findIndex(s => s.sensor_id === sensor_id);
    if (existingIndex >= 0) {
      // Update existing sensor
      sensorsState[existingIndex] = { ...sensorsState[existingIndex], bpm };
      console.log("[CompositeHeartrate] Updated sensor:", sensor_id, "bpm:", bpm);
    } else {
      // Add new sensor
      sensorsState = [...sensorsState, { sensor_id, bpm }];
      console.log("[CompositeHeartrate] Added new sensor:", sensor_id, "bpm:", bpm);
    }
  }

  onMount(() => {
    console.log("[CompositeHeartrate] Component mounted, listening for composite-measurement-event");
    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
  });

  onDestroy(() => {
    window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
  });
</script>

<div class="composite-hr">
  <!-- Summary Stats Bar -->
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
      <span class="stat-unit">bpm</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-label">Max</span>
      <span class="stat-value" style="color: {getBpmColor(maxBpm)}">{maxBpm}</span>
      <span class="stat-unit">bpm</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-label">Sensors</span>
      <span class="stat-value text-white">{validSensors.length}</span>
      <span class="stat-unit">/ {sensorsState.length}</span>
    </div>
  </div>

  <!-- Compact Sensor Grid -->
  <div class="sensor-grid">
    {#each sortedSensors as sensor (sensor.sensor_id)}
      <div
        class="sensor-pill"
        style="border-color: {getBpmColor(sensor.bpm)}"
        title="{getDisplayName(sensor)}: {sensor.bpm > 0 ? sensor.bpm + ' bpm (' + getBpmZone(sensor.bpm) + ')' : 'No data'}"
      >
        <span class="sensor-name">{getDisplayName(sensor)}</span>
        <span class="sensor-bpm" style="color: {getBpmColor(sensor.bpm)}">
          {sensor.bpm > 0 ? sensor.bpm : '—'}
        </span>
      </div>
    {/each}
  </div>

  <!-- Legend -->
  <div class="legend">
    <div class="legend-item">
      <span class="legend-dot" style="background: #3b82f6"></span>
      <span>&lt;60 Low</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: #22c55e"></span>
      <span>60-99 Normal</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: #eab308"></span>
      <span>100-119 Elevated</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: #ef4444"></span>
      <span>120+ High</span>
    </div>
  </div>
</div>

<style>
  .composite-hr {
    background: rgba(31, 41, 55, 0.6);
    border-radius: 0.5rem;
    padding: 0.75rem;
  }

  .stats-bar {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 1rem;
    padding: 0.5rem 1rem;
    background: rgba(17, 24, 39, 0.5);
    border-radius: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .stat {
    display: flex;
    align-items: baseline;
    gap: 0.25rem;
  }

  .stat-label {
    font-size: 0.7rem;
    color: #9ca3af;
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  .stat-value {
    font-size: 1.25rem;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }

  .stat-unit {
    font-size: 0.65rem;
    color: #6b7280;
  }

  .stat-divider {
    width: 1px;
    height: 1.5rem;
    background: rgba(75, 85, 99, 0.5);
  }

  .sensor-grid {
    display: flex;
    flex-wrap: wrap;
    gap: 0.375rem;
    margin-bottom: 0.5rem;
  }

  .sensor-pill {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    padding: 0.25rem 0.5rem;
    background: rgba(17, 24, 39, 0.6);
    border: 1px solid;
    border-radius: 9999px;
    font-size: 0.75rem;
    transition: transform 0.1s ease;
  }

  .sensor-pill:hover {
    transform: scale(1.02);
    background: rgba(17, 24, 39, 0.8);
  }

  .sensor-name {
    color: #d1d5db;
    max-width: 80px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  .sensor-bpm {
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .legend {
    display: flex;
    justify-content: center;
    gap: 1rem;
    padding-top: 0.5rem;
    border-top: 1px solid rgba(75, 85, 99, 0.3);
  }

  .legend-item {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    font-size: 0.65rem;
    color: #9ca3af;
  }

  .legend-dot {
    width: 6px;
    height: 6px;
    border-radius: 50%;
  }

  .text-white {
    color: #ffffff;
  }
</style>

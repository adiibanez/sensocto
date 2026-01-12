<script lang="ts">
  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; sensor_name?: string; spo2: number }>;
  } = $props();

  // Compute stats from current sensor data
  const validSensors = $derived(sensors.filter(s => s.spo2 > 0));
  const avgSpo2 = $derived(
    validSensors.length > 0
      ? Math.round(validSensors.reduce((sum, s) => sum + s.spo2, 0) / validSensors.length * 10) / 10
      : 0
  );
  const minSpo2 = $derived(
    validSensors.length > 0
      ? Math.round(Math.min(...validSensors.map(s => s.spo2)) * 10) / 10
      : 0
  );
  const maxSpo2 = $derived(
    validSensors.length > 0
      ? Math.round(Math.max(...validSensors.map(s => s.spo2)) * 10) / 10
      : 0
  );

  // SpO2 zones for clinical color coding
  function getSpo2Color(spo2: number): string {
    if (spo2 <= 0) return '#6b7280'; // gray for no data
    if (spo2 < 85) return '#ef4444'; // red - severe hypoxemia
    if (spo2 < 90) return '#f97316'; // orange - moderate hypoxemia
    if (spo2 < 95) return '#eab308'; // yellow - mild hypoxemia
    return '#22c55e'; // green - normal
  }

  function getSpo2Zone(spo2: number): string {
    if (spo2 <= 0) return 'No data';
    if (spo2 < 85) return 'Severe';
    if (spo2 < 90) return 'Moderate';
    if (spo2 < 95) return 'Mild';
    return 'Normal';
  }

  function getSpo2Status(spo2: number): string {
    if (spo2 <= 0) return 'No data';
    if (spo2 < 85) return 'Critical';
    if (spo2 < 90) return 'Warning';
    if (spo2 < 95) return 'Low';
    return 'OK';
  }

  // Sort sensors by SpO2 ascending (lowest/most critical first)
  const sortedSensors = $derived(
    [...sensors].sort((a, b) => {
      // Put sensors with no data at the end
      if (a.spo2 <= 0 && b.spo2 <= 0) return 0;
      if (a.spo2 <= 0) return 1;
      if (b.spo2 <= 0) return -1;
      return a.spo2 - b.spo2;
    })
  );

  // Count sensors in each zone
  const criticalCount = $derived(validSensors.filter(s => s.spo2 < 85).length);
  const warningCount = $derived(validSensors.filter(s => s.spo2 >= 85 && s.spo2 < 90).length);
  const lowCount = $derived(validSensors.filter(s => s.spo2 >= 90 && s.spo2 < 95).length);
  const normalCount = $derived(validSensors.filter(s => s.spo2 >= 95).length);

  function getDisplayName(sensor: { sensor_id: string; sensor_name?: string }): string {
    return sensor.sensor_name || sensor.sensor_id.substring(0, 12);
  }

  function formatSpo2(value: number): string {
    return value > 0 ? value.toFixed(1) : '—';
  }
</script>

<div class="composite-spo2">
  <!-- Summary Stats Bar -->
  <div class="stats-bar">
    <div class="stat">
      <span class="stat-label">Avg</span>
      <span class="stat-value" style="color: {getSpo2Color(avgSpo2)}">{avgSpo2.toFixed(1)}</span>
      <span class="stat-unit">%</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-label">Min</span>
      <span class="stat-value" style="color: {getSpo2Color(minSpo2)}">{minSpo2.toFixed(1)}</span>
      <span class="stat-unit">%</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-label">Max</span>
      <span class="stat-value" style="color: {getSpo2Color(maxSpo2)}">{maxSpo2.toFixed(1)}</span>
      <span class="stat-unit">%</span>
    </div>
    <div class="stat-divider"></div>
    <div class="stat">
      <span class="stat-label">Sensors</span>
      <span class="stat-value text-white">{validSensors.length}</span>
      <span class="stat-unit">/ {sensors.length}</span>
    </div>
  </div>

  <!-- Zone Summary (only if there are concerning values) -->
  {#if criticalCount > 0 || warningCount > 0 || lowCount > 0}
    <div class="zone-summary">
      {#if criticalCount > 0}
        <div class="zone-badge critical">
          <span class="zone-count">{criticalCount}</span>
          <span class="zone-label">Critical</span>
        </div>
      {/if}
      {#if warningCount > 0}
        <div class="zone-badge warning">
          <span class="zone-count">{warningCount}</span>
          <span class="zone-label">Warning</span>
        </div>
      {/if}
      {#if lowCount > 0}
        <div class="zone-badge low">
          <span class="zone-count">{lowCount}</span>
          <span class="zone-label">Low</span>
        </div>
      {/if}
      {#if normalCount > 0}
        <div class="zone-badge normal">
          <span class="zone-count">{normalCount}</span>
          <span class="zone-label">Normal</span>
        </div>
      {/if}
    </div>
  {/if}

  <!-- Compact Sensor Grid -->
  <div class="sensor-grid">
    {#each sortedSensors as sensor (sensor.sensor_id)}
      <div
        class="sensor-pill"
        style="border-color: {getSpo2Color(sensor.spo2)}"
        title="{getDisplayName(sensor)}: {sensor.spo2 > 0 ? sensor.spo2.toFixed(1) + '% (' + getSpo2Zone(sensor.spo2) + ')' : 'No data'}"
      >
        <span class="sensor-name">{getDisplayName(sensor)}</span>
        <span class="sensor-value" style="color: {getSpo2Color(sensor.spo2)}">
          {formatSpo2(sensor.spo2)}
        </span>
        {#if sensor.spo2 > 0 && sensor.spo2 < 95}
          <span class="status-indicator" style="background: {getSpo2Color(sensor.spo2)}"></span>
        {/if}
      </div>
    {/each}
  </div>

  <!-- Legend -->
  <div class="legend">
    <div class="legend-item">
      <span class="legend-dot" style="background: #ef4444"></span>
      <span>&lt;85% Severe</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: #f97316"></span>
      <span>85-89% Moderate</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: #eab308"></span>
      <span>90-94% Mild</span>
    </div>
    <div class="legend-item">
      <span class="legend-dot" style="background: #22c55e"></span>
      <span>95%+ Normal</span>
    </div>
  </div>
</div>

<style>
  .composite-spo2 {
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

  .zone-summary {
    display: flex;
    justify-content: center;
    gap: 0.5rem;
    margin-bottom: 0.75rem;
  }

  .zone-badge {
    display: flex;
    align-items: center;
    gap: 0.25rem;
    padding: 0.25rem 0.5rem;
    border-radius: 9999px;
    font-size: 0.7rem;
  }

  .zone-badge.critical {
    background: rgba(239, 68, 68, 0.2);
    color: #ef4444;
  }

  .zone-badge.warning {
    background: rgba(249, 115, 22, 0.2);
    color: #f97316;
  }

  .zone-badge.low {
    background: rgba(234, 179, 8, 0.2);
    color: #eab308;
  }

  .zone-badge.normal {
    background: rgba(34, 197, 94, 0.2);
    color: #22c55e;
  }

  .zone-count {
    font-weight: 700;
  }

  .zone-label {
    font-weight: 500;
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

  .sensor-value {
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .status-indicator {
    width: 6px;
    height: 6px;
    border-radius: 50%;
    animation: pulse 2s infinite;
  }

  @keyframes pulse {
    0%, 100% {
      opacity: 1;
    }
    50% {
      opacity: 0.5;
    }
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

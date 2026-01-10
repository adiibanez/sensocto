<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; level: number; sensor_name?: string }>;
  } = $props();

  let batteryLevels: Map<string, { level: number; name: string; timestamp: number }> = $state(new Map());

  function initializeSensorData() {
    sensors.forEach((sensor) => {
      if (!batteryLevels.has(sensor.sensor_id)) {
        batteryLevels.set(sensor.sensor_id, {
          level: sensor.level || 0,
          name: sensor.sensor_name || sensor.sensor_id,
          timestamp: Date.now()
        });
      }
    });
    batteryLevels = new Map(batteryLevels);
  }

  function updateBatteryLevel(sensorId: string, level: number, name?: string) {
    const existing = batteryLevels.get(sensorId);
    batteryLevels.set(sensorId, {
      level: level,
      name: name || existing?.name || sensorId,
      timestamp: Date.now()
    });
    batteryLevels = new Map(batteryLevels);
  }

  function getBatteryColor(level: number): string {
    if (level >= 60) return '#22c55e';
    if (level >= 30) return '#eab308';
    if (level >= 15) return '#f97316';
    return '#ef4444';
  }

  function getBatteryIcon(level: number): string {
    if (level >= 75) return 'full';
    if (level >= 50) return 'three-quarters';
    if (level >= 25) return 'half';
    if (level >= 10) return 'quarter';
    return 'empty';
  }

  onMount(() => {
    initializeSensorData();

    const handleCompositeMeasurement = (e: CustomEvent) => {
      const { sensor_id, attribute_id, payload } = e.detail;

      if (attribute_id === "battery") {
        let level: number | null = null;

        if (typeof payload === "number") {
          level = payload;
        } else if (typeof payload === "object" && payload !== null) {
          level = payload.level ?? payload["level"] ?? null;
        }

        if (level !== null) {
          updateBatteryLevel(sensor_id, level);
        }
      }
    };

    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;

      if (attributeId === "battery") {
        const data = e?.detail?.data;
        let level: number | null = null;

        if (Array.isArray(data) && data.length > 0) {
          const lastMeasurement = data[data.length - 1];
          const payload = lastMeasurement?.payload;
          if (typeof payload === "number") {
            level = payload;
          } else if (typeof payload === "object" && payload !== null) {
            level = payload.level ?? payload["level"] ?? null;
          }
        } else if (data?.payload !== undefined) {
          const payload = data.payload;
          if (typeof payload === "number") {
            level = payload;
          } else if (typeof payload === "object" && payload !== null) {
            level = payload.level ?? payload["level"] ?? null;
          }
        }

        if (level !== null) {
          updateBatteryLevel(eventSensorId, level);
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

  let sortedBatteries = $derived(
    Array.from(batteryLevels.entries())
      .map(([id, data]) => ({ id, ...data }))
      .sort((a, b) => a.level - b.level)
  );
</script>

<div class="composite-battery-container">
  <div class="chart-header">
    <h2>Battery Overview</h2>
    <span class="sensor-count">{sensors.length} sensors</span>
  </div>

  <div class="battery-grid">
    {#each sortedBatteries as battery (battery.id)}
      <div class="battery-card">
        <div class="battery-info">
          <span class="battery-name" title={battery.id}>{battery.name}</span>
          <span class="battery-id">{battery.id}</span>
        </div>

        <div class="battery-visual">
          <div class="battery-icon">
            <div class="battery-body">
              <div
                class="battery-fill"
                style="width: {battery.level}%; background-color: {getBatteryColor(battery.level)};"
              ></div>
            </div>
            <div class="battery-tip"></div>
          </div>
          <span class="battery-percentage" style="color: {getBatteryColor(battery.level)};">
            {Math.round(battery.level)}%
          </span>
        </div>

        {#if battery.level < 20}
          <div class="low-battery-warning">
            <svg class="warning-icon" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M8.257 3.099c.765-1.36 2.722-1.36 3.486 0l5.58 9.92c.75 1.334-.213 2.98-1.742 2.98H4.42c-1.53 0-2.493-1.646-1.743-2.98l5.58-9.92zM11 13a1 1 0 11-2 0 1 1 0 012 0zm-1-8a1 1 0 00-1 1v3a1 1 0 002 0V6a1 1 0 00-1-1z" clip-rule="evenodd" />
            </svg>
            <span>Low Battery</span>
          </div>
        {/if}
      </div>
    {/each}
  </div>

  {#if sortedBatteries.length === 0}
    <div class="no-data">
      <p>No battery data available</p>
    </div>
  {/if}
</div>

<style>
  .composite-battery-container {
    background: rgba(31, 41, 55, 0.8);
    border-radius: 0.75rem;
    border: 1px solid rgba(75, 85, 99, 0.5);
    padding: 1rem;
    min-height: 300px;
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

  .battery-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(160px, 1fr));
    gap: 0.5rem;
  }

  .battery-card {
    background: rgba(17, 24, 39, 0.6);
    border: 1px solid rgba(75, 85, 99, 0.4);
    border-radius: 0.375rem;
    padding: 0.5rem 0.75rem;
    transition: border-color 0.2s;
  }

  .battery-card:hover {
    border-color: rgba(75, 85, 99, 0.8);
  }

  .battery-info {
    margin-bottom: 0.25rem;
  }

  .battery-name {
    display: block;
    font-size: 0.75rem;
    font-weight: 500;
    color: #ffffff;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .battery-id {
    display: block;
    font-size: 0.5rem;
    color: #6b7280;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
    margin-top: 0.0625rem;
  }

  .battery-visual {
    display: flex;
    align-items: center;
    gap: 0.5rem;
  }

  .battery-icon {
    display: flex;
    align-items: center;
  }

  .battery-body {
    width: 24px;
    height: 12px;
    border: 1.5px solid #4b5563;
    border-radius: 2px;
    padding: 1px;
    background: rgba(0, 0, 0, 0.3);
  }

  .battery-fill {
    height: 100%;
    border-radius: 1px;
    transition: width 0.3s ease, background-color 0.3s ease;
  }

  .battery-tip {
    width: 2px;
    height: 5px;
    background: #4b5563;
    border-radius: 0 1px 1px 0;
    margin-left: 1px;
  }

  .battery-percentage {
    font-size: 1rem;
    font-weight: 600;
    font-variant-numeric: tabular-nums;
  }

  .low-battery-warning {
    display: flex;
    align-items: center;
    gap: 0.375rem;
    margin-top: 0.5rem;
    padding: 0.25rem 0.5rem;
    background: rgba(239, 68, 68, 0.15);
    border-radius: 0.25rem;
    color: #ef4444;
    font-size: 0.75rem;
  }

  .warning-icon {
    width: 14px;
    height: 14px;
  }

  .no-data {
    display: flex;
    justify-content: center;
    align-items: center;
    min-height: 200px;
    color: #6b7280;
  }
</style>

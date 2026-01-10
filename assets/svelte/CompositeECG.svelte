<script lang="ts">
  import { onMount, onDestroy } from "svelte";
  import Highcharts from "highcharts";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; value: number }>;
  } = $props();

  let chartContainer: HTMLDivElement;
  let chart: Highcharts.Chart | null = null;

  const COLORS = [
    '#22c55e', '#ef4444', '#0ea5e9', '#f97316', '#a855f7',
    '#eab308', '#14b8a6', '#6366f1', '#ec4899', '#84cc16'
  ];

  const MAX_DATA_POINTS = 500;

  let sensorData: Map<string, Array<{ x: number; y: number }>> = new Map();
  let sensorColors: Map<string, string> = new Map();

  function initializeSensorData() {
    sensors.forEach((sensor, index) => {
      if (!sensorData.has(sensor.sensor_id)) {
        sensorData.set(sensor.sensor_id, []);
        sensorColors.set(sensor.sensor_id, COLORS[index % COLORS.length]);
      }
    });
  }

  function addDataPoint(sensorId: string, value: number) {
    const data = sensorData.get(sensorId) || [];
    data.push({ x: Date.now(), y: value });
    if (data.length > MAX_DATA_POINTS) {
      data.shift();
    }
    sensorData.set(sensorId, data);
  }

  function createChart() {
    if (!chartContainer) return;
    if (chart) {
      chart.destroy();
    }

    const series: Highcharts.SeriesOptionsType[] = Array.from(sensorData.entries()).map(([sensorId, data]) => ({
      type: 'line' as const,
      name: sensorId,
      data: data.map(d => [d.x, d.y]),
      color: sensorColors.get(sensorId) || '#22c55e',
      lineWidth: 1.5,
      marker: { enabled: false },
      animation: false
    }));

    chart = Highcharts.chart(chartContainer, {
      chart: {
        type: 'line',
        backgroundColor: 'rgba(31, 41, 55, 0.8)',
        animation: false,
        style: {
          fontFamily: 'inherit'
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
          text: 'Time',
          style: { color: '#9ca3af' }
        },
        labels: {
          style: { color: '#9ca3af' },
          format: '{value:%H:%M:%S}'
        },
        gridLineColor: 'rgba(75, 85, 99, 0.3)',
        lineColor: 'rgba(75, 85, 99, 0.5)'
      },
      yAxis: {
        title: {
          text: 'mV',
          style: { color: '#9ca3af' }
        },
        labels: {
          style: { color: '#9ca3af' }
        },
        gridLineColor: 'rgba(75, 85, 99, 0.3)',
        min: -1,
        max: 2
      },
      legend: {
        enabled: true,
        itemStyle: {
          color: '#9ca3af'
        },
        itemHoverStyle: {
          color: '#ffffff'
        }
      },
      tooltip: {
        backgroundColor: 'rgba(17, 24, 39, 0.9)',
        borderColor: 'rgba(75, 85, 99, 0.5)',
        style: {
          color: '#ffffff'
        },
        xDateFormat: '%H:%M:%S.%L',
        valueDecimals: 3,
        valueSuffix: ' mV'
      },
      plotOptions: {
        line: {
          animation: false,
          enableMouseTracking: true
        },
        series: {
          animation: false
        }
      },
      series: series
    });
  }

  function updateChart() {
    if (!chart) return;

    Array.from(sensorData.entries()).forEach(([sensorId, data], index) => {
      const seriesIndex = chart!.series.findIndex(s => s.name === sensorId);

      if (seriesIndex >= 0) {
        chart!.series[seriesIndex].setData(
          data.map(d => [d.x, d.y]),
          false,
          false,
          false
        );
      } else {
        chart!.addSeries({
          type: 'line',
          name: sensorId,
          data: data.map(d => [d.x, d.y]),
          color: sensorColors.get(sensorId) || COLORS[index % COLORS.length],
          lineWidth: 1.5,
          marker: { enabled: false },
          animation: false
        }, false);
      }
    });

    chart.redraw(false);
  }

  onMount(() => {
    initializeSensorData();

    setTimeout(() => {
      createChart();
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
          addDataPoint(sensor_id, value);
          updateChart();
        }
      }
    };

    const handleAccumulatorEvent = (e: CustomEvent) => {
      const eventSensorId = e?.detail?.sensor_id;
      const attributeId = e?.detail?.attribute_id;

      if (attributeId === "ecg") {
        const data = e?.detail?.data;
        let value: number | null = null;

        if (Array.isArray(data) && data.length > 0) {
          const lastMeasurement = data[data.length - 1];
          value = lastMeasurement?.payload;
        } else if (data?.payload !== undefined) {
          value = data.payload;
        }

        if (typeof value === "number") {
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
    <h2>ECG Overview</h2>
    <span class="sensor-count">{sensors.length} sensors</span>
  </div>
  <div class="chart-wrapper" bind:this={chartContainer}></div>
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
</style>

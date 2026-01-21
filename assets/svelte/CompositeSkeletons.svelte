<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string }>;
  } = $props();

  let canvas: HTMLCanvasElement;
  let ctx: CanvasRenderingContext2D | null = null;
  let animationFrameId: number | null = null;

  // Store skeleton data per sensor
  let skeletonData: Map<string, { landmarks: any[]; lastUpdate: number }> = new Map();

  // MediaPipe Pose landmark connections
  const POSE_CONNECTIONS = [
    // Face
    [0, 1], [1, 2], [2, 3], [3, 7],
    [0, 4], [4, 5], [5, 6], [6, 8],
    [9, 10],
    // Torso
    [11, 12], // shoulders
    [11, 23], [12, 24], // shoulder to hip
    [23, 24], // hips
    // Left arm
    [11, 13], [13, 15], [15, 17], [15, 19], [15, 21], [17, 19],
    // Right arm
    [12, 14], [14, 16], [16, 18], [16, 20], [16, 22], [18, 20],
    // Left leg
    [23, 25], [25, 27], [27, 29], [27, 31], [29, 31],
    // Right leg
    [24, 26], [26, 28], [28, 30], [28, 32], [30, 32]
  ];

  // Colors for different body parts
  const BODY_COLORS = {
    face: "#8b5cf6",      // purple
    torso: "#3b82f6",     // blue
    leftArm: "#22c55e",   // green
    rightArm: "#ef4444",  // red
    leftLeg: "#22c55e",   // green
    rightLeg: "#ef4444"   // red
  };

  // Distinct colors for each sensor's skeleton
  const SENSOR_COLORS = [
    "#8b5cf6", // purple
    "#22c55e", // green
    "#ef4444", // red
    "#f59e0b", // amber
    "#06b6d4", // cyan
    "#ec4899", // pink
    "#84cc16", // lime
    "#6366f1", // indigo
    "#14b8a6", // teal
    "#f97316"  // orange
  ];

  function getConnectionColor(start: number, end: number): string {
    if (start <= 10 && end <= 10) return BODY_COLORS.face;
    if ([11, 12, 23, 24].includes(start) && [11, 12, 23, 24].includes(end)) return BODY_COLORS.torso;
    if ([11, 13, 15, 17, 19, 21].includes(start) && [11, 13, 15, 17, 19, 21].includes(end)) return BODY_COLORS.leftArm;
    if ([12, 14, 16, 18, 20, 22].includes(start) && [12, 14, 16, 18, 20, 22].includes(end)) return BODY_COLORS.rightArm;
    if ([23, 25, 27, 29, 31].includes(start) && [23, 25, 27, 29, 31].includes(end)) return BODY_COLORS.leftLeg;
    if ([24, 26, 28, 30, 32].includes(start) && [24, 26, 28, 30, 32].includes(end)) return BODY_COLORS.rightLeg;
    return BODY_COLORS.torso;
  }

  function drawSkeleton(
    landmarks: any[],
    centerX: number,
    centerY: number,
    size: number,
    sensorColor: string,
    sensorId: string
  ) {
    if (!ctx || !landmarks || landmarks.length === 0) return;

    const scale = size * 0.8;
    const offsetX = centerX - scale / 2;
    const offsetY = centerY - scale / 2;

    // Draw connections
    ctx.lineWidth = 2;
    for (const [start, end] of POSE_CONNECTIONS) {
      const startLm = landmarks[start];
      const endLm = landmarks[end];

      if (!startLm || !endLm) continue;

      const minVisibility = 0.3;
      if ((startLm.v ?? 1) < minVisibility || (endLm.v ?? 1) < minVisibility) continue;

      const x1 = offsetX + startLm.x * scale;
      const y1 = offsetY + startLm.y * scale;
      const x2 = offsetX + endLm.x * scale;
      const y2 = offsetY + endLm.y * scale;

      ctx.strokeStyle = getConnectionColor(start, end);
      ctx.globalAlpha = Math.min(startLm.v ?? 1, endLm.v ?? 1) * 0.9;
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }

    // Draw landmark points
    ctx.globalAlpha = 1;
    const pointRadius = 3;

    for (let i = 0; i < landmarks.length; i++) {
      const lm = landmarks[i];
      if (!lm || (lm.v ?? 1) < 0.3) continue;

      const x = offsetX + lm.x * scale;
      const y = offsetY + lm.y * scale;

      let color = BODY_COLORS.torso;
      if (i <= 10) color = BODY_COLORS.face;
      else if ([11, 13, 15, 17, 19, 21].includes(i)) color = BODY_COLORS.leftArm;
      else if ([12, 14, 16, 18, 20, 22].includes(i)) color = BODY_COLORS.rightArm;
      else if ([23, 25, 27, 29, 31].includes(i)) color = BODY_COLORS.leftLeg;
      else if ([24, 26, 28, 30, 32].includes(i)) color = BODY_COLORS.rightLeg;

      ctx.fillStyle = color;
      ctx.globalAlpha = lm.v ?? 1;
      ctx.beginPath();
      ctx.arc(x, y, pointRadius, 0, Math.PI * 2);
      ctx.fill();
    }

    ctx.globalAlpha = 1;

    // Draw sensor label with colored indicator
    const labelY = centerY + size / 2 + 20;
    const displayId = sensorId.length > 10 ? sensorId.slice(-8) : sensorId;

    // Draw colored dot
    ctx.fillStyle = sensorColor;
    ctx.beginPath();
    ctx.arc(centerX - 25, labelY - 4, 5, 0, Math.PI * 2);
    ctx.fill();

    // Draw label
    ctx.fillStyle = "#9ca3af";
    ctx.font = "11px monospace";
    ctx.textAlign = "center";
    ctx.fillText(displayId, centerX + 5, labelY);
  }

  function drawPlaceholder(centerX: number, centerY: number, size: number, label: string) {
    if (!ctx) return;

    // Draw dashed circle placeholder
    ctx.strokeStyle = "#374151";
    ctx.lineWidth = 1;
    ctx.setLineDash([5, 5]);
    ctx.beginPath();
    ctx.arc(centerX, centerY, size * 0.3, 0, Math.PI * 2);
    ctx.stroke();
    ctx.setLineDash([]);

    // Draw waiting text
    ctx.fillStyle = "#6b7280";
    ctx.font = "10px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText("Waiting...", centerX, centerY);

    // Draw label
    const displayId = label.length > 10 ? label.slice(-8) : label;
    ctx.fillStyle = "#4b5563";
    ctx.font = "11px monospace";
    ctx.fillText(displayId, centerX, centerY + size / 2 + 20);
  }

  function render() {
    if (!ctx || !canvas) return;

    const width = canvas.width;
    const height = canvas.height;

    // Clear canvas with dark background
    ctx.fillStyle = "#111827";
    ctx.fillRect(0, 0, width, height);

    // Get active sensors (from props or from data)
    const activeSensorIds = new Set<string>();
    sensors.forEach(s => activeSensorIds.add(s.sensor_id));
    skeletonData.forEach((_, id) => activeSensorIds.add(id));

    const sensorList = Array.from(activeSensorIds);
    const numSensors = sensorList.length;

    if (numSensors === 0) {
      // No sensors - show placeholder
      ctx.fillStyle = "#6b7280";
      ctx.font = "14px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No skeleton sensors connected", width / 2, height / 2);
      return;
    }

    // Calculate layout - arrange in circle
    const centerX = width / 2;
    const centerY = height / 2;
    const maxSkeletonSize = Math.min(width, height) * 0.4;

    // Adjust size based on number of sensors
    let skeletonSize: number;
    let radius: number;

    if (numSensors === 1) {
      skeletonSize = maxSkeletonSize;
      radius = 0;
    } else if (numSensors <= 4) {
      skeletonSize = maxSkeletonSize * 0.6;
      radius = Math.min(width, height) * 0.25;
    } else {
      skeletonSize = maxSkeletonSize * 0.4;
      radius = Math.min(width, height) * 0.35;
    }

    sensorList.forEach((sensorId, index) => {
      const angle = (2 * Math.PI * index) / numSensors - Math.PI / 2;
      const x = numSensors === 1 ? centerX : centerX + radius * Math.cos(angle);
      const y = numSensors === 1 ? centerY : centerY + radius * Math.sin(angle);
      const color = SENSOR_COLORS[index % SENSOR_COLORS.length];

      const data = skeletonData.get(sensorId);
      if (data && data.landmarks && data.landmarks.length > 0) {
        drawSkeleton(data.landmarks, x, y, skeletonSize, color, sensorId);
      } else {
        drawPlaceholder(x, y, skeletonSize, sensorId);
      }
    });

    // Draw title
    ctx.fillStyle = "#9ca3af";
    ctx.font = "bold 12px sans-serif";
    ctx.textAlign = "left";
    ctx.fillText(`Pose Composite (${numSensors} sensor${numSensors !== 1 ? 's' : ''})`, 10, 20);
  }

  function handleCompositeMeasurement(e: CustomEvent) {
    const { sensor_id, attribute_id, payload, timestamp } = e.detail;

    if (attribute_id === "skeleton" || attribute_id === "pose_skeleton") {
      let data;
      if (typeof payload === "string") {
        try {
          data = JSON.parse(payload);
        } catch {
          return;
        }
      } else {
        data = payload;
      }

      if (data && data.landmarks) {
        skeletonData.set(sensor_id, {
          landmarks: data.landmarks,
          lastUpdate: timestamp || Date.now()
        });
      }
    }
  }

  function handleAccumulatorEvent(e: CustomEvent) {
    const eventSensorId = e?.detail?.sensor_id;
    const attributeId = e?.detail?.attribute_id;

    if (attributeId === "skeleton" || attributeId === "pose_skeleton") {
      const eventData = e?.detail?.data;
      let payload;

      if (Array.isArray(eventData)) {
        const latest = eventData[eventData.length - 1];
        payload = latest?.payload;
      } else if (eventData?.payload !== undefined) {
        payload = eventData.payload;
      } else {
        payload = eventData;
      }

      if (!payload) return;

      let data;
      if (typeof payload === "string") {
        try {
          data = JSON.parse(payload);
        } catch {
          return;
        }
      } else {
        data = payload;
      }

      if (data && data.landmarks) {
        skeletonData.set(eventSensorId, {
          landmarks: data.landmarks,
          lastUpdate: Date.now()
        });
      }
    }
  }

  function renderLoop() {
    render();
    animationFrameId = requestAnimationFrame(renderLoop);
  }

  function resizeCanvas() {
    if (!canvas) return;
    const container = canvas.parentElement;
    if (container) {
      canvas.width = container.clientWidth;
      canvas.height = container.clientHeight;
      render();
    }
  }

  onMount(() => {
    if (canvas) {
      ctx = canvas.getContext("2d");
      resizeCanvas();
      renderLoop();
    }

    window.addEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
    window.addEventListener("accumulator-data-event", handleAccumulatorEvent as EventListener);
    window.addEventListener("resize", resizeCanvas);

    return () => {
      window.removeEventListener("composite-measurement-event", handleCompositeMeasurement as EventListener);
      window.removeEventListener("accumulator-data-event", handleAccumulatorEvent as EventListener);
      window.removeEventListener("resize", resizeCanvas);
    };
  });

  onDestroy(() => {
    if (animationFrameId) {
      cancelAnimationFrame(animationFrameId);
    }
  });
</script>

<div class="composite-skeletons-container">
  <canvas bind:this={canvas} class="skeleton-canvas"></canvas>
</div>

<style>
  .composite-skeletons-container {
    width: 100%;
    height: 100%;
    min-height: 400px;
    background: #111827;
    border-radius: 0.5rem;
    border: 1px solid rgba(107, 114, 128, 0.3);
    overflow: hidden;
  }

  .skeleton-canvas {
    width: 100%;
    height: 100%;
    display: block;
  }
</style>

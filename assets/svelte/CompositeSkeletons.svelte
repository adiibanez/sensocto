<script lang="ts">
  import { onMount, onDestroy } from "svelte";

  let { sensors = [] }: {
    sensors: Array<{ sensor_id: string; username?: string; attention?: number; bpm?: number }>;
  } = $props();

  let canvas: HTMLCanvasElement;
  let ctx: CanvasRenderingContext2D | null = null;
  let animationFrameId: number | null = null;

  // Store skeleton data per sensor with activity tracking
  let skeletonData: Map<string, {
    landmarks: any[];
    lastUpdate: number;
    username?: string;
    activity: number;        // 0-1 based on movement
    attention: number;       // 0-3 from props
    movementHistory: number[]; // Track recent movement for smoothing
    bpm: number;             // Heart rate in beats per minute
    lastHeartbeat: number;   // Timestamp of last heartbeat animation
    heartScale: number;      // Current heart animation scale (1.0 = normal, 1.3 = peak)
  }> = new Map();

  // Activity calculation constants
  const ACTIVITY_HISTORY_LENGTH = 10;

  // Build a map of sensor_id -> username/attention/bpm from props for fallback lookup
  $effect(() => {
    sensors.forEach(s => {
      const existing = skeletonData.get(s.sensor_id);
      if (existing) {
        if (s.username && !existing.username) {
          existing.username = s.username;
        }
        if (s.attention !== undefined) {
          existing.attention = s.attention;
        }
        if (s.bpm !== undefined && s.bpm > 0) {
          existing.bpm = s.bpm;
        }
      }
    });
  });

  // Calculate activity level from landmark movement
  function calculateActivity(sensorId: string, newLandmarks: any[]): number {
    const existing = skeletonData.get(sensorId);
    if (!existing || !existing.landmarks || existing.landmarks.length === 0) {
      return 0.5; // Default medium activity for new sensors
    }

    // Calculate total movement across key body landmarks (shoulders, hips, hands, feet)
    const keyLandmarks = [11, 12, 15, 16, 23, 24, 27, 28]; // shoulders, wrists, hips, ankles
    let totalMovement = 0;
    let validPoints = 0;

    for (const idx of keyLandmarks) {
      const oldLm = existing.landmarks[idx];
      const newLm = newLandmarks[idx];
      if (oldLm && newLm && (oldLm.v ?? 1) > 0.3 && (newLm.v ?? 1) > 0.3) {
        const dx = (newLm.x - oldLm.x);
        const dy = (newLm.y - oldLm.y);
        totalMovement += Math.sqrt(dx * dx + dy * dy);
        validPoints++;
      }
    }

    if (validPoints === 0) return existing.activity;

    // Normalize movement (0-1 scale, with 0.1 being significant movement)
    const avgMovement = totalMovement / validPoints;
    const normalizedMovement = Math.min(1, avgMovement / 0.1);

    // Smooth with history
    const history = existing.movementHistory || [];
    history.push(normalizedMovement);
    if (history.length > ACTIVITY_HISTORY_LENGTH) {
      history.shift();
    }

    // Calculate smoothed activity
    const smoothedActivity = history.reduce((a, b) => a + b, 0) / history.length;

    return smoothedActivity;
  }

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

  // Calculate bounding box of visible landmarks
  function getLandmarkBounds(landmarks: any[]): { minX: number; maxX: number; minY: number; maxY: number } | null {
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    let hasVisible = false;

    for (const lm of landmarks) {
      if (!lm || (lm.v ?? 1) < 0.3) continue;
      hasVisible = true;
      minX = Math.min(minX, lm.x);
      maxX = Math.max(maxX, lm.x);
      minY = Math.min(minY, lm.y);
      maxY = Math.max(maxY, lm.y);
    }

    if (!hasVisible) return null;
    return { minX, maxX, minY, maxY };
  }

  function drawSkeleton(
    landmarks: any[],
    areaX: number,
    areaY: number,
    areaWidth: number,
    areaHeight: number,
    sensorColor: string,
    sensorId: string,
    username?: string
  ) {
    if (!ctx || !landmarks || landmarks.length === 0) return;

    // Calculate actual bounding box of the skeleton
    const bounds = getLandmarkBounds(landmarks);
    if (!bounds) return;

    const { minX, maxX, minY, maxY } = bounds;
    const skeletonWidth = maxX - minX;
    const skeletonHeight = maxY - minY;

    // Reserve space for label
    const labelHeight = 25;
    const availableHeight = areaHeight - labelHeight;

    // Calculate scale to maximize skeleton size while fitting in area
    // Add small padding (5%) to prevent clipping at edges
    const padding = 0.05;
    const scaleX = (areaWidth * (1 - padding * 2)) / Math.max(skeletonWidth, 0.01);
    const scaleY = (availableHeight * (1 - padding * 2)) / Math.max(skeletonHeight, 0.01);
    const scale = Math.min(scaleX, scaleY);

    // Calculate center of skeleton in normalized coords
    const skeletonCenterX = (minX + maxX) / 2;
    const skeletonCenterY = (minY + maxY) / 2;

    // Calculate offset to center skeleton in drawing area
    const areaCenterX = areaX + areaWidth / 2;
    const areaCenterY = areaY + availableHeight / 2;

    // Transform function: normalized coords -> canvas coords (centered)
    const toCanvasX = (x: number) => areaCenterX + (x - skeletonCenterX) * scale;
    const toCanvasY = (y: number) => areaCenterY + (y - skeletonCenterY) * scale;

    // Draw connections with thicker lines for larger skeletons
    const lineWidth = Math.max(2, Math.min(4, scale * 0.015));
    ctx.lineWidth = lineWidth;

    for (const [start, end] of POSE_CONNECTIONS) {
      const startLm = landmarks[start];
      const endLm = landmarks[end];

      if (!startLm || !endLm) continue;

      const minVisibility = 0.3;
      if ((startLm.v ?? 1) < minVisibility || (endLm.v ?? 1) < minVisibility) continue;

      const x1 = toCanvasX(startLm.x);
      const y1 = toCanvasY(startLm.y);
      const x2 = toCanvasX(endLm.x);
      const y2 = toCanvasY(endLm.y);

      ctx.strokeStyle = getConnectionColor(start, end);
      ctx.globalAlpha = Math.min(startLm.v ?? 1, endLm.v ?? 1) * 0.9;
      ctx.beginPath();
      ctx.moveTo(x1, y1);
      ctx.lineTo(x2, y2);
      ctx.stroke();
    }

    // Draw landmark points with size proportional to skeleton scale
    ctx.globalAlpha = 1;
    const pointRadius = Math.max(3, Math.min(6, scale * 0.01));

    for (let i = 0; i < landmarks.length; i++) {
      const lm = landmarks[i];
      if (!lm || (lm.v ?? 1) < 0.3) continue;

      const x = toCanvasX(lm.x);
      const y = toCanvasY(lm.y);

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

    // Draw sensor label at bottom of area
    const labelY = areaY + areaHeight - 8;
    const displayLabel = username || sensorId;
    const truncatedLabel = displayLabel.length > 25 ? displayLabel.slice(0, 22) + "..." : displayLabel;

    ctx.font = "11px sans-serif";
    const textWidth = ctx.measureText(truncatedLabel).width;

    // Draw colored dot to the left of the label
    ctx.fillStyle = sensorColor;
    ctx.beginPath();
    ctx.arc(areaCenterX - textWidth / 2 - 10, labelY - 4, 5, 0, Math.PI * 2);
    ctx.fill();

    // Draw label
    ctx.fillStyle = "#9ca3af";
    ctx.textAlign = "center";
    ctx.fillText(truncatedLabel, areaCenterX, labelY);
  }

  function drawPlaceholder(centerX: number, centerY: number, size: number, sensorId: string, username?: string) {
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

    // Draw label - prefer username over sensor_id
    const displayLabel = username || sensorId;
    const truncatedLabel = displayLabel.length > 25 ? displayLabel.slice(0, 22) + "..." : displayLabel;
    ctx.fillStyle = "#4b5563";
    ctx.font = "11px sans-serif";
    ctx.fillText(truncatedLabel, centerX, centerY + size / 2 + 20);
  }

  // Draw a beating heart with BPM
  function drawHeart(x: number, y: number, size: number, bpm: number, scale: number) {
    if (!ctx || bpm <= 0) return;

    const heartSize = size * scale;

    // Heart color based on BPM zones
    let heartColor = "#22c55e"; // green - normal (60-99)
    if (bpm < 60) heartColor = "#3b82f6"; // blue - low
    else if (bpm >= 100 && bpm < 120) heartColor = "#eab308"; // yellow - elevated
    else if (bpm >= 120) heartColor = "#ef4444"; // red - high

    ctx.save();
    ctx.translate(x, y);
    ctx.scale(heartSize / 24, heartSize / 24);
    ctx.translate(-12, -12);

    // Draw heart shape (SVG path converted to canvas)
    ctx.beginPath();
    ctx.moveTo(12, 21.35);
    ctx.bezierCurveTo(10.55, 20.03, 5, 14.56, 5, 10);
    ctx.bezierCurveTo(5, 7.42, 7.42, 5, 10, 5);
    ctx.bezierCurveTo(11.31, 5, 12, 5.69, 12, 5.69);
    ctx.bezierCurveTo(12, 5.69, 12.69, 5, 14, 5);
    ctx.bezierCurveTo(16.58, 5, 19, 7.42, 19, 10);
    ctx.bezierCurveTo(19, 14.56, 13.45, 20.03, 12, 21.35);
    ctx.closePath();

    ctx.fillStyle = heartColor;
    ctx.globalAlpha = 0.9;
    ctx.fill();

    ctx.restore();

    // Draw BPM text below heart
    ctx.globalAlpha = 1;
    ctx.fillStyle = heartColor;
    ctx.font = "bold 10px sans-serif";
    ctx.textAlign = "center";
    ctx.fillText(`${Math.round(bpm)}`, x, y + heartSize / 2 + 10);
  }

  // Update heart animation based on BPM
  function updateHeartAnimation(sensorId: string, now: number) {
    const data = skeletonData.get(sensorId);
    if (!data || data.bpm <= 0) return 1.0;

    const msPerBeat = 60000 / data.bpm;
    const timeSinceLastBeat = now - (data.lastHeartbeat || 0);

    if (timeSinceLastBeat >= msPerBeat) {
      data.lastHeartbeat = now;
      data.heartScale = 1.3; // Start pulse
    } else if (timeSinceLastBeat < 150) {
      // Pulse animation (150ms duration)
      const pulseProgress = timeSinceLastBeat / 150;
      data.heartScale = 1.3 - (0.3 * pulseProgress);
    } else {
      data.heartScale = 1.0;
    }

    return data.heartScale;
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

    // Sort sensors by username for stable ordering
    const sortedSensors = sensorList.map(sensorId => {
      const data = skeletonData.get(sensorId);
      const sensorFromProps = sensors.find(s => s.sensor_id === sensorId);
      const username = data?.username || sensorFromProps?.username || sensorId;
      return { sensorId, username };
    }).sort((a, b) => a.username.localeCompare(b.username));

    const now = Date.now();
    const titleHeight = 18; // Space for title at top

    // Layout based on number of sensors - maximize space usage
    if (numSensors === 1) {
      // Single sensor - use entire canvas (minus title)
      const { sensorId } = sortedSensors[0];
      const data = skeletonData.get(sensorId);
      const sensorFromProps = sensors.find(s => s.sensor_id === sensorId);
      const username = data?.username || sensorFromProps?.username;
      const bpm = data?.bpm || sensorFromProps?.bpm || 0;
      const color = SENSOR_COLORS[0];

      // Full canvas area for skeleton (minus title)
      const areaX = 0;
      const areaY = titleHeight;
      const areaWidth = width;
      const areaHeight = height - titleHeight;

      if (data && data.landmarks && data.landmarks.length > 0) {
        drawSkeleton(data.landmarks, areaX, areaY, areaWidth, areaHeight, color, sensorId, username);

        // Draw heart if BPM available - position relative to skeleton bounds
        if (bpm > 0) {
          const bounds = getLandmarkBounds(data.landmarks);
          if (bounds) {
            const heartScale = updateHeartAnimation(sensorId, now);
            // Position heart at top-right of the drawn skeleton
            const heartX = width * 0.85;
            const heartY = titleHeight + 30;
            drawHeart(heartX, heartY, 28, bpm, heartScale);
          }
        }
      } else {
        const size = Math.min(areaWidth, areaHeight) * 0.5;
        drawPlaceholder(areaX + areaWidth / 2, areaY + areaHeight / 2, size, sensorId, username);
      }
    } else {
      // Multiple sensors - pack in grid, maximizing space
      const cols = numSensors <= 2 ? 2 : numSensors <= 4 ? 2 : numSensors <= 6 ? 3 : 4;
      const rows = Math.ceil(numSensors / cols);

      const cellWidth = width / cols;
      const cellHeight = (height - titleHeight) / rows;

      sortedSensors.forEach(({ sensorId }, index) => {
        const col = index % cols;
        const row = Math.floor(index / cols);

        // Cell area for this skeleton
        const areaX = col * cellWidth;
        const areaY = titleHeight + row * cellHeight;
        const areaWidth = cellWidth;
        const areaHeight = cellHeight;

        const data = skeletonData.get(sensorId);
        const sensorFromProps = sensors.find(s => s.sensor_id === sensorId);
        const username = data?.username || sensorFromProps?.username;
        const bpm = data?.bpm || sensorFromProps?.bpm || 0;
        const color = SENSOR_COLORS[index % SENSOR_COLORS.length];

        if (data && data.landmarks && data.landmarks.length > 0) {
          drawSkeleton(data.landmarks, areaX, areaY, areaWidth, areaHeight, color, sensorId, username);

          // Draw heart if BPM available
          if (bpm > 0) {
            const heartScale = updateHeartAnimation(sensorId, now);
            const heartX = areaX + areaWidth * 0.85;
            const heartY = areaY + 25;
            drawHeart(heartX, heartY, 20, bpm, heartScale);
          }
        } else {
          const size = Math.min(areaWidth, areaHeight) * 0.5;
          drawPlaceholder(areaX + areaWidth / 2, areaY + areaHeight / 2, size, sensorId, username);
        }
      });
    }

    // Draw compact title
    ctx.fillStyle = "#6b7280";
    ctx.font = "10px sans-serif";
    ctx.textAlign = "left";
    ctx.fillText(`Pose (${numSensors})`, 8, 14);

    // Draw distance hint on first render or when few sensors
    if (numSensors <= 2) {
      ctx.fillStyle = "#4b5563";
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.fillText("Tip: Stand 1-2m from camera", width - 8, 14);
    }
  }

  function handleCompositeMeasurement(e: CustomEvent) {
    const { sensor_id, username, attribute_id, payload, timestamp } = e.detail;

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
        const existing = skeletonData.get(sensor_id);
        const activity = calculateActivity(sensor_id, data.landmarks);
        const sensorFromProps = sensors.find(s => s.sensor_id === sensor_id);

        skeletonData.set(sensor_id, {
          landmarks: data.landmarks,
          lastUpdate: timestamp || Date.now(),
          username: username || existing?.username,
          activity: activity,
          attention: existing?.attention ?? sensorFromProps?.attention ?? 1,
          movementHistory: existing?.movementHistory || [],
          bpm: existing?.bpm ?? sensorFromProps?.bpm ?? 0,
          lastHeartbeat: existing?.lastHeartbeat ?? 0,
          heartScale: existing?.heartScale ?? 1.0
        });
      }
    }

    // Also handle heartrate events
    if (attribute_id === "heartrate" || attribute_id === "hr") {
      let bpm = 0;
      if (typeof payload === "number") {
        bpm = payload;
      } else if (typeof payload === "object" && payload !== null) {
        bpm = payload.bpm ?? payload.heartRate ?? payload.value ?? 0;
      }

      if (bpm > 0) {
        const existing = skeletonData.get(sensor_id);
        if (existing) {
          existing.bpm = bpm;
        } else {
          const sensorFromProps = sensors.find(s => s.sensor_id === sensor_id);
          skeletonData.set(sensor_id, {
            landmarks: [],
            lastUpdate: Date.now(),
            username: username || sensorFromProps?.username,
            activity: 0.5,
            attention: sensorFromProps?.attention ?? 1,
            movementHistory: [],
            bpm: bpm,
            lastHeartbeat: 0,
            heartScale: 1.0
          });
        }
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
        const existing = skeletonData.get(eventSensorId);
        const activity = calculateActivity(eventSensorId, data.landmarks);
        const sensorFromProps = sensors.find(s => s.sensor_id === eventSensorId);

        skeletonData.set(eventSensorId, {
          landmarks: data.landmarks,
          lastUpdate: Date.now(),
          username: existing?.username,
          activity: activity,
          attention: existing?.attention ?? sensorFromProps?.attention ?? 1,
          movementHistory: existing?.movementHistory || [],
          bpm: existing?.bpm ?? sensorFromProps?.bpm ?? 0,
          lastHeartbeat: existing?.lastHeartbeat ?? 0,
          heartScale: existing?.heartScale ?? 1.0
        });
      }
    }

    // Also handle heartrate events from accumulator
    if (attributeId === "heartrate" || attributeId === "hr") {
      const eventData = e?.detail?.data;
      let bpm = 0;

      if (Array.isArray(eventData)) {
        const latest = eventData[eventData.length - 1];
        const payload = latest?.payload;
        if (typeof payload === "number") bpm = payload;
        else if (payload?.bpm) bpm = payload.bpm;
      } else if (typeof eventData === "number") {
        bpm = eventData;
      } else if (eventData?.payload) {
        const payload = eventData.payload;
        if (typeof payload === "number") bpm = payload;
        else if (payload?.bpm) bpm = payload.bpm;
      }

      if (bpm > 0) {
        const existing = skeletonData.get(eventSensorId);
        if (existing) {
          existing.bpm = bpm;
        }
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
    min-height: 200px;
    background: #111827;
    border-radius: 0.375rem;
    border: 1px solid rgba(75, 85, 99, 0.3);
    overflow: hidden;
  }

  .skeleton-canvas {
    width: 100%;
    height: 100%;
    display: block;
  }

  /* Responsive height based on viewport */
  @media (max-height: 600px) {
    .composite-skeletons-container {
      min-height: 150px;
    }
  }

  @media (min-height: 800px) {
    .composite-skeletons-container {
      min-height: 300px;
    }
  }
</style>

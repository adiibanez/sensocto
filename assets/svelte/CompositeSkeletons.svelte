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
    smoothedLandmarks: any[];       // Jitter-filtered landmarks for rendering
    faceLandmarks?: any[];          // 468 face mesh landmarks (optional)
    smoothedFaceLandmarks?: any[];  // Jitter-filtered face landmarks
    blendshapes?: any;              // Face blendshapes for expressions
    mode?: string;                  // "full" or "face" from hybrid client
    lastUpdate: number;
    username?: string;
    activity: number;               // 0-1 based on movement
    attention: number;              // 0-3 from props
    movementHistory: number[];      // Track recent movement for smoothing
    bpm: number;                    // Heart rate in beats per minute
    lastHeartbeat: number;          // Timestamp of last heartbeat animation
    heartScale: number;             // Current heart animation scale (1.0 = normal, 1.3 = peak)
  }> = new Map();

  // Activity calculation constants
  const ACTIVITY_HISTORY_LENGTH = 10;

  // Jitter filtering constants - EMA (Exponential Moving Average)
  // Lower alpha = more smoothing (0.0-1.0), higher = more responsive
  const BODY_SMOOTHING_ALPHA = 0.4;    // Body landmarks: moderate smoothing
  const FACE_SMOOTHING_ALPHA = 0.25;   // Face landmarks: stronger smoothing (more jittery)
  const VISIBILITY_THRESHOLD = 0.3;    // Min visibility to include in smoothing

  // Apply exponential moving average smoothing to landmarks
  function smoothLandmarks(
    newLandmarks: any[],
    previousSmoothed: any[] | undefined,
    alpha: number
  ): any[] {
    if (!previousSmoothed || previousSmoothed.length !== newLandmarks.length) {
      // First frame or landmark count changed - no smoothing possible
      return newLandmarks.map(lm => ({ ...lm }));
    }

    return newLandmarks.map((newLm, i) => {
      const prevLm = previousSmoothed[i];
      if (!newLm || !prevLm) return newLm;

      // Only smooth if both points have sufficient visibility
      const newVis = newLm.v ?? newLm.visibility ?? 1;
      const prevVis = prevLm.v ?? prevLm.visibility ?? 1;

      if (newVis < VISIBILITY_THRESHOLD || prevVis < VISIBILITY_THRESHOLD) {
        // Low visibility - use new value directly (or skip)
        return { ...newLm };
      }

      // Apply EMA: smoothed = alpha * new + (1 - alpha) * previous
      return {
        x: alpha * newLm.x + (1 - alpha) * prevLm.x,
        y: alpha * newLm.y + (1 - alpha) * prevLm.y,
        z: newLm.z !== undefined ? alpha * newLm.z + (1 - alpha) * (prevLm.z ?? newLm.z) : undefined,
        v: newLm.v,
        visibility: newLm.visibility
      };
    });
  }

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

  // Face-only connections - minimal, used as fallback
  const FACE_CONNECTIONS = [
    [9, 10],                  // mouth line
  ];

  // MediaPipe Face Mesh landmark indices for key features (468 landmarks)
  const FACE_MESH_INDICES = {
    // Face oval contour
    silhouette: [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109],
    // Left eyebrow
    leftEyebrowUpper: [336, 296, 334, 293, 300],
    // Right eyebrow
    rightEyebrowUpper: [107, 66, 105, 63, 70],
    // Left eye contour
    leftEyeUpper: [362, 398, 384, 385, 386, 387, 388, 466, 263],
    leftEyeLower: [263, 249, 390, 373, 374, 380, 381, 382, 362],
    // Right eye contour
    rightEyeUpper: [133, 173, 157, 158, 159, 160, 161, 246, 33],
    rightEyeLower: [33, 7, 163, 144, 145, 153, 154, 155, 133],
    // Nose
    noseBridge: [168, 6, 197, 195, 5],
    noseBottom: [4, 45, 220, 115, 48, 64, 98, 97, 2, 326, 327, 278, 294, 440, 275],
    // Lips outer contour
    lipsUpperOuter: [61, 185, 40, 39, 37, 0, 267, 269, 270, 409, 291],
    lipsLowerOuter: [291, 375, 321, 405, 314, 17, 84, 181, 91, 146, 61],
    // Lips inner contour
    lipsUpperInner: [78, 191, 80, 81, 82, 13, 312, 311, 310, 415, 308],
    lipsLowerInner: [308, 324, 318, 402, 317, 14, 87, 178, 88, 95, 78],
  };

  // Draw detailed face using 468 face mesh landmarks
  function drawFaceMesh(
    ctx: CanvasRenderingContext2D,
    faceLandmarks: any[],
    toCanvasX: (x: number) => number,
    toCanvasY: (y: number) => number,
    scale: number,
    blendshapes?: any
  ) {
    if (!faceLandmarks || faceLandmarks.length < 468) return;

    const getLm = (idx: number) => {
      const lm = faceLandmarks[idx];
      if (!lm) return null;
      return { x: toCanvasX(lm.x), y: toCanvasY(lm.y) };
    };

    // Helper to draw a path through landmark indices
    const drawPath = (indices: number[], closed = false) => {
      const points = indices.map(getLm).filter((p): p is {x: number; y: number} => p !== null);
      if (points.length < 2) return;

      ctx.beginPath();
      ctx.moveTo(points[0].x, points[0].y);
      for (let i = 1; i < points.length; i++) {
        ctx.lineTo(points[i].x, points[i].y);
      }
      if (closed) ctx.closePath();
    };

    // Calculate face dimensions for scaling stroke widths
    const leftCheek = getLm(234);
    const rightCheek = getLm(454);
    const faceWidth = leftCheek && rightCheek ? Math.abs(rightCheek.x - leftCheek.x) : 100 * scale;
    const strokeWidth = Math.max(1, Math.min(3, faceWidth * 0.015));

    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    // 1. Face silhouette (oval)
    ctx.strokeStyle = "#a78bfa";
    ctx.lineWidth = strokeWidth * 1.2;
    ctx.globalAlpha = 0.5;
    drawPath(FACE_MESH_INDICES.silhouette, true);
    ctx.stroke();

    // 2. Eyebrows
    ctx.strokeStyle = "#d4d4d8";
    ctx.lineWidth = strokeWidth * 1.5;
    ctx.globalAlpha = 0.8;

    drawPath(FACE_MESH_INDICES.leftEyebrowUpper);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.rightEyebrowUpper);
    ctx.stroke();

    // 3. Eyes
    ctx.strokeStyle = "#60a5fa";
    ctx.lineWidth = strokeWidth;
    ctx.globalAlpha = 0.9;

    drawPath(FACE_MESH_INDICES.leftEyeUpper);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.leftEyeLower);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.rightEyeUpper);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.rightEyeLower);
    ctx.stroke();

    // Draw iris centers
    ctx.fillStyle = "#1e293b";
    ctx.globalAlpha = 0.8;

    const leftIrisCenter = getLm(473);
    if (leftIrisCenter) {
      const irisRadius = faceWidth * 0.025;
      ctx.beginPath();
      ctx.arc(leftIrisCenter.x, leftIrisCenter.y, irisRadius, 0, Math.PI * 2);
      ctx.fill();
    }

    const rightIrisCenter = getLm(468);
    if (rightIrisCenter) {
      const irisRadius = faceWidth * 0.025;
      ctx.beginPath();
      ctx.arc(rightIrisCenter.x, rightIrisCenter.y, irisRadius, 0, Math.PI * 2);
      ctx.fill();
    }

    // 4. Nose
    ctx.strokeStyle = "#f472b6";
    ctx.lineWidth = strokeWidth;
    ctx.globalAlpha = 0.7;

    drawPath(FACE_MESH_INDICES.noseBridge);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.noseBottom);
    ctx.stroke();

    // 5. Lips - with blendshape-based mouth openness
    const jawOpen = blendshapes?.jawOpen ?? 0;

    ctx.strokeStyle = "#f87171";
    ctx.lineWidth = strokeWidth * 1.3;
    ctx.globalAlpha = 0.85;

    drawPath(FACE_MESH_INDICES.lipsUpperOuter);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.lipsLowerOuter);
    ctx.stroke();

    // Inner mouth when open
    if (jawOpen > 0.1) {
      ctx.fillStyle = "#1e293b";
      ctx.globalAlpha = Math.min(0.7, jawOpen);

      const innerPoints = FACE_MESH_INDICES.lipsUpperInner.concat(
        FACE_MESH_INDICES.lipsLowerInner.slice(1, -1).reverse()
      ).map(getLm).filter((p): p is {x: number; y: number} => p !== null);

      if (innerPoints.length >= 3) {
        ctx.beginPath();
        ctx.moveTo(innerPoints[0].x, innerPoints[0].y);
        for (let i = 1; i < innerPoints.length; i++) {
          ctx.lineTo(innerPoints[i].x, innerPoints[i].y);
        }
        ctx.closePath();
        ctx.fill();
      }
    }

    // Inner lip lines
    ctx.strokeStyle = "#dc2626";
    ctx.lineWidth = strokeWidth * 0.8;
    ctx.globalAlpha = 0.6;
    drawPath(FACE_MESH_INDICES.lipsUpperInner);
    ctx.stroke();
    drawPath(FACE_MESH_INDICES.lipsLowerInner);
    ctx.stroke();

    ctx.globalAlpha = 1;
  }

  // Draw a natural-looking face with proper facial features (from 33 pose landmarks)
  function drawFaceFromPose(
    ctx: CanvasRenderingContext2D,
    landmarks: any[],
    toCanvasX: (x: number) => number,
    toCanvasY: (y: number) => number,
    scale: number
  ) {
    const minVisibility = 0.3;
    const getLm = (idx: number) => {
      const lm = landmarks[idx];
      if (!lm || (lm.v ?? 1) < minVisibility) return null;
      return { x: toCanvasX(lm.x), y: toCanvasY(lm.y), v: lm.v ?? 1 };
    };

    // Get key face landmarks
    const nose = getLm(0);
    const leftEyeInner = getLm(1);
    const leftEye = getLm(2);
    const leftEyeOuter = getLm(3);
    const rightEyeInner = getLm(4);
    const rightEye = getLm(5);
    const rightEyeOuter = getLm(6);
    const leftEar = getLm(7);
    const rightEar = getLm(8);
    const mouthLeft = getLm(9);
    const mouthRight = getLm(10);

    if (!nose) return;

    // Calculate face dimensions for proportional drawing
    const eyeWidth = leftEyeOuter && leftEyeInner
      ? Math.abs(leftEyeOuter.x - leftEyeInner.x)
      : 20 * scale;
    const faceWidth = leftEar && rightEar
      ? Math.abs(rightEar.x - leftEar.x)
      : eyeWidth * 4;
    const strokeWidth = Math.max(2, Math.min(4, faceWidth * 0.02));

    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    // 1. Draw head contour (oval)
    if (leftEar && rightEar && nose) {
      const centerX = (leftEar.x + rightEar.x) / 2;
      const centerY = nose.y;
      const radiusX = faceWidth / 2 * 1.1;
      const radiusY = faceWidth / 1.5;

      ctx.strokeStyle = "#a78bfa"; // light purple
      ctx.lineWidth = strokeWidth * 1.2;
      ctx.globalAlpha = 0.6;
      ctx.beginPath();
      ctx.ellipse(centerX, centerY, radiusX, radiusY, 0, 0, Math.PI * 2);
      ctx.stroke();
    }

    // 2. Draw eyebrows (curved arcs above eyes)
    ctx.strokeStyle = "#d4d4d8"; // light gray
    ctx.lineWidth = strokeWidth * 1.5;
    ctx.globalAlpha = 0.8;

    // Left eyebrow
    if (leftEyeInner && leftEyeOuter) {
      const browY = leftEye ? leftEye.y - eyeWidth * 0.5 : leftEyeInner.y - eyeWidth * 0.5;
      ctx.beginPath();
      ctx.moveTo(leftEyeInner.x, browY + eyeWidth * 0.1);
      ctx.quadraticCurveTo(
        (leftEyeInner.x + leftEyeOuter.x) / 2,
        browY - eyeWidth * 0.15,
        leftEyeOuter.x,
        browY + eyeWidth * 0.05
      );
      ctx.stroke();
    }

    // Right eyebrow
    if (rightEyeInner && rightEyeOuter) {
      const browY = rightEye ? rightEye.y - eyeWidth * 0.5 : rightEyeInner.y - eyeWidth * 0.5;
      ctx.beginPath();
      ctx.moveTo(rightEyeInner.x, browY + eyeWidth * 0.1);
      ctx.quadraticCurveTo(
        (rightEyeInner.x + rightEyeOuter.x) / 2,
        browY - eyeWidth * 0.15,
        rightEyeOuter.x,
        browY + eyeWidth * 0.05
      );
      ctx.stroke();
    }

    // 3. Draw eyes (almond shapes)
    ctx.fillStyle = "#60a5fa"; // light blue
    ctx.globalAlpha = 0.9;

    // Left eye
    if (leftEyeInner && leftEyeOuter && leftEye) {
      const eyeCenterX = leftEye.x;
      const eyeCenterY = leftEye.y;
      const eyeRadiusX = eyeWidth * 0.4;
      const eyeRadiusY = eyeWidth * 0.2;

      ctx.beginPath();
      ctx.ellipse(eyeCenterX, eyeCenterY, eyeRadiusX, eyeRadiusY, 0, 0, Math.PI * 2);
      ctx.fill();

      // Pupil
      ctx.fillStyle = "#1e293b";
      ctx.beginPath();
      ctx.arc(eyeCenterX, eyeCenterY, eyeRadiusY * 0.6, 0, Math.PI * 2);
      ctx.fill();
    }

    // Right eye
    ctx.fillStyle = "#60a5fa";
    if (rightEyeInner && rightEyeOuter && rightEye) {
      const eyeCenterX = rightEye.x;
      const eyeCenterY = rightEye.y;
      const eyeRadiusX = eyeWidth * 0.4;
      const eyeRadiusY = eyeWidth * 0.2;

      ctx.beginPath();
      ctx.ellipse(eyeCenterX, eyeCenterY, eyeRadiusX, eyeRadiusY, 0, 0, Math.PI * 2);
      ctx.fill();

      // Pupil
      ctx.fillStyle = "#1e293b";
      ctx.beginPath();
      ctx.arc(eyeCenterX, eyeCenterY, eyeRadiusY * 0.6, 0, Math.PI * 2);
      ctx.fill();
    }

    // 4. Draw nose
    if (nose && mouthLeft && mouthRight) {
      const mouthCenterY = (mouthLeft.y + mouthRight.y) / 2;
      const noseHeight = Math.abs(mouthCenterY - nose.y) * 0.6;
      const noseWidth = eyeWidth * 0.4;

      ctx.strokeStyle = "#f472b6"; // pink
      ctx.lineWidth = strokeWidth;
      ctx.globalAlpha = 0.7;

      // Nose bridge and tip
      ctx.beginPath();
      // Start from between eyes, draw down to nose tip
      const noseBridgeY = nose.y - noseHeight * 0.3;
      ctx.moveTo(nose.x, noseBridgeY);
      ctx.lineTo(nose.x, nose.y);
      // Nose wings
      ctx.moveTo(nose.x - noseWidth, nose.y + noseHeight * 0.1);
      ctx.quadraticCurveTo(nose.x, nose.y + noseHeight * 0.3, nose.x + noseWidth, nose.y + noseHeight * 0.1);
      ctx.stroke();
    }

    // 5. Draw mouth (with open/closed state based on landmark positions)
    if (mouthLeft && mouthRight && nose) {
      const mouthWidth = Math.abs(mouthRight.x - mouthLeft.x);
      const mouthCenterX = (mouthLeft.x + mouthRight.x) / 2;
      const mouthCenterY = (mouthLeft.y + mouthRight.y) / 2;

      // Estimate mouth openness from vertical difference between corners
      // and distance from nose (mouth opens = corners move down and apart vertically)
      const cornerVerticalDiff = Math.abs(mouthLeft.y - mouthRight.y);
      const noseToMouthDist = mouthCenterY - nose.y;

      // Normalize openness: when mouth corners are at different heights or far from nose
      // A typical closed mouth has corners at same height
      // Ratio of vertical diff to mouth width indicates openness
      const openRatio = Math.min(1, (cornerVerticalDiff / mouthWidth) * 3 +
                                     Math.max(0, (noseToMouthDist - eyeWidth * 0.8) / eyeWidth) * 0.5);
      const mouthOpenness = openRatio * mouthWidth * 0.4; // Max opening is 40% of mouth width

      ctx.strokeStyle = "#f87171"; // red/coral
      ctx.lineWidth = strokeWidth * 1.3;
      ctx.globalAlpha = 0.85;

      // Upper lip line
      ctx.beginPath();
      ctx.moveTo(mouthLeft.x, mouthLeft.y);
      ctx.quadraticCurveTo(
        mouthCenterX,
        mouthCenterY - mouthWidth * 0.08,
        mouthRight.x,
        mouthRight.y
      );
      ctx.stroke();

      // Lower lip - moves down when mouth is open
      ctx.globalAlpha = 0.7;
      ctx.beginPath();
      ctx.moveTo(mouthLeft.x + mouthWidth * 0.1, mouthLeft.y);
      ctx.quadraticCurveTo(
        mouthCenterX,
        mouthCenterY + mouthWidth * 0.12 + mouthOpenness,
        mouthRight.x - mouthWidth * 0.1,
        mouthRight.y
      );
      ctx.stroke();

      // If mouth is significantly open, draw inner mouth (dark opening)
      if (mouthOpenness > mouthWidth * 0.08) {
        ctx.fillStyle = "#1e293b"; // dark
        ctx.globalAlpha = 0.6;
        ctx.beginPath();
        ctx.moveTo(mouthLeft.x + mouthWidth * 0.15, mouthLeft.y);
        ctx.quadraticCurveTo(
          mouthCenterX,
          mouthCenterY - mouthWidth * 0.05,
          mouthRight.x - mouthWidth * 0.15,
          mouthRight.y
        );
        ctx.quadraticCurveTo(
          mouthCenterX,
          mouthCenterY + mouthOpenness * 0.8,
          mouthLeft.x + mouthWidth * 0.15,
          mouthLeft.y
        );
        ctx.fill();
      }
    }

    ctx.globalAlpha = 1;
  }

  // Landmark indices for body part detection
  const FACE_INDICES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
  const SHOULDER_INDICES = [11, 12];
  const UPPER_ARM_INDICES = [13, 14];
  const HIP_INDICES = [23, 24];
  const LEG_INDICES = [25, 26, 27, 28, 29, 30, 31, 32];

  // Wrist/hand indices for detecting full arm visibility
  const LOWER_ARM_INDICES = [15, 16, 17, 18, 19, 20, 21, 22];

  // Mode stability: prevent flickering between modes (per-sensor)
  // Uses hysteresis - harder to switch modes than to stay in current mode
  const sensorModeState: Map<string, { currentMode: "full" | "face"; modeCounter: number }> = new Map();
  const MODE_STABILITY_THRESHOLD_TO_FACE = 20;
  const MODE_STABILITY_THRESHOLD_TO_FULL = 12;

  // Face coverage thresholds with hysteresis
  const FACE_COVERAGE_ENTER_THRESHOLD = 0.45;
  const FACE_COVERAGE_EXIT_THRESHOLD = 0.25;

  // Calculate bounding box area for a set of landmark indices
  function calculateBoundingBoxArea(landmarks: any[], indices: number[], minVisibility = 0.3) {
    let minX = Infinity, maxX = -Infinity;
    let minY = Infinity, maxY = -Infinity;
    let validCount = 0;

    for (const idx of indices) {
      const lm = landmarks[idx];
      if (!lm || (lm.v ?? 1) < minVisibility) continue;

      minX = Math.min(minX, lm.x);
      maxX = Math.max(maxX, lm.x);
      minY = Math.min(minY, lm.y);
      maxY = Math.max(maxY, lm.y);
      validCount++;
    }

    if (validCount < 2 || minX >= maxX || minY >= maxY) {
      return { area: 0, width: 0, height: 0, validCount };
    }

    const width = maxX - minX;
    const height = maxY - minY;
    return { area: width * height, width, height, validCount };
  }

  // Detect visualization mode based on visible landmarks and face coverage
  // Uses hysteresis to prevent jittery transitions
  function detectVisualizationMode(landmarks: any[], sensorId: string, minVisibility = 0.3): "full" | "face" {
    // Get or initialize mode state for this sensor
    let state = sensorModeState.get(sensorId);
    if (!state) {
      state = { currentMode: "full", modeCounter: 0 };
      sensorModeState.set(sensorId, state);
    }

    const isVisible = (idx: number) => {
      const lm = landmarks[idx];
      return lm && (lm.v ?? 1) >= minVisibility;
    };

    const countVisible = (indices: number[]) => indices.filter(isVisible).length;

    const faceVisible = countVisible(FACE_INDICES);
    const shouldersVisible = countVisible(SHOULDER_INDICES);
    const lowerArmsVisible = countVisible(LOWER_ARM_INDICES);
    const hipsVisible = countVisible(HIP_INDICES);
    const legsVisible = countVisible(LEG_INDICES);

    const hasFace = faceVisible >= 3;

    // Require more substantial body evidence
    const hasSubstantialBody = lowerArmsVisible >= 2 || hipsVisible >= 1 || legsVisible >= 2;

    // Determine what mode the current frame suggests
    let suggestedMode: "full" | "face" = "full";

    // Clear case: only face + maybe shoulders/elbows, no hands/hips/legs
    if (hasFace && !hasSubstantialBody) {
      suggestedMode = "face";
    } else if (!hasFace) {
      suggestedMode = "full";
    } else {
      // Calculate face coverage for hysteresis-based decision
      const allIndices: number[] = [];
      for (let i = 0; i < landmarks.length; i++) {
        if (isVisible(i)) allIndices.push(i);
      }

      const faceBbox = calculateBoundingBoxArea(landmarks, FACE_INDICES, minVisibility);
      const totalBbox = calculateBoundingBoxArea(landmarks, allIndices, minVisibility);

      if (totalBbox.area > 0 && faceBbox.area > 0) {
        const faceCoverage = faceBbox.area / totalBbox.area;

        if (state.currentMode === "full") {
          if (faceCoverage > FACE_COVERAGE_ENTER_THRESHOLD && shouldersVisible >= 1) {
            suggestedMode = "face";
          }
        } else {
          if (faceCoverage < FACE_COVERAGE_EXIT_THRESHOLD && hasSubstantialBody) {
            suggestedMode = "full";
          } else {
            suggestedMode = "face";
          }
        }
      }
    }

    // Apply stability threshold (hysteresis)
    if (suggestedMode === state.currentMode) {
      state.modeCounter = 0;
      return state.currentMode;
    }

    state.modeCounter++;
    const threshold = suggestedMode === "face"
      ? MODE_STABILITY_THRESHOLD_TO_FACE
      : MODE_STABILITY_THRESHOLD_TO_FULL;

    if (state.modeCounter >= threshold) {
      state.currentMode = suggestedMode;
      state.modeCounter = 0;
    }

    return state.currentMode;
  }

  // Colors for different body parts
  const BODY_COLORS = {
    face: "#8b5cf6",      // purple
    torso: "#3b82f6",     // blue
    leftArm: "#22c55e",   // green
    rightArm: "#ef4444",  // red
    leftLeg: "#22c55e",   // green
    rightLeg: "#ef4444",  // red
    // Face detail colors for enhanced visualization
    nose: "#f472b6",      // pink
    leftEye: "#60a5fa",   // light blue
    rightEye: "#34d399",  // light green
    mouth: "#fbbf24",     // amber
    ears: "#a78bfa",      // light purple
    jawline: "#fb923c"    // orange
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
  function getLandmarkBounds(landmarks: any[], mode: "full" | "face" = "full"): { minX: number; maxX: number; minY: number; maxY: number } | null {
    let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
    let hasVisible = false;

    // In face mode, only consider face landmarks for bounding box
    const indicesToConsider = mode === "face" ? FACE_INDICES : null;

    for (let i = 0; i < landmarks.length; i++) {
      const lm = landmarks[i];
      if (!lm || (lm.v ?? 1) < 0.3) continue;

      // Skip non-face landmarks in face mode
      if (indicesToConsider && !indicesToConsider.includes(i)) continue;

      hasVisible = true;
      minX = Math.min(minX, lm.x);
      maxX = Math.max(maxX, lm.x);
      minY = Math.min(minY, lm.y);
      maxY = Math.max(maxY, lm.y);
    }

    if (!hasVisible) return null;
    return { minX, maxX, minY, maxY };
  }

  // Wrapper function that chooses the best face drawing method
  function drawFace(
    ctx: CanvasRenderingContext2D,
    landmarks: any[],
    faceLandmarks: any[] | null | undefined,
    blendshapes: any,
    toCanvasX: (x: number) => number,
    toCanvasY: (y: number) => number,
    scale: number
  ) {
    // Prefer detailed face mesh if available (468 landmarks)
    if (faceLandmarks && faceLandmarks.length >= 468) {
      drawFaceMesh(ctx, faceLandmarks, toCanvasX, toCanvasY, scale, blendshapes);
    } else {
      // Fall back to pose-based face drawing (11 landmarks)
      drawFaceFromPose(ctx, landmarks, toCanvasX, toCanvasY, scale);
    }
  }

  function drawSkeleton(
    landmarks: any[],
    areaX: number,
    areaY: number,
    areaWidth: number,
    areaHeight: number,
    sensorColor: string,
    sensorId: string,
    username?: string,
    faceLandmarks?: any[],
    blendshapes?: any,
    dataMode?: string
  ) {
    if (!ctx || !landmarks || landmarks.length === 0) return;

    // Detect visualization mode (full skeleton or face-only)
    // Prefer the mode sent by the client if available
    const mode = dataMode || detectVisualizationMode(landmarks, sensorId);

    // Calculate actual bounding box based on mode
    const bounds = getLandmarkBounds(landmarks, mode);
    if (!bounds) return;

    const { minX, maxX, minY, maxY } = bounds;
    const skeletonWidth = maxX - minX;
    const skeletonHeight = maxY - minY;

    // Reserve space for label
    const labelHeight = 25;
    const drawHeight = areaHeight - labelHeight;

    // Calculate center of skeleton in normalized coords
    const skeletonCenterX = (minX + maxX) / 2;
    const skeletonCenterY = (minY + maxY) / 2;

    // Add padding (more for face mode)
    const padding = mode === "face" ? 0.15 : 0.1;
    const availableWidth = areaWidth * (1 - 2 * padding);
    const availableDrawHeight = drawHeight * (1 - 2 * padding);

    // Scale to fit while maintaining aspect ratio
    // Formula matches SkeletonVisualization.svelte: availableSize / (bboxSize * canvasSize)
    const scaleX = availableWidth / (skeletonWidth * areaWidth);
    const scaleY = availableDrawHeight / (skeletonHeight * drawHeight);
    // Cap the zoom - higher for face mode since face is small
    const maxZoom = mode === "face" ? 4.0 : 2.5;
    const scale = Math.min(scaleX, scaleY, maxZoom);

    // Calculate offset to center the skeleton in the drawing area
    // Offset formula: (areaCenter) - (skeletonCenter * areaSize * scale)
    const offsetX = (areaX + areaWidth / 2) - (skeletonCenterX * areaWidth * scale);
    const offsetY = (areaY + drawHeight / 2) - (skeletonCenterY * drawHeight * scale);

    // Transform function: normalized coords -> canvas coords
    // Same formula as SkeletonVisualization: x * size * scale + offset
    const toCanvasX = (x: number) => x * areaWidth * scale + offsetX;
    const toCanvasY = (y: number) => y * drawHeight * scale + offsetY;

    // Full body mode: draw body skeleton with proper limb thickness
    if (mode === "full") {
      // Calculate body scale for proportional limb thickness
      // Use shoulder width as reference for sizing
      const leftShoulder = landmarks[11];
      const rightShoulder = landmarks[12];
      let bodyScale = 1;
      if (leftShoulder && rightShoulder && (leftShoulder.v ?? 1) > 0.3 && (rightShoulder.v ?? 1) > 0.3) {
        const shoulderWidth = Math.abs(toCanvasX(rightShoulder.x) - toCanvasX(leftShoulder.x));
        bodyScale = Math.max(0.5, Math.min(2.0, shoulderWidth / 80));
      }

      // Limb thickness varies by body part (thicker for torso/thighs, thinner for forearms/calves)
      const baseThickness = 4;
      const getLimbThickness = (start: number, end: number) => {
        // Torso connections (shoulders, hips) - thickest
        if ([11, 12, 23, 24].includes(start) && [11, 12, 23, 24].includes(end)) {
          return baseThickness * bodyScale * 1.4;
        }
        // Upper arms and thighs - thick
        if ([11, 13].includes(start) && [11, 13].includes(end)) return baseThickness * bodyScale * 1.2;
        if ([12, 14].includes(start) && [12, 14].includes(end)) return baseThickness * bodyScale * 1.2;
        if ([23, 25].includes(start) && [23, 25].includes(end)) return baseThickness * bodyScale * 1.3;
        if ([24, 26].includes(start) && [24, 26].includes(end)) return baseThickness * bodyScale * 1.3;
        // Forearms and calves - medium
        if ([13, 15].includes(start) && [13, 15].includes(end)) return baseThickness * bodyScale * 1.0;
        if ([14, 16].includes(start) && [14, 16].includes(end)) return baseThickness * bodyScale * 1.0;
        if ([25, 27].includes(start) && [25, 27].includes(end)) return baseThickness * bodyScale * 1.1;
        if ([26, 28].includes(start) && [26, 28].includes(end)) return baseThickness * bodyScale * 1.1;
        // Hands and feet - thinner
        return baseThickness * bodyScale * 0.7;
      };

      ctx.lineCap = "round";
      ctx.lineJoin = "round";

      // First pass: draw limb connections with proper thickness
      for (const [start, end] of POSE_CONNECTIONS) {
        // Skip face connections - we'll draw the face separately
        if (start <= 10 && end <= 10) continue;

        const startLm = landmarks[start];
        const endLm = landmarks[end];

        if (!startLm || !endLm) continue;

        const minVisibility = 0.3;
        if ((startLm.v ?? 1) < minVisibility || (endLm.v ?? 1) < minVisibility) continue;

        const x1 = toCanvasX(startLm.x);
        const y1 = toCanvasY(startLm.y);
        const x2 = toCanvasX(endLm.x);
        const y2 = toCanvasY(endLm.y);

        ctx.lineWidth = getLimbThickness(start, end);
        ctx.strokeStyle = getConnectionColor(start, end);
        ctx.globalAlpha = Math.min(startLm.v ?? 1, endLm.v ?? 1) * 0.9;
        ctx.beginPath();
        ctx.moveTo(x1, y1);
        ctx.lineTo(x2, y2);
        ctx.stroke();
      }

      // Second pass: draw joints at key body points for better definition
      ctx.globalAlpha = 1;
      const jointRadius = 4;
      const smallJointRadius = 2.5;

      // Major joints: shoulders, elbows, wrists, hips, knees, ankles
      const majorJoints = [11, 12, 13, 14, 15, 16, 23, 24, 25, 26, 27, 28];
      // Minor joints: hands and feet details
      const minorJoints = [17, 18, 19, 20, 21, 22, 29, 30, 31, 32];

      // Draw major joints with larger circles and highlight effect
      for (const i of majorJoints) {
        const lm = landmarks[i];
        if (!lm || (lm.v ?? 1) < 0.3) continue;

        const x = toCanvasX(lm.x);
        const y = toCanvasY(lm.y);

        let color = BODY_COLORS.torso;
        if ([11, 13, 15].includes(i)) color = BODY_COLORS.leftArm;
        else if ([12, 14, 16].includes(i)) color = BODY_COLORS.rightArm;
        else if ([23, 25, 27].includes(i)) color = BODY_COLORS.leftLeg;
        else if ([24, 26, 28].includes(i)) color = BODY_COLORS.rightLeg;

        // Draw joint with slight highlight effect
        ctx.globalAlpha = lm.v ?? 1;

        // Outer ring (main color)
        ctx.fillStyle = color;
        ctx.beginPath();
        ctx.arc(x, y, jointRadius * bodyScale, 0, Math.PI * 2);
        ctx.fill();

        // Inner highlight
        ctx.fillStyle = "#ffffff";
        ctx.globalAlpha = (lm.v ?? 1) * 0.3;
        ctx.beginPath();
        ctx.arc(x - jointRadius * bodyScale * 0.2, y - jointRadius * bodyScale * 0.2,
                jointRadius * bodyScale * 0.4, 0, Math.PI * 2);
        ctx.fill();
      }

      // Draw minor joints (hands/feet) with smaller circles
      ctx.globalAlpha = 1;
      for (const i of minorJoints) {
        const lm = landmarks[i];
        if (!lm || (lm.v ?? 1) < 0.3) continue;

        const x = toCanvasX(lm.x);
        const y = toCanvasY(lm.y);

        let color = BODY_COLORS.torso;
        if ([17, 19, 21].includes(i)) color = BODY_COLORS.leftArm;
        else if ([18, 20, 22].includes(i)) color = BODY_COLORS.rightArm;
        else if ([29, 31].includes(i)) color = BODY_COLORS.leftLeg;
        else if ([30, 32].includes(i)) color = BODY_COLORS.rightLeg;

        ctx.fillStyle = color;
        ctx.globalAlpha = lm.v ?? 1;
        ctx.beginPath();
        ctx.arc(x, y, smallJointRadius * bodyScale, 0, Math.PI * 2);
        ctx.fill();
      }
    }

    // Always draw the face visualization (in both face and full body modes)
    // Uses detailed 468 face mesh when available, otherwise falls back to pose landmarks
    drawFace(ctx, landmarks, faceLandmarks, blendshapes, toCanvasX, toCanvasY, scale);

    ctx.globalAlpha = 1;

    // Draw sensor label at bottom of area
    const labelY = areaY + areaHeight - 8;
    const labelCenterX = areaX + areaWidth / 2;
    const displayLabel = username || sensorId;
    const truncatedLabel = displayLabel.length > 25 ? displayLabel.slice(0, 22) + "..." : displayLabel;

    // Add mode indicator for face mode
    const modeIndicator = mode === "face" ? " (face)" : "";
    const fullLabel = truncatedLabel + modeIndicator;

    ctx.font = "11px sans-serif";
    const textWidth = ctx.measureText(fullLabel).width;

    // Draw colored dot to the left of the label
    ctx.fillStyle = sensorColor;
    ctx.beginPath();
    ctx.arc(labelCenterX - textWidth / 2 - 10, labelY - 4, 5, 0, Math.PI * 2);
    ctx.fill();

    // Draw label
    ctx.fillStyle = "#9ca3af";
    ctx.textAlign = "center";
    ctx.fillText(fullLabel, labelCenterX, labelY);
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

    // Only render sensors that have actual skeleton data
    // (sensors prop is used for metadata like username/bpm, but doesn't determine rendering)
    const activeSensorIds = new Set<string>();
    skeletonData.forEach((data, id) => {
      // Only include if they have valid smoothed landmarks for rendering
      if (data.smoothedLandmarks && data.smoothedLandmarks.length > 0) {
        activeSensorIds.add(id);
      }
    });

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

      if (data && data.smoothedLandmarks && data.smoothedLandmarks.length > 0) {
        // Use smoothed landmarks for jitter-free rendering
        drawSkeleton(data.smoothedLandmarks, areaX, areaY, areaWidth, areaHeight, color, sensorId, username, data.smoothedFaceLandmarks, data.blendshapes, data.mode);

        // Draw heart if BPM available - position relative to skeleton bounds
        if (bpm > 0) {
          const bounds = getLandmarkBounds(data.smoothedLandmarks);
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

        if (data && data.smoothedLandmarks && data.smoothedLandmarks.length > 0) {
          // Use smoothed landmarks for jitter-free rendering
          drawSkeleton(data.smoothedLandmarks, areaX, areaY, areaWidth, areaHeight, color, sensorId, username, data.smoothedFaceLandmarks, data.blendshapes, data.mode);

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

        // Apply jitter filtering (EMA smoothing)
        const smoothedLandmarks = smoothLandmarks(
          data.landmarks,
          existing?.smoothedLandmarks,
          BODY_SMOOTHING_ALPHA
        );

        // Apply stronger smoothing to face landmarks (they're more jittery)
        const smoothedFaceLandmarks = data.faceLandmarks
          ? smoothLandmarks(data.faceLandmarks, existing?.smoothedFaceLandmarks, FACE_SMOOTHING_ALPHA)
          : undefined;

        skeletonData.set(sensor_id, {
          landmarks: data.landmarks,
          smoothedLandmarks: smoothedLandmarks,
          faceLandmarks: data.faceLandmarks,
          smoothedFaceLandmarks: smoothedFaceLandmarks,
          blendshapes: data.blendshapes,
          mode: data.mode,
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

        // Apply jitter filtering (EMA smoothing)
        const smoothedLandmarks = smoothLandmarks(
          data.landmarks,
          existing?.smoothedLandmarks,
          BODY_SMOOTHING_ALPHA
        );

        // Apply stronger smoothing to face landmarks (they're more jittery)
        const smoothedFaceLandmarks = data.faceLandmarks
          ? smoothLandmarks(data.faceLandmarks, existing?.smoothedFaceLandmarks, FACE_SMOOTHING_ALPHA)
          : undefined;

        skeletonData.set(eventSensorId, {
          landmarks: data.landmarks,
          smoothedLandmarks: smoothedLandmarks,
          faceLandmarks: data.faceLandmarks,
          smoothedFaceLandmarks: smoothedFaceLandmarks,
          blendshapes: data.blendshapes,
          mode: data.mode,
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

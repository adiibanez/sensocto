<script>
    import { onMount, onDestroy } from "svelte";

    export let sensor_id;
    export let attribute_id;
    export let size = "normal"; // "small" for summary mode, "normal" for full mode

    let canvas;
    let ctx;
    let lastData = null;

    // Throttling: only render on animation frame, drop intermediate updates
    let pendingData = null;
    let rafId = null;

    // Mode stability: prevent flickering between modes
    let currentMode = "full";
    let modeCounter = 0;
    const MODE_STABILITY_THRESHOLD = 5; // Need N consecutive frames to switch mode

    // Transform smoothing for stable animation
    let smoothTransform = { scale: 1, offsetX: 0, offsetY: 0 };
    const SMOOTHING_FACTOR = 0.15; // How quickly transform catches up (0-1)

    // MediaPipe Pose landmark indices
    const LANDMARK_NAMES = [
        "nose", "left_eye_inner", "left_eye", "left_eye_outer",
        "right_eye_inner", "right_eye", "right_eye_outer",
        "left_ear", "right_ear", "mouth_left", "mouth_right",
        "left_shoulder", "right_shoulder", "left_elbow", "right_elbow",
        "left_wrist", "right_wrist", "left_pinky", "right_pinky",
        "left_index", "right_index", "left_thumb", "right_thumb",
        "left_hip", "right_hip", "left_knee", "right_knee",
        "left_ankle", "right_ankle", "left_heel", "right_heel",
        "left_foot_index", "right_foot_index"
    ];

    // Connections for drawing the skeleton
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
    const COLORS = {
        face: "#8b5cf6",      // purple
        torso: "#3b82f6",     // blue
        leftArm: "#22c55e",   // green
        rightArm: "#ef4444",  // red
        leftLeg: "#22c55e",   // green
        rightLeg: "#ef4444"   // red
    };

    // Face-only connections - minimal fallback
    const FACE_CONNECTIONS = [
        [9, 10],  // mouth line only
    ];

    // MediaPipe Face Mesh landmark indices for key features (468 landmarks)
    // Reference: https://github.com/google/mediapipe/blob/master/mediapipe/modules/face_geometry/data/canonical_face_model_uv_visualization.png
    const FACE_MESH_INDICES = {
        // Face oval contour
        silhouette: [10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379, 378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127, 162, 21, 54, 103, 67, 109],
        // Left eyebrow
        leftEyebrowUpper: [336, 296, 334, 293, 300],
        leftEyebrowLower: [285, 295, 282, 283, 276],
        // Right eyebrow
        rightEyebrowUpper: [107, 66, 105, 63, 70],
        rightEyebrowLower: [55, 65, 52, 53, 46],
        // Left eye contour
        leftEyeUpper: [362, 398, 384, 385, 386, 387, 388, 466, 263],
        leftEyeLower: [263, 249, 390, 373, 374, 380, 381, 382, 362],
        leftIris: [473, 474, 475, 476, 477], // Iris landmarks (when available)
        // Right eye contour
        rightEyeUpper: [133, 173, 157, 158, 159, 160, 161, 246, 33],
        rightEyeLower: [33, 7, 163, 144, 145, 153, 154, 155, 133],
        rightIris: [468, 469, 470, 471, 472], // Iris landmarks (when available)
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
    function drawFaceMesh(faceLandmarks, tx, ty, scale, blendshapes) {
        if (!faceLandmarks || faceLandmarks.length < 468) return;

        const getLm = (idx) => {
            const lm = faceLandmarks[idx];
            if (!lm) return null;
            return { x: tx(lm.x), y: ty(lm.y) };
        };

        // Helper to draw a path through landmark indices
        const drawPath = (indices, closed = false) => {
            const points = indices.map(getLm).filter(p => p !== null);
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

        // Left eyebrow
        drawPath(FACE_MESH_INDICES.leftEyebrowUpper);
        ctx.stroke();

        // Right eyebrow
        drawPath(FACE_MESH_INDICES.rightEyebrowUpper);
        ctx.stroke();

        // 3. Eyes
        ctx.strokeStyle = "#60a5fa";
        ctx.lineWidth = strokeWidth;
        ctx.globalAlpha = 0.9;

        // Left eye outline
        drawPath(FACE_MESH_INDICES.leftEyeUpper);
        ctx.stroke();
        drawPath(FACE_MESH_INDICES.leftEyeLower);
        ctx.stroke();

        // Right eye outline
        drawPath(FACE_MESH_INDICES.rightEyeUpper);
        ctx.stroke();
        drawPath(FACE_MESH_INDICES.rightEyeLower);
        ctx.stroke();

        // Draw iris if available (landmarks 468-477)
        ctx.fillStyle = "#1e293b";
        ctx.globalAlpha = 0.8;

        // Left iris center (index 473)
        const leftIrisCenter = getLm(473);
        if (leftIrisCenter) {
            const irisRadius = faceWidth * 0.025;
            ctx.beginPath();
            ctx.arc(leftIrisCenter.x, leftIrisCenter.y, irisRadius, 0, Math.PI * 2);
            ctx.fill();
        }

        // Right iris center (index 468)
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

        // Outer lips
        ctx.strokeStyle = "#f87171";
        ctx.lineWidth = strokeWidth * 1.3;
        ctx.globalAlpha = 0.85;

        drawPath(FACE_MESH_INDICES.lipsUpperOuter);
        ctx.stroke();
        drawPath(FACE_MESH_INDICES.lipsLowerOuter);
        ctx.stroke();

        // Inner lips (darker when mouth is open)
        if (jawOpen > 0.1) {
            ctx.fillStyle = "#1e293b";
            ctx.globalAlpha = Math.min(0.7, jawOpen);

            // Draw filled inner mouth
            const innerPoints = FACE_MESH_INDICES.lipsUpperInner.concat(
                FACE_MESH_INDICES.lipsLowerInner.slice(1, -1).reverse()
            ).map(getLm).filter(p => p !== null);

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
    function drawFaceFromPose(landmarks, tx, ty, scale) {
        const minVisibility = 0.3;
        const getLm = (idx) => {
            const lm = landmarks[idx];
            if (!lm || (lm.v ?? 1) < minVisibility) return null;
            return { x: tx(lm.x), y: ty(lm.y), v: lm.v ?? 1 };
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

            ctx.strokeStyle = "#a78bfa";
            ctx.lineWidth = strokeWidth * 1.2;
            ctx.globalAlpha = 0.6;
            ctx.beginPath();
            ctx.ellipse(centerX, centerY, radiusX, radiusY, 0, 0, Math.PI * 2);
            ctx.stroke();
        }

        // 2. Draw eyebrows (curved arcs above eyes)
        ctx.strokeStyle = "#d4d4d8";
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
        ctx.fillStyle = "#60a5fa";
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

            ctx.strokeStyle = "#f472b6";
            ctx.lineWidth = strokeWidth;
            ctx.globalAlpha = 0.7;

            ctx.beginPath();
            const noseBridgeY = nose.y - noseHeight * 0.3;
            ctx.moveTo(nose.x, noseBridgeY);
            ctx.lineTo(nose.x, nose.y);
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

            // Normalize openness based on corner positions
            const openRatio = Math.min(1, (cornerVerticalDiff / mouthWidth) * 3 +
                                         Math.max(0, (noseToMouthDist - eyeWidth * 0.8) / eyeWidth) * 0.5);
            const mouthOpenness = openRatio * mouthWidth * 0.4;

            ctx.strokeStyle = "#f87171";
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
                ctx.fillStyle = "#1e293b";
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

    // Wrapper function that chooses the best face drawing method
    function drawFace(landmarks, faceLandmarks, blendshapes, tx, ty, scale) {
        // Prefer detailed face mesh if available (468 landmarks)
        if (faceLandmarks && faceLandmarks.length >= 468) {
            drawFaceMesh(faceLandmarks, tx, ty, scale, blendshapes);
        } else {
            // Fall back to pose-based face drawing (11 landmarks)
            drawFaceFromPose(landmarks, tx, ty, scale);
        }
    }

    // Landmark indices for body part detection
    const FACE_INDICES = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10];
    const SHOULDER_INDICES = [11, 12];
    const UPPER_ARM_INDICES = [13, 14]; // elbows
    const LOWER_ARM_INDICES = [15, 16, 17, 18, 19, 20, 21, 22]; // wrists and hands
    const HIP_INDICES = [23, 24];
    const LEG_INDICES = [25, 26, 27, 28, 29, 30, 31, 32];

    // Detect visualization mode based on visible landmarks
    // Switch to face mode when only upper body (shoulders + elbows) is visible
    // Show full mode when hands/wrists, hips, or legs are visible
    function detectVisualizationMode(landmarks, minVisibility = 0.3) {
        const isVisible = (idx) => {
            const lm = landmarks[idx];
            return lm && (lm.v ?? 1) >= minVisibility;
        };

        const countVisible = (indices) => indices.filter(isVisible).length;

        const faceVisible = countVisible(FACE_INDICES);
        const lowerArmsVisible = countVisible(LOWER_ARM_INDICES);
        const hipsVisible = countVisible(HIP_INDICES);
        const legsVisible = countVisible(LEG_INDICES);

        const hasFace = faceVisible >= 3;

        // Show full mode if we have meaningful body parts beyond just shoulders/elbows:
        // - Any wrists/hands visible (lower arms)
        // - Any hips visible
        // - Any legs visible
        const hasSubstantialBody = lowerArmsVisible >= 1 || hipsVisible >= 1 || legsVisible >= 1;

        // Face mode: only face + maybe shoulders/elbows, but no hands/hips/legs
        if (hasFace && !hasSubstantialBody) {
            return "face";
        }

        return "full";
    }

    function getConnectionColor(start, end) {
        // Face connections (indices 0-10)
        if (start <= 10 && end <= 10) return COLORS.face;
        // Torso (11, 12, 23, 24)
        if ([11, 12, 23, 24].includes(start) && [11, 12, 23, 24].includes(end)) return COLORS.torso;
        // Left arm (11, 13, 15, 17, 19, 21)
        if ([11, 13, 15, 17, 19, 21].includes(start) && [11, 13, 15, 17, 19, 21].includes(end)) return COLORS.leftArm;
        // Right arm (12, 14, 16, 18, 20, 22)
        if ([12, 14, 16, 18, 20, 22].includes(start) && [12, 14, 16, 18, 20, 22].includes(end)) return COLORS.rightArm;
        // Left leg (23, 25, 27, 29, 31)
        if ([23, 25, 27, 29, 31].includes(start) && [23, 25, 27, 29, 31].includes(end)) return COLORS.leftLeg;
        // Right leg (24, 26, 28, 30, 32)
        if ([24, 26, 28, 30, 32].includes(start) && [24, 26, 28, 30, 32].includes(end)) return COLORS.rightLeg;
        return COLORS.torso;
    }

    // Calculate bounding box and transform to center and maximize skeleton
    function calculateTransform(landmarks, width, height, mode = "full") {
        const minVisibility = 0.3;
        let minX = Infinity, maxX = -Infinity;
        let minY = Infinity, maxY = -Infinity;
        let validCount = 0;

        // In face mode, only consider face landmarks for bounding box
        const indicesToConsider = mode === "face" ? FACE_INDICES : null;

        for (let i = 0; i < landmarks.length; i++) {
            const lm = landmarks[i];
            if (!lm || (lm.v ?? 1) < minVisibility) continue;

            // Skip non-face landmarks in face mode
            if (indicesToConsider && !indicesToConsider.includes(i)) continue;

            minX = Math.min(minX, lm.x);
            maxX = Math.max(maxX, lm.x);
            minY = Math.min(minY, lm.y);
            maxY = Math.max(maxY, lm.y);
            validCount++;
        }

        if (validCount < 2 || minX >= maxX || minY >= maxY) {
            // Fallback: no valid transform, use identity
            return { scale: 1, offsetX: 0, offsetY: 0 };
        }

        const bboxWidth = maxX - minX;
        const bboxHeight = maxY - minY;
        const centerX = (minX + maxX) / 2;
        const centerY = (minY + maxY) / 2;

        // Add padding (15% for face mode to give more breathing room, 10% otherwise)
        const padding = mode === "face" ? 0.15 : 0.1;
        const availableWidth = width * (1 - 2 * padding);
        const availableHeight = height * (1 - 2 * padding);

        // Scale to fit while maintaining aspect ratio
        const scaleX = availableWidth / (bboxWidth * width);
        const scaleY = availableHeight / (bboxHeight * height);
        // Higher max zoom for face mode (4x) since face is small
        const maxZoom = mode === "face" ? 4.0 : 2.5;
        const scale = Math.min(scaleX, scaleY, maxZoom);

        // Calculate offset to center the skeleton
        const offsetX = (width / 2) - (centerX * width * scale);
        const offsetY = (height / 2) - (centerY * height * scale);

        return { scale, offsetX, offsetY };
    }

    // Stabilize mode to prevent flickering
    function getStableMode(detectedMode) {
        if (detectedMode === currentMode) {
            modeCounter = 0;
            return currentMode;
        }

        modeCounter++;
        if (modeCounter >= MODE_STABILITY_THRESHOLD) {
            currentMode = detectedMode;
            modeCounter = 0;
        }

        return currentMode;
    }

    // Smooth transform interpolation
    function smoothenTransform(targetTransform) {
        smoothTransform.scale += (targetTransform.scale - smoothTransform.scale) * SMOOTHING_FACTOR;
        smoothTransform.offsetX += (targetTransform.offsetX - smoothTransform.offsetX) * SMOOTHING_FACTOR;
        smoothTransform.offsetY += (targetTransform.offsetY - smoothTransform.offsetY) * SMOOTHING_FACTOR;

        return { ...smoothTransform };
    }

    function drawSkeleton(data) {
        if (!ctx || !canvas) return;

        const width = canvas.width;
        const height = canvas.height;

        // Clear canvas
        ctx.fillStyle = "#1f2937";
        ctx.fillRect(0, 0, width, height);

        if (!data || !data.landmarks || data.landmarks.length === 0) {
            // Draw placeholder text
            ctx.fillStyle = "#6b7280";
            ctx.font = size === "small" ? "10px sans-serif" : "12px sans-serif";
            ctx.textAlign = "center";
            ctx.fillText("No pose detected", width / 2, height / 2);
            return;
        }

        const landmarks = data.landmarks;
        const faceLandmarks = data.faceLandmarks || null;
        const blendshapes = data.blendshapes || null;
        const dataMode = data.mode || null; // "full" or "face" from hybrid client

        // Detect visualization mode (full skeleton or face-only) with stability
        // Prefer the mode sent by the client if available
        const detectedMode = dataMode || detectVisualizationMode(landmarks);
        const mode = getStableMode(detectedMode);

        // Calculate auto-centering transform based on mode, then smooth it
        const targetTransform = calculateTransform(landmarks, width, height, mode);
        const transform = smoothenTransform(targetTransform);

        // Helper to transform coordinates
        const tx = (x) => x * width * transform.scale + transform.offsetX;
        const ty = (y) => y * height * transform.scale + transform.offsetY;

        // Full body mode: draw body skeleton connections (skip face connections)
        if (mode === "full") {
            ctx.lineWidth = size === "small" ? 1.5 : 2;

            for (const [start, end] of POSE_CONNECTIONS) {
                // Skip face connections - we'll draw the face separately
                if (start <= 10 && end <= 10) continue;

                const startLm = landmarks[start];
                const endLm = landmarks[end];

                if (!startLm || !endLm) continue;

                const minVisibility = 0.3;
                if ((startLm.v ?? 1) < minVisibility || (endLm.v ?? 1) < minVisibility) continue;

                const x1 = tx(startLm.x);
                const y1 = ty(startLm.y);
                const x2 = tx(endLm.x);
                const y2 = ty(endLm.y);

                ctx.strokeStyle = getConnectionColor(start, end);
                ctx.globalAlpha = Math.min(startLm.v ?? 1, endLm.v ?? 1);
                ctx.beginPath();
                ctx.moveTo(x1, y1);
                ctx.lineTo(x2, y2);
                ctx.stroke();
            }

            // Draw body landmark points (skip face landmarks - indices 0-10)
            ctx.globalAlpha = 1;
            const pointRadius = size === "small" ? 2 : 3;

            for (let i = 11; i < landmarks.length; i++) {
                const lm = landmarks[i];
                if (!lm || (lm.v ?? 1) < 0.3) continue;

                const x = tx(lm.x);
                const y = ty(lm.y);

                let color = COLORS.torso;
                if ([11, 13, 15, 17, 19, 21].includes(i)) color = COLORS.leftArm;
                else if ([12, 14, 16, 18, 20, 22].includes(i)) color = COLORS.rightArm;
                else if ([23, 25, 27, 29, 31].includes(i)) color = COLORS.leftLeg;
                else if ([24, 26, 28, 30, 32].includes(i)) color = COLORS.rightLeg;

                ctx.fillStyle = color;
                ctx.globalAlpha = lm.v ?? 1;
                ctx.beginPath();
                ctx.arc(x, y, pointRadius, 0, Math.PI * 2);
                ctx.fill();
            }
        }

        // Always draw the face visualization (in both face and full body modes)
        // Uses detailed 468 face mesh when available, otherwise falls back to pose landmarks
        drawFace(landmarks, faceLandmarks, blendshapes, tx, ty, transform.scale);

        ctx.globalAlpha = 1;
    }

    // Throttled render using requestAnimationFrame
    // Only renders at most once per frame, dropping intermediate updates
    function scheduleRender(data) {
        pendingData = data;

        if (rafId === null) {
            rafId = requestAnimationFrame(() => {
                rafId = null;
                if (pendingData !== null) {
                    lastData = pendingData;
                    drawSkeleton(pendingData);
                    pendingData = null;
                }
            });
        }
    }

    function handleAccumulatorEvent(event) {
        // Check if this event is for our sensor and attribute
        if (event.detail?.sensor_id !== sensor_id || event.detail?.attribute_id !== attribute_id) {
            return;
        }

        const eventData = event.detail?.data;
        if (!eventData) return;

        // Handle multiple data formats:
        // 1. Array of measurements: [{timestamp, payload}, ...] (from measurements_batch)
        // 2. Single measurement: {timestamp, payload} (from measurement event)
        // 3. Direct payload: {landmarks: [...]}
        let payload;
        if (Array.isArray(eventData)) {
            // Batch format - get the latest measurement's payload
            const latest = eventData[eventData.length - 1];
            payload = latest?.payload;
        } else if (eventData.payload !== undefined) {
            // Single measurement format
            payload = eventData.payload;
        } else {
            // Direct payload format
            payload = eventData;
        }

        if (!payload) return;

        try {
            const data = typeof payload === "string" ? JSON.parse(payload) : payload;
            // Use throttled render instead of immediate draw
            scheduleRender(data);
        } catch (e) {
            console.error("SkeletonVisualization: Failed to parse data", e);
        }
    }

    onMount(() => {
        if (canvas) {
            ctx = canvas.getContext("2d");
            drawSkeleton(null); // Draw placeholder
        }

        // Listen for accumulator-data-event on window (same pattern as ECGVisualization)
        window.addEventListener("accumulator-data-event", handleAccumulatorEvent);
    });

    onDestroy(() => {
        window.removeEventListener("accumulator-data-event", handleAccumulatorEvent);
        // Cancel any pending animation frame
        if (rafId !== null) {
            cancelAnimationFrame(rafId);
            rafId = null;
        }
    });

    // Expose method to update from parent
    export function updateSkeleton(payload) {
        handleAccumulatorEvent({ detail: { sensor_id, attribute_id, data: { payload } }});
    }

    $: canvasSize = size === "small" ? { width: 80, height: 80 } : { width: 300, height: 300 };
</script>

<div class="skeleton-container">
    <canvas
        bind:this={canvas}
        width={canvasSize.width}
        height={canvasSize.height}
        class="rounded bg-gray-800"
    ></canvas>
</div>

<style>
    .skeleton-container {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 100%;
        height: 100%;
    }

    canvas {
        max-width: 100%;
        max-height: 100%;
    }

    canvas {
        image-rendering: crisp-edges;
    }
</style>

<script>
    import { onMount, onDestroy } from "svelte";

    export let sensor_id;
    export let attribute_id;
    export let size = "normal"; // "small" for summary mode, "normal" for full mode

    let canvas;
    let ctx;
    let lastData = null;

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

        // Draw connections first (so points appear on top)
        ctx.lineWidth = size === "small" ? 1.5 : 2;
        for (const [start, end] of POSE_CONNECTIONS) {
            const startLm = landmarks[start];
            const endLm = landmarks[end];

            if (!startLm || !endLm) continue;

            // Skip low visibility landmarks
            const minVisibility = 0.3;
            if ((startLm.v ?? 1) < minVisibility || (endLm.v ?? 1) < minVisibility) continue;

            const x1 = startLm.x * width;
            const y1 = startLm.y * height;
            const x2 = endLm.x * width;
            const y2 = endLm.y * height;

            ctx.strokeStyle = getConnectionColor(start, end);
            ctx.globalAlpha = Math.min(startLm.v ?? 1, endLm.v ?? 1);
            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.lineTo(x2, y2);
            ctx.stroke();
        }

        // Draw landmark points
        ctx.globalAlpha = 1;
        const pointRadius = size === "small" ? 2 : 3;

        for (let i = 0; i < landmarks.length; i++) {
            const lm = landmarks[i];
            if (!lm || (lm.v ?? 1) < 0.3) continue;

            const x = lm.x * width;
            const y = lm.y * height;

            // Determine color based on landmark index
            let color = COLORS.torso;
            if (i <= 10) color = COLORS.face;
            else if ([11, 13, 15, 17, 19, 21].includes(i)) color = COLORS.leftArm;
            else if ([12, 14, 16, 18, 20, 22].includes(i)) color = COLORS.rightArm;
            else if ([23, 25, 27, 29, 31].includes(i)) color = COLORS.leftLeg;
            else if ([24, 26, 28, 30, 32].includes(i)) color = COLORS.rightLeg;

            ctx.fillStyle = color;
            ctx.globalAlpha = lm.v ?? 1;
            ctx.beginPath();
            ctx.arc(x, y, pointRadius, 0, Math.PI * 2);
            ctx.fill();
        }

        ctx.globalAlpha = 1;
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
            lastData = data;
            drawSkeleton(data);
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
    });

    // Expose method to update from parent
    export function updateSkeleton(payload) {
        handleAccumulatorEvent({ detail: { sensor_id, attribute_id, data: { payload } }});
    }

    $: canvasSize = size === "small" ? { width: 80, height: 80 } : { width: 160, height: 160 };
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
    }

    canvas {
        image-rendering: crisp-edges;
    }
</style>

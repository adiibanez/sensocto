<script>
    import { getContext, onMount, onDestroy } from "svelte";
    import { get } from "svelte/store";
    import { autostart } from "./stores.js";
    import { logger } from "../logger_svelte.js";
    import { PoseLandmarker, FilesetResolver, DrawingUtils } from "@mediapipe/tasks-vision";

    export let compact = false;
    export let videoElementId = "local-video";

    let loggerCtxName = "PoseClient";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    let detecting = false;
    let poseLandmarker = null;
    let animationFrameId = null;

    const TARGET_FPS = 15;
    const FRAME_INTERVAL = 1000 / TARGET_FPS;
    let lastFrameTime = 0;

    async function initPoseLandmarker() {
        try {
            const vision = await FilesetResolver.forVisionTasks(
                "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.18/wasm"
            );

            poseLandmarker = await PoseLandmarker.createFromOptions(vision, {
                baseOptions: {
                    modelAssetPath: "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task",
                    delegate: "GPU"
                },
                runningMode: "VIDEO",
                numPoses: 1,
                minPoseDetectionConfidence: 0.5,
                minPosePresenceConfidence: 0.5,
                minTrackingConfidence: 0.5,
                outputSegmentationMasks: false
            });

            logger.log(loggerCtxName, "PoseLandmarker initialized successfully");
            return true;
        } catch (error) {
            logger.error(loggerCtxName, "Failed to initialize PoseLandmarker:", error);
            return false;
        }
    }

    function findVideoElement() {
        // Try to find the video element inside the video tile
        const container = document.getElementById(videoElementId);
        if (container) {
            const video = container.querySelector("video");
            if (video) return video;
        }

        // Fallback: try direct ID
        const direct = document.getElementById(videoElementId);
        if (direct && direct.tagName === "VIDEO") return direct;

        // Try any video with local in the name
        const localVideo = document.querySelector('[id*="local"] video');
        if (localVideo) return localVideo;

        return null;
    }

    async function startPose() {
        if (detecting) return;

        logger.log(loggerCtxName, "Starting pose detection...");

        // Initialize the pose landmarker if not already done
        if (!poseLandmarker) {
            const success = await initPoseLandmarker();
            if (!success) {
                logger.error(loggerCtxName, "Could not initialize pose landmarker");
                return;
            }
        }

        // Find the video element
        const videoEl = findVideoElement();
        if (!videoEl) {
            logger.error(loggerCtxName, "Could not find video element:", videoElementId);
            return;
        }

        // Wait for video to be ready
        if (videoEl.readyState < 2) {
            logger.log(loggerCtxName, "Waiting for video to be ready...");
            await new Promise((resolve) => {
                videoEl.addEventListener("loadeddata", resolve, { once: true });
            });
        }

        // Setup sensor channel
        sensorService.setupChannel(channelIdentifier);
        sensorService.registerAttribute(channelIdentifier, {
            attribute_id: "pose_skeleton",
            attribute_type: "skeleton",
            sampling_rate: TARGET_FPS
        });

        detecting = true;

        // Start the detection loop
        detectFrame(videoEl);
        logger.log(loggerCtxName, "Pose detection started");
    }

    function detectFrame(videoEl) {
        if (!detecting || !poseLandmarker) return;

        const now = performance.now();

        // Throttle to target FPS
        if (now - lastFrameTime < FRAME_INTERVAL) {
            animationFrameId = requestAnimationFrame(() => detectFrame(videoEl));
            return;
        }
        lastFrameTime = now;

        // Process frame if video is ready (don't check currentTime for live streams)
        if (videoEl.readyState >= 2) {
            try {
                const results = poseLandmarker.detectForVideo(videoEl, now);

                if (results.landmarks && results.landmarks.length > 0) {
                    sendSkeletonData(results);
                }
            } catch (error) {
                logger.error(loggerCtxName, "Detection error:", error);
            }
        }

        animationFrameId = requestAnimationFrame(() => detectFrame(videoEl));
    }

    function sendSkeletonData(results) {
        // Extract the first pose (we're configured for single pose)
        const landmarks = results.landmarks[0];
        const worldLandmarks = results.worldLandmarks?.[0];

        const payload = {
            landmarks: landmarks.map(lm => ({
                x: lm.x,
                y: lm.y,
                z: lm.z,
                v: lm.visibility ?? 1.0
            })),
            worldLandmarks: worldLandmarks?.map(lm => ({
                x: lm.x,
                y: lm.y,
                z: lm.z
            }))
        };

        sensorService.sendChannelMessage(channelIdentifier, {
            payload: JSON.stringify(payload),
            attribute_id: "pose_skeleton",
            timestamp: Date.now()
        });
    }

    function stopPose() {
        if (!detecting) return;

        logger.log(loggerCtxName, "Stopping pose detection...");

        detecting = false;

        if (animationFrameId) {
            cancelAnimationFrame(animationFrameId);
            animationFrameId = null;
        }

        sensorService.unregisterAttribute(channelIdentifier, "pose_skeleton");
        sensorService.leaveChannelIfUnused(channelIdentifier);

        logger.log(loggerCtxName, "Pose detection stopped");
    }

    function togglePose() {
        if (detecting) {
            stopPose();
        } else {
            startPose();
        }
    }

    onMount(() => {
        // Check if autostart is enabled
        const autostartValue = get(autostart);
        if (autostartValue === true) {
            sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Autostart triggered, starting pose detection");
                startPose();
            });
        }
    });

    onDestroy(() => {
        stopPose();
        if (poseLandmarker) {
            poseLandmarker.close();
            poseLandmarker = null;
        }
    });
</script>

{#if compact}
    <button
        onclick={togglePose}
        class="icon-btn"
        class:active={detecting}
        title={detecting ? "Pose detection active" : "Start pose detection"}
    >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
            <path d="M12 2C13.1 2 14 2.9 14 4C14 5.1 13.1 6 12 6C10.9 6 10 5.1 10 4C10 2.9 10.9 2 12 2ZM21 9H15V22H13V16H11V22H9V9H3V7H21V9Z"/>
        </svg>
    </button>
{:else}
    <div class="flex items-center gap-2">
        {#if detecting}
            <button onclick={stopPose} class="btn btn-blue text-xs">Stop Pose</button>
            <span class="text-xs text-gray-400">{TARGET_FPS} FPS</span>
        {:else}
            <button onclick={startPose} class="btn btn-blue text-xs">Start Pose</button>
        {/if}
    </div>
{/if}

<style>
    .icon-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.5rem;
        height: 1.5rem;
        border-radius: 0.375rem;
        background: #374151;
        color: #9ca3af;
        border: none;
        cursor: pointer;
        transition: all 0.15s ease;
    }
    .icon-btn:hover {
        background: #4b5563;
        color: #d1d5db;
    }
    .icon-btn.active {
        background: #8b5cf6;
        color: white;
    }
</style>

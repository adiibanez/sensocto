<script>
    import { getContext, onMount, onDestroy } from "svelte";
    import { get } from "svelte/store";
    import { autostart } from "./stores.js";
    import { logger } from "../logger_svelte.js";
    import { PoseLandmarker, FilesetResolver, DrawingUtils } from "@mediapipe/tasks-vision";

    export let compact = false;
    export let videoElementId = "local-video";
    // When true, will use standalone camera if call video is not available
    export let allowStandalone = true;

    let loggerCtxName = "PoseClient";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    let detecting = false;
    let poseLandmarker = null;
    let animationFrameId = null;

    // Standalone camera management
    let standaloneStream = null;
    let standaloneVideoEl = null;
    let usingStandalone = false;
    let cameraError = null;

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

    function findCallVideoElement() {
        // Try to find the video element from the call system
        const container = document.getElementById(videoElementId);
        if (container) {
            const video = container.querySelector("video");
            if (video && video.srcObject) return video;
        }

        // Fallback: try direct ID
        const direct = document.getElementById(videoElementId);
        if (direct && direct.tagName === "VIDEO" && direct.srcObject) return direct;

        // Try any video with local in the name that has a stream
        const localVideo = document.querySelector('[id*="local"] video');
        if (localVideo && localVideo.srcObject) return localVideo;

        return null;
    }

    async function setupStandaloneCamera() {
        if (standaloneStream) {
            // Already have a stream
            return standaloneVideoEl;
        }

        logger.log(loggerCtxName, "Setting up standalone camera...");
        cameraError = null;

        try {
            standaloneStream = await navigator.mediaDevices.getUserMedia({
                video: {
                    width: { ideal: 640 },
                    height: { ideal: 480 },
                    frameRate: { ideal: TARGET_FPS }
                },
                audio: false
            });

            // Create a hidden video element for pose detection
            // Note: Using position/visibility instead of display:none because
            // MediaPipe requires the video to be rendering frames with actual dimensions
            standaloneVideoEl = document.createElement("video");
            standaloneVideoEl.id = "pose-standalone-video";
            standaloneVideoEl.autoplay = true;
            standaloneVideoEl.playsInline = true;
            standaloneVideoEl.muted = true;
            standaloneVideoEl.width = 640;
            standaloneVideoEl.height = 480;
            standaloneVideoEl.style.position = "fixed";
            standaloneVideoEl.style.top = "-9999px";
            standaloneVideoEl.style.left = "-9999px";
            standaloneVideoEl.style.pointerEvents = "none";
            standaloneVideoEl.srcObject = standaloneStream;
            document.body.appendChild(standaloneVideoEl);

            // Wait for video to be ready and playing
            await new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error("Video load timeout")), 5000);
                standaloneVideoEl.onloadeddata = async () => {
                    clearTimeout(timeout);
                    try {
                        await standaloneVideoEl.play();
                        resolve();
                    } catch (e) {
                        reject(e);
                    }
                };
                standaloneVideoEl.onerror = (e) => {
                    clearTimeout(timeout);
                    reject(e);
                };
            });

            logger.log(loggerCtxName, "Standalone camera ready");
            return standaloneVideoEl;
        } catch (error) {
            logger.error(loggerCtxName, "Failed to setup standalone camera:", error);
            cameraError = getCameraErrorMessage(error);
            cleanupStandaloneCamera();
            return null;
        }
    }

    function getCameraErrorMessage(error) {
        const name = error?.name || "";
        if (name === "NotAllowedError" || name === "PermissionDeniedError") {
            return "Camera access denied. Please allow camera permissions.";
        }
        if (name === "NotFoundError" || name === "DevicesNotFoundError") {
            return "No camera found. Please connect a camera.";
        }
        if (name === "NotReadableError" || name === "TrackStartError") {
            return "Camera is in use by another application.";
        }
        return error?.message || "Failed to access camera.";
    }

    function cleanupStandaloneCamera() {
        if (standaloneStream) {
            standaloneStream.getTracks().forEach(track => track.stop());
            standaloneStream = null;
        }
        if (standaloneVideoEl) {
            standaloneVideoEl.srcObject = null;
            standaloneVideoEl.remove();
            standaloneVideoEl = null;
        }
        usingStandalone = false;
    }

    async function getVideoSource() {
        // First, try to use the call video if available
        const callVideo = findCallVideoElement();
        if (callVideo) {
            logger.log(loggerCtxName, "Using call video for pose detection");
            usingStandalone = false;
            return callVideo;
        }

        // If no call video and standalone is allowed, setup standalone camera
        if (allowStandalone) {
            logger.log(loggerCtxName, "No call video found, trying standalone camera");
            const standaloneVideo = await setupStandaloneCamera();
            if (standaloneVideo) {
                usingStandalone = true;
                return standaloneVideo;
            }
        }

        return null;
    }

    async function startPose() {
        if (detecting) return;

        logger.log(loggerCtxName, "Starting pose detection...");
        cameraError = null;

        // Initialize the pose landmarker if not already done
        if (!poseLandmarker) {
            const success = await initPoseLandmarker();
            if (!success) {
                logger.error(loggerCtxName, "Could not initialize pose landmarker");
                return;
            }
        }

        // Get video source (call video or standalone)
        const videoEl = await getVideoSource();
        if (!videoEl) {
            logger.error(loggerCtxName, "Could not find or create video source");
            if (!cameraError) {
                cameraError = "No video source available. Join a call or allow camera access.";
            }
            return;
        }

        // Wait for video to be ready
        if (videoEl.readyState < 2) {
            logger.log(loggerCtxName, "Waiting for video to be ready...");
            await new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error("Video ready timeout")), 10000);
                videoEl.addEventListener("loadeddata", () => {
                    clearTimeout(timeout);
                    resolve();
                }, { once: true });
            }).catch(err => {
                logger.error(loggerCtxName, "Video ready timeout:", err);
                cameraError = "Video source not ready. Please try again.";
                return;
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
        logger.log(loggerCtxName, `Pose detection started (${usingStandalone ? "standalone" : "call"} mode)`);
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

        // Check if video source is still valid
        if (!videoEl.srcObject && !usingStandalone) {
            // Call video was removed, try to switch to standalone
            logger.log(loggerCtxName, "Call video lost, attempting to switch to standalone");
            switchToStandalone();
            return;
        }

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

    async function switchToStandalone() {
        if (!allowStandalone || usingStandalone) return;

        const standaloneVideo = await setupStandaloneCamera();
        if (standaloneVideo) {
            usingStandalone = true;
            logger.log(loggerCtxName, "Switched to standalone camera");
            detectFrame(standaloneVideo);
        } else {
            logger.error(loggerCtxName, "Could not switch to standalone camera, stopping detection");
            stopPose();
        }
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

        // Cleanup standalone camera if we were using it
        cleanupStandaloneCamera();

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
        cleanupStandaloneCamera();
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
        class:standalone={detecting && usingStandalone}
        title={detecting
            ? `Pose detection active (${usingStandalone ? "standalone camera" : "call video"})`
            : "Start pose detection"}
    >
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
            <path d="M12 2C13.1 2 14 2.9 14 4C14 5.1 13.1 6 12 6C10.9 6 10 5.1 10 4C10 2.9 10.9 2 12 2ZM21 9H15V22H13V16H11V22H9V9H3V7H21V9Z"/>
        </svg>
    </button>
    {#if cameraError}
        <span class="text-xs text-red-400 ml-1" title={cameraError}>!</span>
    {/if}
{:else}
    <div class="flex items-center gap-2">
        {#if detecting}
            <button onclick={stopPose} class="btn btn-blue text-xs">Stop Pose</button>
            <span class="text-xs text-gray-400">
                {TARGET_FPS} FPS
                {#if usingStandalone}
                    <span class="text-cyan-400">(standalone)</span>
                {:else}
                    <span class="text-green-400">(call)</span>
                {/if}
            </span>
        {:else}
            <button onclick={startPose} class="btn btn-blue text-xs">Start Pose</button>
            {#if cameraError}
                <span class="text-xs text-red-400">{cameraError}</span>
            {/if}
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
    .icon-btn.active.standalone {
        background: #0891b2;
        color: white;
    }
</style>

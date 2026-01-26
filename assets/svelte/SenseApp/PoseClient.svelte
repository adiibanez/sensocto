<script>
    import { getContext, onMount, onDestroy } from "svelte";
    import { get } from "svelte/store";
    import { autostart, sensorSettings } from "./stores.js";
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

    // Mobile detection for adaptive performance
    const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);

    // Edge browser detection - Edge has issues with MediaPipe GPU delegate (used for FPS adjustment)
    const isEdge = /Edg\//i.test(navigator.userAgent);

    // Lower FPS on mobile to reduce main thread blocking
    // Mobile GPUs struggle with MediaPipe at higher frame rates
    // Edge with CPU delegate also needs lower FPS
    const TARGET_FPS = (isMobile || isEdge) ? 8 : 15;
    const FRAME_INTERVAL = 1000 / TARGET_FPS;
    let lastFrameTime = 0;

    // Skip frames counter for additional throttling under load
    let frameSkipCounter = 0;
    const MOBILE_FRAME_SKIP = isMobile ? 1 : 0; // Skip every other detection on mobile

    // Track which delegate is being used
    let usingDelegate = "GPU";

    async function initPoseLandmarker() {
        try {
            const vision = await FilesetResolver.forVisionTasks(
                "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.18/wasm"
            );

            // Always try GPU first, then fall back to CPU
            try {
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
                usingDelegate = "GPU";
                logger.log(loggerCtxName, "PoseLandmarker initialized with GPU delegate");
                return true;
            } catch (gpuError) {
                // GPU failed, fall back to CPU
                logger.warn(loggerCtxName, `GPU delegate failed, falling back to CPU:`, gpuError);

                poseLandmarker = await PoseLandmarker.createFromOptions(vision, {
                    baseOptions: {
                        modelAssetPath: "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task",
                        delegate: "CPU"
                    },
                    runningMode: "VIDEO",
                    numPoses: 1,
                    minPoseDetectionConfidence: 0.5,
                    minPosePresenceConfidence: 0.5,
                    minTrackingConfidence: 0.5,
                    outputSegmentationMasks: false
                });
                usingDelegate = "CPU";
                logger.log(loggerCtxName, "PoseLandmarker initialized with CPU delegate (fallback)");
                return true;
            }
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

        // Use lower resolution on mobile to reduce GPU/CPU load
        const videoWidth = isMobile ? 320 : 640;
        const videoHeight = isMobile ? 240 : 480;

        try {
            standaloneStream = await navigator.mediaDevices.getUserMedia({
                video: {
                    width: { ideal: videoWidth },
                    height: { ideal: videoHeight },
                    frameRate: { ideal: TARGET_FPS },
                    // Use front camera so user can see themselves while streaming facial landmarks
                    facingMode: "user"
                },
                audio: false
            });

            // Create a hidden video element for pose detection
            // Note: Using clip-path instead of opacity/off-screen because
            // Edge browser needs the video at full dimensions for MediaPipe to work
            standaloneVideoEl = document.createElement("video");
            standaloneVideoEl.id = "pose-standalone-video";
            standaloneVideoEl.autoplay = true;
            standaloneVideoEl.playsInline = true;
            standaloneVideoEl.muted = true;
            standaloneVideoEl.width = videoWidth;
            standaloneVideoEl.height = videoHeight;
            standaloneVideoEl.style.position = "fixed";
            standaloneVideoEl.style.bottom = "0";
            standaloneVideoEl.style.left = "0";
            standaloneVideoEl.style.width = `${videoWidth}px`;
            standaloneVideoEl.style.height = `${videoHeight}px`;
            standaloneVideoEl.style.clipPath = "inset(100%)"; // Clips entire element, making it invisible
            standaloneVideoEl.style.pointerEvents = "none";
            standaloneVideoEl.style.zIndex = "-1";
            standaloneVideoEl.srcObject = standaloneStream;
            document.body.appendChild(standaloneVideoEl);

            // Wait for video to be ready and playing
            // Use canplay event which is more reliable on Android Chrome
            await new Promise((resolve, reject) => {
                const timeout = setTimeout(() => reject(new Error("Video load timeout")), 10000);

                const tryPlay = async () => {
                    clearTimeout(timeout);
                    try {
                        // On Android, play() may need multiple attempts
                        await standaloneVideoEl.play();
                        resolve();
                    } catch (e) {
                        // If autoplay blocked, try again after a short delay
                        if (e.name === "NotAllowedError") {
                            logger.warn(loggerCtxName, "Autoplay blocked, retrying...");
                            setTimeout(async () => {
                                try {
                                    await standaloneVideoEl.play();
                                    resolve();
                                } catch (e2) {
                                    reject(e2);
                                }
                            }, 100);
                        } else {
                            reject(e);
                        }
                    }
                };

                // Try both events - canplay fires earlier and is more reliable on Android
                standaloneVideoEl.oncanplay = tryPlay;
                standaloneVideoEl.onloadeddata = tryPlay;
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

    // Clean up any orphaned video elements from previous instances
    // This handles cases where hot-reload or LiveView reconnection leaves orphaned elements
    function cleanupOrphanedVideos() {
        const orphanedVideos = document.querySelectorAll('#pose-standalone-video');
        orphanedVideos.forEach(video => {
            if (video !== standaloneVideoEl) {
                logger.log(loggerCtxName, "Cleaning up orphaned video element");
                if (video.srcObject) {
                    video.srcObject.getTracks().forEach(track => track.stop());
                }
                video.srcObject = null;
                video.remove();
            }
        });
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

        // Additional frame skipping for mobile - skip detection but still schedule next frame
        // This prevents blocking the main thread with back-to-back ML inference
        if (MOBILE_FRAME_SKIP > 0) {
            frameSkipCounter++;
            if (frameSkipCounter <= MOBILE_FRAME_SKIP) {
                animationFrameId = requestAnimationFrame(() => detectFrame(videoEl));
                return;
            }
            frameSkipCounter = 0;
        }

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
        // Guard: don't send if detection has been stopped
        if (!detecting) {
            logger.log(loggerCtxName, "Skipping send - detection stopped");
            return;
        }

        // Extract the first pose (we're configured for single pose)
        const landmarks = results.landmarks[0];

        // Optimize: reduce precision to 3 decimal places to minimize payload size
        // and reduce JSON serialization overhead on mobile
        const roundTo3 = (n) => Math.round(n * 1000) / 1000;

        // Build payload with reduced precision - skip worldLandmarks on mobile to reduce payload
        const payload = {
            landmarks: landmarks.map(lm => ({
                x: roundTo3(lm.x),
                y: roundTo3(lm.y),
                z: roundTo3(lm.z),
                v: roundTo3(lm.visibility ?? 1.0)
            }))
        };

        // Only include worldLandmarks on desktop (not critical for visualization)
        if (!isMobile && results.worldLandmarks?.[0]) {
            payload.worldLandmarks = results.worldLandmarks[0].map(lm => ({
                x: roundTo3(lm.x),
                y: roundTo3(lm.y),
                z: roundTo3(lm.z)
            }));
        }

        sensorService.sendChannelMessage(channelIdentifier, {
            payload: JSON.stringify(payload),
            attribute_id: "pose_skeleton",
            timestamp: Date.now()
        });
    }

    function stopPose() {
        if (!detecting) return;

        logger.log(loggerCtxName, "Stopping pose detection...");

        // FIRST: Stop the detection loop to prevent new measurements
        detecting = false;

        if (animationFrameId) {
            cancelAnimationFrame(animationFrameId);
            animationFrameId = null;
        }

        // Cleanup standalone camera if we were using it
        cleanupStandaloneCamera();

        // THEN: Unregister the attribute after detection is fully stopped
        // Small delay ensures any in-flight sendSkeletonData calls see detecting=false
        setTimeout(() => {
            sensorService.unregisterAttribute(channelIdentifier, "pose_skeleton");
            // Note: leaveChannelIfUnused is already called by unregisterAttribute after a delay
        }, 50);

        logger.log(loggerCtxName, "Pose detection stopped");
    }

    // Wrapper functions that also persist to localStorage
    function enablePose() {
        sensorSettings.setSensorEnabled('pose', true);
        startPose();
    }

    function disablePose() {
        sensorSettings.setSensorEnabled('pose', false);
        stopPose();
    }

    function togglePose() {
        if (detecting) {
            disablePose();
        } else {
            enablePose();
        }
    }

    let unsubscribeSocket = null;
    let autostartUnsubscribe = null;

    // Subscribe to sensor settings changes for auto-reconnect and auto-stop
    // This handles the case where settings change AFTER initial mount (e.g., user enables/disables via another instance)
    // We only act on explicit enable actions (configured=true means user action)
    let initialSettingsLoad = true;
    sensorSettings.subscribe((settings) => {
        logger.log(loggerCtxName, "sensorSettings update", settings.pose, "detecting:", detecting, "initialLoad:", initialSettingsLoad);

        // Skip the initial subscription call - let onMount handle that
        if (initialSettingsLoad) {
            initialSettingsLoad = false;
            return;
        }

        // If explicitly disabled (configured=true, enabled=false) and we're detecting, stop
        if (settings.pose?.configured && !settings.pose?.enabled && detecting) {
            logger.log(loggerCtxName, "Settings indicate disabled, stopping pose detection");
            stopPose();
            return;
        }

        // Only auto-start if explicitly enabled (configured=true means user action)
        if (settings.pose?.enabled && settings.pose?.configured && !detecting) {
            if (autostartUnsubscribe) {
                autostartUnsubscribe();
                autostartUnsubscribe = null;
            }

            autostartUnsubscribe = sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Auto-reconnect triggered via sensorSettings, starting pose");
                startPose();
            });
        }
    });

    // Legacy autostart support (for backwards compatibility)
    // Only triggers if user has NEVER configured the sensor (configured=false)
    autostart.subscribe((value) => {
        logger.log(loggerCtxName, "Autostart update", value, "detecting:", detecting);

        // Check if user has explicitly configured this sensor - if so, respect their choice
        const poseConfigured = sensorSettings.isSensorConfigured('pose');
        if (poseConfigured) {
            logger.log(loggerCtxName, "Autostart skipped - pose already configured by user");
            return;
        }

        if (value === true && !detecting) {
            if (autostartUnsubscribe) {
                autostartUnsubscribe();
                autostartUnsubscribe = null;
            }

            autostartUnsubscribe = sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Autostart triggered, starting pose detection");
                enablePose();
            });
        }
    });

    onMount(() => {
        // Clean up any orphaned video elements from previous instances
        cleanupOrphanedVideos();

        unsubscribeSocket = sensorService.onSocketReady(() => {
            // Check per-sensor settings first (takes precedence)
            const poseEnabled = sensorSettings.isSensorEnabled('pose');
            const poseConfigured = sensorSettings.isSensorConfigured('pose');

            logger.log(loggerCtxName, "onMount onSocketReady - checking settings", { poseEnabled, poseConfigured });

            // If user has ever configured pose settings, respect that choice
            if (poseConfigured) {
                if (poseEnabled) {
                    logger.log(loggerCtxName, "onMount onSocketReady - Pose was previously enabled, restarting");
                    startPose();
                } else {
                    logger.log(loggerCtxName, "onMount onSocketReady - Pose is explicitly disabled, not starting");
                }
                return;
            }

            // Fall back to legacy autostart behavior only if pose was never configured
            const autostartValue = get(autostart);
            if (autostartValue === true) {
                logger.log(loggerCtxName, "Autostart triggered, starting pose detection");
                enablePose();
            }
        });

        sensorService.onSocketDisconnected(() => {
            if (detecting) {
                // Don't clear settings on disconnect - just stop the sensor
                stopPose();
            }
        });
    });

    onDestroy(() => {
        if (unsubscribeSocket) {
            unsubscribeSocket();
        }
        if (autostartUnsubscribe) {
            autostartUnsubscribe();
        }
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
            ? `Pose detection active (${usingStandalone ? "standalone camera" : "call video"}, ${usingDelegate})`
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
            <button onclick={disablePose} class="btn btn-blue text-xs">Stop Pose</button>
            <span class="text-xs text-gray-400">
                {TARGET_FPS} FPS{isMobile ? ' (mobile)' : ''}{isEdge ? ' (Edge)' : ''}
                {#if usingStandalone}
                    <span class="text-cyan-400">(standalone)</span>
                {:else}
                    <span class="text-green-400">(call)</span>
                {/if}
                {#if usingDelegate === "CPU"}
                    <span class="text-yellow-400">(CPU)</span>
                {/if}
            </span>
        {:else}
            <button onclick={enablePose} class="btn btn-blue text-xs">Start Pose</button>
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

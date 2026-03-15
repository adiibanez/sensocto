<script>
    import { getContext, onMount, onDestroy } from "svelte";
    import { get } from "svelte/store";
    import { autostart, sensorSettings } from "./stores.js";
    import { logger } from "../logger_svelte.js";
    import { PoseLandmarker, FaceLandmarker, FilesetResolver } from "@mediapipe/tasks-vision";

    export let compact = false;
    export let videoElementId = "local-video";
    export let allowStandalone = true;

    let loggerCtxName = "HybridPoseClient";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId();

    let detecting = false;
    let poseLandmarker = null;
    let faceLandmarker = null;
    let animationFrameId = null;

    // Current detection mode
    let currentMode = "full"; // "full" | "face"

    // Standalone camera management
    let standaloneStream = null;
    let standaloneVideoEl = null;
    let usingStandalone = false;
    let cameraError = null;

    // Mobile detection for adaptive performance
    const isMobile = /Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);

    // Edge browser detection - Edge has issues with MediaPipe GPU delegate (used for FPS adjustment)
    const isEdge = /Edg\//i.test(navigator.userAgent);

    // Base FPS settings (can be overridden by backpressure)
    // Higher base FPS for smoother pose visualization
    const BASE_FPS = (isMobile || isEdge) ? 15 : 30;
    let targetFps = BASE_FPS;
    let frameInterval = 1000 / targetFps;
    let lastFrameTime = 0;

    // Skip frames counter for additional throttling under load
    let frameSkipCounter = 0;
    const MOBILE_FRAME_SKIP = isMobile ? 1 : 0;

    // Backpressure state
    let backpressurePaused = false;
    let attentionLevel = "none";
    let unsubscribeBackpressure = null;

    // Track which delegate is being used
    let usingDelegate = "GPU";

    // Mode switch cooldown to prevent rapid switching
    let lastModeSwitch = 0;
    const MODE_SWITCH_COOLDOWN = 1000; // 1 second

    // Preload status
    let preloadStarted = false;
    let preloadPromise = null;

    // Loading state for UI feedback
    let initializing = false;
    let initStatus = "";

    // Preload MediaPipe models in the background when component mounts
    // This significantly speeds up "Start" time since models are already cached
    async function preloadModels() {
        if (preloadStarted) return preloadPromise;
        preloadStarted = true;

        logger.log(loggerCtxName, "Preloading MediaPipe models in background...");
        const startTime = performance.now();

        preloadPromise = (async () => {
            try {
                // Preload WASM files first (required by both models)
                const vision = await FilesetResolver.forVisionTasks(
                    "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.18/wasm"
                );
                logger.log(loggerCtxName, `WASM preloaded in ${(performance.now() - startTime).toFixed(0)}ms`);

                // Preload both model files in parallel using fetch (they'll be cached by browser)
                const modelUrls = [
                    "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task",
                    "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task"
                ];

                await Promise.all(modelUrls.map(url =>
                    fetch(url).then(r => r.blob()).catch(() => null)
                ));

                logger.log(loggerCtxName, `Models preloaded in ${(performance.now() - startTime).toFixed(0)}ms`);
                return vision;
            } catch (error) {
                logger.warn(loggerCtxName, "Preload failed (will retry on start):", error);
                preloadStarted = false;
                return null;
            }
        })();

        return preloadPromise;
    }

    // Handle backpressure configuration from server
    function handleBackpressureConfig(config) {
        logger.log(loggerCtxName, "Backpressure config received:", config);

        const prevFps = targetFps;
        attentionLevel = config.attention_level || "none";
        backpressurePaused = config.paused || false;

        // Adjust frame rate based on attention level directly
        // Pose visualization needs higher framerates than generic sensor data
        // Use attention level to set FPS targets appropriate for real-time pose
        switch (attentionLevel) {
            case "high":
                // Full framerate for actively viewed pose
                targetFps = BASE_FPS;
                break;
            case "medium":
                // Still smooth but reduced (15fps desktop, 10fps mobile)
                targetFps = (isMobile || isEdge) ? 10 : 15;
                break;
            case "low":
                // Minimal but still usable (5fps)
                targetFps = 5;
                break;
            case "none":
            default:
                // Very low when no one is watching (2fps)
                targetFps = 2;
                break;
        }

        // Apply system load multiplier if provided (reduces FPS under load)
        if (config.load_multiplier && config.load_multiplier > 1) {
            targetFps = Math.max(2, targetFps / config.load_multiplier);
        }

        frameInterval = 1000 / targetFps;

        // When FPS increases (attention went up), reset lastFrameTime so the
        // next rAF immediately captures a frame instead of waiting out the old interval
        if (targetFps > prevFps) {
            lastFrameTime = 0;
        }

        logger.log(loggerCtxName, `Adjusted FPS to ${targetFps.toFixed(1)} based on attention level: ${attentionLevel}`);

        if (backpressurePaused) {
            logger.log(loggerCtxName, "Pose detection paused by backpressure (critical load + low attention)");
        }
    }

    // Race a promise against a timeout — returns the promise result or rejects on timeout
    function withTimeout(promise, ms, label) {
        return Promise.race([
            promise,
            new Promise((_, reject) => setTimeout(() => reject(new Error(`${label} timed out after ${ms}ms`)), ms))
        ]);
    }

    async function initLandmarkers() {
        const startTime = performance.now();
        logger.log(loggerCtxName, "Initializing landmarkers...");
        initStatus = "Loading vision models...";

        try {
            // Use preloaded vision instance if available, otherwise load fresh
            let vision = preloadPromise ? await preloadPromise : null;
            if (!vision) {
                logger.log(loggerCtxName, "No preloaded vision, loading fresh...");
                vision = await withTimeout(
                    FilesetResolver.forVisionTasks(
                        "https://cdn.jsdelivr.net/npm/@mediapipe/tasks-vision@0.10.18/wasm"
                    ),
                    15000,
                    "WASM loading"
                );
            }
            logger.log(loggerCtxName, `Vision ready in ${(performance.now() - startTime).toFixed(0)}ms`);

            const poseModelUrl = "https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task";
            const poseOptions = {
                runningMode: "VIDEO",
                numPoses: 1,
                minPoseDetectionConfidence: 0.5,
                minPosePresenceConfidence: 0.5,
                minTrackingConfidence: 0.5,
                outputSegmentationMasks: false
            };

            // Try GPU with a 10s timeout — GPU delegate can hang on some systems
            initStatus = "Initializing pose (GPU)...";
            let gpuSucceeded = false;
            try {
                poseLandmarker = await withTimeout(
                    PoseLandmarker.createFromOptions(vision, {
                        baseOptions: { modelAssetPath: poseModelUrl, delegate: "GPU" },
                        ...poseOptions
                    }),
                    10000,
                    "GPU PoseLandmarker"
                );
                usingDelegate = "GPU";
                gpuSucceeded = true;
                logger.log(loggerCtxName, `PoseLandmarker initialized with GPU in ${(performance.now() - startTime).toFixed(0)}ms`);
            } catch (gpuError) {
                logger.warn(loggerCtxName, `GPU delegate failed for Pose, falling back to CPU:`, gpuError);
                initStatus = "GPU unavailable, trying CPU...";
                poseLandmarker = await withTimeout(
                    PoseLandmarker.createFromOptions(vision, {
                        baseOptions: { modelAssetPath: poseModelUrl, delegate: "CPU" },
                        ...poseOptions
                    }),
                    15000,
                    "CPU PoseLandmarker"
                );
                usingDelegate = "CPU";
                logger.log(loggerCtxName, `PoseLandmarker initialized with CPU in ${(performance.now() - startTime).toFixed(0)}ms`);
            }

            // Start face initialization in background (optional, can fail)
            initStatus = "Starting camera...";
            const faceDelegate = usingDelegate;
            const initFace = async () => {
                try {
                    const landmarker = await withTimeout(
                        FaceLandmarker.createFromOptions(vision, {
                            baseOptions: {
                                modelAssetPath: "https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/1/face_landmarker.task",
                                delegate: faceDelegate
                            },
                            runningMode: "VIDEO",
                            numFaces: 1,
                            minFaceDetectionConfidence: 0.5,
                            minFacePresenceConfidence: 0.5,
                            minTrackingConfidence: 0.5,
                            outputFaceBlendshapes: true,
                            outputFacialTransformationMatrixes: false
                        }),
                        15000,
                        "FaceLandmarker"
                    );
                    logger.log(loggerCtxName, `FaceLandmarker initialized with ${faceDelegate} in ${(performance.now() - startTime).toFixed(0)}ms`);
                    return landmarker;
                } catch (faceError) {
                    logger.warn(loggerCtxName, "Failed to initialize FaceLandmarker:", faceError);
                    return null;
                }
            };

            initFace().then(fl => {
                faceLandmarker = fl;
                if (fl) {
                    logger.log(loggerCtxName, `FaceLandmarker ready, total init time: ${(performance.now() - startTime).toFixed(0)}ms`);
                }
            });

            logger.log(loggerCtxName, `Pose ready, starting detection. Total pose init: ${(performance.now() - startTime).toFixed(0)}ms`);
            return true;
        } catch (error) {
            logger.error(loggerCtxName, "Failed to initialize landmarkers:", error);
            initStatus = "";
            return false;
        }
    }

    function findCallVideoElement() {
        const container = document.getElementById(videoElementId);
        if (container) {
            const video = container.querySelector("video");
            if (video && video.srcObject) return video;
        }

        const direct = document.getElementById(videoElementId);
        if (direct && direct.tagName === "VIDEO" && direct.srcObject) return direct;

        const localVideo = document.querySelector('[id*="local"] video');
        if (localVideo && localVideo.srcObject) return localVideo;

        return null;
    }

    async function setupStandaloneCamera() {
        if (standaloneStream) {
            return standaloneVideoEl;
        }

        logger.log(loggerCtxName, "Setting up standalone camera...");
        cameraError = null;

        const videoWidth = isMobile ? 320 : 640;
        const videoHeight = isMobile ? 240 : 480;

        try {
            standaloneStream = await navigator.mediaDevices.getUserMedia({
                video: {
                    width: { ideal: videoWidth },
                    height: { ideal: videoHeight },
                    frameRate: { ideal: BASE_FPS },
                    // Use front camera so user can see themselves while streaming facial landmarks
                    facingMode: "user"
                },
                audio: false
            });

            standaloneVideoEl = document.createElement("video");
            standaloneVideoEl.id = "hybrid-pose-standalone-video";
            standaloneVideoEl.autoplay = true;
            standaloneVideoEl.playsInline = true;
            standaloneVideoEl.muted = true;
            standaloneVideoEl.width = videoWidth;
            standaloneVideoEl.height = videoHeight;
            // Hide video but keep it rendering at full size for MediaPipe detection
            // Edge browser requires the video to be visible and at proper dimensions
            // Using clip-path to make it invisible while maintaining dimensions
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
        const orphanedVideos = document.querySelectorAll('#hybrid-pose-standalone-video');
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
        const callVideo = findCallVideoElement();
        if (callVideo) {
            logger.log(loggerCtxName, "Using call video for pose detection");
            usingStandalone = false;
            return callVideo;
        }

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

    // Determine if we're in face-only mode based on pose landmarks
    function isFaceOnlyMode(landmarks) {
        if (!landmarks || landmarks.length < 33) return false;

        // Check visibility of body parts
        const visThreshold = 0.5;

        // Hands/wrists (indices 15-22)
        const hasHands = landmarks.slice(15, 23).some(lm => lm.visibility > visThreshold);

        // Hips (indices 23-24)
        const hasHips = landmarks[23]?.visibility > visThreshold || landmarks[24]?.visibility > visThreshold;

        // Knees/ankles (indices 25-32)
        const hasLegs = landmarks.slice(25, 33).some(lm => lm.visibility > visThreshold);

        // If we have substantial body parts, we're in full body mode
        if (hasHands || hasHips || hasLegs) {
            return false;
        }

        // Check if face is visible (nose, eyes, ears - indices 0-10)
        const hasFace = landmarks.slice(0, 11).some(lm => lm.visibility > visThreshold);

        // Face-only mode if we have face but no body
        return hasFace;
    }

    async function startPose() {
        if (detecting || initializing) return;

        logger.log(loggerCtxName, "Starting hybrid pose detection...");
        initializing = true;
        initStatus = "Initializing...";
        cameraError = null;

        try {
            if (!poseLandmarker) {
                const success = await initLandmarkers();
                if (!success) {
                    logger.error(loggerCtxName, "Could not initialize landmarkers");
                    cameraError = "Failed to initialize pose models. Please try again.";
                    return;
                }
            }

            initStatus = "Starting camera...";
            const videoEl = await getVideoSource();
            if (!videoEl) {
                logger.error(loggerCtxName, "Could not find or create video source");
                if (!cameraError) {
                    cameraError = "No video source available. Join a call or allow camera access.";
                }
                return;
            }

            if (videoEl.readyState < 2) {
                initStatus = "Waiting for camera...";
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

            // Setup sensor channel with hybrid skeleton type
            sensorService.setupChannel(channelIdentifier);
            sensorService.registerAttribute(channelIdentifier, {
                attribute_id: "pose_skeleton",
                attribute_type: "skeleton",
                sampling_rate: targetFps
            });

            // Subscribe to backpressure updates
            unsubscribeBackpressure = sensorService.onBackpressure(channelIdentifier, handleBackpressureConfig);

            detecting = true;
            currentMode = "full";

            detectFrame(videoEl);
            logger.log(loggerCtxName, `Hybrid pose detection started (${usingStandalone ? "standalone" : "call"} mode)`);
        } finally {
            initializing = false;
            initStatus = "";
        }
    }

    function detectFrame(videoEl) {
        if (!detecting || !poseLandmarker) return;

        // Respect backpressure pause signal
        if (backpressurePaused) {
            animationFrameId = requestAnimationFrame(() => detectFrame(videoEl));
            return;
        }

        const now = performance.now();

        if (now - lastFrameTime < frameInterval) {
            animationFrameId = requestAnimationFrame(() => detectFrame(videoEl));
            return;
        }
        lastFrameTime = now;

        if (MOBILE_FRAME_SKIP > 0) {
            frameSkipCounter++;
            if (frameSkipCounter <= MOBILE_FRAME_SKIP) {
                animationFrameId = requestAnimationFrame(() => detectFrame(videoEl));
                return;
            }
            frameSkipCounter = 0;
        }

        if (!videoEl.srcObject && !usingStandalone) {
            logger.log(loggerCtxName, "Call video lost, attempting to switch to standalone");
            switchToStandalone();
            return;
        }

        if (videoEl.readyState >= 2) {
            try {
                // Always run pose detection first to determine mode
                const poseResults = poseLandmarker.detectForVideo(videoEl, now);

                let faceMeshLandmarks = null;
                let blendshapes = null;

                // Debug: log every 60 frames (~2-4 seconds) to help diagnose detection issues
                if (Math.floor(now / 2000) !== Math.floor(lastFrameTime / 2000)) {
                    logger.log(loggerCtxName, `Detection status: landmarks=${poseResults.landmarks?.length || 0}, video=${videoEl.videoWidth}x${videoEl.videoHeight}, readyState=${videoEl.readyState}`);
                }

                if (poseResults.landmarks && poseResults.landmarks.length > 0) {
                    const landmarks = poseResults.landmarks[0];
                    const shouldUseFaceMode = isFaceOnlyMode(landmarks);

                    // Check cooldown before switching modes
                    const canSwitchMode = (now - lastModeSwitch) > MODE_SWITCH_COOLDOWN;

                    if (shouldUseFaceMode && faceLandmarker && (currentMode === "face" || canSwitchMode)) {
                        // Use FaceLandmarker for detailed face mesh
                        if (currentMode !== "face") {
                            currentMode = "face";
                            lastModeSwitch = now;
                            logger.log(loggerCtxName, "Switched to face mesh mode (468 landmarks)");
                        }

                        const faceResults = faceLandmarker.detectForVideo(videoEl, now);
                        if (faceResults.faceLandmarks && faceResults.faceLandmarks.length > 0) {
                            faceMeshLandmarks = faceResults.faceLandmarks[0];
                            blendshapes = faceResults.faceBlendshapes?.[0]?.categories || null;
                        }
                    } else if (!shouldUseFaceMode && (currentMode === "full" || canSwitchMode)) {
                        // Full body mode - just use pose landmarks
                        if (currentMode !== "full") {
                            currentMode = "full";
                            lastModeSwitch = now;
                            logger.log(loggerCtxName, "Switched to full body mode (33 landmarks)");
                        }
                    }

                    sendSkeletonData(poseResults, faceMeshLandmarks, blendshapes);
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

    function sendSkeletonData(poseResults, faceMeshLandmarks, blendshapes) {
        if (!detecting) {
            logger.log(loggerCtxName, "Skipping send - detection stopped");
            return;
        }

        const landmarks = poseResults.landmarks[0];

        const roundTo3 = (n) => Math.round(n * 1000) / 1000;

        const payload = {
            mode: currentMode,
            landmarks: landmarks.map(lm => ({
                x: roundTo3(lm.x),
                y: roundTo3(lm.y),
                z: roundTo3(lm.z),
                v: roundTo3(lm.visibility ?? 1.0)
            }))
        };

        // Include face mesh landmarks when in face mode
        if (faceMeshLandmarks && currentMode === "face") {
            payload.faceLandmarks = faceMeshLandmarks.map(lm => ({
                x: roundTo3(lm.x),
                y: roundTo3(lm.y),
                z: roundTo3(lm.z)
            }));

            // Include key blendshapes for mouth state
            if (blendshapes) {
                const keyBlendshapes = [
                    "jawOpen",
                    "mouthSmileLeft",
                    "mouthSmileRight",
                    "mouthPucker",
                    "eyeBlinkLeft",
                    "eyeBlinkRight",
                    "browDownLeft",
                    "browDownRight",
                    "browInnerUp"
                ];
                payload.blendshapes = {};
                for (const shape of blendshapes) {
                    if (keyBlendshapes.includes(shape.categoryName)) {
                        payload.blendshapes[shape.categoryName] = roundTo3(shape.score);
                    }
                }
            }
        }

        // Include world landmarks on desktop
        if (!isMobile && poseResults.worldLandmarks?.[0]) {
            payload.worldLandmarks = poseResults.worldLandmarks[0].map(lm => ({
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
        const wasDetecting = detecting;

        logger.log(loggerCtxName, "Stopping hybrid pose detection...");

        detecting = false;

        if (animationFrameId) {
            cancelAnimationFrame(animationFrameId);
            animationFrameId = null;
        }

        // Unsubscribe from backpressure updates
        if (unsubscribeBackpressure) {
            unsubscribeBackpressure();
            unsubscribeBackpressure = null;
        }

        // Reset backpressure state
        backpressurePaused = false;
        targetFps = BASE_FPS;
        frameInterval = 1000 / targetFps;

        // Always clean up camera — handles race condition where startPose opened
        // the camera but detecting wasn't set to true yet when user hit stop
        cleanupStandaloneCamera();

        // Close MediaPipe landmarkers to release GPU/camera references
        // Without this, some browsers keep the camera indicator active
        if (poseLandmarker) {
            try {
                poseLandmarker.close();
            } catch (e) {
                logger.warn(loggerCtxName, "Error closing PoseLandmarker:", e);
            }
            poseLandmarker = null;
        }
        if (faceLandmarker) {
            try {
                faceLandmarker.close();
            } catch (e) {
                logger.warn(loggerCtxName, "Error closing FaceLandmarker:", e);
            }
            faceLandmarker = null;
        }

        if (wasDetecting) {
            setTimeout(() => {
                sensorService.unregisterAttribute(channelIdentifier, "pose_skeleton");
            }, 50);
        }

        logger.log(loggerCtxName, "Hybrid pose detection stopped");
    }

    async function enablePose() {
        if (initializing || detecting) return;
        sensorSettings.setSensorEnabled('hybrid_pose', true);
        await startPose();
        // If startPose failed (detecting is still false), reset the setting
        if (!detecting) {
            sensorSettings.setSensorEnabled('hybrid_pose', false);
        }
    }

    function disablePose() {
        sensorSettings.setSensorEnabled('hybrid_pose', false);
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

    let initialSettingsLoad = true;
    sensorSettings.subscribe((settings) => {
        logger.log(loggerCtxName, "sensorSettings update", settings.hybrid_pose, "detecting:", detecting, "initialLoad:", initialSettingsLoad);

        if (initialSettingsLoad) {
            initialSettingsLoad = false;
            return;
        }

        if (settings.hybrid_pose?.configured && !settings.hybrid_pose?.enabled && detecting) {
            logger.log(loggerCtxName, "Settings indicate disabled, stopping pose detection");
            stopPose();
            return;
        }

        if (settings.hybrid_pose?.enabled && settings.hybrid_pose?.configured && !detecting) {
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

    autostart.subscribe((value) => {
        logger.log(loggerCtxName, "Autostart update", value, "detecting:", detecting);

        const poseConfigured = sensorSettings.isSensorConfigured('hybrid_pose');
        if (poseConfigured) {
            logger.log(loggerCtxName, "Autostart skipped - hybrid_pose already configured by user");
            return;
        }

        if (value === true && !detecting) {
            if (autostartUnsubscribe) {
                autostartUnsubscribe();
                autostartUnsubscribe = null;
            }

            autostartUnsubscribe = sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Autostart triggered, starting hybrid pose detection");
                enablePose();
            });
        }
    });

    onMount(() => {
        // Clean up any orphaned video elements from previous instances
        cleanupOrphanedVideos();

        // Start preloading MediaPipe models immediately in background
        // This speeds up "Start" by having models already cached
        preloadModels();

        unsubscribeSocket = sensorService.onSocketReady(() => {
            const poseEnabled = sensorSettings.isSensorEnabled('hybrid_pose');
            const poseConfigured = sensorSettings.isSensorConfigured('hybrid_pose');

            logger.log(loggerCtxName, "onMount onSocketReady - checking settings", { poseEnabled, poseConfigured });

            if (poseConfigured) {
                if (poseEnabled) {
                    logger.log(loggerCtxName, "onMount onSocketReady - Hybrid pose was previously enabled, restarting");
                    startPose();
                } else {
                    logger.log(loggerCtxName, "onMount onSocketReady - Hybrid pose is explicitly disabled, not starting");
                }
                return;
            }

            const autostartValue = get(autostart);
            if (autostartValue === true) {
                logger.log(loggerCtxName, "Autostart triggered, starting hybrid pose detection");
                enablePose();
            }
        });

        sensorService.onSocketDisconnected(() => {
            if (detecting) {
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
        if (faceLandmarker) {
            faceLandmarker.close();
            faceLandmarker = null;
        }
    });
</script>

{#if compact}
    <button
        onclick={togglePose}
        class="icon-btn"
        class:active={detecting}
        class:loading={initializing}
        class:standalone={detecting && usingStandalone}
        class:face-mode={detecting && currentMode === "face"}
        class:paused={detecting && backpressurePaused}
        disabled={initializing}
        title={initializing
            ? initStatus
            : detecting
                ? `Hybrid pose active (${currentMode} mode, ${usingStandalone ? "standalone" : "call"}, ${usingDelegate}, ${targetFps.toFixed(0)}fps${backpressurePaused ? " PAUSED" : ""})`
                : "Start hybrid pose detection"}
    >
        {#if initializing}
            <svg class="w-3.5 h-3.5 spin" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
            </svg>
        {:else}
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
                {#if currentMode === "face" && detecting}
                    <path d="M12 2C6.48 2 2 6.48 2 12s4.48 10 10 10 10-4.48 10-10S17.52 2 12 2zm0 18c-4.41 0-8-3.59-8-8s3.59-8 8-8 8 3.59 8 8-3.59 8-8 8zm-5-6c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm10 0c.55 0 1 .45 1 1s-.45 1-1 1-1-.45-1-1 .45-1 1-1zm-5 4c2.21 0 4-1.79 4-4h-8c0 2.21 1.79 4 4 4z"/>
                {:else}
                    <path d="M12 2C13.1 2 14 2.9 14 4C14 5.1 13.1 6 12 6C10.9 6 10 5.1 10 4C10 2.9 10.9 2 12 2ZM21 9H15V22H13V16H11V22H9V9H3V7H21V9Z"/>
                {/if}
            </svg>
        {/if}
    </button>
    {#if cameraError}
        <span class="text-xs text-red-400 ml-1" title={cameraError}>!</span>
    {/if}
{:else}
    <div class="flex items-center gap-2">
        {#if initializing}
            <button disabled class="btn btn-blue text-xs opacity-70 cursor-wait">
                <span class="inline-flex items-center gap-1">
                    <svg class="w-3 h-3 spin" xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke="currentColor">
                        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15" />
                    </svg>
                    Initializing...
                </span>
            </button>
            <span class="text-xs text-gray-500">{initStatus}</span>
        {:else if detecting}
            <button onclick={disablePose} class="btn btn-blue text-xs">Stop Hybrid</button>
            <span class="text-xs text-gray-400">
                {targetFps.toFixed(0)} FPS{isMobile ? ' (mobile)' : ''}{isEdge ? ' (Edge)' : ''}
                {#if backpressurePaused}
                    <span class="text-red-400">(PAUSED)</span>
                {/if}
                {#if attentionLevel !== "none" && attentionLevel !== "high"}
                    <span class="text-orange-400">({attentionLevel})</span>
                {/if}
                {#if currentMode === "face"}
                    <span class="text-pink-400">(face mesh)</span>
                {:else}
                    <span class="text-purple-400">(full body)</span>
                {/if}
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
            <button onclick={enablePose} class="btn btn-blue text-xs">Start Hybrid</button>
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
    .icon-btn.active.face-mode {
        background: #ec4899;
        color: white;
    }
    .icon-btn.active.paused {
        background: #f59e0b;
        animation: pulse 1.5s ease-in-out infinite;
    }
    .icon-btn.loading {
        background: #4b5563;
        color: #60a5fa;
        cursor: wait;
    }
    .icon-btn:disabled {
        cursor: wait;
    }
    :global(.spin) {
        animation: spin 1s linear infinite;
    }
    @keyframes pulse {
        0%, 100% { opacity: 1; }
        50% { opacity: 0.6; }
    }
    @keyframes spin {
        from { transform: rotate(0deg); }
        to { transform: rotate(360deg); }
    }
</style>

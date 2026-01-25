<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";
    import { get } from "svelte/store";
    import { usersettings, autostart, sensorSettings } from "./stores.js";
    import { isMobile } from "../utils.js";
    import { logger } from "../logger_svelte.js";

    export let compact = false;

    let loggerCtxName = "IMUClient";

    let unsubscribeSocket;

    //import { AHRSEKF } from 'js-ahrs';

    //import { AHRS } from "../js/www-ahrs.js";
    //import { AHRSEKF } from "../js/www-ahrs.js";

    const AHRS = require("ahrs");
    const madgwick = new AHRS({
        //sampleInterval: 20,
        algorithm: "Madgwick",
        beta: 0.4,
        kp: 0.5,
        ki: 0,
        doInitialisation: true,
    });

    let sensorService = getContext("sensorService");
    let accelerometer;
    let gyroscope;

    let imuFrequency = 25; //Default IMU frequency
    let imuOutput = null;
    let initialOrientation;
    let previousTimestamp = null;

    let readingIMU = false;
    let channelIdentifier = sensorService.getDeviceId(); // + ":imu";

    let autostartUnsubscribe = null;

    // Wrapper functions that also persist to localStorage
    function enableIMU() {
        sensorSettings.setSensorEnabled('imu', true);
        startIMU();
    }

    function disableIMU() {
        sensorSettings.setSensorEnabled('imu', false);
        stopIMU();
    }

    // Subscribe to sensor settings changes for auto-reconnect
    // Skip initial load - let onMount handle that
    let initialSettingsLoad = true;
    sensorSettings.subscribe((settings) => {
        logger.log(loggerCtxName, "sensorSettings update", settings.imu, readingIMU, "initialLoad:", initialSettingsLoad);

        if (initialSettingsLoad) {
            initialSettingsLoad = false;
            return;
        }

        // Only auto-start if explicitly enabled after initial load
        if (settings.imu?.enabled && settings.imu?.configured && !readingIMU && imuAvailable()) {
            if (autostartUnsubscribe) {
                autostartUnsubscribe();
                autostartUnsubscribe = null;
            }

            autostartUnsubscribe = sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Auto-reconnect triggered via sensorSettings, starting IMU");
                startIMU();
            });
        }
    });

    // Legacy autostart support (for backwards compatibility)
    // Only triggers if user has NEVER configured the sensor (configured=false)
    autostart.subscribe((value) => {
        logger.log(loggerCtxName, "pre Autostart update", value, readingIMU);

        // Check if user has explicitly configured this sensor - if so, respect their choice
        const imuConfigured = sensorSettings.isSensorConfigured('imu');
        if (imuConfigured) {
            logger.log(loggerCtxName, "Autostart skipped - IMU already configured by user");
            return;
        }

        if (value === true && !readingIMU && imuAvailable()) {
            if (autostartUnsubscribe) {
                autostartUnsubscribe();
                autostartUnsubscribe = null;
            }

            autostartUnsubscribe = sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Autostart triggered via subscribe, starting IMU");
                enableIMU();
            });
        }
    });

    onMount(() => {
        // Now you can use sensorService.setupChannel, etc.
        if (!sensorService) {
            console.error("Sensor service not available!"); // Add error handling
        }
    });

    onDestroy(() => {
        // ... IMU cleanup (same as before)
        //sensorService.leaveChannel(channelIdentifier);
    });

    // Detect iOS for permission handling
    const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
                  (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);

    // Track permission state for UI feedback
    let motionPermissionState = null; // 'granted', 'denied', 'prompt', or null

    function imuAvailable() {
        if (!isMobile()) return false;

        if ("LinearAccelerationSensor" in window && "Gyroscope" in window) {
            // Both Linear Acceleration and Gyroscope sensors are available. This is ideal for mobile devices.
            // Note: These APIs are NOT available on iOS Safari
            return "mobile";
        } else if (window.DeviceMotionEvent) {
            // DeviceMotionEvent is available, but specific sensor types are not guaranteed.
            // On iOS 13+, this requires explicit permission request
            return "desktop"; // Or 'maybe' if you're unsure
        } else {
            // No motion sensors are available
            return false;
        }
    }

    // iOS 13+ requires explicit permission for DeviceMotionEvent
    async function requestMotionPermission() {
        // Check if this is iOS and requires permission
        if (typeof DeviceMotionEvent !== 'undefined' &&
            typeof DeviceMotionEvent.requestPermission === 'function') {
            try {
                const permission = await DeviceMotionEvent.requestPermission();
                logger.log(loggerCtxName, "DeviceMotionEvent permission:", permission);
                motionPermissionState = permission;
                return permission === 'granted';
            } catch (error) {
                logger.error(loggerCtxName, "Error requesting DeviceMotionEvent permission:", error);
                motionPermissionState = 'denied';
                return false;
            }
        }
        // requestPermission not needed (non-iOS or older iOS)
        motionPermissionState = 'granted';
        return true;
    }

    function resetInitialOrientation() {
        initialOrientation = {
            alpha: 0,
            beta: 0,
            gamma: 0,
        };
    }

    async function startIMU() {
        let imuType = imuAvailable();

        if (imuType === "mobile") {
            try {
                sensorService.setupChannel(channelIdentifier);
                sensorService.registerAttribute(channelIdentifier, {
                    attribute_id: "imu",
                    attribute_type: "imu",
                    sampling_rate: imuFrequency,
                });

                accelerometer = new LinearAccelerationSensor({
                    frequency: imuFrequency,
                });

                gyroscope = new Gyroscope({ frequency: imuFrequency });

                accelerometer.addEventListener("reading", () =>
                    handleMobileIMU(),
                );
                gyroscope.addEventListener("reading", () => handleMobileIMU());

                await accelerometer.start(); // Promise, resolves if started succesfully
                await gyroscope.start();

                absoluteorientation = new AbsoluteOrientationSensor();
                Promise.all([
                    navigator.permissions.query({ name: "accelerometer" }),
                    navigator.permissions.query({ name: "magnetometer" }),
                    navigator.permissions.query({ name: "gyroscope" }),
                ]).then((results) => {
                    if (results.every((result) => result.state === "granted")) {
                        absoluteorientation.start();
                        // …
                    } else {
                        console.log(
                            "No permissions to use AbsoluteOrientationSensor.",
                        );
                    }
                });

                absoluteorientation.addEventListener("reading", () =>
                    handleMobileIMU(),
                );

                readingIMU = true;
            } catch (error) {
                // Handle errors, e.g., sensor not available or permission denied
                console.error("Error starting IMU sensors:", error);
                readingIMU = false; // Set readingIMU to false if an error occurs
            }
        } else if (imuType === "desktop") {
            // On iOS 13+, DeviceMotionEvent requires explicit permission
            // This MUST be called from a user gesture (click/tap)
            const hasPermission = await requestMotionPermission();
            if (!hasPermission) {
                logger.error(loggerCtxName, "Motion permission denied on iOS");
                return;
            }

            sensorService.setupChannel(channelIdentifier);
            sensorService.registerAttribute(channelIdentifier, {
                attribute_id: "imu",
                attribute_type: "imu",
                sampling_rate: imuFrequency,
            });

            readingIMU = true;
            window.addEventListener("devicemotion", handleDeviceMotion);
        }
    }

    function stopIMU() {
        if (readingIMU) {
            let imuType = imuAvailable();

            if (imuType === "mobile") {
                accelerometer.removeEventListener("reading", () =>
                    handleMobileIMU(),
                );
                gyroscope.removeEventListener("reading", () =>
                    handleMobileIMU(),
                );
                absoluteorientation.removeEventListener("reading", () =>
                    handleMobileIMU(),
                );
                absoluteorientation.stop();
                accelerometer.stop();
                gyroscope.stop();
            } else if (imuType === "desktop") {
                window.removeEventListener("devicemotion", handleDeviceMotion);
            }

            readingIMU = false;
            sensorService.unregisterAttribute(channelIdentifier, "imu");
            sensorService.leaveChannelIfUnused(channelIdentifier);

            imuData = null; // Reset data when stopped
        }
    }

    function handleDeviceMotion(event) {
        imuData = {
            acceleration: {
                x: event.acceleration.x,
                y: event.acceleration.y,
                z: event.acceleration.z,
            },
            accelerationIncludingGravity: {
                x: event.accelerationIncludingGravity.x,
                y: event.accelerationIncludingGravity.y,
                z: event.accelerationIncludingGravity.z,
            },
            rotationRate: {
                alpha: event.rotationRate.alpha,
                beta: event.rotationRate.beta,
                gamma: event.rotationRate.gamma,
            },
            interval: event.interval,
        };

        imuData.rotationAngles = rotationRateToAngle(
            imuData.rotationRate.alpha,
            imuData.rotationRate.beta,
            imuData.rotationRate.gamma,
        );

        let payload = {
            // same as before ...
            number:
                imuData.rotationAngles.x +
                "," +
                imuData.rotationAngles.y +
                "," +
                imuData.rotationAngles.z,
            attribute_id: "imu", // Or some other unique ID for IMU data
            timestamp: Math.round(new Date().getTime()),
        };

        sensorService.sendChannelMessage(channelIdentifier, payload);
    }

    function handleMobileIMU_(event) {
        madgwick.update(
            gyroscope.x,
            gyroscope.y,
            gyroscope.z,
            accelerometer.x,
            accelerometer.y,
            accelerometer.z,
        );

        //  * compass.x,
        //     compass.y,
        //     compass.z,
    }

    function handleMobileIMU(event) {
        let dt = 1; // initial value.
        const currentTimestamp = Date.now();

        if (previousTimestamp !== null) {
            dt = (currentTimestamp - previousTimestamp) / 1000;
        }
        previousTimestamp = currentTimestamp;

        if (initialOrientation === null) {
            initialOrientation = {
                alpha: 0,
                beta: 0,
                gamma: 0,
            };
        }

        let imuData = {
            a: {
                // acceleration
                x: accelerometer?.x || 0,
                y: accelerometer?.y || 0,
                z: accelerometer?.z || 0,
            },
            r: {
                // rotation rate
                x: gyroscope?.x || 0,
                y: gyroscope?.y || 0,
                z: gyroscope?.z || 0,
            },
        };

        let rotationAngles = rotationRateToAngle(
            imuData.r.x,
            imuData.r.y,
            imuData.r.z,
            initialOrientation,
            dt,
        ); // get delta rotation.

        initialOrientation = {
            // Update using calculated angles.
            alpha: parseFloat(rotationAngles.x),
            beta: parseFloat(rotationAngles.y),
            gamma: parseFloat(rotationAngles.z),
        };

        // Calculate quaternion from Euler angles (rotationAngles)
        const q = eulerToQuaternion(
            rotationAngles.x,
            rotationAngles.y,
            rotationAngles.z,
        );

        let output = {
            t: Math.round(new Date().getTime()), // time
            a: {
                // acceleration
                x: imuData.a.x,
                y: imuData.a.y,
                z: imuData.a.z,
            },
            r: {
                // rotation rate
                x: imuData.r.x,
                y: imuData.r.y,
                z: imuData.r.z,
            },
            q: {
                // Quaternion
                w: q.w,
                x: q.x,
                y: q.y,
                z: q.z,
            },
        };

        let imuString = `${output.t},${output.a.x.toFixed(3)},${output.a.y.toFixed(3)},${output.a.z.toFixed(3)},${output.r.x.toFixed(3)},${output.r.y.toFixed(3)},${output.r.z.toFixed(3)},${output.q.w.toFixed(3)},${output.q.x.toFixed(3)},${output.q.y.toFixed(3)},${output.q.z.toFixed(3)}`;

        logger.log(
            loggerCtxName,
            "handleMobileIMU",
            initialOrientation,
            output.q,
            dt,
        );

        imuOutput = output;

        let payload = {
            payload: imuString, // Send as a string, like the visualization expects
            attribute_id: "imu",
            timestamp: Math.round(new Date().getTime()),
        };

        sensorService.sendChannelMessage(channelIdentifier, payload);

        //return JSON.stringify(output); // Return object as JSON string
    }

    function eulerToQuaternion(x, y, z) {
        const cy = Math.cos(z * 0.5);
        const sy = Math.sin(z * 0.5);
        const cp = Math.cos(y * 0.5);
        const sp = Math.sin(y * 0.5);
        const cr = Math.cos(x * 0.5);
        const sr = Math.sin(x * 0.5);

        const w = cr * cp * cy + sr * sp * sy;
        const x_quat = sr * cp * cy - cr * sp * sy;
        const y_quat = cr * sp * cy + sr * cp * sy;
        const z_quat = cr * cp * sy - sr * sp * cy;

        return {
            w: w,
            x: x_quat,
            y: y_quat,
            z: z_quat,
        };
    }

    function rotationRateToAngle(alpha, beta, gamma, initialOrientation, dt) {
        // Convert radians to degrees
        const alphaDeg = alpha * (180 / Math.PI);
        const betaDeg = beta * (180 / Math.PI);
        const gammaDeg = gamma * (180 / Math.PI);

        // Important: Use parseFloat to handle cases where those variables are `string`, or other formats:
        return {
            x: (
                alphaDeg * dt +
                parseFloat(initialOrientation?.alpha || 0)
            ).toFixed(1), // Important: Use parseFloat
            y: (
                betaDeg * dt +
                parseFloat(initialOrientation?.beta || 0)
            ).toFixed(1),
            z: (
                gammaDeg * dt +
                parseFloat(initialOrientation?.gamma || 0)
            ).toFixed(1),
        };
    }

    onMount(() => {
        unsubscribeSocket = sensorService.onSocketReady(() => {
            // Check per-sensor settings first (takes precedence)
            const imuEnabled = sensorSettings.isSensorEnabled('imu');
            const imuConfigured = sensorSettings.isSensorConfigured('imu');

            logger.log(loggerCtxName, "onMount onSocketReady - checking settings", { imuEnabled, imuConfigured });

            // If user has ever configured IMU settings, respect that choice
            if (imuConfigured) {
                if (imuEnabled && imuAvailable()) {
                    logger.log(loggerCtxName, "onMount onSocketReady - IMU was previously enabled, restarting");
                    startIMU();
                } else {
                    logger.log(loggerCtxName, "onMount onSocketReady - IMU is explicitly disabled, not starting");
                }
                return;
            }

            // Fall back to legacy autostart behavior only if IMU was never configured
            const autostartValue = get(autostart);
            if (autostartValue === true && imuAvailable()) {
                logger.log(loggerCtxName, "onMount onSocketReady Autostart going to start", autostartValue);
                enableIMU();
            }
        });

        sensorService.onSocketDisconnected(() => {
            if (readingIMU) {
                // Don't clear settings on disconnect - just stop the sensor
                stopIMU();
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
        stopIMU();
        sensorService.unregisterAttribute(channelIdentifier, "imu");
        sensorService.leaveChannelIfUnused(channelIdentifier);
    });
</script>

{#if imuAvailable()}
    {#if compact}
        <button
            on:click={readingIMU ? disableIMU : enableIMU}
            class="icon-btn"
            class:active={readingIMU}
            class:error={motionPermissionState === 'denied'}
            title={motionPermissionState === 'denied'
                ? "Motion permission denied"
                : readingIMU
                    ? `IMU active (${imuFrequency}Hz)`
                    : isIOS
                        ? "Start IMU (will request permission)"
                        : "Start IMU"}
        >
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
                <path fill-rule="evenodd" d="M12 2.25c-5.385 0-9.75 4.365-9.75 9.75s4.365 9.75 9.75 9.75 9.75-4.365 9.75-9.75S17.385 2.25 12 2.25zM8.547 4.505a8.25 8.25 0 1011.672 11.672L8.547 4.505z" clip-rule="evenodd"/>
            </svg>
        </button>
    {:else}
        <div>
            {#if readingIMU}
                <button on:click={() => disableIMU()} class="btn btn-blue text-xs">Stop IMU</button>
                <button on:click={resetInitialOrientation} class="btn btn-blue text-xs">Cal</button>
                {imuFrequency} Hz
            {:else}
                <button on:click={() => enableIMU()} class="btn btn-blue text-xs">Start IMU</button>
                <input
                    type="number"
                    bind:value={imuFrequency}
                    min="1"
                    max="50"
                    aria-describedby="Frequency of IM"
                    required
                /> Hz
            {/if}
        </div>
    {/if}
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
        background: #f97316;
        color: white;
    }
    .icon-btn.error {
        background: #dc2626;
        color: white;
    }
</style>

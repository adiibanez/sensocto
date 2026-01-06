<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";
    import { get } from "svelte/store";
    import { usersettings, autostart } from "./stores.js";
    import { isMobile } from "../utils.js";
    import { logger } from "../logger_svelte.js";

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

    let imuFrequency = 5; //Default IMU frequency
    let imuOutput = null;
    let initialOrientation;
    let previousTimestamp = null;

    let readingIMU = false;
    let channelIdentifier = sensorService.getDeviceId(); // + ":imu";

    let autostartUnsubscribe = null;

    autostart.subscribe((value) => {
        logger.log(loggerCtxName, "pre Autostart update", value, readingIMU);

        if (value === true && !readingIMU && imuAvailable()) {
            // Clean up previous subscription if any
            if (autostartUnsubscribe) {
                autostartUnsubscribe();
                autostartUnsubscribe = null;
            }

            autostartUnsubscribe = sensorService.onSocketReady(() => {
                logger.log(loggerCtxName, "Autostart triggered via subscribe, starting IMU");
                startIMU();
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

    function imuAvailable() {
        if (!isMobile()) return false;

        if ("LinearAccelerationSensor" in window && "Gyroscope" in window) {
            // Both Linear Acceleration and Gyroscope sensors are available. This is ideal for mobile devices.
            return "mobile";
        } else if (window.DeviceMotionEvent) {
            // DeviceMotionEvent is available, but specific sensor types are not guaranteed. This might work on some desktops.
            return "desktop"; // Or 'maybe' if you're unsure
        } else {
            // No motion sensors are available
            return false;
        }
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
            const autostartValue = get(autostart);
            if (autostartValue === true) {
                logger.log(
                    loggerCtxName,
                    "onMount onSocketReady Autostart going to start",
                    autostartValue,
                );
                startIMU();
            }
        });

        sensorService.onSocketDisconnected(() => {
            if (readingIMU) {
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
    <div>
        {#if readingIMU}
            <button on:click={() => stopIMU()} class="btn btn-blue text-xs"
                >Stop IMU</button
            ><button
                on:click={resetInitialOrientation}
                class="btn btn-blue text-xs">Cal</button
            >
            {imuFrequency} Hz
        {/if}
        {#if !readingIMU}
            <button on:click={() => startIMU()} class="btn btn-blue text-xs"
                >Start IMU</button
            >
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

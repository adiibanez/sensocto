<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    import { logger } from "./logger.js";

    loggerCtxName = "IMUClient";

    //import { AHRSEKF } from 'js-ahrs';

    //import { AHRS } from "../js/www-ahrs.js";
    //import { AHRSEKF } from "../js/www-ahrs.js";

    const AHRS = require('ahrs');

    console.log("AHRS", AHRS);

    const madgwick = new AHRS({
        //sampleInterval: 20,
        algorithm: "Madgwick",
        beta: 0.4,
        kp: 0.5,
        ki: 0,
        doInitialisation: true
    });

    let sensorService = getContext("sensorService");
    let accelerometer;
    let gyroscope;

    let imuFrequency = 5; //Default IMU frequency
    let imuOutput = null;
    let initialOrientation;
    let previousTimestamp = null;

    let readingIMU = false;
    let channelIdentifier = sensorService.getDeviceId() + ":imu";

    onMount(() => {
        // Now you can use sensorService.setupChannel, etc.
        if (!sensorService) {
            console.error("Sensor service not available!"); // Add error handling
        }
    });

    onDestroy(() => {
        // ... IMU cleanup (same as before)
        sensorService.leaveChannel(channelIdentifier);
    });

    function imuAvailable() {
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

        console.log("IMU type: ", imuType);

        if (imuType === "mobile") {
            try {
                const metadata = {
                    sensor_name: channelIdentifier,
                    sensor_id: sensorService.getDeviceId() + ":imu",
                    sensor_type: "imu",
                    sampling_rate: imuFrequency,
                };

                sensorService.setupChannel(channelIdentifier, metadata);

                console.log("IMU frequency", imuFrequency, "Hz");

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

                absoluteorientation.addEventListener("reading", () => handleMobileIMU());

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
                console.log("stop mobileIMU");
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
            sensorService.leaveChannel(channelIdentifier);

            imuData = null; // Reset data when stopped
        }
    }

    function handleDeviceMotion(event) {
        console.log("handleDeviceMotion");
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
            uuid: channelIdentifier, // Or some other unique ID for IMU data
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
         
        console.log(madgwick.toVector(), gyroscope, accelerometer, absoluteorientation);
        //console.log(madgwick.getEulerAngles(), gyroscope, accelerometer, absoluteorientation);
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

        let output = {
            t: Math.round(new Date().getTime()), // time
            a: {
                // acceleration
                x: imuData.a.x.toFixed(4),
                y: imuData.a.y.toFixed(4),
                z: imuData.a.z.toFixed(4),
            },
            o: {
                //  orientation
                x: rotationAngles.x,
                y: rotationAngles.y,
                z: rotationAngles.z,
            },
            r: {
                // rotation rate
                x: imuData.r.x.toFixed(4),
                y: imuData.r.y.toFixed(4),
                z: imuData.r.z.toFixed(4),
            },
            i: dt.toFixed(4), // interval
        };

        logger.log(
            loggerCtxName,
            "handleMobileIMU",
            initialOrientation,
            output.o,
            dt,
        );

        imuOutput = output;

        let payload = {
            payload: JSON.stringify(output),
            uuid: channelIdentifier,
            timestamp: Math.round(new Date().getTime()),
        };

        sensorService.sendChannelMessage(channelIdentifier, payload);

        //return JSON.stringify(output); // Return object as JSON string
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

    onDestroy(() => {
        stopIMU();
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

            <p>{JSON.stringify(imuOutput)}</p>
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

<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    /*const AHRS = require('./www-ahrs.js');

    const madgwick = new AHRS({
        sampleInterval: 20,
        algorithm: 'Madgwick',
        beta: 0.4,
        kp: 0.5,
        ki: 0,
    });*/

    let sensorService = getContext("sensorService");

    let imuFrequency = 5; //Default IMU frequency
    let imuData = null;
    let initialOrientation = null;
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

    function handleMobileIMU(
        accelerometer,
        gyroscope,
        dt,
        initialOrientation = { alpha: 0, beta: 0, gamma: 0 },
    ) {
        let imuData = {
            a: {
                // acceleration
                x: accelerometer.x,
                y: accelerometer.y,
                z: accelerometer.z,
            },
            r: {
                // rotation rate
                x: gyroscope.x,
                y: gyroscope.y,
                z: gyroscope.z,
            },
        };
        imuData.rotationAngles = rotationRateToAngle(
            imuData.r.x,
            imuData.r.y,
            imuData.r.z,
            initialOrientation,
        ); // use correct values.

        let output = {
            t: Math.round(new Date().getTime()), // time
            a: {
                x: imuData.acceleration.x.toFixed(4),
                y: imuData.acceleration.y.toFixed(4),
                z: imuData.acceleration.z.toFixed(4),
            },
            o: {
                // orientation
                x: imuData.rotationAngles.x,
                y: imuData.rotationAngles.y,
                z: imuData.rotationAngles.z,
            },
            r: {
                // rotation rate
                x: imuData.rotationRate.alpha.toFixed(4),
                y: imuData.rotationRate.beta.toFixed(4),
                z: imuData.rotationRate.gamma.toFixed(4),
            },
            i: dt.toFixed(4), // interval
        };

        return JSON.stringify(output); // Return output as a valid JSON object
    }

    function rotationRateToAngle(alpha, beta, gamma, initialOrientation) {
        // Convert radians to degrees
        const alphaDeg = alpha * (180 / Math.PI);
        const betaDeg = beta * (180 / Math.PI);
        const gammaDeg = gamma * (180 / Math.PI);

        // Add initial orientation (for absolute rotation).
        return {
            x: (alphaDeg + initialOrientation.alpha).toFixed(1),
            y: (betaDeg + initialOrientation.beta).toFixed(1),
            z: (gammaDeg + initialOrientation.gamma).toFixed(1),
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
            ><button on:click={initialOrientation=null} class="btn btn-blue text-xs">Cal</button
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

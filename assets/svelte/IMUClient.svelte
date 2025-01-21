<script>
    import {getContext, createEventDispatcher, onDestroy, onMount} from 'svelte';

    /*const AHRS = require('./www-ahrs.js');

    const madgwick = new AHRS({
        sampleInterval: 20,
        algorithm: 'Madgwick',
        beta: 0.4,
        kp: 0.5,
        ki: 0,
    });*/

    let sensorService = getContext('sensorService');

    let imuFrequency = 5; //Default IMU frequency
    let imuData = null;
    let initialOrientation = null;
    let readingIMU = false;
    let channelIdentifier = sensorService.getDeviceId() + ":IMU";

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

        if ('LinearAccelerationSensor' in window && 'Gyroscope' in window) {
            // Both Linear Acceleration and Gyroscope sensors are available. This is ideal for mobile devices.
            return 'mobile';
        } else if (window.DeviceMotionEvent) {
            // DeviceMotionEvent is available, but specific sensor types are not guaranteed. This might work on some desktops.
            return 'desktop'; // Or 'maybe' if you're unsure
        } else {
            // No motion sensors are available
            return false;
        }
    }

    async function startIMU() {

        let imuType = imuAvailable();

        console.log("IMU type: ", imuType);

        if (imuType === 'mobile') {
            try {
                sensorService.setupChannel(channelIdentifier);

                console.log('IMU frequency', imuFrequency, 'Hz');

                accelerometer = new LinearAccelerationSensor({frequency: imuFrequency});
                gyroscope = new Gyroscope({frequency: imuFrequency});

                accelerometer.addEventListener('reading', () => handleMobileIMU());
                gyroscope.addEventListener('reading', () => handleMobileIMU());

                await accelerometer.start();// Promise, resolves if started succesfully
                await gyroscope.start();

                readingIMU = true;
            } catch (error) {
                // Handle errors, e.g., sensor not available or permission denied
                console.error("Error starting IMU sensors:", error);
                readingIMU = false; // Set readingIMU to false if an error occurs
            }

        } else if (imuType === 'desktop') {
            readingIMU = true;
            window.addEventListener("devicemotion", handleDeviceMotion);
        }
    }

    function stopIMU() {
        if (readingIMU) {

            let imuType = imuAvailable();

            if (imuType === 'mobile') {
                console.log('stop mobileIMU');
                accelerometer.removeEventListener('reading', () => handleMobileIMU());
                gyroscope.removeEventListener('reading', () => handleMobileIMU());
                accelerometer.stop();
                gyroscope.stop();
            } else if (imuType === 'desktop') {
                window.removeEventListener("devicemotion", handleDeviceMotion);
            }

            readingIMU = false;
            sensorService.leaveChannel(channelIdentifier)

            imuData = null; // Reset data when stopped
        }
    }

    function handleDeviceMotion(event) {
        console.log("handleDeviceMotion");
        imuData = {
            acceleration: {
                x: event.acceleration.x,
                y: event.acceleration.y,
                z: event.acceleration.z
            },
            accelerationIncludingGravity: {
                x: event.accelerationIncludingGravity.x,
                y: event.accelerationIncludingGravity.y,
                z: event.accelerationIncludingGravity.z
            },
            rotationRate: {
                alpha: event.rotationRate.alpha,
                beta: event.rotationRate.beta,
                gamma: event.rotationRate.gamma
            },
            interval: event.interval
        };

        imuData.rotationAngles = rotationRateToAngle(imuData.rotationRate.alpha, imuData.rotationRate.beta, imuData.rotationRate.gamma);

        let payload = { // same as before ...
            number: imuData.rotationAngles.x + "," + imuData.rotationAngles.y + "," + imuData.rotationAngles.z,
            uuid: channelIdentifier, // Or some other unique ID for IMU data
            timestamp: Math.round((new Date()).getTime()),
        };

        sensorService.sendChannelMessage(channelIdentifier, payload);
    }

    function handleMobileIMU() {

        let dt = 0;
        if (imuData && imuData.timestamp) {
            dt = (timestamp - imuData.timestamp) / 1000; // Convert milliseconds to seconds
        }

        console.log("handleMobileIMU");
        imuData = {
            acceleration: {
                x: accelerometer.x,
                y: accelerometer.y,
                z: accelerometer.z,
            },
            rotationRate: {
                alpha: gyroscope.x,
                beta: gyroscope.y,
                gamma: gyroscope.z,
            },
        };

        let firstSensorValue = imuData == null;

        imuData.rotationAngles = rotationRateToAngle(imuData.rotationRate.alpha, imuData.rotationRate.beta, imuData.rotationRate.gamma);
        imuData.relativeOrientation = updateOrientation(imuData.acceleration, imuData.rotationRate, dt);

        let rotationAnglesDelta = Math.abs(imuData.rotationAngles.x + imuData.rotationAngles.y + imuData.rotationAngles.z);
        //console.log("rotationAnglesDelta: " + rotationAnglesDelta, imuData.rotationAngles);

        //madgwick.update(gyroscope.x, gyroscope.y, gyroscope.z, accelerometer.x, accelerometer.y, accelerometer.z); // , compass.x, compass.y, compass.z
        //console.log("madgwick", madgwick.toVector());

        if (!firstSensorValue && rotationAnglesDelta < 0.3) {
            return;
        }

        let payload = { // same as before ...
            //number: imuData.relativeOrientation.roll + ',' + imuData.relativeOrientation.pitch + ',' + imuData.relativeOrientation.yaw,
            payload: imuData.rotationAngles.x + "," + imuData.rotationAngles.y + "," + imuData.rotationAngles.z,
            uuid: channelIdentifier, // Or some other unique ID for IMU data
            timestamp: Math.round((new Date()).getTime()),
        };

        sensorService.sendChannelMessage(channelIdentifier, payload);

    }

    function updateOrientation(accelData, gyroData, dt) {
        const rollAccel = Math.atan2(accelData.y, accelData.z) * 180 / Math.PI;
        const pitchAccel = Math.atan2(-accelData.x, Math.sqrt(accelData.y * accelData.y + accelData.z * accelData.z)) * 180 / Math.PI;

        // If initialOrientation hasn't been set yet, this is the first reading
        if (!initialOrientation) {
            initialOrientation = {roll: rollAccel, pitch: pitchAccel, yaw: 0};
        }

        let yawDelta = gyroData.z * dt;  // Change in yaw since last reading


        // Calculate changes relative to the initial orientation
        const rollDelta = (rollAccel - initialOrientation.roll)
        const pitchDelta = pitchAccel - initialOrientation.pitch;
        const yaw = initialOrientation.yaw + yawDelta;

        initialOrientation.yaw = yaw;

        const relativeOrientation = {roll: rollDelta, pitch: pitchDelta, yaw: yaw};
        return relativeOrientation; // Now you have relative changes from the beginning.
    }

    function rotationRateToAngle(alpha, beta, gamma) {
        return {
            x: Number.parseFloat((alpha * (180 / Math.PI)).toFixed(1)),
            y: Number.parseFloat((beta * (180 / Math.PI)).toFixed(1)),
            z: Number.parseFloat((gamma * (180 / Math.PI)).toFixed(1))
        }
    }

    onDestroy(() => {
        stopIMU();
    });

</script>

{#if imuAvailable()}
    <div>
        {#if readingIMU }
            <button on:click={() => stopIMU()} class="btn btn-blue text-xs">Stop IMU</button>
            { imuFrequency } Hz
        {/if}
        {#if !readingIMU }
            <button on:click={() => startIMU()} class="btn btn-blue text-xs">Start IMU</button>
            <input type="number" bind:value={imuFrequency} min="1" max="50" aria-describedby="Frequency of IM"
                   required/> Hz
        {/if}
    </div>
{/if}

<script>
    import { getContext, onDestroy, onMount } from "svelte";

    let sensorService = getContext("sensorService");
    let channelIdentifier = sensorService.getDeviceId() + ":bat";
    let batteryData = null;

    const startBatterySensor = async () => {
        if ("getBattery" in navigator) {
            const metadata = {
                sensor_name: channelIdentifier,
                sensor_id: channelIdentifier,
                sensor_type: "battery",
                sampling_rate: 1,
            };

            sensorService.setupChannel(channelIdentifier, metadata);
            try {
                const battery = await navigator.getBattery();
                updateBatteryData(battery); // Initial data

                battery.addEventListener("levelchange", () => {
                    updateBatteryData(battery);
                });

                battery.addEventListener("chargingchange", () => {
                    updateBatteryData(battery);
                });
            } catch (err) {
                batteryData = { error: err.message }; // Error handling for getBattery()
            }
        } else {
            batteryData = { error: "Battery Status API not supported" };
        }
    };

    const updateBatteryData = (battery) => {
        batteryData = {
            level: (battery.level * 100).toFixed(0),
            charging: battery.charging,
            timestamp: Math.round(new Date().getTime()),
        };

        let payload = {
            payload: JSON.stringify({
                level: batteryData.level,
                charging: batteryData.charging ? "yes" : "no",
            }),
            uuid: channelIdentifier,
            timestamp: batteryData.timestamp,
        };
        sensorService.sendChannelMessage(channelIdentifier, payload);
    };

    async function stopBatterySensor() {
        const battery = await navigator.getBattery();
        battery.removeEventListener("levelchange", updateBatteryData);
        battery.removeEventListener("chargingchange", updateBatteryData);
        sensorService.leaveChannel(channelIdentifier);
        batteryData = null;
    }

    onDestroy(() => {
        sensorService.leaveChannel(channelIdentifier); // Important: Leave the channel
    });
</script>

{#if batteryData != null}
    <button class="btn btn-blue text-xs" on:click={stopBatterySensor}
        >Stop Battery Status</button
    >
{:else if "getBattery" in navigator}
    <button class="btn btn-blue text-xs" on:click={startBatterySensor}
        >Start Battery Status</button
    >
{/if}

{#if batteryData}
    {#if batteryData.error}
        <p style="color: red">{batteryData.error}</p>
    {:else}
        <p>Level: {batteryData.level}%</p>
        <p>Charging: {batteryData.charging ? "Yes" : "No"}</p>
    {/if}
{/if}

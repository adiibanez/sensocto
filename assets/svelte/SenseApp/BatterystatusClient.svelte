<script>
  import { getContext, onDestroy, onMount } from "svelte";
  import { usersettings, autostart } from "./stores.js";
  import { logger } from "../logger_svelte.js";

  let loggerCtxName = "BatteryStatusClient";

  let sensorService = getContext("sensorService");
  let channelIdentifier = sensorService.getDeviceId();
  let batteryData = null;

  let unsubscribeSocket;

  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "pre Autostart update", value, batteryData);

    if (value == true && !batteryData) {
      unsubscribeSocket = sensorService.onSocketReady(() => {
        logger.log(loggerCtxName, "Autostart", value, autostart);
        startBatterySensor();
      });
    }
  });

  const startBatterySensor = async () => {
    if ("getBattery" in navigator) {
      sensorService.setupChannel(channelIdentifier);
      sensorService.registerAttribute(sensorService.getDeviceId(), {
        attribute_id: "battery",
        attribute_type: "battery",
        sampling_rate: 1,
      });

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
      payload: {
        level: parseInt(batteryData.level),
        charging: batteryData.charging ? "yes" : "no",
      },
      attribute_id: "battery",
      timestamp: batteryData.timestamp,
    };
    sensorService.sendChannelMessage(channelIdentifier, payload);
  };

  async function stopBatterySensor() {
    const battery = await navigator.getBattery();
    battery.removeEventListener("levelchange", updateBatteryData);
    battery.removeEventListener("chargingchange", updateBatteryData);

    sensorService.unregisterAttribute(sensorService.getDeviceId(), "battery");

    sensorService.leaveChannelIfUnused(channelIdentifier);
    batteryData = null;
  }

  onMount(() => {
    unsubscribeSocket = sensorService.onSocketReady(() => {
      if (autostart == true) {
        logger.log(
          loggerCtxName,
          "onMount onSocketReady Autostart going to start",
          autostart
        );
        startBatterySensor();
      }
    });

    sensorService.onSocketDisconnected(() => {
      if (batteryData) {
        stopBatterySensor();
      }
    });
  });

  onDestroy(() => {
    if (unsubscribeSocket) {
      unsubscribeSocket();
    }
    console.log("sensorService", sensorService);
    stopBatterySensor();
    sensorService.leaveChannelIfUnused(channelIdentifier); // Important: Leave the channel
  });
</script>

{#if !$autostart && batteryData != null}
  <button class="btn btn-blue text-xs" on:click={stopBatterySensor}
    >Stop Battery Status</button
  >
{:else if !$autostart && "getBattery" in navigator}
  <button class="btn btn-blue text-xs" on:click={startBatterySensor}
    >Start Battery Status</button
  >
{/if}

{#if batteryData}
  {#if batteryData.error}
    <p style="color: red">{batteryData.error}</p>
    <!--{:else}
        <p>Level: {batteryData.level}%</p>
        <p>Charging: {batteryData.charging ? "Yes" : "No"}</p>-->
  {/if}
{/if}

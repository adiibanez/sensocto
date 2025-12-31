<script>
  import { getContext, onDestroy, onMount } from "svelte";
  import { usersettings, autostart } from "./stores.js";
  import { logger } from "../logger_svelte.js";

  let loggerCtxName = "BatteryStatusClient";

  let sensorService = getContext("sensorService");
  let channelIdentifier = sensorService.getDeviceId();
  let batteryData = null;
  let batteryStatus = null; // Track API availability status
  let batteryRef = null; // Store battery reference for cleanup

  let unsubscribeSocket;

  // Check if Battery Status API is available
  const checkBatterySupport = () => {
    if (!("getBattery" in navigator)) {
      batteryStatus = "unsupported";
      return false;
    }
    return true;
  };

  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "pre Autostart update", value, batteryData);

    if (value == true && !batteryData) {
      unsubscribeSocket = sensorService.onSocketReady(() => {
        logger.log(loggerCtxName, "Autostart", value, autostart);
        requestAndStartBattery();
      });
    }
  });

  const requestAndStartBattery = async () => {
    if (!checkBatterySupport()) {
      batteryData = { error: "Battery Status API not supported in this browser (Safari, iOS, and some browsers don't support it)" };
      return;
    }

    await startBatterySensorInternal();
  };

  const startBatterySensor = () => {
    requestAndStartBattery();
  };

  const startBatterySensorInternal = async () => {
    if ("getBattery" in navigator) {
      sensorService.setupChannel(channelIdentifier);
      sensorService.registerAttribute(sensorService.getDeviceId(), {
        attribute_id: "battery",
        attribute_type: "battery",
        sampling_rate: 1,
      });

      try {
        const battery = await navigator.getBattery();
        batteryRef = battery;
        batteryStatus = "active";
        updateBatteryData(battery); // Initial data

        battery.addEventListener("levelchange", () => {
          updateBatteryData(battery);
        });

        battery.addEventListener("chargingchange", () => {
          updateBatteryData(battery);
        });

        logger.log(loggerCtxName, "Battery sensor started successfully");
      } catch (err) {
        batteryStatus = "error";
        let errorMessage;

        // Handle specific error types
        if (err.name === "NotAllowedError") {
          errorMessage = "Battery access not allowed. This may be due to browser privacy settings.";
        } else if (err.name === "NotSupportedError") {
          errorMessage = "Battery Status API not supported in this context.";
        } else if (err.name === "SecurityError") {
          errorMessage = "Battery access blocked for security reasons. Try using HTTPS.";
        } else {
          errorMessage = err.message || "Unknown error accessing battery status";
        }

        logger.log(loggerCtxName, "Battery error:", err.name, errorMessage);
        batteryData = { error: errorMessage };
      }
    } else {
      batteryStatus = "unsupported";
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
    if (batteryRef) {
      batteryRef.removeEventListener("levelchange", updateBatteryData);
      batteryRef.removeEventListener("chargingchange", updateBatteryData);
      batteryRef = null;
    }

    sensorService.unregisterAttribute(sensorService.getDeviceId(), "battery");
    sensorService.leaveChannelIfUnused(channelIdentifier);

    batteryData = null;
    batteryStatus = null;
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

{#if !$autostart}
  {#if batteryStatus === "unsupported" || !("getBattery" in navigator)}
    <div class="text-xs text-gray-400 p-2 bg-gray-800/50 rounded">
      <p>Battery Status not available</p>
      <p class="text-gray-500 mt-1">Safari and iOS don't support the Battery API.</p>
    </div>
  {:else if batteryStatus === "error"}
    <div class="text-xs text-yellow-400 p-2 bg-yellow-900/20 rounded">
      <p>Battery Status error</p>
      {#if batteryData?.error}
        <p class="text-gray-400 mt-1">{batteryData.error}</p>
      {/if}
    </div>
  {:else if batteryStatus === "active" && batteryData != null}
    <button class="btn btn-blue text-xs" on:click={stopBatterySensor}
      >Stop Battery Status</button
    >
  {:else}
    <button class="btn btn-blue text-xs" on:click={startBatterySensor}
      >Start Battery Status</button
    >
  {/if}
{/if}

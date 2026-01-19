<script>
  import { getContext, onDestroy, onMount } from "svelte";
  import { get } from "svelte/store";
  import { usersettings, autostart } from "./stores.js";
  import { logger } from "../logger_svelte.js";

  export let compact = false;

  let loggerCtxName = "BatteryStatusClient";

  let sensorService = getContext("sensorService");
  let channelIdentifier = sensorService.getDeviceId();
  let batteryData = null;
  let batteryStatus = null; // Track API availability status
  let batteryRef = null; // Store battery reference for cleanup

  let unsubscribeSocket;
  let batteryStarted = false; // Track if battery sensor was started

  // Check if Battery Status API is available
  const checkBatterySupport = () => {
    if (!("getBattery" in navigator)) {
      batteryStatus = "unsupported";
      return false;
    }
    return true;
  };

  // Track if we've subscribed to socket ready
  let autostartUnsubscribe = null;

  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "Autostart update", value, "batteryStarted:", batteryStarted);

    if (value === true && !batteryStarted) {
      // Clean up previous subscription if any
      if (autostartUnsubscribe) {
        autostartUnsubscribe();
        autostartUnsubscribe = null;
      }

      // Register for socket ready - this will fire immediately if socket is already ready
      autostartUnsubscribe = sensorService.onSocketReady(() => {
        logger.log(loggerCtxName, "Autostart triggered via subscribe, starting battery");
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
    if (batteryStarted) {
      logger.log(loggerCtxName, "Battery sensor already started, skipping");
      return;
    }

    if ("getBattery" in navigator) {
      batteryStarted = true;
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
    batteryStarted = false;
  }

  onMount(() => {
    unsubscribeSocket = sensorService.onSocketReady(() => {
      const autostartValue = get(autostart);
      if (autostartValue === true) {
        logger.log(
          loggerCtxName,
          "onMount onSocketReady Autostart going to start",
          autostartValue
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
    if (autostartUnsubscribe) {
      autostartUnsubscribe();
    }
    logger.log(loggerCtxName, "onDestroy - cleaning up");
    stopBatterySensor();
    sensorService.leaveChannelIfUnused(channelIdentifier);
  });
</script>

{#if compact}
  {#if "getBattery" in navigator}
    <button
      on:click={batteryStarted ? stopBatterySensor : startBatterySensor}
      class="icon-btn"
      class:active={batteryStarted}
      class:unsupported={batteryStatus === "unsupported"}
      title={batteryStatus === "unsupported" ? "Battery API not supported" : batteryStarted ? "Stop Battery" : "Start Battery"}
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
        <path d="M21.75 10.5h-.375a.375.375 0 00-.375.375v2.25c0 .207.168.375.375.375h.375a.375.375 0 00.375-.375v-2.25a.375.375 0 00-.375-.375zM3 7.5A1.5 1.5 0 014.5 6h13.5A1.5 1.5 0 0119.5 7.5v9a1.5 1.5 0 01-1.5 1.5H4.5A1.5 1.5 0 013 16.5v-9z"/>
      </svg>
    </button>
  {/if}
{:else if batteryStatus === "unsupported" || !("getBattery" in navigator)}
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
{:else if !$autostart}
  {#if batteryStatus === "active" && batteryData != null}
    <button class="btn btn-blue text-xs" on:click={stopBatterySensor}>Stop Battery</button>
  {:else}
    <button class="btn btn-blue text-xs" on:click={startBatterySensor}>Start Battery</button>
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
    background: #eab308;
    color: white;
  }
  .icon-btn.unsupported {
    opacity: 0.4;
    cursor: not-allowed;
  }
</style>

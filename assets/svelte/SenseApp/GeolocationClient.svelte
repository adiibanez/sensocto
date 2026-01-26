<script>
  import { getContext, onMount, onDestroy } from "svelte";
  import { get } from "svelte/store";
  import { logger } from "../logger_svelte.js";
  import { usersettings, autostart, sensorSettings } from "./stores.js";

  export let compact = false;

  console.log("Here2");

  let loggerCtxName = "GeolocationClient";

  let sensorService = getContext("sensorService");
  let channelIdentifier = sensorService.getDeviceId();
  let geolocationData = null;
  let watchId = null; // To store the watchPosition ID
  let permissionState = null; // Track permission state

  let unsubscribeSocket;

  logger.log(loggerCtxName, "GeolocationClient");
  console.log("GeolocationClient test");

  // Check geolocation permission status
  const checkPermission = async () => {
    if (!navigator.permissions) {
      // Permissions API not supported, try geolocation directly
      return "prompt";
    }

    try {
      const result = await navigator.permissions.query({ name: "geolocation" });
      permissionState = result.state;

      // Listen for permission changes
      result.onchange = () => {
        permissionState = result.state;
        logger.log(loggerCtxName, "Permission state changed:", permissionState);

        if (permissionState === "denied") {
          stopGeolocation();
          geolocationData = { error: "Location permission denied. Please enable it in your browser settings." };
        }
      };

      return result.state;
    } catch (error) {
      logger.log(loggerCtxName, "Permission check failed:", error);
      return "prompt";
    }
  };

  // Request permission and start geolocation
  const requestAndStartGeolocation = async () => {
    if (!navigator.geolocation) {
      geolocationData = { error: "Geolocation not supported by this browser" };
      return;
    }

    const permission = await checkPermission();

    if (permission === "denied") {
      geolocationData = { error: "Location permission denied. Please enable it in your browser settings." };
      return;
    }

    // For "prompt" or "granted", proceed with geolocation
    startGeolocationInternal();
  };

  // Wrapper functions that also persist to localStorage
  const enableGeolocation = () => {
    sensorSettings.setSensorEnabled('geolocation', true);
    requestAndStartGeolocation();
  };

  const disableGeolocation = () => {
    sensorSettings.setSensorEnabled('geolocation', false);
    stopGeolocation();
  };

  // Subscribe to sensor settings changes for auto-reconnect
  // Skip initial load - let onMount handle that
  let initialSettingsLoad = true;
  sensorSettings.subscribe((settings) => {
    logger.log(loggerCtxName, "sensorSettings update", settings.geolocation, geolocationData, "initialLoad:", initialSettingsLoad);

    if (initialSettingsLoad) {
      initialSettingsLoad = false;
      return;
    }

    // Only auto-start if explicitly enabled after initial load
    if (settings.geolocation?.enabled && settings.geolocation?.configured && !geolocationData && !watchId) {
      setTimeout(() => {
        logger.log(loggerCtxName, "Auto-reconnect triggered via sensorSettings");
        requestAndStartGeolocation();
      }, 1000);
    }
  });

  // Legacy autostart support (for backwards compatibility)
  // Only triggers if user has NEVER configured the sensor (configured=false)
  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "pre Autostart", value, geolocationData);

    // Check if user has explicitly configured this sensor - if so, respect their choice
    const geoConfigured = sensorSettings.isSensorConfigured('geolocation');
    if (geoConfigured) {
      logger.log(loggerCtxName, "Autostart skipped - geolocation already configured by user");
      return;
    }

    if (value == true && !geolocationData) {
      logger.log(loggerCtxName, "Autostart", value, autostart);

      setTimeout(() => {
        enableGeolocation();
      }, 1000);
    }
  });

  const startGeolocation = () => {
    requestAndStartGeolocation();
  };

  const startGeolocationInternal = () => {
    if (navigator.geolocation) {
      sensorService.setupChannel(channelIdentifier);
      sensorService.registerAttribute(sensorService.getDeviceId(), {
        attribute_id: "geolocation",
        attribute_type: "geolocation",
        sampling_rate: 1,
      });

      watchId = navigator.geolocation.watchPosition(
        (position) => {
          permissionState = "granted";
          geolocationData = {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy,
            timestamp: position.timestamp,
          };
          let payload = {
            payload: {
              latitude: geolocationData.latitude,
              longitude: geolocationData.longitude,
              accuracy: Number(geolocationData.accuracy.toFixed(1)),
            },
            // Combine lat/long for simplicity
            attribute_id: "geolocation",
            timestamp: Math.round(new Date().getTime()), // Ensure consistent timestamp format
          };

          logger.log(loggerCtxName, "Sending geolocation data", payload);
          sensorService.sendChannelMessage(channelIdentifier, payload);
        },
        (error) => {
          // Handle specific error codes
          let errorMessage;
          switch (error.code) {
            case error.PERMISSION_DENIED:
              permissionState = "denied";
              errorMessage = "Location permission denied. Please enable it in your browser settings.";
              break;
            case error.POSITION_UNAVAILABLE:
              errorMessage = "Location unavailable. Please check your device's location services.";
              break;
            case error.TIMEOUT:
              errorMessage = "Location request timed out. Please try again.";
              break;
            default:
              errorMessage = error.message || "Unknown geolocation error";
          }
          logger.log(loggerCtxName, "Geolocation error:", error.code, errorMessage);
          geolocationData = { error: errorMessage };
        },
        {
          enableHighAccuracy: true,
          timeout: 10000,
          maximumAge: 60000
        }
      );
    } else {
      geolocationData = { error: "Geolocation not supported" };
    }
  };

  const stopGeolocation = () => {
    if (watchId) {
      navigator.geolocation.clearWatch(watchId);
      watchId = null;
      geolocationData = null; // Reset data

      sensorService.unregisterAttribute(
        sensorService.getDeviceId(),
        "geolocation"
      );
      sensorService.leaveChannelIfUnused(channelIdentifier);
    }
  };

  onMount(() => {
    unsubscribeSocket = sensorService.onSocketReady(() => {
      // Check per-sensor settings first (takes precedence)
      const geoEnabled = sensorSettings.isSensorEnabled('geolocation');
      const geoConfigured = sensorSettings.isSensorConfigured('geolocation');

      logger.log(loggerCtxName, "onMount onSocketReady - checking settings", { geoEnabled, geoConfigured });

      // If user has ever configured geolocation settings, respect that choice
      if (geoConfigured) {
        if (geoEnabled) {
          logger.log(loggerCtxName, "onMount onSocketReady - Geolocation was previously enabled, restarting");
          requestAndStartGeolocation();
        } else {
          logger.log(loggerCtxName, "onMount onSocketReady - Geolocation is explicitly disabled, not starting");
        }
        return;
      }

      // Fall back to legacy autostart behavior only if geolocation was never configured
      const autostartValue = get(autostart);
      if (autostartValue === true) {
        enableGeolocation();
      }
    });

    sensorService.onSocketDisconnected(() => {
      if (geolocationData) {
        // Don't clear settings on disconnect - just stop the sensor
        stopGeolocation();
      }
    });
  });

  onDestroy(() => {
    console.log("onDestroy");
    if (unsubscribeSocket) {
      unsubscribeSocket();
    }

    stopGeolocation();
    sensorService.unregisterAttribute(
      sensorService.getDeviceId(),
      "geolocation"
    );
    sensorService.leaveChannelIfUnused(channelIdentifier);
  });
</script>

{#if navigator.geolocation}
  {#if compact}
    <button
      on:click={watchId ? disableGeolocation : enableGeolocation}
      class="icon-btn"
      class:active={watchId}
      class:error={permissionState === "denied"}
      title={permissionState === "denied" ? "Location denied" : watchId ? "Stop GPS" : "Start GPS"}
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
        <path fill-rule="evenodd" d="m11.54 22.351.07.04.028.016a.76.76 0 00.723 0l.028-.015.071-.041a16.975 16.975 0 001.144-.742 19.58 19.58 0 002.683-2.282c1.944-1.99 3.963-4.98 3.963-8.827a8.25 8.25 0 00-16.5 0c0 3.846 2.02 6.837 3.963 8.827a19.58 19.58 0 002.682 2.282 16.975 16.975 0 001.145.742zM12 13.5a3 3 0 100-6 3 3 0 000 6z" clip-rule="evenodd"/>
      </svg>
    </button>
  {:else if !$autostart}
    {#if permissionState === "denied"}
      <div class="text-xs text-red-400 p-2 bg-red-900/20 rounded">
        <p>Location permission denied.</p>
        <p class="text-gray-400 mt-1">Enable in browser settings to use geolocation.</p>
      </div>
    {:else if watchId}
      <button class="btn btn-blue text-xs" on:click={disableGeolocation}>Stop Geolocation</button>
    {:else}
      <button class="btn btn-blue text-xs" on:click={enableGeolocation}>Start Geolocation</button>
    {/if}
    {#if geolocationData}
      {#if geolocationData.error && permissionState !== "denied"}
        <p class="text-xs text-yellow-400 mt-1">{geolocationData.error}</p>
      {/if}
    {/if}
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
    background: #22c55e;
    color: white;
  }
  .icon-btn.error {
    background: #dc2626;
    color: white;
  }
</style>

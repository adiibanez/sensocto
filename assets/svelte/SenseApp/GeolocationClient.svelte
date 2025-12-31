<script>
  import { getContext, onMount, onDestroy } from "svelte";
  import { logger } from "../logger_svelte.js";
  import { usersettings, autostart } from "./stores.js";

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

  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "pre Autostart", value, geolocationData);
    if (value == true && !geolocationData) {
      logger.log(loggerCtxName, "Autostart", value, autostart);

      setTimeout(() => {
        requestAndStartGeolocation();
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
      if (autostart == true) {
        startGeolocation();
      }
    });

    sensorService.onSocketDisconnected(() => {
      if (geolocationData) {
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

{#if !$autostart && navigator.geolocation}
  {#if permissionState === "denied"}
    <div class="text-xs text-red-400 p-2 bg-red-900/20 rounded">
      <p>Location permission denied.</p>
      <p class="text-gray-400 mt-1">Enable in browser settings to use geolocation.</p>
    </div>
  {:else if watchId}
    <button class="btn btn-blue text-xs" on:click={stopGeolocation}
      >Stop Geolocation</button
    >
  {:else}
    <button class="btn btn-blue text-xs" on:click={startGeolocation}
      >Start Geolocation</button
    >
  {/if}
  {#if geolocationData}
    {#if geolocationData.error && permissionState !== "denied"}
      <p class="text-xs text-yellow-400 mt-1">{geolocationData.error}</p>
    {/if}
  {/if}
{/if}

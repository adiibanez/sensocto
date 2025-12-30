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

  let unsubscribeSocket;

  logger.log(loggerCtxName, "GeolocationClient");
  console.log("GeolocationClient test");

  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "pre Autostart", value, geolocationData);
    if (value == true && !geolocationData) {
      logger.log(loggerCtxName, "Autostart", value, autostart);

      setTimeout(() => {
        startGeolocation();
      }, 1000);
    }
  });

  const startGeolocation = () => {
    if (navigator.geolocation) {
      sensorService.setupChannel(channelIdentifier);
      sensorService.registerAttribute(sensorService.getDeviceId(), {
        attribute_id: "geolocation",
        attribute_type: "geolocation",
        sampling_rate: 1,
      });

      watchId = navigator.geolocation.watchPosition(
        (position) => {
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
          console.error("Geolocation error:", error);
          geolocationData = { error: error.message }; // Store error for display
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
  {#if watchId}
    <button class="btn btn-blue text-xs" on:click={stopGeolocation}
      >Stop Geolocation</button
    >
  {:else if !$autostart}
    <button class="btn btn-blue text-xs" on:click={startGeolocation}
      >Start Geolocation</button
    >
  {/if}
  {#if geolocationData}
    {#if geolocationData.error}
      <p style="color: red">{geolocationData.error}</p>
      <!--{:else}
      <p>Lat: {geolocationData.latitude}</p>
      <p>Lon: {geolocationData.longitude}</p>
      <p>Acc: {geolocationData.accuracy}m</p>-->
    {/if}
  {/if}
{/if}

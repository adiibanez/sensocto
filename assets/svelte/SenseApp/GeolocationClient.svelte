<script>
  import { getContext, onDestroy } from "svelte";
  import { logger } from "../logger_svelte.js";
  let loggerCtxName = "GoelocationClient";

  let sensorService = getContext("sensorService");
  let channelIdentifier = sensorService.getDeviceId();
  let geolocationData = null;
  let watchId = null; // To store the watchPosition ID

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
        },
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
        "geolocation",
      );
      sensorService.leaveChannelIfUnused(channelIdentifier);
    }
  };

  onDestroy(() => {
    console.log("onDestroy");
    stopGeolocation(); // Cleanup on component destroy
    sensorService.unregisterAttribute(
      sensorService.getDeviceId(),
      "geolocation",
    );
    sensorService.leaveChannelIfUnused(channelIdentifier); // ALWAYS leave channels on destroy!
  });
</script>

{#if navigator.geolocation}
  {#if watchId}
    <button class="btn btn-blue text-xs" on:click={stopGeolocation}
      >Stop Geolocation</button
    >
  {:else}
    <button class="btn btn-blue text-xs" on:click={startGeolocation}
      >Start Geolocation</button
    >
  {/if}
  {#if geolocationData}
    {#if geolocationData.error}
      <p style="color: red">{geolocationData.error}</p>
    {:else}
      <p>Latitude: {geolocationData.latitude}</p>
      <p>Longitude: {geolocationData.longitude}</p>
      <p>Accuracy: {geolocationData.accuracy} meters</p>
    {/if}
  {/if}
{/if}

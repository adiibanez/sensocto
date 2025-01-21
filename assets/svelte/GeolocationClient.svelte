<script>
    import { getContext, onDestroy } from 'svelte';
    let sensorService = getContext('sensorService');
    let channelIdentifier = sensorService.getDeviceId() + ":GEO";
    let geolocationData = null;
    let watchId = null;  // To store the watchPosition ID
  
    const startGeolocation = () => {
      if (navigator.geolocation) {

        sensorService.setupChannel(channelIdentifier);
        watchId = navigator.geolocation.watchPosition(position => {
          geolocationData = {
            latitude: position.coords.latitude,
            longitude: position.coords.longitude,
            accuracy: position.coords.accuracy,
            timestamp: position.timestamp,
          };
            let payload = {
              payload: geolocationData.latitude + "," + geolocationData.longitude + "," + Number((geolocationData.accuracy).toFixed(1)), // Combine lat/long for simplicity
              uuid: channelIdentifier,
              timestamp: Math.round((new Date()).getTime()), // Ensure consistent timestamp format
            };
          sensorService.sendChannelMessage(channelIdentifier, payload);
        }, error => {
          console.error("Geolocation error:", error);
          geolocationData = { error: error.message }; // Store error for display
        });
      } else {
        geolocationData = { error: "Geolocation not supported" };
      }
    };
  
    const stopGeolocation = () => {
      if (watchId) {
        navigator.geolocation.clearWatch(watchId);
        watchId = null;
        geolocationData = null; // Reset data

        sensorService.leaveChannel(channelIdentifier);
      }
    };
  
  
    onDestroy(() => {
      console.log("onDestroy");
      stopGeolocation(); // Cleanup on component destroy
      sensorService.leaveChannel(channelIdentifier); // ALWAYS leave channels on destroy!
    });
  
  </script>

  {#if navigator.geolocation }
    
    {#if watchId}
    <button class="btn btn-blue text-xs" on:click={stopGeolocation}>Stop Geolocation</button>
    {:else}
    <button class="btn btn-blue text-xs" on:click={startGeolocation}>Start Geolocation</button>
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
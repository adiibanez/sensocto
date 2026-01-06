<script>
  import { getContext, onMount, onDestroy } from "svelte";
  import { get } from "svelte/store";
  import { logger } from "../logger_svelte.js";
  import { autostart } from "./stores.js";

  let loggerCtxName = "RichPresenceClient";

  let sensorService = getContext("sensorService");
  let channelIdentifier = sensorService.getDeviceId();
  let presenceData = null;
  let presenceStatus = null;
  let isTracking = false;
  let pollInterval = null;
  let unsubscribeSocket = null;
  let autostartUnsubscribe = null;

  // Check if Media Session API is available
  const checkMediaSessionSupport = () => {
    if (!("mediaSession" in navigator)) {
      presenceStatus = "unsupported";
      return false;
    }
    return true;
  };

  // Get current media metadata
  const getMediaMetadata = () => {
    if (!navigator.mediaSession) return null;

    const metadata = navigator.mediaSession.metadata;
    const playbackState = navigator.mediaSession.playbackState;

    if (!metadata && playbackState === "none") {
      return null;
    }

    return {
      title: metadata?.title || null,
      artist: metadata?.artist || null,
      album: metadata?.album || null,
      artwork: metadata?.artwork?.[0]?.src || null,
      playbackState: playbackState || "none"
    };
  };

  // Poll for media changes (Media Session API doesn't have change events)
  const startPolling = () => {
    if (pollInterval) return;

    // Initial check
    updatePresence();

    // Poll every 2 seconds for changes
    pollInterval = setInterval(() => {
      updatePresence();
    }, 2000);
  };

  const stopPolling = () => {
    if (pollInterval) {
      clearInterval(pollInterval);
      pollInterval = null;
    }
  };

  const updatePresence = () => {
    const media = getMediaMetadata();

    // Check if media changed
    const hasChanged = !presenceData ||
      presenceData?.title !== media?.title ||
      presenceData?.artist !== media?.artist ||
      presenceData?.playbackState !== media?.playbackState;

    if (hasChanged) {
      presenceData = media;

      if (media && isTracking) {
        sendPresenceUpdate(media);
      } else if (!media && isTracking) {
        // Send "idle" state when no media is playing
        sendPresenceUpdate({
          title: null,
          artist: null,
          album: null,
          artwork: null,
          playbackState: "none"
        });
      }
    }
  };

  const sendPresenceUpdate = (data) => {
    const payload = {
      payload: {
        title: data.title || "",
        artist: data.artist || "",
        album: data.album || "",
        artwork_url: data.artwork || "",
        state: data.playbackState || "none",
        source: "media_session"
      },
      attribute_id: "rich_presence",
      timestamp: Math.round(Date.now())
    };

    logger.log(loggerCtxName, "Sending presence update", payload);
    sensorService.sendChannelMessage(channelIdentifier, payload);
  };

  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "Autostart update", value, "isTracking:", isTracking);

    if (value === true && !isTracking) {
      if (autostartUnsubscribe) {
        autostartUnsubscribe();
        autostartUnsubscribe = null;
      }

      autostartUnsubscribe = sensorService.onSocketReady(() => {
        logger.log(loggerCtxName, "Autostart triggered, starting presence tracking");
        startPresenceTracking();
      });
    }
  });

  const startPresenceTracking = async () => {
    if (isTracking) {
      logger.log(loggerCtxName, "Already tracking, skipping");
      return;
    }

    if (!checkMediaSessionSupport()) {
      presenceData = { error: "Media Session API not supported in this browser" };
      return;
    }

    isTracking = true;
    presenceStatus = "active";

    sensorService.setupChannel(channelIdentifier);
    sensorService.registerAttribute(channelIdentifier, {
      attribute_id: "rich_presence",
      attribute_type: "rich_presence",
      sampling_rate: 0.5 // Updates on change, ~0.5Hz polling
    });

    startPolling();
    logger.log(loggerCtxName, "Rich presence tracking started");
  };

  const stopPresenceTracking = () => {
    if (!isTracking) return;

    stopPolling();
    isTracking = false;
    presenceStatus = null;
    presenceData = null;

    sensorService.unregisterAttribute(channelIdentifier, "rich_presence");
    sensorService.leaveChannelIfUnused(channelIdentifier);

    logger.log(loggerCtxName, "Rich presence tracking stopped");
  };

  onMount(() => {
    unsubscribeSocket = sensorService.onSocketReady(() => {
      const autostartValue = get(autostart);
      if (autostartValue === true) {
        logger.log(loggerCtxName, "onMount onSocketReady - autostart enabled");
        startPresenceTracking();
      }
    });

    sensorService.onSocketDisconnected(() => {
      if (isTracking) {
        stopPresenceTracking();
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
    stopPresenceTracking();
  });

  // Format display for current media
  $: displayText = presenceData?.title
    ? `${presenceData.title}${presenceData.artist ? ` - ${presenceData.artist}` : ""}`
    : "No media playing";
</script>

{#if presenceStatus === "unsupported" || !("mediaSession" in navigator)}
  <div class="text-xs text-gray-400 p-2 bg-gray-800/50 rounded">
    <p>Rich Presence not available</p>
    <p class="text-gray-500 mt-1">Media Session API not supported.</p>
  </div>
{:else if !$autostart}
  {#if isTracking}
    <div class="flex items-center gap-2">
      <button class="btn btn-blue text-xs" on:click={stopPresenceTracking}>
        Stop Presence
      </button>
      {#if presenceData?.playbackState === "playing"}
        <span class="text-xs text-green-400 flex items-center gap-1">
          <span class="w-2 h-2 bg-green-400 rounded-full animate-pulse"></span>
          Playing
        </span>
      {:else if presenceData?.playbackState === "paused"}
        <span class="text-xs text-yellow-400">Paused</span>
      {:else}
        <span class="text-xs text-gray-400">Idle</span>
      {/if}
    </div>
    {#if presenceData?.title}
      <p class="text-xs text-gray-300 mt-1 truncate max-w-[200px]" title={displayText}>
        {displayText}
      </p>
    {/if}
  {:else}
    <button class="btn btn-blue text-xs" on:click={startPresenceTracking}>
      Start Presence
    </button>
  {/if}
{/if}

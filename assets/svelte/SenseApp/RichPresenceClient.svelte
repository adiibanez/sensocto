<script>
  import { getContext, onMount, onDestroy } from "svelte";
  import { get } from "svelte/store";
  import { logger } from "../logger_svelte.js";
  import { autostart, sensorSettings } from "./stores.js";

  export let compact = false;

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

  // Wrapper functions that also persist to localStorage
  const enableRichPresence = () => {
    sensorSettings.setSensorEnabled('richPresence', true);
    startPresenceTracking();
  };

  const disableRichPresence = () => {
    sensorSettings.setSensorEnabled('richPresence', false);
    stopPresenceTracking();
  };

  // Subscribe to sensor settings changes for auto-reconnect
  // Skip initial load - let onMount handle that
  let initialSettingsLoad = true;
  sensorSettings.subscribe((settings) => {
    logger.log(loggerCtxName, "sensorSettings update", settings.richPresence, "isTracking:", isTracking, "initialLoad:", initialSettingsLoad);

    if (initialSettingsLoad) {
      initialSettingsLoad = false;
      return;
    }

    // Only auto-start if explicitly enabled after initial load
    if (settings.richPresence?.enabled && settings.richPresence?.configured && !isTracking) {
      if (autostartUnsubscribe) {
        autostartUnsubscribe();
        autostartUnsubscribe = null;
      }

      autostartUnsubscribe = sensorService.onSocketReady(() => {
        logger.log(loggerCtxName, "Auto-reconnect triggered via sensorSettings, starting presence tracking");
        startPresenceTracking();
      });
    }
  });

  // Legacy autostart support (for backwards compatibility)
  // Only triggers if user has NEVER configured the sensor (configured=false)
  autostart.subscribe((value) => {
    logger.log(loggerCtxName, "Autostart update", value, "isTracking:", isTracking);

    // Check if user has explicitly configured this sensor - if so, respect their choice
    const richPresenceConfigured = sensorSettings.isSensorConfigured('richPresence');
    if (richPresenceConfigured) {
      logger.log(loggerCtxName, "Autostart skipped - rich presence already configured by user");
      return;
    }

    if (value === true && !isTracking) {
      if (autostartUnsubscribe) {
        autostartUnsubscribe();
        autostartUnsubscribe = null;
      }

      autostartUnsubscribe = sensorService.onSocketReady(() => {
        logger.log(loggerCtxName, "Autostart triggered, starting presence tracking");
        enableRichPresence();
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
      // Check per-sensor settings first (takes precedence)
      const richPresenceEnabled = sensorSettings.isSensorEnabled('richPresence');
      const richPresenceConfigured = sensorSettings.isSensorConfigured('richPresence');

      logger.log(loggerCtxName, "onMount onSocketReady - checking settings", { richPresenceEnabled, richPresenceConfigured });

      // If user has ever configured rich presence settings, respect that choice
      if (richPresenceConfigured) {
        if (richPresenceEnabled) {
          logger.log(loggerCtxName, "onMount onSocketReady - Rich presence was previously enabled, restarting");
          startPresenceTracking();
        } else {
          logger.log(loggerCtxName, "onMount onSocketReady - Rich presence is explicitly disabled, not starting");
        }
        return;
      }

      // Fall back to legacy autostart behavior only if rich presence was never configured
      const autostartValue = get(autostart);
      if (autostartValue === true) {
        logger.log(loggerCtxName, "onMount onSocketReady - autostart enabled");
        enableRichPresence();
      }
    });

    sensorService.onSocketDisconnected(() => {
      if (isTracking) {
        // Don't clear settings on disconnect - just stop the sensor
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

{#if compact}
  {#if "mediaSession" in navigator}
    <button
      on:click={isTracking ? disableRichPresence : enableRichPresence}
      class="icon-btn"
      class:active={isTracking}
      class:playing={presenceData?.playbackState === "playing"}
      title={isTracking ? (presenceData?.title || "Tracking media") : "Start Presence"}
    >
      <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" class="w-3.5 h-3.5">
        <path fill-rule="evenodd" d="M19.952 1.651a.75.75 0 01.298.599V16.303a3 3 0 01-2.176 2.884l-1.32.377a2.553 2.553 0 11-1.403-4.909l2.311-.66a1.5 1.5 0 001.088-1.442V6.994l-9 2.572v9.737a3 3 0 01-2.176 2.884l-1.32.377a2.553 2.553 0 11-1.402-4.909l2.31-.66a1.5 1.5 0 001.088-1.442V5.25a.75.75 0 01.544-.721l10.5-3a.75.75 0 01.658.122z" clip-rule="evenodd"/>
      </svg>
    </button>
  {/if}
{:else if presenceStatus === "unsupported" || !("mediaSession" in navigator)}
  <div class="text-xs text-gray-400 p-2 bg-gray-800/50 rounded">
    <p>Rich Presence not available</p>
    <p class="text-gray-500 mt-1">Media Session API not supported.</p>
  </div>
{:else if !$autostart}
  {#if isTracking}
    <div class="flex items-center gap-2">
      <button class="btn btn-blue text-xs" on:click={disableRichPresence}>
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
    <button class="btn btn-blue text-xs" on:click={enableRichPresence}>
      Start Presence
    </button>
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
    background: #8b5cf6;
    color: white;
  }
  .icon-btn.playing {
    background: #22c55e;
    color: white;
  }
</style>

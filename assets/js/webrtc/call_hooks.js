/**
 * LiveView Hooks for Video/Voice Calls
 * Coordinates between LiveView and WebRTC client
 *
 * Robust error handling and reconnection logic included.
 */

import { Socket } from "phoenix";
import { MembraneClient } from "./membrane_client.js";
import { MediaManager } from "./media_manager.js";
import { QualityManager } from "./quality_manager.js";
import { SpeakingDetector } from "./speaking_detector.js";
import { AdaptiveProducer } from "./adaptive_producer.js";
import { AdaptiveConsumer } from "./adaptive_consumer.js";

// Call states for robust state machine
const CallState = {
  IDLE: "idle",
  JOINING: "joining",
  CONNECTED: "connected",
  RECONNECTING: "reconnecting",
  LEAVING: "leaving",
  ERROR: "error",
};

// Media error types for user-friendly messages
const MediaErrorType = {
  NOT_ALLOWED: "not_allowed",
  NOT_FOUND: "not_found",
  NOT_READABLE: "not_readable",
  OVERCONSTRAINED: "overconstrained",
  UNKNOWN: "unknown",
};

function classifyMediaError(error) {
  const name = error?.name || "";
  const message = error?.message || "";

  if (name === "NotAllowedError" || name === "PermissionDeniedError") {
    return {
      type: MediaErrorType.NOT_ALLOWED,
      userMessage: "Camera/microphone access denied. Please allow access in your browser settings and try again.",
      canRetry: true,
    };
  }
  if (name === "NotFoundError" || name === "DevicesNotFoundError") {
    return {
      type: MediaErrorType.NOT_FOUND,
      userMessage: "No camera or microphone found. Please connect a device and try again.",
      canRetry: true,
    };
  }
  if (name === "NotReadableError" || name === "TrackStartError") {
    return {
      type: MediaErrorType.NOT_READABLE,
      userMessage: "Camera or microphone is already in use by another application. Please close other apps and try again.",
      canRetry: true,
    };
  }
  if (name === "OverconstrainedError") {
    return {
      type: MediaErrorType.OVERCONSTRAINED,
      userMessage: "Camera doesn't support the requested settings. Trying with lower quality.",
      canRetry: true,
    };
  }
  return {
    type: MediaErrorType.UNKNOWN,
    userMessage: message || "Failed to access camera/microphone. Please check your device settings.",
    canRetry: true,
  };
}

/**
 * Main Call Hook - manages the entire call lifecycle
 */
export const CallHook = {
  mounted() {
    this.roomId = this.el.dataset.roomId;
    this.userId = this.el.dataset.userId;
    this.userName = this.el.dataset.userName || "User";

    // Check if this is a persistent hook (mounted separately from UI container)
    this.isPersistent = this.el.id === "call-hook-persistent";

    this.membraneClient = null;
    this.mediaManager = new MediaManager();
    this.channel = null;
    this.socket = null;
    this.localStream = null;
    this.audioEnabled = true;
    this.videoEnabled = true;
    this.inCall = false;
    this.iceServers = [];

    // Robust state management
    this.callState = CallState.IDLE;
    this._destroyed = false;
    this._joinAttempts = 0;
    this._maxJoinAttempts = 3;
    this._channelReconnectTimer = null;

    this.participants = new Map();
    this.videoElements = new Map();
    this.pendingTracks = new Map();
    this.containerObserver = null;

    // Adaptive quality manager
    this.qualityManager = new QualityManager({
      onQualityChange: (level, settings) => this.handleQualityChange(level, settings),
      onStatsUpdate: (stats) => this.handleStatsUpdate(stats),
    });

    // Speaking detector for adaptive quality
    this.speakingDetector = new SpeakingDetector({
      onSpeakingChange: (speaking) => this._handleSpeakingChange(speaking),
      onVolumeChange: (volume) => this._handleVolumeChange(volume),
    });

    // Adaptive producer for tier-based video quality
    this.adaptiveProducer = new AdaptiveProducer({
      onModeChange: (tier, mode) => this._handleProducerModeChange(tier, mode),
      onSnapshot: (snapshot) => this._handleSnapshot(snapshot),
      onError: (error) => console.error("[CallHook] AdaptiveProducer error:", error),
    });

    // Current tier for this participant
    this.currentTier = "viewer";

    // Adaptive consumer for handling remote participants' video
    this.adaptiveConsumer = new AdaptiveConsumer({
      onModeChange: (userId, mode, tier) => {
        this.pushEvent("consumer_mode_changed", { user_id: userId, mode, tier });
      },
    });

    // Expose hook globally for debugging
    window.__callHook = this;
    console.log("[CallHook] mounted, exposed as window.__callHook");

    this.handleEvent("join_call", (data) => this.handleJoinCall(data));
    this.handleEvent("leave_call", () => this.handleLeaveCall());
    this.handleEvent("toggle_audio", (data) => this.handleToggleAudio(data));
    this.handleEvent("toggle_video", (data) => this.handleToggleVideo(data));
    this.handleEvent("set_quality", (data) => this.handleSetQuality(data));
    this.handleEvent("set_attention_level", (data) => this.handleSetAttentionLevel(data));
    this.handleEvent("set_participant_attention", (data) => this.handleSetParticipantAttention(data));

    // Handle visibility change to manage call state when tab is hidden/shown
    this._visibilityHandler = () => this._handleVisibilityChange();
    document.addEventListener("visibilitychange", this._visibilityHandler);

    // Handle focus/blur for attention tracking
    this._focusHandler = () => this._handleFocusChange(true);
    this._blurHandler = () => this._handleFocusChange(false);
    window.addEventListener("focus", this._focusHandler);
    window.addEventListener("blur", this._blurHandler);

    // Handle before unload to clean up properly
    this._beforeUnloadHandler = () => this._handleBeforeUnload();
    window.addEventListener("beforeunload", this._beforeUnloadHandler);
  },

  _setCallState(state) {
    if (this.callState !== state) {
      console.log(`[CallHook] State: ${this.callState} -> ${state}`);
      this.callState = state;
      this.pushEvent("call_state_changed", { state });
    }
  },

  _handleVisibilityChange() {
    if (document.hidden && this.inCall) {
      console.log("[CallHook] Tab hidden, call still active");
      // Send low attention state to server (idle tier)
      this._sendAttentionState("low");
    } else if (!document.hidden && this.inCall) {
      console.log("[CallHook] Tab visible, checking connection health");
      this._checkConnectionHealth();
      // Restore attention state based on focus
      this._sendAttentionState(document.hasFocus() ? "high" : "medium");
    }
  },

  _handleBeforeUnload() {
    if (this.inCall) {
      this.handleLeaveCall();
    }
  },

  _checkConnectionHealth() {
    if (this.membraneClient && !this.membraneClient.connected) {
      console.log("[CallHook] Connection unhealthy, triggering reconnect");
      this.pushEvent("connection_unhealthy", {});
    }
  },

  attachLocalStream() {
    // When persistent, look for video element in the separate call-container
    const localVideoEl = document.querySelector("#local-video video");
    if (localVideoEl && this.localStream) {
      localVideoEl.srcObject = this.localStream;
      localVideoEl.muted = true;
      console.log("[CallHook] Attached local stream to video element");
      return true;
    }
    // Not found - might be unmounted during mode switch (expected when persistent)
    if (this.isPersistent) {
      console.log("[CallHook] Local video element not found (persistent mode, UI may be hidden)");
    } else {
      console.log("[CallHook] Local video element not found, will retry...");
    }
    return false;
  },

  // Retry attaching local stream with exponential backoff
  attachLocalStreamWithRetry(maxRetries = 10, delay = 100) {
    let attempts = 0;
    const tryAttach = () => {
      if (this.attachLocalStream()) {
        return;
      }
      attempts++;
      if (attempts < maxRetries) {
        setTimeout(tryAttach, delay * Math.min(attempts, 5));
      } else {
        console.error("Failed to attach local stream after", maxRetries, "attempts");
      }
    };
    tryAttach();
  },

  async handleJoinCall(data) {
    if (this.inCall || this.callState === CallState.JOINING) {
      console.log("[CallHook] Already in call or joining, ignoring join request");
      return;
    }

    if (this._destroyed) {
      console.log("[CallHook] Hook destroyed, cannot join call");
      return;
    }

    const mode = data?.mode || "video";
    const withVideo = mode === "video";
    this.videoEnabled = withVideo;
    this._joinAttempts++;

    this._setCallState(CallState.JOINING);
    console.log(`[CallHook] Joining call (attempt ${this._joinAttempts}/${this._maxJoinAttempts}), mode: ${mode}`);

    try {
      // Step 1: Get local media FIRST - fail fast if no permissions
      console.log("[CallHook] Step 1: Acquiring local media...");
      try {
        if (withVideo) {
          this.localStream = await this.mediaManager.getMediaStream();
        } else {
          this.localStream = await this.mediaManager.getAudioOnlyStream();
        }
        console.log("[CallHook] Local media acquired successfully");
      } catch (mediaError) {
        const classified = classifyMediaError(mediaError);
        console.error("[CallHook] Media error:", classified);

        // Try fallback for overconstrained
        if (classified.type === MediaErrorType.OVERCONSTRAINED && withVideo) {
          console.log("[CallHook] Retrying with lower video quality...");
          try {
            this.localStream = await this.mediaManager.getMediaStream({
              video: { width: 640, height: 480, frameRate: 15 }
            });
          } catch (retryError) {
            throw new Error(classified.userMessage);
          }
        } else {
          throw new Error(classified.userMessage);
        }
      }

      // Step 2: Connect to Phoenix channel
      console.log("[CallHook] Step 2: Connecting to channel...");
      await this.connectToChannel();

      // Step 3: Join call on server
      console.log("[CallHook] Step 3: Joining call on server...");
      const response = await this.pushChannelEvent("join_call", {}, 15000);

      if (!response.endpoint_id) {
        throw new Error("Server did not return endpoint_id");
      }

      this.endpointId = response.endpoint_id;
      console.log("[CallHook] Got endpoint_id:", this.endpointId);

      // Step 4: Create and connect MembraneClient
      console.log("[CallHook] Step 4: Creating MembraneClient...");
      this.membraneClient = new MembraneClient({
        roomId: this.roomId,
        userId: this.userId,
        userInfo: { name: this.userName },
        channel: this.channel,
        connectionTimeout: 30000,
        maxReconnectAttempts: 3,
        reconnectDelay: 2000,
        onTrackReady: (ctx) => this.handleTrackReady(ctx),
        onTrackRemoved: (ctx) => this.handleTrackRemoved(ctx),
        onParticipantJoined: (peer) => this.handleParticipantJoined(peer),
        onParticipantLeft: (peer) => this.handleParticipantLeft(peer),
        onConnectionStateChange: (state) => this.handleConnectionStateChange(state),
        onError: (error) => this.handleError(error),
        onReconnecting: (attempt, max) => this._handleReconnecting(attempt, max),
        onReconnected: () => this._handleReconnected(),
      });

      // Step 5: Connect to WebRTC endpoint
      console.log("[CallHook] Step 5: Connecting to WebRTC endpoint...");
      await this.membraneClient.connect(this.iceServers);

      // Set up MutationObserver to watch for new participant containers
      this.setupContainerObserver();

      // Step 6: Add local tracks
      console.log("[CallHook] Step 6: Adding local tracks...");
      for (const track of this.localStream.getTracks()) {
        console.log(`[CallHook] Adding local ${track.kind} track: ${track.id}`);
        await this.membraneClient.addLocalTrack(track);
      }

      // Success!
      this.inCall = true;
      this._joinAttempts = 0;
      this._setCallState(CallState.CONNECTED);
      this.pushEvent("call_joined", { endpoint_id: this.endpointId });
      console.log("[CallHook] Successfully joined call");

      // Start quality monitoring
      this._startQualityMonitoring();

      // Start speaking detection for adaptive quality
      this._startSpeakingDetection();

      // Initialize adaptive producer with video track
      this._initAdaptiveProducer();

      // Attach local stream with retry
      this.attachLocalStreamWithRetry();

      // Handle existing participants
      Object.values(response.participants || {}).forEach((p) => {
        this.handleParticipantJoined(p);
      });

    } catch (error) {
      console.error("[CallHook] Failed to join call:", error);
      console.error("[CallHook] Error stack:", error?.stack);

      // Cleanup partial state
      this._cleanupPartialJoin();

      const message = typeof error === 'string' ? error : (error?.message || error?.reason || "Failed to join call");

      // Check if we should retry
      if (this._joinAttempts < this._maxJoinAttempts && this._isRetryableError(error)) {
        console.log(`[CallHook] Retrying join in 2 seconds...`);
        this._setCallState(CallState.RECONNECTING);
        this.pushEvent("call_joining_retry", { attempt: this._joinAttempts, max: this._maxJoinAttempts });

        setTimeout(() => {
          if (!this._destroyed && !this.inCall) {
            this.handleJoinCall(data);
          }
        }, 2000);
      } else {
        this._setCallState(CallState.ERROR);
        this._joinAttempts = 0;
        this.pushEvent("call_error", { message, canRetry: true });
      }
    }
  },

  _isRetryableError(error) {
    const message = error?.message || "";
    // Don't retry permission errors
    if (message.includes("denied") || message.includes("permission")) {
      return false;
    }
    // Retry network/timeout errors
    return message.includes("timeout") || message.includes("network") || message.includes("connection");
  },

  _cleanupPartialJoin() {
    if (this.membraneClient) {
      try {
        this.membraneClient.destroy();
      } catch (e) {
        // Ignore
      }
      this.membraneClient = null;
    }

    if (this.localStream) {
      this.localStream.getTracks().forEach(track => {
        try {
          track.stop();
        } catch (e) {
          // Ignore
        }
      });
      this.localStream = null;
    }

    // Don't disconnect channel here - we might want to retry
  },

  _startQualityMonitoring() {
    try {
      if (this.membraneClient?.webrtc) {
        const pc = this.membraneClient.webrtc.connection;
        if (pc) {
          this.qualityManager.setConnection(pc);
          this.qualityManager.start(1000);
        }
      }
    } catch (e) {
      console.warn("[CallHook] Failed to start quality monitoring:", e);
    }
  },

  _startSpeakingDetection() {
    if (this.localStream && this.speakingDetector) {
      this.speakingDetector.start(this.localStream);
      console.log("[CallHook] Speaking detection started");
    }
  },

  _stopSpeakingDetection() {
    if (this.speakingDetector) {
      this.speakingDetector.stop();
      console.log("[CallHook] Speaking detection stopped");
    }
  },

  _handleSpeakingChange(speaking) {
    console.log(`[CallHook] Speaking state changed: ${speaking}`);

    // Send to server via channel
    if (this.channel && this.inCall) {
      this.channel.push("speaking_state", { speaking });
    }

    // Notify LiveView for local UI updates
    this.pushEvent("speaking_changed", { speaking });
  },

  _handleVolumeChange(volume) {
    // Only push volume updates periodically to avoid flooding
    const now = Date.now();
    if (!this._lastVolumePush || now - this._lastVolumePush > 100) {
      this._lastVolumePush = now;
      // Volume is used for local UI (e.g., volume meter)
      // Not sent to server - only speaking state matters there
    }
  },

  _handleFocusChange(focused) {
    if (!this.inCall || document.hidden) {
      return;
    }

    console.log(`[CallHook] Focus changed: ${focused}`);
    // high = focused on this tab, medium = tab visible but not focused
    this._sendAttentionState(focused ? "high" : "medium");
  },

  _sendAttentionState(level) {
    if (this.channel && this.inCall) {
      console.log(`[CallHook] Sending attention state: ${level}`);
      this.channel.push("attention_state", { level });
    }
  },

  _initAdaptiveProducer() {
    if (!this.localStream || !this.adaptiveProducer) return;

    const videoTrack = this.localStream.getVideoTracks()[0];
    if (videoTrack) {
      // Get the sender for this track if available
      let sender = null;
      if (this.membraneClient?.webrtc?.connection) {
        const senders = this.membraneClient.webrtc.connection.getSenders();
        sender = senders.find(s => s.track?.kind === "video");
      }

      this.adaptiveProducer.init(videoTrack, sender);
      console.log("[CallHook] Adaptive producer initialized");
    }
  },

  _handleProducerModeChange(tier, mode) {
    console.log(`[CallHook] Producer mode changed: tier=${tier}, mode=${mode}`);
    this.pushEvent("producer_mode_changed", { tier, mode });
  },

  _handleSnapshot(snapshot) {
    // Send snapshot to server via channel for distribution to viewers
    if (this.channel && this.inCall) {
      this.channel.push("video_snapshot", {
        data: snapshot.data,
        width: snapshot.width,
        height: snapshot.height,
        timestamp: snapshot.timestamp,
      });
    }
  },

  _handleTierChange(tier) {
    if (tier === this.currentTier) return;

    console.log(`[CallHook] Tier changed: ${this.currentTier} -> ${tier}`);
    this.currentTier = tier;

    // Update adaptive producer with new tier
    if (this.adaptiveProducer) {
      this.adaptiveProducer.setTier(tier);
    }

    // Notify LiveView
    this.pushEvent("my_tier_changed", { tier });
  },

  _handleReconnecting(attempt, max) {
    console.log(`[CallHook] WebRTC reconnecting (${attempt}/${max})`);
    this._setCallState(CallState.RECONNECTING);
    this.pushEvent("call_reconnecting", { attempt, max });
  },

  _handleReconnected() {
    console.log("[CallHook] WebRTC reconnected");
    this._setCallState(CallState.CONNECTED);
    this.pushEvent("call_reconnected", {});
    this.attachLocalStreamWithRetry();
  },

  async handleLeaveCall() {
    if (!this.inCall && this.callState === CallState.IDLE) {
      console.log("[CallHook] Not in call, nothing to leave");
      return;
    }

    console.log("[CallHook] Leaving call...");
    this._setCallState(CallState.LEAVING);

    try {
      // Stop speaking detection
      this._stopSpeakingDetection();

      // Stop quality monitoring
      if (this.qualityManager) {
        try {
          this.qualityManager.stop();
        } catch (e) {
          console.warn("[CallHook] Error stopping quality manager:", e);
        }
      }

      // Disconnect WebRTC
      if (this.membraneClient) {
        try {
          this.membraneClient.destroy();
        } catch (e) {
          console.warn("[CallHook] Error disconnecting membrane client:", e);
        }
        this.membraneClient = null;
      }

      // Stop local tracks
      if (this.localStream) {
        this.localStream.getTracks().forEach(track => {
          try {
            track.stop();
          } catch (e) {
            // Ignore
          }
        });
        this.localStream = null;
      }

      // Notify server and leave channel
      if (this.channel) {
        try {
          await this.pushChannelEvent("leave_call", {}, 5000);
        } catch (e) {
          console.warn("[CallHook] Error notifying server of leave:", e);
        }
        try {
          this.channel.leave();
        } catch (e) {
          // Ignore
        }
        this.channel = null;
      }

      // Disconnect socket
      if (this.socket) {
        try {
          this.socket.disconnect();
        } catch (e) {
          // Ignore
        }
        this.socket = null;
      }

      this.clearRemoteVideos();

      this.inCall = false;
      this._joinAttempts = 0;
      this._setCallState(CallState.IDLE);
      this.pushEvent("call_left", {});
      console.log("[CallHook] Successfully left call");
    } catch (error) {
      console.error("[CallHook] Error during leave call:", error);
      // Still reset state even if cleanup had errors
      this.inCall = false;
      this._setCallState(CallState.IDLE);
      this.pushEvent("call_left", {});
    }
  },

  handleToggleAudio(data) {
    this.audioEnabled = data.enabled;

    if (this.membraneClient) {
      this.membraneClient.toggleAudio(this.audioEnabled);
    }

    if (this.channel) {
      this.channel.push("toggle_audio", { enabled: this.audioEnabled });
    }
  },

  handleToggleVideo(data) {
    this.videoEnabled = data.enabled;

    if (this.membraneClient) {
      this.membraneClient.toggleVideo(this.videoEnabled);
    }

    if (this.channel) {
      this.channel.push("toggle_video", { enabled: this.videoEnabled });
    }
  },

  handleSetQuality(data) {
    if (this.mediaManager) {
      this.mediaManager.setQualityProfile(data.quality);
    }
    if (this.qualityManager) {
      this.qualityManager.setQuality(data.quality);
    }
  },

  handleSetAttentionLevel(data) {
    if (this.qualityManager) {
      this.qualityManager.setAttentionLevel(data.level);
    }
  },

  handleSetParticipantAttention(data) {
    const { connector_id, level } = data;
    console.log(`[CallHook] Set participant attention: ${connector_id} -> ${level}`);

    const tier = this._attentionToTier(level);

    for (const [userId, participant] of this.participants) {
      if (this._matchesConnector(userId, participant, connector_id)) {
        console.log(`[CallHook] Found participant ${userId} for connector ${connector_id}, setting tier to ${tier}`);

        if (this.adaptiveConsumer) {
          this.adaptiveConsumer.setParticipantTier(userId, tier);
        }

        if (this.channel) {
          this.channel.push("request_quality_tier", { target_user_id: userId, tier });
        }
        break;
      }
    }
  },

  _matchesConnector(userId, participant, connectorId) {
    if (userId === connectorId) return true;
    if (participant?.user_info?.connector_id === connectorId) return true;
    if (participant?.metadata?.connector_id === connectorId) return true;
    if (participant?.connector_id === connectorId) return true;
    return false;
  },

  _attentionToTier(level) {
    switch (level) {
      case "high": return "active";
      case "medium": return "recent";
      case "low": return "viewer";
      default: return "viewer";
    }
  },

  handleQualityChange(level, settings) {
    console.log(`[CallHook] Quality changed to ${level}:`, settings);

    // Apply to media manager
    if (this.mediaManager) {
      this.mediaManager.setQualityProfile(level);
    }

    // Apply to RTCRtpSender if available
    if (this.membraneClient?.webrtc?.connection) {
      const pc = this.membraneClient.webrtc.connection;
      const senders = pc.getSenders();
      for (const sender of senders) {
        if (sender.track?.kind === "video") {
          this.qualityManager.applyToSender(sender);
        }
      }
    }

    // Notify LiveView
    this.pushEvent("quality_changed", {
      quality: level,
      settings: settings,
      summary: this.qualityManager.getStatsSummary()
    });
  },

  handleStatsUpdate(stats) {
    // Periodically push stats to LiveView for UI display (every 5 seconds)
    if (Date.now() - (this._lastStatsPush || 0) > 5000) {
      this._lastStatsPush = Date.now();
      const summary = this.qualityManager.getStatsSummary();
      if (summary) {
        this.pushEvent("webrtc_stats", summary);
      }
    }
  },

  async connectToChannel() {
    return new Promise((resolve, reject) => {
      const socketTimeout = setTimeout(() => {
        reject(new Error("Socket connection timeout"));
      }, 15000);

      this.socket = new Socket("/socket", {
        params: {},
        reconnectAfterMs: (tries) => {
          // Exponential backoff: 1s, 2s, 4s, 8s, max 10s
          return Math.min(1000 * Math.pow(2, tries - 1), 10000);
        },
      });

      this.socket.onError(() => {
        console.error("[CallHook] Socket error");
        if (!this._destroyed) {
          this.pushEvent("socket_error", {});
        }
      });

      this.socket.onClose(() => {
        console.log("[CallHook] Socket closed");
        if (this.inCall && !this._destroyed) {
          this._handleChannelDisconnect();
        }
      });

      this.socket.connect();

      this.channel = this.socket.channel(`call:${this.roomId}`, {
        user_id: this.userId,
        user_info: { name: this.userName },
      });

      this.channel.onError(() => {
        console.error("[CallHook] Channel error");
        if (this.inCall && !this._destroyed) {
          this._handleChannelDisconnect();
        }
      });

      this.channel.onClose(() => {
        console.log("[CallHook] Channel closed");
      });

      this.channel.on("media_event", (payload) => {
        if (this.membraneClient && !this._destroyed) {
          this.membraneClient.handleMediaEvent(payload.data);
        }
      });

      this.channel.on("participant_joined", (participant) => {
        if (!this._destroyed) {
          this.handleParticipantJoined(participant);
        }
      });

      this.channel.on("participant_left", (data) => {
        if (!this._destroyed) {
          this.handleParticipantLeft(data);
        }
      });

      this.channel.on("participant_audio_changed", (data) => {
        if (!this._destroyed) {
          this.updateParticipantAudioState(data.user_id, data.audio_enabled);
        }
      });

      this.channel.on("participant_video_changed", (data) => {
        if (!this._destroyed) {
          this.updateParticipantVideoState(data.user_id, data.video_enabled);
        }
      });

      this.channel.on("quality_changed", (data) => {
        if (!this._destroyed) {
          if (this.mediaManager) {
            this.mediaManager.setQualityProfile(data.quality);
          }
          this.pushEvent("quality_changed", data);
        }
      });

      // Adaptive quality: speaking state from other participants
      this.channel.on("participant_speaking", (data) => {
        if (!this._destroyed) {
          this.pushEvent("participant_speaking", {
            user_id: data.user_id,
            speaking: data.speaking
          });
        }
      });

      // Adaptive quality: tier changes from server
      this.channel.on("tier_changed", (data) => {
        if (!this._destroyed) {
          // Check if this is our own tier change
          if (data.user_id === this.userId) {
            this._handleTierChange(data.tier);
          } else {
            // Update adaptive consumer for remote participant
            if (this.adaptiveConsumer) {
              this.adaptiveConsumer.setParticipantTier(data.user_id, data.tier);
            }
          }
          // Also notify LiveView for UI updates
          this.pushEvent("tier_changed", {
            user_id: data.user_id,
            tier: data.tier
          });
        }
      });

      // Adaptive quality: receive snapshots from other participants
      this.channel.on("video_snapshot", (data) => {
        if (!this._destroyed && this.adaptiveConsumer && data.user_id !== this.userId) {
          this.adaptiveConsumer.receiveSnapshot(data.user_id, data);
        }
      });

      this.channel.on("call_ended", () => {
        if (!this._destroyed) {
          console.log("[CallHook] Call ended by server");
          this.handleLeaveCall();
        }
      });

      this.channel.on("quality_tier_request", (data) => {
        if (!this._destroyed && data.target_user_id === this.userId) {
          console.log(`[CallHook] Quality tier request from ${data.from_user_id}: ${data.tier}`);
          if (this.adaptiveProducer) {
            this.adaptiveProducer.setTier(data.tier);
          }
        }
      });

      this.channel
        .join()
        .receive("ok", (response) => {
          clearTimeout(socketTimeout);
          console.log("[CallHook] Channel joined successfully");
          this.iceServers = response.ice_servers || [];
          resolve(response);
        })
        .receive("error", (error) => {
          clearTimeout(socketTimeout);
          console.error("[CallHook] Channel join error:", error);
          reject(new Error(error.reason || "Failed to join channel"));
        })
        .receive("timeout", () => {
          clearTimeout(socketTimeout);
          console.error("[CallHook] Channel join timeout");
          reject(new Error("Channel join timeout"));
        });
    });
  },

  _handleChannelDisconnect() {
    if (this._destroyed || !this.inCall) return;

    console.log("[CallHook] Channel disconnected, will attempt reconnection via socket");
    this._setCallState(CallState.RECONNECTING);
    this.pushEvent("channel_reconnecting", {});

    // Socket will auto-reconnect, but we need to handle if it doesn't
    this._channelReconnectTimer = setTimeout(() => {
      if (this.inCall && !this._destroyed) {
        console.error("[CallHook] Channel reconnection timeout");
        this._setCallState(CallState.ERROR);
        this.pushEvent("call_error", {
          message: "Lost connection to server. Please try rejoining.",
          canRetry: true,
        });
      }
    }, 30000);
  },

  pushChannelEvent(event, payload, timeout = 10000) {
    return new Promise((resolve, reject) => {
      if (!this.channel) {
        reject(new Error("Channel not connected"));
        return;
      }

      this.channel
        .push(event, payload, timeout)
        .receive("ok", resolve)
        .receive("error", (error) => {
          const message = typeof error === 'string' ? error : (error?.reason || "Channel error");
          reject(new Error(message));
        })
        .receive("timeout", () => {
          reject(new Error(`${event} timeout`));
        });
    });
  },

  handleTrackReady(ctx) {
    console.log("Track ready:", ctx.trackId, ctx.track?.kind, "endpoint:", ctx.endpoint?.id);

    if (ctx.track && ctx.endpoint) {
      const endpointId = ctx.endpoint.id;
      const userId = this.extractUserId(endpointId);

      // Try to attach the track, or buffer it if container not ready
      if (!this.attachTrackToContainer(userId, ctx)) {
        console.log(`Buffering track ${ctx.trackId} for participant ${userId} - container not ready yet`);
        this.bufferTrack(userId, ctx);
      }
    }

    this.pushEvent("track_ready", {
      track_id: ctx.trackId,
      kind: ctx.track?.kind,
      peer_id: ctx.endpoint?.id,
    });
  },

  // Extract user_id from endpoint_id (format: "{user_id}_{random_number}")
  extractUserId(endpointId) {
    if (!endpointId) return null;
    return endpointId.includes("_")
      ? endpointId.substring(0, endpointId.lastIndexOf("_"))
      : endpointId;
  },

  // Buffer a track for later attachment when container becomes available
  bufferTrack(userId, ctx) {
    if (!this.pendingTracks.has(userId)) {
      this.pendingTracks.set(userId, []);
    }
    this.pendingTracks.get(userId).push(ctx);
  },

  // Try to attach a track to its participant container
  // Returns true if successful, false if container not found
  attachTrackToContainer(userId, ctx) {
    const containerEl = document.getElementById(`participant-${userId}`);

    if (!containerEl) {
      return false;
    }

    if (ctx.track.kind === "video") {
      let videoEl = containerEl.querySelector("video");
      if (!videoEl) {
        videoEl = document.createElement("video");
        videoEl.autoplay = true;
        videoEl.playsInline = true;
        videoEl.classList.add("w-full", "h-full", "object-cover", "rounded-lg");
        containerEl.appendChild(videoEl);
      }

      let stream = videoEl.srcObject;
      if (!stream) {
        stream = new MediaStream();
        videoEl.srcObject = stream;
      }

      // Check if track already in stream
      const existingTrack = stream.getVideoTracks().find(t => t.id === ctx.track.id);
      if (!existingTrack) {
        stream.addTrack(ctx.track);
      }

      this.videoElements.set(ctx.trackId, { element: videoEl, peerId: userId });
      console.log(`Attached video track ${ctx.trackId} to participant-${userId}`);
    } else if (ctx.track.kind === "audio") {
      let audioEl = containerEl.querySelector("audio");
      if (!audioEl) {
        audioEl = document.createElement("audio");
        audioEl.autoplay = true;
        containerEl.appendChild(audioEl);
      }

      let stream = audioEl.srcObject;
      if (!stream) {
        stream = new MediaStream();
        audioEl.srcObject = stream;
      }

      // Check if track already in stream
      const existingTrack = stream.getAudioTracks().find(t => t.id === ctx.track.id);
      if (!existingTrack) {
        stream.addTrack(ctx.track);
      }
      console.log(`Attached audio track ${ctx.trackId} to participant-${userId}`);
    }

    return true;
  },

  // Attach any buffered tracks for a user when their container becomes available
  attachBufferedTracks(userId) {
    const pendingTracksForUser = this.pendingTracks.get(userId);
    if (!pendingTracksForUser || pendingTracksForUser.length === 0) {
      return;
    }

    console.log(`Attaching ${pendingTracksForUser.length} buffered tracks for participant ${userId}`);

    for (const ctx of pendingTracksForUser) {
      this.attachTrackToContainer(userId, ctx);
    }

    // Clear the buffer for this user
    this.pendingTracks.delete(userId);
  },

  // Set up MutationObserver to watch for new participant containers
  setupContainerObserver() {
    if (this.containerObserver) {
      this.containerObserver.disconnect();
    }

    this.containerObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            // Check if the added node is a participant container
            if (node.id && node.id.startsWith("participant-")) {
              const userId = node.id.replace("participant-", "");
              console.log(`[CallHook] Detected new participant container: ${node.id}`);
              this.attachBufferedTracks(userId);
            }
            // Check if this is the local video container (for mode switches)
            if (node.id === "local-video") {
              console.log("[CallHook] Detected local-video container, attaching stream");
              this.attachLocalStream();
            }
            // Also check children of added nodes
            const participantContainers = node.querySelectorAll?.('[id^="participant-"]') || [];
            for (const container of participantContainers) {
              const userId = container.id.replace("participant-", "");
              console.log(`[CallHook] Detected new participant container (nested): ${container.id}`);
              this.attachBufferedTracks(userId);
            }
            // Check for local-video in children
            const localVideoEl = node.querySelector?.("#local-video");
            if (localVideoEl) {
              console.log("[CallHook] Detected local-video in added node, attaching stream");
              this.attachLocalStream();
            }
            // Check if the call-container itself was added (mode switch back to call mode)
            if (node.id === "call-container" || node.querySelector?.("#call-container")) {
              console.log("[CallHook] Call container mounted, reattaching all streams");
              this.attachLocalStream();
              // Reattach all pending tracks
              for (const [userId, tracks] of this.pendingTracks) {
                for (const ctx of tracks) {
                  this.attachTrackToContainer(userId, ctx);
                }
              }
            }
          }
        }
      }
    });

    // When persistent, observe the entire document body to catch mode switches
    // Otherwise, just observe the call container
    if (this.isPersistent) {
      console.log("[CallHook] Setting up document-wide observer (persistent mode)");
      this.containerObserver.observe(document.body, {
        childList: true,
        subtree: true
      });
    } else {
      const callContainer = document.getElementById("call-container");
      if (callContainer) {
        this.containerObserver.observe(callContainer, {
          childList: true,
          subtree: true
        });
      }
    }
  },

  handleTrackRemoved(ctx) {
    const videoInfo = this.videoElements.get(ctx.trackId);
    if (videoInfo) {
      const stream = videoInfo.element.srcObject;
      if (stream && ctx.track) {
        stream.removeTrack(ctx.track);
        if (stream.getTracks().length === 0) {
          videoInfo.element.srcObject = null;
        }
      }
      this.videoElements.delete(ctx.trackId);
    }

    this.pushEvent("track_removed", { track_id: ctx.trackId });
  },

  handleParticipantJoined(peer) {
    // peer.id is the endpoint_id from Membrane (format: "{user_id}_{random}"),
    // peer.user_id might be provided by server-side participant info
    const endpointId = peer.id || peer.endpoint_id;
    const userId = peer.user_id || this.extractUserId(endpointId);

    console.log("Participant joined:", { endpointId, userId, peer });

    if (userId && !this.participants.has(userId)) {
      const participantInfo = {
        ...peer,
        resolvedUserId: userId,
        user_id: userId,
        endpoint_id: endpointId,
      };
      this.participants.set(userId, participantInfo);

      // Push event with full participant info so LiveView can render the container
      this.pushEvent("participant_joined", {
        peer_id: userId,
        user_id: userId,
        endpoint_id: endpointId,
        metadata: peer.metadata || peer.user_info || {},
        user_info: peer.metadata || peer.user_info || {},
      });

      // Also try to attach any tracks that arrived before this participant was registered
      // (though this is unlikely since tracks arrive after endpoints)
      setTimeout(() => this.attachBufferedTracks(userId), 100);
    }
  },

  handleParticipantLeft(peer) {
    // Same extraction logic as handleParticipantJoined
    const endpointId = peer.id || peer.endpoint_id;
    const userId = peer.user_id || this.extractUserId(endpointId);

    console.log("Participant left:", { endpointId, userId });
    this.participants.delete(userId);

    // Clear any pending tracks for this user
    this.pendingTracks.delete(userId);

    const containerEl = document.getElementById(`participant-${userId}`);
    if (containerEl) {
      const videoEl = containerEl.querySelector("video");
      const audioEl = containerEl.querySelector("audio");
      if (videoEl) videoEl.srcObject = null;
      if (audioEl) audioEl.srcObject = null;
    }

    this.pushEvent("participant_left", { peer_id: userId, user_id: userId });
  },

  handleConnectionStateChange(state) {
    this.pushEvent("connection_state_changed", { state });
  },

  handleError(error) {
    console.error("Call error:", error);
    const message = typeof error === 'string' ? error : (error?.message || error?.reason || "Unknown error");
    this.pushEvent("call_error", { message });
  },

  updateParticipantAudioState(userId, enabled) {
    this.pushEvent("participant_audio_changed", { user_id: userId, enabled });
  },

  updateParticipantVideoState(userId, enabled) {
    this.pushEvent("participant_video_changed", { user_id: userId, enabled });
  },

  clearRemoteVideos() {
    this.videoElements.forEach(({ element }) => {
      if (element.srcObject) {
        element.srcObject.getTracks().forEach((track) => track.stop());
        element.srcObject = null;
      }
    });
    this.videoElements.clear();
    this.participants.clear();
    this.pendingTracks.clear();

    // Disconnect the observer
    if (this.containerObserver) {
      this.containerObserver.disconnect();
      this.containerObserver = null;
    }
  },

  destroyed() {
    console.log("[CallHook] Hook being destroyed");
    this._destroyed = true;

    // Remove event listeners
    if (this._visibilityHandler) {
      document.removeEventListener("visibilitychange", this._visibilityHandler);
      this._visibilityHandler = null;
    }
    if (this._focusHandler) {
      window.removeEventListener("focus", this._focusHandler);
      this._focusHandler = null;
    }
    if (this._blurHandler) {
      window.removeEventListener("blur", this._blurHandler);
      this._blurHandler = null;
    }
    if (this._beforeUnloadHandler) {
      window.removeEventListener("beforeunload", this._beforeUnloadHandler);
      this._beforeUnloadHandler = null;
    }

    // Clear timers
    if (this._channelReconnectTimer) {
      clearTimeout(this._channelReconnectTimer);
      this._channelReconnectTimer = null;
    }

    // Leave call if in one
    this.handleLeaveCall();

    // Cleanup quality manager
    if (this.qualityManager) {
      try {
        this.qualityManager.destroy();
      } catch (e) {
        // Ignore
      }
      this.qualityManager = null;
    }

    // Cleanup speaking detector
    if (this.speakingDetector) {
      try {
        this.speakingDetector.destroy();
      } catch (e) {
        // Ignore
      }
      this.speakingDetector = null;
    }

    // Cleanup adaptive producer
    if (this.adaptiveProducer) {
      try {
        this.adaptiveProducer.destroy();
      } catch (e) {
        // Ignore
      }
      this.adaptiveProducer = null;
    }

    // Cleanup adaptive consumer
    if (this.adaptiveConsumer) {
      try {
        this.adaptiveConsumer.destroy();
      } catch (e) {
        // Ignore
      }
      this.adaptiveConsumer = null;
    }

    // Stop local stream
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {
          // Ignore
        }
      });
      this.localStream = null;
    }

    // Cleanup media manager
    if (this.mediaManager) {
      try {
        this.mediaManager.stopAllTracks();
      } catch (e) {
        // Ignore
      }
    }

    // Clear global reference
    if (window.__callHook === this) {
      window.__callHook = null;
    }

    console.log("[CallHook] Cleanup complete");
  },
};

/**
 * Video Tile Hook - manages individual participant video tiles
 * Note: Local video stream is attached by CallHook, not auto-captured here
 */
export const VideoTileHook = {
  mounted() {
    this.peerId = this.el.dataset.peerId;
    this.isLocal = this.el.dataset.isLocal === "true";
  },

  destroyed() {
    const videoEl = this.el.querySelector("video");
    if (videoEl && videoEl.srcObject) {
      videoEl.srcObject.getTracks().forEach((track) => track.stop());
      videoEl.srcObject = null;
    }
  },
};

/**
 * Call Controls Hook - manages call control buttons
 */
export const CallControlsHook = {
  mounted() {
    this.audioEnabled = true;
    this.videoEnabled = true;
  },
};

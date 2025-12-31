/**
 * LiveView Hooks for Video/Voice Calls
 * Coordinates between LiveView and WebRTC client
 */

import { Socket } from "phoenix";
import { MembraneClient } from "./membrane_client.js";
import { MediaManager } from "./media_manager.js";

/**
 * Main Call Hook - manages the entire call lifecycle
 */
export const CallHook = {
  mounted() {
    this.roomId = this.el.dataset.roomId;
    this.userId = this.el.dataset.userId;
    this.userName = this.el.dataset.userName || "User";

    this.membraneClient = null;
    this.mediaManager = new MediaManager();
    this.channel = null;
    this.socket = null;
    this.localStream = null;
    this.audioEnabled = true;
    this.videoEnabled = true;
    this.inCall = false;
    this.iceServers = [];

    this.participants = new Map();
    this.videoElements = new Map();
    // Buffer for tracks that arrive before their participant container is rendered
    this.pendingTracks = new Map();
    // MutationObserver to watch for new participant containers
    this.containerObserver = null;

    // Expose hook globally for debugging
    window.__callHook = this;
    console.log("CallHook mounted, exposed as window.__callHook");

    this.handleEvent("join_call", (data) => this.handleJoinCall(data));
    this.handleEvent("leave_call", () => this.handleLeaveCall());
    this.handleEvent("toggle_audio", (data) => this.handleToggleAudio(data));
    this.handleEvent("toggle_video", (data) => this.handleToggleVideo(data));
    this.handleEvent("set_quality", (data) => this.handleSetQuality(data));
  },

  attachLocalStream() {
    const localVideoEl = document.querySelector("#local-video video");
    if (localVideoEl && this.localStream) {
      localVideoEl.srcObject = this.localStream;
      localVideoEl.muted = true;
      console.log("Attached local stream to video element");
      return true;
    }
    console.log("Local video element not found, will retry...");
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
    if (this.inCall) return;

    const mode = data?.mode || "video";
    const withVideo = mode === "video";
    this.videoEnabled = withVideo;

    try {
      await this.connectToChannel();

      const response = await this.pushChannelEvent("join_call", {});

      if (response.endpoint_id) {
        this.endpointId = response.endpoint_id;

        this.membraneClient = new MembraneClient({
          roomId: this.roomId,
          userId: this.userId,
          userInfo: { name: this.userName },
          channel: this.channel,
          onTrackReady: (ctx) => this.handleTrackReady(ctx),
          onTrackRemoved: (ctx) => this.handleTrackRemoved(ctx),
          onParticipantJoined: (peer) => this.handleParticipantJoined(peer),
          onParticipantLeft: (peer) => this.handleParticipantLeft(peer),
          onConnectionStateChange: (state) => this.handleConnectionStateChange(state),
          onError: (error) => this.handleError(error),
        });

        await this.membraneClient.connect(this.iceServers);

        // Set up MutationObserver to watch for new participant containers
        this.setupContainerObserver();

        if (withVideo) {
          this.localStream = await this.mediaManager.getMediaStream();
        } else {
          this.localStream = await this.mediaManager.getAudioOnlyStream();
        }

        for (const track of this.localStream.getTracks()) {
          await this.membraneClient.addLocalTrack(track);
        }

        this.inCall = true;
        this.pushEvent("call_joined", { endpoint_id: this.endpointId });

        // Attach local stream to the local video element
        // Use retry because LiveView needs time to render the video element after call_joined
        this.attachLocalStreamWithRetry();

        Object.values(response.participants || {}).forEach((p) => {
          this.handleParticipantJoined(p);
        });
      }
    } catch (error) {
      console.error("Failed to join call:", error);
      this.pushEvent("call_error", { message: error.message });
    }
  },

  async handleLeaveCall() {
    if (!this.inCall) return;

    try {
      if (this.membraneClient) {
        this.membraneClient.disconnect();
        this.membraneClient = null;
      }

      if (this.channel) {
        await this.pushChannelEvent("leave_call", {});
        this.channel.leave();
        this.channel = null;
      }

      if (this.socket) {
        this.socket.disconnect();
        this.socket = null;
      }

      this.clearRemoteVideos();

      this.inCall = false;
      this.pushEvent("call_left", {});
    } catch (error) {
      console.error("Failed to leave call:", error);
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
  },

  async connectToChannel() {
    return new Promise((resolve, reject) => {
      this.socket = new Socket("/socket", {
        params: {},
      });
      this.socket.connect();

      this.channel = this.socket.channel(`call:${this.roomId}`, {
        user_id: this.userId,
        user_info: { name: this.userName },
      });

      this.channel.on("media_event", (payload) => {
        if (this.membraneClient) {
          this.membraneClient.handleMediaEvent(payload.data);
        }
      });

      this.channel.on("participant_joined", (participant) => {
        this.handleParticipantJoined(participant);
      });

      this.channel.on("participant_left", (data) => {
        this.handleParticipantLeft(data);
      });

      this.channel.on("participant_audio_changed", (data) => {
        this.updateParticipantAudioState(data.user_id, data.audio_enabled);
      });

      this.channel.on("participant_video_changed", (data) => {
        this.updateParticipantVideoState(data.user_id, data.video_enabled);
      });

      this.channel.on("quality_changed", (data) => {
        if (this.mediaManager) {
          this.mediaManager.setQualityProfile(data.quality);
        }
        this.pushEvent("quality_changed", data);
      });

      this.channel.on("call_ended", () => {
        this.handleLeaveCall();
      });

      this.channel
        .join()
        .receive("ok", (response) => {
          this.iceServers = response.ice_servers || [];
          resolve(response);
        })
        .receive("error", (error) => {
          reject(new Error(error.reason || "Failed to join channel"));
        });
    });
  },

  pushChannelEvent(event, payload) {
    return new Promise((resolve, reject) => {
      this.channel
        .push(event, payload)
        .receive("ok", resolve)
        .receive("error", reject);
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
              console.log(`Detected new participant container: ${node.id}`);
              this.attachBufferedTracks(userId);
            }
            // Also check children of added nodes
            const participantContainers = node.querySelectorAll?.('[id^="participant-"]') || [];
            for (const container of participantContainers) {
              const userId = container.id.replace("participant-", "");
              console.log(`Detected new participant container (nested): ${container.id}`);
              this.attachBufferedTracks(userId);
            }
          }
        }
      }
    });

    // Start observing the call container and its subtree
    const callContainer = document.getElementById("call-container");
    if (callContainer) {
      this.containerObserver.observe(callContainer, {
        childList: true,
        subtree: true
      });
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
    this.pushEvent("call_error", { message: error.message });
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
    this.handleLeaveCall();

    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
      this.localStream = null;
    }
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

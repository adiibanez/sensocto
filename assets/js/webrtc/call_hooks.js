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

    this.handleEvent("join_call", (data) => this.handleJoinCall(data));
    this.handleEvent("leave_call", () => this.handleLeaveCall());
    this.handleEvent("toggle_audio", (data) => this.handleToggleAudio(data));
    this.handleEvent("toggle_video", (data) => this.handleToggleVideo(data));
    this.handleEvent("set_quality", (data) => this.handleSetQuality(data));

    this.setupLocalVideoPreview();
  },

  async setupLocalVideoPreview() {
    const previewEl = document.getElementById("local-video-preview");
    if (previewEl) {
      try {
        const stream = await this.mediaManager.getMediaStream();
        previewEl.srcObject = stream;
        this.localStream = stream;
      } catch (error) {
        console.error("Failed to setup video preview:", error);
      }
    }
  },

  async handleJoinCall(data) {
    if (this.inCall) return;

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

        if (this.localStream) {
          for (const track of this.localStream.getTracks()) {
            await this.membraneClient.addLocalTrack(track);
          }
        } else {
          await this.membraneClient.addLocalMedia({ audio: true, video: true });
          this.localStream = this.membraneClient.localStream;
        }

        this.inCall = true;
        this.pushEvent("call_joined", { endpoint_id: this.endpointId });

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
      // endpoint.id format is "{user_id}_{random_number}", but DOM elements use just user_id
      const endpointId = ctx.endpoint.id;
      const userId = endpointId.includes("_") ? endpointId.substring(0, endpointId.lastIndexOf("_")) : endpointId;
      const containerEl = document.getElementById(`participant-${userId}`);

      if (!containerEl) {
        console.warn(`Container element not found for participant-${userId}. Available elements:`,
          Array.from(document.querySelectorAll('[id^="participant-"]')).map(el => el.id));
      }

      if (containerEl) {
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
          stream.addTrack(ctx.track);
          this.videoElements.set(ctx.trackId, { element: videoEl, peerId: userId });
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
          stream.addTrack(ctx.track);
        }
      }
    }

    this.pushEvent("track_ready", {
      track_id: ctx.trackId,
      kind: ctx.track?.kind,
      peer_id: ctx.endpoint?.id,
    });
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
    const userId = peer.user_id || (endpointId && endpointId.includes("_")
      ? endpointId.substring(0, endpointId.lastIndexOf("_"))
      : endpointId);

    console.log("Participant joined:", { endpointId, userId, peer });

    if (userId && !this.participants.has(userId)) {
      this.participants.set(userId, { ...peer, resolvedUserId: userId });
      this.pushEvent("participant_joined", {
        peer_id: userId,
        metadata: peer.metadata || peer.user_info,
      });
    }
  },

  handleParticipantLeft(peer) {
    // Same extraction logic as handleParticipantJoined
    const endpointId = peer.id || peer.endpoint_id;
    const userId = peer.user_id || (endpointId && endpointId.includes("_")
      ? endpointId.substring(0, endpointId.lastIndexOf("_"))
      : endpointId);

    console.log("Participant left:", { endpointId, userId });
    this.participants.delete(userId);

    const containerEl = document.getElementById(`participant-${userId}`);
    if (containerEl) {
      const videoEl = containerEl.querySelector("video");
      const audioEl = containerEl.querySelector("audio");
      if (videoEl) videoEl.srcObject = null;
      if (audioEl) audioEl.srcObject = null;
    }

    this.pushEvent("participant_left", { peer_id: userId });
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
 */
export const VideoTileHook = {
  mounted() {
    this.peerId = this.el.dataset.peerId;
    this.isLocal = this.el.dataset.isLocal === "true";

    if (this.isLocal) {
      this.setupLocalVideo();
    }
  },

  async setupLocalVideo() {
    const videoEl = this.el.querySelector("video");
    if (videoEl) {
      try {
        const stream = await navigator.mediaDevices.getUserMedia({
          audio: true,
          video: true,
        });
        videoEl.srcObject = stream;
        videoEl.muted = true;
      } catch (error) {
        console.error("Failed to setup local video:", error);
      }
    }
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

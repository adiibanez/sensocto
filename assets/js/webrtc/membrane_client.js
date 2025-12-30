/**
 * Membrane WebRTC Client Wrapper
 * Handles connection to Membrane RTC Engine via Phoenix Channel
 */

import { WebRTCEndpoint } from "@jellyfish-dev/membrane-webrtc-js";

export class MembraneClient {
  constructor(options) {
    this.roomId = options.roomId;
    this.userId = options.userId;
    this.userInfo = options.userInfo || {};
    this.channel = options.channel;
    this.onTrackReady = options.onTrackReady || (() => {});
    this.onTrackRemoved = options.onTrackRemoved || (() => {});
    this.onParticipantJoined = options.onParticipantJoined || (() => {});
    this.onParticipantLeft = options.onParticipantLeft || (() => {});
    this.onConnectionStateChange = options.onConnectionStateChange || (() => {});
    this.onError = options.onError || console.error;

    this.webrtc = null;
    this.localStream = null;
    this.localTracks = new Map();
    this.remoteTracks = new Map();
    this.participants = new Map();
    this.connected = false;
  }

  async connect(iceServers = []) {
    try {
      this.webrtc = new WebRTCEndpoint();

      // Set up event listeners
      this.webrtc.on("sendMediaEvent", (event) => {
        this.channel.push("media_event", { data: event });
      });

      this.webrtc.on("connectionError", (error) => {
        console.error("Connection error:", error);
        this.onError(new Error(error.message || "Connection error"));
      });

      this.webrtc.on("connected", (endpointId, otherEndpoints) => {
        console.log("Connected to call", endpointId);
        this.connected = true;
        this.onConnectionStateChange("connected");

        otherEndpoints.forEach((endpoint) => {
          this.participants.set(endpoint.id, endpoint);
          this.onParticipantJoined(endpoint);
        });
      });

      this.webrtc.on("trackReady", (ctx) => {
        console.log("Track ready:", ctx.trackId, ctx.track?.kind);
        this.remoteTracks.set(ctx.trackId, ctx);
        this.onTrackReady(ctx);
      });

      this.webrtc.on("trackAdded", (ctx) => {
        console.log("Track added:", ctx.trackId);
      });

      this.webrtc.on("trackRemoved", (ctx) => {
        console.log("Track removed:", ctx.trackId);
        this.remoteTracks.delete(ctx.trackId);
        this.onTrackRemoved(ctx);
      });

      this.webrtc.on("trackUpdated", (ctx) => {
        console.log("Track updated:", ctx.trackId);
      });

      this.webrtc.on("endpointAdded", (endpoint) => {
        console.log("Endpoint joined:", endpoint.id);
        this.participants.set(endpoint.id, endpoint);
        this.onParticipantJoined(endpoint);
      });

      this.webrtc.on("endpointRemoved", (endpoint) => {
        console.log("Endpoint left:", endpoint.id);
        this.participants.delete(endpoint.id);
        this.onParticipantLeft(endpoint);
      });

      this.webrtc.on("endpointUpdated", (endpoint) => {
        console.log("Endpoint updated:", endpoint.id);
        this.participants.set(endpoint.id, endpoint);
      });

      this.webrtc.on("disconnected", () => {
        console.log("Disconnected from call");
        this.connected = false;
        this.onConnectionStateChange("disconnected");
      });

      // Connect with metadata
      this.webrtc.connect({
        displayName: this.userInfo.name || this.userId,
        ...this.userInfo,
      });

      return true;
    } catch (error) {
      console.error("Failed to initialize WebRTC:", error);
      this.onError(error);
      return false;
    }
  }

  handleMediaEvent(event) {
    if (this.webrtc) {
      this.webrtc.receiveMediaEvent(event);
    }
  }

  async addLocalMedia(constraints = { audio: true, video: true }) {
    try {
      const stream = await navigator.mediaDevices.getUserMedia(constraints);
      this.localStream = stream;

      for (const track of stream.getTracks()) {
        await this.addLocalTrack(track);
      }

      return stream;
    } catch (error) {
      console.error("Failed to get user media:", error);
      this.onError(error);
      throw error;
    }
  }

  async addLocalTrack(track, metadata = {}) {
    if (!this.webrtc) {
      throw new Error("WebRTC not initialized");
    }

    const trackId = await this.webrtc.addTrack(track, {
      type: track.kind,
      ...metadata,
    });

    this.localTracks.set(trackId, { track, metadata });

    return trackId;
  }

  async removeLocalTrack(trackId) {
    if (!this.webrtc) return;

    const trackInfo = this.localTracks.get(trackId);
    if (trackInfo) {
      trackInfo.track.stop();
      this.webrtc.removeTrack(trackId);
      this.localTracks.delete(trackId);
    }
  }

  setTrackEnabled(trackId, enabled) {
    const trackInfo = this.localTracks.get(trackId);
    if (trackInfo && trackInfo.track) {
      trackInfo.track.enabled = enabled;
    }
  }

  toggleAudio(enabled) {
    if (this.localStream) {
      this.localStream.getAudioTracks().forEach((track) => {
        track.enabled = enabled;
      });
    }
  }

  toggleVideo(enabled) {
    if (this.localStream) {
      this.localStream.getVideoTracks().forEach((track) => {
        track.enabled = enabled;
      });
    }
  }

  async replaceTrack(oldTrackId, newTrack, metadata = {}) {
    if (!this.webrtc) return null;

    await this.removeLocalTrack(oldTrackId);
    return await this.addLocalTrack(newTrack, metadata);
  }

  getParticipants() {
    return Array.from(this.participants.values());
  }

  getRemoteTracks() {
    return Array.from(this.remoteTracks.values());
  }

  getLocalTracks() {
    return Array.from(this.localTracks.entries()).map(([id, info]) => ({
      trackId: id,
      ...info,
    }));
  }

  disconnect() {
    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => track.stop());
      this.localStream = null;
    }

    this.localTracks.clear();
    this.remoteTracks.clear();
    this.participants.clear();

    if (this.webrtc) {
      this.webrtc.disconnect();
      this.webrtc = null;
    }

    this.connected = false;
    this.onConnectionStateChange("disconnected");
  }
}

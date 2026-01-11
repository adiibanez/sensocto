/**
 * Membrane WebRTC Client Wrapper
 * Handles connection to Membrane RTC Engine via Phoenix Channel
 */

import { WebRTCEndpoint } from "@jellyfish-dev/membrane-webrtc-js";

// Connection states for robust state machine
const ConnectionState = {
  DISCONNECTED: "disconnected",
  CONNECTING: "connecting",
  CONNECTED: "connected",
  RECONNECTING: "reconnecting",
  FAILED: "failed",
};

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
    this.onReconnecting = options.onReconnecting || (() => {});
    this.onReconnected = options.onReconnected || (() => {});

    this.webrtc = null;
    this.localStream = null;
    this.localTracks = new Map();
    this.remoteTracks = new Map();
    this.participants = new Map();
    this.connected = false;

    // Robust connection state management
    this.connectionState = ConnectionState.DISCONNECTED;
    this.reconnectAttempts = 0;
    this.maxReconnectAttempts = options.maxReconnectAttempts || 5;
    this.reconnectDelay = options.reconnectDelay || 1000;
    this.connectionTimeout = options.connectionTimeout || 30000;
    this.iceServers = [];
    this._reconnectTimer = null;
    this._connectionTimer = null;
    this._destroyed = false;
  }

  async connect(iceServers = []) {
    if (this._destroyed) {
      throw new Error("Client has been destroyed");
    }

    this.iceServers = iceServers;
    this._setConnectionState(ConnectionState.CONNECTING);

    return new Promise((resolve, reject) => {
      let resolved = false;

      const cleanup = () => {
        this._clearConnectionTimer();
      };

      const safeResolve = (value) => {
        if (!resolved) {
          resolved = true;
          cleanup();
          resolve(value);
        }
      };

      const safeReject = (error) => {
        if (!resolved) {
          resolved = true;
          cleanup();
          reject(error);
        }
      };

      try {
        this.webrtc = new WebRTCEndpoint();

        // Override the default rtcConfig to allow direct connections (not just relay)
        // and add any provided ICE servers. The default config has iceTransportPolicy: "relay"
        // which requires TURN servers, but for local dev we want to allow direct connections.
        if (this.webrtc.rtcConfig) {
          // Allow both direct and relay connections
          this.webrtc.rtcConfig.iceTransportPolicy = "all";

          // Add provided ICE servers (STUN/TURN)
          if (iceServers && iceServers.length > 0) {
            this.webrtc.rtcConfig.iceServers = [
              ...(this.webrtc.rtcConfig.iceServers || []),
              ...iceServers
            ];
          }

          console.log("[MembraneClient] Updated rtcConfig:", this.webrtc.rtcConfig);
        }

        // Set up connection timeout
        this._connectionTimer = setTimeout(() => {
          if (!this.connected) {
            console.error("[MembraneClient] Connection timeout after", this.connectionTimeout, "ms");
            this._setConnectionState(ConnectionState.FAILED);
            safeReject(new Error("Connection timeout - server did not respond"));
          }
        }, this.connectionTimeout);

        // Set up event listeners
        this.webrtc.on("sendMediaEvent", (event) => {
          if (this.channel && !this._destroyed) {
            // Fix ICE candidate events - add sdpMid if missing
            // The server-side ExWebRTC expects sdpMid but the JS library doesn't always include it
            const fixedEvent = this._fixIceCandidateEvent(event);
            this.channel.push("media_event", { data: fixedEvent });
          }
        });

        this.webrtc.on("connectionError", (error) => {
          console.error("[MembraneClient] Connection error:", error);
          const errorMsg = typeof error === 'string' ? error : (error?.message || error?.reason || "Connection error");
          this._setConnectionState(ConnectionState.FAILED);
          this.onError(new Error(errorMsg));
          safeReject(new Error(errorMsg));
        });

        this.webrtc.on("connected", (endpointId, otherEndpoints) => {
          console.log("[MembraneClient] Connected to call", endpointId);
          this.connected = true;
          this.reconnectAttempts = 0;
          this._setConnectionState(ConnectionState.CONNECTED);

          otherEndpoints.forEach((endpoint) => {
            this.participants.set(endpoint.id, endpoint);
            this.onParticipantJoined(endpoint);
          });

          // Resolve the promise now that we're connected and can add tracks
          safeResolve(true);
        });

        this.webrtc.on("trackReady", (ctx) => {
          console.log("[MembraneClient] Track ready:", ctx.trackId, ctx.track?.kind);
          this.remoteTracks.set(ctx.trackId, ctx);
          this.onTrackReady(ctx);
        });

        this.webrtc.on("trackAdded", (ctx) => {
          console.log("[MembraneClient] Track added:", ctx.trackId);
        });

        this.webrtc.on("trackRemoved", (ctx) => {
          console.log("[MembraneClient] Track removed:", ctx.trackId);
          this.remoteTracks.delete(ctx.trackId);
          this.onTrackRemoved(ctx);
        });

        this.webrtc.on("trackUpdated", (ctx) => {
          console.log("[MembraneClient] Track updated:", ctx.trackId);
        });

        this.webrtc.on("endpointAdded", (endpoint) => {
          console.log("[MembraneClient] Endpoint joined:", endpoint.id);
          this.participants.set(endpoint.id, endpoint);
          this.onParticipantJoined(endpoint);
        });

        this.webrtc.on("endpointRemoved", (endpoint) => {
          console.log("[MembraneClient] Endpoint left:", endpoint.id);
          this.participants.delete(endpoint.id);
          this.onParticipantLeft(endpoint);
        });

        this.webrtc.on("endpointUpdated", (endpoint) => {
          console.log("[MembraneClient] Endpoint updated:", endpoint.id);
          this.participants.set(endpoint.id, endpoint);
        });

        this.webrtc.on("disconnected", () => {
          console.log("[MembraneClient] Disconnected from call");
          this.connected = false;

          // Only attempt reconnect if not intentionally destroyed
          if (!this._destroyed && this.connectionState !== ConnectionState.FAILED) {
            this._handleDisconnect();
          } else {
            this._setConnectionState(ConnectionState.DISCONNECTED);
          }
        });

        // Connect with metadata - the promise resolves when "connected" event fires
        this.webrtc.connect({
          displayName: this.userInfo.name || this.userId,
          ...this.userInfo,
        });

      } catch (error) {
        console.error("[MembraneClient] Failed to initialize WebRTC:", error);
        this._setConnectionState(ConnectionState.FAILED);
        this.onError(error);
        safeReject(error);
      }
    });
  }

  _setConnectionState(state) {
    if (this.connectionState !== state) {
      console.log(`[MembraneClient] State: ${this.connectionState} -> ${state}`);
      this.connectionState = state;
      this.onConnectionStateChange(state);
    }
  }

  _clearConnectionTimer() {
    if (this._connectionTimer) {
      clearTimeout(this._connectionTimer);
      this._connectionTimer = null;
    }
  }

  _clearReconnectTimer() {
    if (this._reconnectTimer) {
      clearTimeout(this._reconnectTimer);
      this._reconnectTimer = null;
    }
  }

  _handleDisconnect() {
    if (this._destroyed) return;

    if (this.reconnectAttempts < this.maxReconnectAttempts) {
      this._setConnectionState(ConnectionState.RECONNECTING);
      this.reconnectAttempts++;

      const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
      console.log(`[MembraneClient] Attempting reconnect ${this.reconnectAttempts}/${this.maxReconnectAttempts} in ${delay}ms`);

      this.onReconnecting(this.reconnectAttempts, this.maxReconnectAttempts);

      this._reconnectTimer = setTimeout(() => {
        if (!this._destroyed) {
          this._attemptReconnect();
        }
      }, delay);
    } else {
      console.error("[MembraneClient] Max reconnect attempts reached");
      this._setConnectionState(ConnectionState.FAILED);
      this.onError(new Error("Failed to reconnect after maximum attempts"));
    }
  }

  async _attemptReconnect() {
    if (this._destroyed) return;

    try {
      // Clean up old connection
      if (this.webrtc) {
        try {
          this.webrtc.disconnect();
        } catch (e) {
          // Ignore cleanup errors
        }
        this.webrtc = null;
      }

      // Attempt to reconnect
      await this.connect(this.iceServers);

      // Re-add local tracks after reconnect
      const tracksToReAdd = Array.from(this.localTracks.values());
      for (const { track, metadata } of tracksToReAdd) {
        if (track.readyState === 'live') {
          await this.addLocalTrack(track, metadata);
        }
      }

      this.onReconnected();
      console.log("[MembraneClient] Reconnected successfully");
    } catch (error) {
      console.error("[MembraneClient] Reconnect attempt failed:", error);
      this._handleDisconnect();
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

    console.log(`[MembraneClient] Adding ${track.kind} track to WebRTC endpoint`);

    const trackMetadata = {
      type: track.kind,
      active: track.enabled,
      ...metadata,
    };

    const trackId = await this.webrtc.addTrack(track, trackMetadata);
    console.log(`[MembraneClient] Track added with ID: ${trackId}`);

    this.localTracks.set(trackId, { track, metadata: trackMetadata });

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
    this._destroyed = true;
    this._clearConnectionTimer();
    this._clearReconnectTimer();

    if (this.localStream) {
      this.localStream.getTracks().forEach((track) => {
        try {
          track.stop();
        } catch (e) {
          // Ignore track stop errors
        }
      });
      this.localStream = null;
    }

    this.localTracks.clear();
    this.remoteTracks.clear();
    this.participants.clear();

    if (this.webrtc) {
      try {
        this.webrtc.disconnect();
      } catch (e) {
        console.warn("[MembraneClient] Error during disconnect:", e);
      }
      this.webrtc = null;
    }

    this.connected = false;
    this._setConnectionState(ConnectionState.DISCONNECTED);
  }

  getConnectionState() {
    return this.connectionState;
  }

  isReconnecting() {
    return this.connectionState === ConnectionState.RECONNECTING;
  }

  destroy() {
    this.disconnect();
    this._destroyed = true;
  }

  // Fix ICE candidate events that are missing sdpMid
  // The server-side ExWebRTC expects sdpMid but the JS membrane-webrtc-js library doesn't always include it
  _fixIceCandidateEvent(eventStr) {
    try {
      const event = JSON.parse(eventStr);

      // Check if this is a candidate event
      if (event.type === "custom" &&
          event.data?.type === "candidate" &&
          event.data?.data) {
        const candidateData = event.data.data;

        // Add sdpMid if missing - derive from sdpMLineIndex
        if (candidateData.sdpMLineIndex !== undefined && candidateData.sdpMid === undefined) {
          // sdpMid is typically the media line index as a string
          candidateData.sdpMid = String(candidateData.sdpMLineIndex);
          console.log("[MembraneClient] Fixed ICE candidate - added sdpMid:", candidateData.sdpMid);
          return JSON.stringify(event);
        }
      }

      return eventStr;
    } catch (e) {
      // If parsing fails, return original
      console.warn("[MembraneClient] Failed to parse media event for ICE fix:", e);
      return eventStr;
    }
  }
}

/**
 * Media Device Manager
 * Handles getUserMedia, device enumeration, and device switching
 */

export class MediaManager {
  constructor() {
    this.currentDevices = {
      audioInput: null,
      videoInput: null,
      audioOutput: null,
    };
    this.currentStream = null;
    this.deviceChangeListeners = [];
  }

  async initialize() {
    if (navigator.mediaDevices && navigator.mediaDevices.ondevicechange !== undefined) {
      navigator.mediaDevices.ondevicechange = () => {
        this.notifyDeviceChange();
      };
    }
  }

  async enumerateDevices() {
    try {
      const devices = await navigator.mediaDevices.enumerateDevices();

      return {
        audioInputs: devices.filter((d) => d.kind === "audioinput"),
        videoInputs: devices.filter((d) => d.kind === "videoinput"),
        audioOutputs: devices.filter((d) => d.kind === "audiooutput"),
      };
    } catch (error) {
      console.error("Failed to enumerate devices:", error);
      throw error;
    }
  }

  async getMediaStream(constraints = {}) {
    const defaultConstraints = {
      audio: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
      video: {
        width: { ideal: 1280, max: 1280 },
        height: { ideal: 720, max: 720 },
        frameRate: { ideal: 30, max: 30 },
      },
    };

    const mergedConstraints = this.mergeConstraints(defaultConstraints, constraints);

    try {
      const stream = await navigator.mediaDevices.getUserMedia(mergedConstraints);
      this.currentStream = stream;

      const audioTrack = stream.getAudioTracks()[0];
      const videoTrack = stream.getVideoTracks()[0];

      if (audioTrack) {
        this.currentDevices.audioInput = audioTrack.getSettings().deviceId;
      }
      if (videoTrack) {
        this.currentDevices.videoInput = videoTrack.getSettings().deviceId;
      }

      return stream;
    } catch (error) {
      console.error("Failed to get media stream:", error);
      throw error;
    }
  }

  async getAudioOnlyStream(constraints = {}) {
    return this.getMediaStream({
      audio: constraints.audio || true,
      video: false,
    });
  }

  async getVideoOnlyStream(constraints = {}) {
    return this.getMediaStream({
      audio: false,
      video: constraints.video || true,
    });
  }

  async switchAudioDevice(deviceId) {
    if (!this.currentStream) return null;

    try {
      const newStream = await navigator.mediaDevices.getUserMedia({
        audio: { deviceId: { exact: deviceId } },
      });

      const oldAudioTrack = this.currentStream.getAudioTracks()[0];
      const newAudioTrack = newStream.getAudioTracks()[0];

      if (oldAudioTrack) {
        this.currentStream.removeTrack(oldAudioTrack);
        oldAudioTrack.stop();
      }

      this.currentStream.addTrack(newAudioTrack);
      this.currentDevices.audioInput = deviceId;

      return newAudioTrack;
    } catch (error) {
      console.error("Failed to switch audio device:", error);
      throw error;
    }
  }

  async switchVideoDevice(deviceId) {
    if (!this.currentStream) return null;

    try {
      const newStream = await navigator.mediaDevices.getUserMedia({
        video: { deviceId: { exact: deviceId } },
      });

      const oldVideoTrack = this.currentStream.getVideoTracks()[0];
      const newVideoTrack = newStream.getVideoTracks()[0];

      if (oldVideoTrack) {
        this.currentStream.removeTrack(oldVideoTrack);
        oldVideoTrack.stop();
      }

      this.currentStream.addTrack(newVideoTrack);
      this.currentDevices.videoInput = deviceId;

      return newVideoTrack;
    } catch (error) {
      console.error("Failed to switch video device:", error);
      throw error;
    }
  }

  applyVideoConstraints(constraints) {
    if (!this.currentStream) return;

    const videoTrack = this.currentStream.getVideoTracks()[0];
    if (videoTrack) {
      videoTrack.applyConstraints(constraints);
    }
  }

  setQualityProfile(profile) {
    const profiles = {
      high: { width: 1280, height: 720, frameRate: 30 },
      medium: { width: 640, height: 480, frameRate: 24 },
      low: { width: 640, height: 360, frameRate: 20 },
      minimal: { width: 320, height: 240, frameRate: 15 },
    };

    const constraints = profiles[profile] || profiles.medium;
    this.applyVideoConstraints({
      width: { ideal: constraints.width },
      height: { ideal: constraints.height },
      frameRate: { ideal: constraints.frameRate },
    });
  }

  stopAllTracks() {
    if (this.currentStream) {
      this.currentStream.getTracks().forEach((track) => track.stop());
      this.currentStream = null;
    }
    this.currentDevices = {
      audioInput: null,
      videoInput: null,
      audioOutput: null,
    };
  }

  async getDisplayMedia(constraints = {}) {
    const defaultConstraints = {
      video: {
        cursor: "always",
        displaySurface: "monitor",
      },
      audio: false,
    };

    const mergedConstraints = this.mergeConstraints(defaultConstraints, constraints);

    try {
      return await navigator.mediaDevices.getDisplayMedia(mergedConstraints);
    } catch (error) {
      console.error("Failed to get display media:", error);
      throw error;
    }
  }

  onDeviceChange(callback) {
    this.deviceChangeListeners.push(callback);
    return () => {
      const index = this.deviceChangeListeners.indexOf(callback);
      if (index > -1) {
        this.deviceChangeListeners.splice(index, 1);
      }
    };
  }

  notifyDeviceChange() {
    this.enumerateDevices().then((devices) => {
      this.deviceChangeListeners.forEach((callback) => callback(devices));
    });
  }

  mergeConstraints(defaults, overrides) {
    const merged = { ...defaults };

    for (const key in overrides) {
      if (overrides[key] === false) {
        merged[key] = false;
      } else if (typeof overrides[key] === "object" && typeof defaults[key] === "object") {
        merged[key] = { ...defaults[key], ...overrides[key] };
      } else if (overrides[key] !== undefined) {
        merged[key] = overrides[key];
      }
    }

    return merged;
  }

  checkBrowserSupport() {
    return {
      getUserMedia: !!(navigator.mediaDevices && navigator.mediaDevices.getUserMedia),
      getDisplayMedia: !!(navigator.mediaDevices && navigator.mediaDevices.getDisplayMedia),
      enumerateDevices: !!(navigator.mediaDevices && navigator.mediaDevices.enumerateDevices),
      webRTC: !!window.RTCPeerConnection,
    };
  }
}

export const mediaManager = new MediaManager();

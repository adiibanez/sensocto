/**
 * Adaptive Producer - Manages video output quality based on tier
 *
 * Switches between video stream modes and snapshot mode based on
 * the participant's assigned quality tier from the server.
 *
 * Tiers:
 * - active: Full video (720p@30fps)
 * - recent: Reduced video (480p@15fps)
 * - viewer: Snapshot mode (1-3fps JPEG)
 * - idle: Static avatar (no video/snapshots)
 */

export class AdaptiveProducer {
  constructor(options = {}) {
    // Callbacks
    this.onModeChange = options.onModeChange || (() => {});
    this.onSnapshot = options.onSnapshot || (() => {});
    this.onError = options.onError || (() => {});

    // Quality settings per tier
    this.tierSettings = {
      active: {
        mode: "video",
        width: 1280,
        height: 720,
        frameRate: 30,
        bitrate: 2500000, // 2.5 Mbps
      },
      recent: {
        mode: "video",
        width: 640,
        height: 480,
        frameRate: 15,
        bitrate: 500000, // 500 Kbps
      },
      viewer: {
        mode: "snapshot",
        snapshotInterval: 1000, // 1 fps
        snapshotQuality: 0.7,   // JPEG quality (0-1)
        maxWidth: 320,
        maxHeight: 240,
      },
      idle: {
        mode: "none",
      },
    };

    // State
    this.currentTier = "viewer";
    this.currentMode = "video";
    this.videoTrack = null;
    this.stream = null;
    this.snapshotCanvas = null;
    this.snapshotContext = null;
    this.snapshotTimer = null;
    this.videoElement = null;
    this.isRunning = false;

    // RTCRtpSender for applying constraints
    this.sender = null;
  }

  /**
   * Initialize with a video track
   * @param {MediaStreamTrack} videoTrack - The video track to manage
   * @param {RTCRtpSender} sender - Optional RTP sender for constraint updates
   */
  init(videoTrack, sender = null) {
    this.videoTrack = videoTrack;
    this.sender = sender;

    // Create hidden video element for snapshot capture
    this.videoElement = document.createElement("video");
    this.videoElement.autoplay = true;
    this.videoElement.playsInline = true;
    this.videoElement.muted = true;

    // Create stream from track
    this.stream = new MediaStream([videoTrack]);
    this.videoElement.srcObject = this.stream;

    // Create canvas for snapshot capture
    this.snapshotCanvas = document.createElement("canvas");
    this.snapshotContext = this.snapshotCanvas.getContext("2d");

    this.isRunning = true;
    console.log("[AdaptiveProducer] Initialized");

    // Apply initial tier
    this.setTier(this.currentTier);
  }

  /**
   * Set the quality tier
   * @param {string} tier - One of: active, recent, viewer, idle
   */
  async setTier(tier) {
    if (!this.tierSettings[tier]) {
      console.warn(`[AdaptiveProducer] Unknown tier: ${tier}`);
      return;
    }

    const oldTier = this.currentTier;
    this.currentTier = tier;
    const settings = this.tierSettings[tier];

    console.log(`[AdaptiveProducer] Tier change: ${oldTier} -> ${tier} (mode: ${settings.mode})`);

    // Stop any existing snapshot timer
    this._stopSnapshotTimer();

    switch (settings.mode) {
      case "video":
        await this._switchToVideoMode(settings);
        break;
      case "snapshot":
        await this._switchToSnapshotMode(settings);
        break;
      case "none":
        this._switchToIdleMode();
        break;
    }

    this.currentMode = settings.mode;
    this.onModeChange(tier, settings.mode);
  }

  /**
   * Switch to video streaming mode with specified constraints
   */
  async _switchToVideoMode(settings) {
    if (!this.videoTrack) return;

    // Re-enable video track if it was disabled
    if (!this.videoTrack.enabled) {
      this.videoTrack.enabled = true;
    }

    // Apply constraints to the video track
    const constraints = {
      width: { ideal: settings.width },
      height: { ideal: settings.height },
      frameRate: { ideal: settings.frameRate },
    };

    try {
      await this.videoTrack.applyConstraints(constraints);
      console.log(`[AdaptiveProducer] Applied video constraints: ${settings.width}x${settings.height}@${settings.frameRate}fps`);
    } catch (error) {
      console.warn("[AdaptiveProducer] Failed to apply constraints:", error);
      // Continue anyway - browser may not support all constraints
    }

    // Apply bitrate via sender if available
    if (this.sender) {
      try {
        const params = this.sender.getParameters();
        if (params.encodings && params.encodings.length > 0) {
          params.encodings[0].maxBitrate = settings.bitrate;
          await this.sender.setParameters(params);
          console.log(`[AdaptiveProducer] Set bitrate: ${settings.bitrate / 1000} Kbps`);
        }
      } catch (error) {
        console.warn("[AdaptiveProducer] Failed to set bitrate:", error);
      }
    }
  }

  /**
   * Switch to snapshot mode - captures JPEG frames at low rate
   */
  async _switchToSnapshotMode(settings) {
    if (!this.videoTrack || !this.videoElement) return;

    // Keep video track enabled for capture, but we'll send snapshots instead
    // The actual WebRTC video track could be disabled/paused if bandwidth is critical
    // For now, we keep it enabled but at lowest quality and capture snapshots separately

    // Apply minimal video constraints to reduce bandwidth
    const minConstraints = {
      width: { ideal: settings.maxWidth },
      height: { ideal: settings.maxHeight },
      frameRate: { ideal: 5 }, // Low framerate for live preview
    };

    try {
      await this.videoTrack.applyConstraints(minConstraints);
    } catch (error) {
      console.warn("[AdaptiveProducer] Failed to apply snapshot constraints:", error);
    }

    // Set canvas size
    this.snapshotCanvas.width = settings.maxWidth;
    this.snapshotCanvas.height = settings.maxHeight;

    // Start snapshot timer
    this._startSnapshotTimer(settings);
  }

  /**
   * Switch to idle mode - no video output
   */
  _switchToIdleMode() {
    if (this.videoTrack) {
      this.videoTrack.enabled = false;
    }
    console.log("[AdaptiveProducer] Video disabled (idle mode)");
  }

  /**
   * Start capturing snapshots at the specified interval
   */
  _startSnapshotTimer(settings) {
    this.snapshotTimer = setInterval(() => {
      this._captureSnapshot(settings);
    }, settings.snapshotInterval);

    // Capture immediately
    this._captureSnapshot(settings);
  }

  /**
   * Stop the snapshot timer
   */
  _stopSnapshotTimer() {
    if (this.snapshotTimer) {
      clearInterval(this.snapshotTimer);
      this.snapshotTimer = null;
    }
  }

  /**
   * Capture a single snapshot from the video element
   */
  _captureSnapshot(settings) {
    if (!this.videoElement || !this.snapshotContext) return;

    // Check if video is ready
    if (this.videoElement.readyState < 2) {
      return;
    }

    try {
      // Draw current frame to canvas
      this.snapshotContext.drawImage(
        this.videoElement,
        0, 0,
        this.snapshotCanvas.width,
        this.snapshotCanvas.height
      );

      // Convert to JPEG data URL
      const dataUrl = this.snapshotCanvas.toDataURL("image/jpeg", settings.snapshotQuality);

      // Extract base64 data (remove data URL prefix)
      const base64Data = dataUrl.split(",")[1];

      // Callback with snapshot data
      this.onSnapshot({
        data: base64Data,
        width: this.snapshotCanvas.width,
        height: this.snapshotCanvas.height,
        timestamp: Date.now(),
      });
    } catch (error) {
      console.error("[AdaptiveProducer] Snapshot capture error:", error);
      this.onError(error);
    }
  }

  /**
   * Get a single snapshot on demand
   * @returns {Object} Snapshot data with base64 and metadata
   */
  captureSnapshotNow(quality = 0.7, maxWidth = 320, maxHeight = 240) {
    if (!this.videoElement || !this.snapshotContext) {
      return null;
    }

    if (this.videoElement.readyState < 2) {
      return null;
    }

    this.snapshotCanvas.width = maxWidth;
    this.snapshotCanvas.height = maxHeight;

    this.snapshotContext.drawImage(
      this.videoElement,
      0, 0,
      maxWidth,
      maxHeight
    );

    const dataUrl = this.snapshotCanvas.toDataURL("image/jpeg", quality);
    const base64Data = dataUrl.split(",")[1];

    return {
      data: base64Data,
      dataUrl: dataUrl,
      width: maxWidth,
      height: maxHeight,
      timestamp: Date.now(),
    };
  }

  /**
   * Update the RTP sender (e.g., after renegotiation)
   */
  setSender(sender) {
    this.sender = sender;
    // Re-apply current tier settings
    if (this.currentMode === "video") {
      const settings = this.tierSettings[this.currentTier];
      this._switchToVideoMode(settings);
    }
  }

  /**
   * Get current state
   */
  getState() {
    return {
      tier: this.currentTier,
      mode: this.currentMode,
      isRunning: this.isRunning,
      settings: this.tierSettings[this.currentTier],
    };
  }

  /**
   * Clean up resources
   */
  destroy() {
    this.isRunning = false;
    this._stopSnapshotTimer();

    if (this.videoElement) {
      this.videoElement.srcObject = null;
      this.videoElement = null;
    }

    this.snapshotCanvas = null;
    this.snapshotContext = null;
    this.videoTrack = null;
    this.sender = null;
    this.stream = null;

    console.log("[AdaptiveProducer] Destroyed");
  }
}

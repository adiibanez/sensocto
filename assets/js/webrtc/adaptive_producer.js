/**
 * Adaptive Producer - Manages video output quality based on tier
 *
 * Switches between video stream modes and snapshot mode based on
 * the participant's assigned quality tier from the server.
 *
 * Tiers:
 * - active: Full video (720p@30fps)
 * - recent: Reduced video (720p@15fps, lower bitrate)
 * - viewer: Snapshot mode (captures JPEG at 1fps, video stays at low bitrate)
 * - idle: Minimal video (very low bitrate/framerate)
 *
 * Key design: Resolution NEVER changes after init to avoid camera reconfiguration
 * which causes black frames. Only bitrate/framerate are adjusted.
 */

export class AdaptiveProducer {
  constructor(options = {}) {
    // Callbacks
    this.onModeChange = options.onModeChange || (() => {});
    this.onSnapshot = options.onSnapshot || (() => {});
    this.onError = options.onError || (() => {});

    // Quality settings per tier
    // Resolution stays constant across all tiers to prevent black-frame flashes
    // when the camera reconfigures. Bandwidth is controlled via bitrate + framerate.
    this.tierSettings = {
      active: {
        mode: "video",
        frameRate: 30,
        bitrate: 2500000, // 2.5 Mbps
      },
      recent: {
        mode: "video",
        frameRate: 15,
        bitrate: 500000, // 500 Kbps
      },
      viewer: {
        mode: "snapshot",
        frameRate: 5,
        bitrate: 150000, // 150 Kbps — low video kept alive as fallback
        snapshotInterval: 1000, // Capture JPEG every 1s
        snapshotQuality: 0.7,
        snapshotMaxWidth: 320,
        snapshotMaxHeight: 240,
      },
      idle: {
        mode: "video",
        frameRate: 5,
        bitrate: 100000, // 100 Kbps
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

    // Store initial resolution so we never change it
    this._initWidth = null;
    this._initHeight = null;
  }

  /**
   * Initialize with a video track
   * @param {MediaStreamTrack} videoTrack - The video track to manage
   * @param {RTCRtpSender} sender - Optional RTP sender for constraint updates
   */
  init(videoTrack, sender = null) {
    this.videoTrack = videoTrack;
    this.sender = sender;

    // Store initial resolution from the track's actual settings
    const trackSettings = videoTrack.getSettings();
    this._initWidth = trackSettings.width || 1280;
    this._initHeight = trackSettings.height || 720;

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
    console.log(`[AdaptiveProducer] Initialized at ${this._initWidth}x${this._initHeight}`);

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

    // Always apply framerate + bitrate (never changes resolution)
    await this._applyQuality(settings);

    // Start snapshot capture if in snapshot mode
    if (settings.mode === "snapshot") {
      this._startSnapshotTimer(settings);
    }

    this.currentMode = settings.mode;
    this.onModeChange(tier, settings.mode);
  }

  /**
   * Apply framerate and bitrate without changing resolution.
   * The video track stays enabled at its original resolution.
   */
  async _applyQuality(settings) {
    if (!this.videoTrack) return;

    // Ensure track is enabled
    if (!this.videoTrack.enabled) {
      this.videoTrack.enabled = true;
    }

    // Only change framerate — keep resolution locked to initial value
    try {
      await this.videoTrack.applyConstraints({
        width: { ideal: this._initWidth },
        height: { ideal: this._initHeight },
        frameRate: { ideal: settings.frameRate },
      });
    } catch (error) {
      console.warn("[AdaptiveProducer] Failed to apply framerate constraint:", error);
    }

    // Apply bitrate via sender
    if (this.sender) {
      try {
        const params = this.sender.getParameters();
        if (params.encodings && params.encodings.length > 0) {
          params.encodings[0].maxBitrate = settings.bitrate;
          await this.sender.setParameters(params);
        }
      } catch (error) {
        console.warn("[AdaptiveProducer] Failed to set bitrate:", error);
      }
    }
  }

  /**
   * Start capturing snapshots at the specified interval
   */
  _startSnapshotTimer(settings) {
    const maxW = settings.snapshotMaxWidth || 320;
    const maxH = settings.snapshotMaxHeight || 240;
    const quality = settings.snapshotQuality || 0.7;

    this.snapshotCanvas.width = maxW;
    this.snapshotCanvas.height = maxH;

    this.snapshotTimer = setInterval(() => {
      this._captureSnapshot(maxW, maxH, quality);
    }, settings.snapshotInterval);

    // Capture immediately
    this._captureSnapshot(maxW, maxH, quality);
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
  _captureSnapshot(width, height, quality) {
    if (!this.videoElement || !this.snapshotContext) return;
    if (this.videoElement.readyState < 2) return;

    try {
      this.snapshotContext.drawImage(this.videoElement, 0, 0, width, height);
      const dataUrl = this.snapshotCanvas.toDataURL("image/jpeg", quality);
      const base64Data = dataUrl.split(",")[1];

      this.onSnapshot({
        data: base64Data,
        width,
        height,
        timestamp: Date.now(),
      });
    } catch (error) {
      console.error("[AdaptiveProducer] Snapshot capture error:", error);
      this.onError(error);
    }
  }

  /**
   * Get a single snapshot on demand
   */
  captureSnapshotNow(quality = 0.7, maxWidth = 320, maxHeight = 240) {
    if (!this.videoElement || !this.snapshotContext) return null;
    if (this.videoElement.readyState < 2) return null;

    this.snapshotCanvas.width = maxWidth;
    this.snapshotCanvas.height = maxHeight;

    this.snapshotContext.drawImage(this.videoElement, 0, 0, maxWidth, maxHeight);
    const dataUrl = this.snapshotCanvas.toDataURL("image/jpeg", quality);
    const base64Data = dataUrl.split(",")[1];

    return {
      data: base64Data,
      dataUrl,
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
    if (this.isRunning) {
      const settings = this.tierSettings[this.currentTier];
      this._applyQuality(settings);
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

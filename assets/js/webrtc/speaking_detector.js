/**
 * Speaking Detector - Uses Web Audio API to detect when user is speaking
 *
 * Detects audio activity for adaptive video quality in large calls.
 * Quick to detect speech start (~100ms), slower to detect stop (~500ms)
 * to avoid flickering during natural pauses.
 */

export class SpeakingDetector {
  constructor(options = {}) {
    // Callbacks
    this.onSpeakingChange = options.onSpeakingChange || (() => {});
    this.onVolumeChange = options.onVolumeChange || (() => {});

    // Detection thresholds (tuned for voice activity)
    this.speakingThreshold = options.speakingThreshold || 0.01; // RMS threshold to consider speaking
    this.silenceThreshold = options.silenceThreshold || 0.005;  // Below this = definitely silence

    // Debounce settings (quick to detect, slow to stop)
    this.speakingDebounceMs = options.speakingDebounceMs || 100;  // Time to confirm speaking
    this.silenceDebounceMs = options.silenceDebounceMs || 500;    // Time to confirm silence

    // Audio analysis settings
    this.fftSize = options.fftSize || 256;
    this.smoothingTimeConstant = options.smoothingTimeConstant || 0.3;

    // Internal state
    this.audioContext = null;
    this.analyser = null;
    this.sourceNode = null;
    this.dataArray = null;
    this.animationFrame = null;
    this.isDetecting = false;
    this.isSpeaking = false;

    // Debounce timers
    this._speakingTimer = null;
    this._silenceTimer = null;
    this._lastVolume = 0;

    // Statistics for debugging
    this._stats = {
      peakVolume: 0,
      avgVolume: 0,
      sampleCount: 0,
    };
  }

  /**
   * Start detecting speaking from a MediaStream
   * @param {MediaStream} stream - The audio stream to analyze
   */
  async start(stream) {
    if (this.isDetecting) {
      console.log("[SpeakingDetector] Already detecting, stopping first");
      this.stop();
    }

    if (!stream) {
      console.error("[SpeakingDetector] No stream provided");
      return false;
    }

    const audioTracks = stream.getAudioTracks();
    if (audioTracks.length === 0) {
      console.warn("[SpeakingDetector] Stream has no audio tracks");
      return false;
    }

    try {
      // Create audio context
      this.audioContext = new (window.AudioContext || window.webkitAudioContext)();

      // Resume context if suspended (browsers require user interaction)
      if (this.audioContext.state === 'suspended') {
        await this.audioContext.resume();
      }

      // Create analyser node
      this.analyser = this.audioContext.createAnalyser();
      this.analyser.fftSize = this.fftSize;
      this.analyser.smoothingTimeConstant = this.smoothingTimeConstant;

      // Create source from stream
      this.sourceNode = this.audioContext.createMediaStreamSource(stream);
      this.sourceNode.connect(this.analyser);

      // Create data array for analysis
      this.dataArray = new Float32Array(this.analyser.fftSize);

      // Start detection loop
      this.isDetecting = true;
      this._detectLoop();

      console.log("[SpeakingDetector] Started detection");
      return true;
    } catch (error) {
      console.error("[SpeakingDetector] Failed to start:", error);
      this.stop();
      return false;
    }
  }

  /**
   * Stop detecting
   */
  stop() {
    this.isDetecting = false;

    if (this.animationFrame) {
      cancelAnimationFrame(this.animationFrame);
      this.animationFrame = null;
    }

    if (this._speakingTimer) {
      clearTimeout(this._speakingTimer);
      this._speakingTimer = null;
    }

    if (this._silenceTimer) {
      clearTimeout(this._silenceTimer);
      this._silenceTimer = null;
    }

    if (this.sourceNode) {
      try {
        this.sourceNode.disconnect();
      } catch (e) {
        // Ignore
      }
      this.sourceNode = null;
    }

    if (this.analyser) {
      this.analyser = null;
    }

    if (this.audioContext) {
      try {
        this.audioContext.close();
      } catch (e) {
        // Ignore
      }
      this.audioContext = null;
    }

    this.dataArray = null;

    // Reset state
    if (this.isSpeaking) {
      this.isSpeaking = false;
      this.onSpeakingChange(false);
    }

    console.log("[SpeakingDetector] Stopped detection");
  }

  /**
   * Main detection loop using requestAnimationFrame
   */
  _detectLoop() {
    if (!this.isDetecting || !this.analyser) {
      return;
    }

    // Get time domain data
    this.analyser.getFloatTimeDomainData(this.dataArray);

    // Calculate RMS (Root Mean Square) for volume level
    let sum = 0;
    for (let i = 0; i < this.dataArray.length; i++) {
      sum += this.dataArray[i] * this.dataArray[i];
    }
    const rms = Math.sqrt(sum / this.dataArray.length);

    // Update statistics
    this._stats.sampleCount++;
    this._stats.peakVolume = Math.max(this._stats.peakVolume, rms);
    this._stats.avgVolume = (this._stats.avgVolume * (this._stats.sampleCount - 1) + rms) / this._stats.sampleCount;

    // Smooth the volume for UI display
    this._lastVolume = this._lastVolume * 0.7 + rms * 0.3;
    this.onVolumeChange(this._lastVolume);

    // Detect speaking state changes with debouncing
    this._updateSpeakingState(rms);

    // Continue loop
    this.animationFrame = requestAnimationFrame(() => this._detectLoop());
  }

  /**
   * Update speaking state with debouncing
   */
  _updateSpeakingState(rms) {
    const isAboveThreshold = rms > this.speakingThreshold;
    const isBelowSilence = rms < this.silenceThreshold;

    if (isAboveThreshold && !this.isSpeaking) {
      // Potentially starting to speak - use short debounce
      if (!this._speakingTimer) {
        this._speakingTimer = setTimeout(() => {
          this._speakingTimer = null;
          if (this.isDetecting && !this.isSpeaking) {
            this.isSpeaking = true;
            console.log("[SpeakingDetector] Speaking started");
            this.onSpeakingChange(true);
          }
        }, this.speakingDebounceMs);
      }

      // Cancel any pending silence detection
      if (this._silenceTimer) {
        clearTimeout(this._silenceTimer);
        this._silenceTimer = null;
      }
    } else if (isBelowSilence && this.isSpeaking) {
      // Potentially stopping speaking - use longer debounce
      if (!this._silenceTimer) {
        this._silenceTimer = setTimeout(() => {
          this._silenceTimer = null;
          if (this.isDetecting && this.isSpeaking) {
            this.isSpeaking = false;
            console.log("[SpeakingDetector] Speaking stopped");
            this.onSpeakingChange(false);
          }
        }, this.silenceDebounceMs);
      }

      // Cancel any pending speaking detection
      if (this._speakingTimer) {
        clearTimeout(this._speakingTimer);
        this._speakingTimer = null;
      }
    } else if (!isBelowSilence && this.isSpeaking) {
      // Still some audio, cancel silence timer
      if (this._silenceTimer) {
        clearTimeout(this._silenceTimer);
        this._silenceTimer = null;
      }
    }
  }

  /**
   * Get current speaking state
   */
  getSpeaking() {
    return this.isSpeaking;
  }

  /**
   * Get current volume level (0-1 range, smoothed)
   */
  getVolume() {
    return this._lastVolume;
  }

  /**
   * Get detection statistics (for debugging)
   */
  getStats() {
    return {
      ...this._stats,
      isSpeaking: this.isSpeaking,
      currentVolume: this._lastVolume,
      isDetecting: this.isDetecting,
    };
  }

  /**
   * Update thresholds dynamically (e.g., for auto-calibration)
   */
  setThresholds(speakingThreshold, silenceThreshold) {
    if (speakingThreshold !== undefined) {
      this.speakingThreshold = speakingThreshold;
    }
    if (silenceThreshold !== undefined) {
      this.silenceThreshold = silenceThreshold;
    }
  }

  /**
   * Clean up resources
   */
  destroy() {
    this.stop();
    this.onSpeakingChange = () => {};
    this.onVolumeChange = () => {};
  }
}

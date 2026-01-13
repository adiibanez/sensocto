/**
 * Adaptive Consumer - Handles receiving video at different quality tiers
 *
 * Manages the display of remote participants' video, which may come as:
 * - Full video stream (active/recent tiers)
 * - JPEG snapshots (viewer tier)
 * - Static avatar (idle tier)
 *
 * Provides smooth transitions between modes.
 */

export class AdaptiveConsumer {
  constructor(options = {}) {
    // Callbacks
    this.onModeChange = options.onModeChange || (() => {});
    this.onError = options.onError || (() => {});

    // Managed participants: Map<userId, ParticipantState>
    this.participants = new Map();

    // Default avatar URL (data URL or external)
    this.defaultAvatarUrl = options.defaultAvatarUrl || this._generateDefaultAvatar();

    // Transition settings
    this.transitionDuration = options.transitionDuration || 300; // ms
  }

  /**
   * Register a participant for adaptive consumption
   * @param {string} userId - Participant user ID
   * @param {HTMLElement} container - Container element for video/image display
   */
  registerParticipant(userId, container) {
    if (this.participants.has(userId)) {
      console.log(`[AdaptiveConsumer] Participant ${userId} already registered, updating`);
      this.unregisterParticipant(userId);
    }

    const state = {
      userId,
      container,
      currentMode: "video", // video, snapshot, avatar
      currentTier: "viewer",
      videoElement: null,
      snapshotElement: null,
      avatarElement: null,
      lastSnapshot: null,
      mediaStream: null,
    };

    // Create elements
    state.videoElement = this._createVideoElement();
    state.snapshotElement = this._createSnapshotElement();
    state.avatarElement = this._createAvatarElement();

    // Initially show video element
    container.appendChild(state.videoElement);
    container.appendChild(state.snapshotElement);
    container.appendChild(state.avatarElement);

    // Default: video visible, others hidden
    state.videoElement.style.display = "block";
    state.snapshotElement.style.display = "none";
    state.avatarElement.style.display = "none";

    this.participants.set(userId, state);
    console.log(`[AdaptiveConsumer] Registered participant ${userId}`);
  }

  /**
   * Unregister a participant
   */
  unregisterParticipant(userId) {
    const state = this.participants.get(userId);
    if (!state) return;

    // Clean up video stream
    if (state.videoElement && state.videoElement.srcObject) {
      state.videoElement.srcObject = null;
    }

    // Remove elements from container
    if (state.container) {
      if (state.videoElement?.parentNode === state.container) {
        state.container.removeChild(state.videoElement);
      }
      if (state.snapshotElement?.parentNode === state.container) {
        state.container.removeChild(state.snapshotElement);
      }
      if (state.avatarElement?.parentNode === state.container) {
        state.container.removeChild(state.avatarElement);
      }
    }

    this.participants.delete(userId);
    console.log(`[AdaptiveConsumer] Unregistered participant ${userId}`);
  }

  /**
   * Set the video stream for a participant
   */
  setVideoStream(userId, stream) {
    const state = this.participants.get(userId);
    if (!state) {
      console.warn(`[AdaptiveConsumer] Unknown participant ${userId}`);
      return;
    }

    state.mediaStream = stream;

    if (state.videoElement) {
      state.videoElement.srcObject = stream;
    }
  }

  /**
   * Add a video track to a participant's stream
   */
  addVideoTrack(userId, track) {
    const state = this.participants.get(userId);
    if (!state) return;

    if (!state.mediaStream) {
      state.mediaStream = new MediaStream();
    }

    // Remove existing video tracks
    state.mediaStream.getVideoTracks().forEach(t => {
      state.mediaStream.removeTrack(t);
    });

    state.mediaStream.addTrack(track);

    if (state.videoElement) {
      state.videoElement.srcObject = state.mediaStream;
    }
  }

  /**
   * Add an audio track to a participant's stream
   */
  addAudioTrack(userId, track) {
    const state = this.participants.get(userId);
    if (!state) return;

    if (!state.mediaStream) {
      state.mediaStream = new MediaStream();
    }

    // Remove existing audio tracks
    state.mediaStream.getAudioTracks().forEach(t => {
      state.mediaStream.removeTrack(t);
    });

    state.mediaStream.addTrack(track);

    if (state.videoElement) {
      state.videoElement.srcObject = state.mediaStream;
    }
  }

  /**
   * Update a participant's tier and switch display mode accordingly
   */
  setParticipantTier(userId, tier) {
    const state = this.participants.get(userId);
    if (!state) return;

    if (state.currentTier === tier) return;

    const oldTier = state.currentTier;
    state.currentTier = tier;

    console.log(`[AdaptiveConsumer] ${userId} tier: ${oldTier} -> ${tier}`);

    // Determine display mode based on tier
    let newMode;
    switch (tier) {
      case "active":
      case "recent":
        newMode = "video";
        break;
      case "viewer":
        newMode = "snapshot";
        break;
      case "idle":
        newMode = "avatar";
        break;
      default:
        newMode = "video";
    }

    this._switchMode(state, newMode);
  }

  /**
   * Receive a snapshot for a participant
   */
  receiveSnapshot(userId, snapshotData) {
    const state = this.participants.get(userId);
    if (!state) return;

    state.lastSnapshot = snapshotData;

    // Update snapshot element
    if (state.snapshotElement && snapshotData.data) {
      state.snapshotElement.src = `data:image/jpeg;base64,${snapshotData.data}`;
    }

    // If in snapshot mode, ensure snapshot is visible
    if (state.currentMode === "snapshot") {
      state.snapshotElement.style.display = "block";
    }
  }

  /**
   * Set a custom avatar for a participant
   */
  setAvatar(userId, avatarUrl) {
    const state = this.participants.get(userId);
    if (!state) return;

    if (state.avatarElement) {
      state.avatarElement.src = avatarUrl;
    }
  }

  /**
   * Get current state for a participant
   */
  getParticipantState(userId) {
    const state = this.participants.get(userId);
    if (!state) return null;

    return {
      userId: state.userId,
      currentMode: state.currentMode,
      currentTier: state.currentTier,
      hasVideoStream: !!state.mediaStream?.getVideoTracks().length,
      hasSnapshot: !!state.lastSnapshot,
    };
  }

  /**
   * Switch display mode for a participant
   */
  _switchMode(state, newMode) {
    if (state.currentMode === newMode) return;

    const oldMode = state.currentMode;
    state.currentMode = newMode;

    console.log(`[AdaptiveConsumer] ${state.userId} mode: ${oldMode} -> ${newMode}`);

    // Animate transition
    this._animateTransition(state, oldMode, newMode);

    this.onModeChange(state.userId, newMode, state.currentTier);
  }

  /**
   * Animate transition between modes
   */
  _animateTransition(state, fromMode, toMode) {
    const elements = {
      video: state.videoElement,
      snapshot: state.snapshotElement,
      avatar: state.avatarElement,
    };

    // Fade out old element
    const oldElement = elements[fromMode];
    if (oldElement) {
      oldElement.style.transition = `opacity ${this.transitionDuration}ms ease-out`;
      oldElement.style.opacity = "0";
      setTimeout(() => {
        oldElement.style.display = "none";
      }, this.transitionDuration);
    }

    // Fade in new element
    const newElement = elements[toMode];
    if (newElement) {
      newElement.style.display = "block";
      newElement.style.opacity = "0";
      // Force reflow
      newElement.offsetHeight;
      newElement.style.transition = `opacity ${this.transitionDuration}ms ease-in`;
      newElement.style.opacity = "1";
    }
  }

  /**
   * Create video element
   */
  _createVideoElement() {
    const video = document.createElement("video");
    video.autoplay = true;
    video.playsInline = true;
    video.muted = false; // Remote audio should play
    video.className = "adaptive-consumer-video w-full h-full object-cover rounded-lg";
    video.style.position = "absolute";
    video.style.top = "0";
    video.style.left = "0";
    return video;
  }

  /**
   * Create snapshot image element
   */
  _createSnapshotElement() {
    const img = document.createElement("img");
    img.className = "adaptive-consumer-snapshot w-full h-full object-cover rounded-lg";
    img.style.position = "absolute";
    img.style.top = "0";
    img.style.left = "0";
    img.alt = "Video snapshot";
    return img;
  }

  /**
   * Create avatar image element
   */
  _createAvatarElement() {
    const img = document.createElement("img");
    img.className = "adaptive-consumer-avatar w-full h-full object-cover rounded-lg";
    img.style.position = "absolute";
    img.style.top = "0";
    img.style.left = "0";
    img.src = this.defaultAvatarUrl;
    img.alt = "User avatar";
    return img;
  }

  /**
   * Generate a default avatar as a data URL
   */
  _generateDefaultAvatar() {
    // Create a simple colored circle with user icon
    const canvas = document.createElement("canvas");
    canvas.width = 200;
    canvas.height = 200;
    const ctx = canvas.getContext("2d");

    // Background
    ctx.fillStyle = "#4B5563"; // gray-600
    ctx.fillRect(0, 0, 200, 200);

    // Circle
    ctx.beginPath();
    ctx.arc(100, 100, 80, 0, Math.PI * 2);
    ctx.fillStyle = "#6B7280"; // gray-500
    ctx.fill();

    // Simple user icon (head)
    ctx.beginPath();
    ctx.arc(100, 80, 30, 0, Math.PI * 2);
    ctx.fillStyle = "#9CA3AF"; // gray-400
    ctx.fill();

    // Body
    ctx.beginPath();
    ctx.arc(100, 160, 50, Math.PI, 0);
    ctx.fill();

    return canvas.toDataURL("image/png");
  }

  /**
   * Clean up all participants
   */
  destroy() {
    for (const userId of this.participants.keys()) {
      this.unregisterParticipant(userId);
    }
    this.participants.clear();
    console.log("[AdaptiveConsumer] Destroyed");
  }
}

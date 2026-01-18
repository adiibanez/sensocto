/**
 * User Video Tile Hook
 *
 * Manages attention-based video quality for user cards in the Users tab.
 * Integrates with the existing AttentionTracker pattern and CallHook.
 */

export const UserVideoTileHook = {
  mounted() {
    this.connectorId = this.el.dataset.connectorId;
    this.inCall = this.el.dataset.inCall === "true";

    console.log(`[UserVideoTile] Mounted for connector: ${this.connectorId}, inCall: ${this.inCall}`);

    // Set up IntersectionObserver for visibility-based attention
    this.setupVisibilityObserver();

    // If user is in call, try to attach their video stream
    if (this.inCall) {
      this.attachVideoStream();
    }
  },

  updated() {
    const wasInCall = this.inCall;
    this.inCall = this.el.dataset.inCall === "true";

    // If call state changed, update video attachment
    if (wasInCall !== this.inCall) {
      if (this.inCall) {
        this.attachVideoStream();
      } else {
        this.detachVideoStream();
      }
    }
  },

  destroyed() {
    if (this.visibilityObserver) {
      this.visibilityObserver.disconnect();
      this.visibilityObserver = null;
    }
    this.detachVideoStream();
  },

  setupVisibilityObserver() {
    // Use IntersectionObserver to track when this card is visible
    this.visibilityObserver = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            // Card is visible - at least medium attention
            this.onVisible();
          } else {
            // Card is not visible - low attention
            this.onHidden();
          }
        }
      },
      {
        threshold: 0.1,
        rootMargin: "50px",
      }
    );

    this.visibilityObserver.observe(this.el);
  },

  onVisible() {
    console.log(`[UserVideoTile] ${this.connectorId} became visible`);
    // Visibility alone gives medium attention
    // Hover will boost to high (handled by LiveView phx-mouseenter)
  },

  onHidden() {
    console.log(`[UserVideoTile] ${this.connectorId} became hidden`);
    // Could reduce video quality here if needed
  },

  attachVideoStream() {
    // Get reference to the main CallHook
    const callHook = window.__callHook;
    if (!callHook) {
      console.log("[UserVideoTile] No active call hook found");
      return;
    }

    const videoEl = this.el.querySelector(`#user-video-${this.connectorId}`);
    const snapshotEl = this.el.querySelector(`#user-snapshot-${this.connectorId}`);

    if (!videoEl) {
      console.log(`[UserVideoTile] No video element found for ${this.connectorId}`);
      return;
    }

    // Try to find this user's tracks in the call
    // The connector_id should map to a user_id in the call
    for (const [userId, participant] of callHook.participants || []) {
      // Check if this participant matches our connector
      // This is a simplified check - in practice you'd need proper user mapping
      if (this.matchesUser(userId, participant)) {
        console.log(`[UserVideoTile] Found matching participant: ${userId}`);
        this.attachParticipantVideo(userId, videoEl, snapshotEl, callHook);
        return;
      }
    }

    // Also check pending tracks
    for (const [userId] of callHook.pendingTracks || []) {
      if (this.matchesUser(userId, null)) {
        console.log(`[UserVideoTile] Found pending tracks for: ${userId}`);
        this.attachPendingTracks(userId, videoEl, callHook);
        return;
      }
    }

    console.log(`[UserVideoTile] No matching participant found for connector: ${this.connectorId}`);
  },

  matchesUser(userId, participant) {
    // Match by connector_id or user_id
    // This is a simplified matching - real implementation would need proper user/connector mapping
    if (userId === this.connectorId) return true;
    if (participant?.user_info?.connector_id === this.connectorId) return true;
    if (participant?.metadata?.connector_id === this.connectorId) return true;
    return false;
  },

  attachParticipantVideo(userId, videoEl, snapshotEl, callHook) {
    // Check if there's already a video element for this participant in the main call container
    const mainVideoEl = document.querySelector(`#participant-${userId} video`);
    if (mainVideoEl?.srcObject) {
      // Clone the stream to this video element
      videoEl.srcObject = mainVideoEl.srcObject;
      console.log(`[UserVideoTile] Cloned video stream for ${userId}`);
      return;
    }

    // Check pending tracks
    const pendingTracks = callHook.pendingTracks?.get(userId);
    if (pendingTracks) {
      this.attachPendingTracks(userId, videoEl, callHook);
    }
  },

  attachPendingTracks(userId, videoEl, callHook) {
    const pendingTracks = callHook.pendingTracks?.get(userId);
    if (!pendingTracks) return;

    let stream = videoEl.srcObject;
    if (!stream) {
      stream = new MediaStream();
      videoEl.srcObject = stream;
    }

    for (const ctx of pendingTracks) {
      if (ctx.track?.kind === "video") {
        const existing = stream.getVideoTracks().find((t) => t.id === ctx.track.id);
        if (!existing) {
          stream.addTrack(ctx.track);
          console.log(`[UserVideoTile] Attached video track for ${userId}`);
        }
      }
    }
  },

  detachVideoStream() {
    const videoEl = this.el.querySelector(`#user-video-${this.connectorId}`);
    if (videoEl?.srcObject) {
      // Don't stop the tracks - they might be used elsewhere
      // Just remove the reference
      videoEl.srcObject = null;
    }
  },

  // Handle snapshot updates for viewer tier
  updateSnapshot(snapshotData) {
    const snapshotEl = this.el.querySelector(`#user-snapshot-${this.connectorId}`);
    if (snapshotEl && snapshotData?.data) {
      snapshotEl.src = snapshotData.data;
    }
  },
};

export default UserVideoTileHook;

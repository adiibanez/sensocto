/**
 * Mini Call Indicator Hook
 *
 * Manages the floating mini call indicator component.
 * Coordinates with the main CallHook to display video streams in the mini view.
 */

export const MiniCallIndicatorHook = {
  mounted() {
    console.log("[MiniCallIndicator] Mounted");

    // Set up observer to detect when mini video containers appear
    this.setupVideoObserver();

    // Try to attach streams if they already exist
    this.attachStreams();
  },

  updated() {
    // Re-attach streams when component updates (e.g., expand/collapse)
    this.attachStreams();
  },

  destroyed() {
    if (this.observer) {
      this.observer.disconnect();
      this.observer = null;
    }
  },

  setupVideoObserver() {
    this.observer = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        for (const node of mutation.addedNodes) {
          if (node.nodeType === Node.ELEMENT_NODE) {
            // Check for mini video containers
            if (node.id === "mini-local-video" || node.id?.startsWith("mini-participant-")) {
              console.log(`[MiniCallIndicator] Detected video container: ${node.id}`);
              this.attachStreams();
            }
            // Check children
            const videoContainers = node.querySelectorAll?.('[id^="mini-"]') || [];
            if (videoContainers.length > 0) {
              this.attachStreams();
            }
          }
        }
      }
    });

    this.observer.observe(this.el, {
      childList: true,
      subtree: true,
    });
  },

  attachStreams() {
    // Get reference to the main CallHook
    const callHook = window.__callHook;
    if (!callHook || !callHook.localStream) {
      console.log("[MiniCallIndicator] No active call stream found");
      return;
    }

    // Attach local stream to mini local video
    const miniLocalVideo = this.el.querySelector("#mini-local-video video");
    if (miniLocalVideo && callHook.localStream) {
      if (miniLocalVideo.srcObject !== callHook.localStream) {
        miniLocalVideo.srcObject = callHook.localStream;
        miniLocalVideo.muted = true;
        console.log("[MiniCallIndicator] Attached local stream to mini view");
      }
    }

    // Attach remote participant streams
    for (const [userId, tracks] of callHook.pendingTracks || []) {
      const miniParticipant = this.el.querySelector(`#mini-participant-${userId} video`);
      if (miniParticipant) {
        for (const ctx of tracks) {
          if (ctx.track?.kind === "video") {
            let stream = miniParticipant.srcObject;
            if (!stream) {
              stream = new MediaStream();
              miniParticipant.srcObject = stream;
            }
            if (!stream.getVideoTracks().find((t) => t.id === ctx.track.id)) {
              stream.addTrack(ctx.track);
              console.log(`[MiniCallIndicator] Attached video track for ${userId}`);
            }
          }
        }
      }
    }

    // Also check videoElements map for already-attached tracks
    for (const [trackId, info] of callHook.videoElements || []) {
      const miniParticipant = this.el.querySelector(`#mini-participant-${info.peerId} video`);
      if (miniParticipant) {
        // Copy the stream from the main container if available
        const mainParticipant = document.querySelector(`#participant-${info.peerId} video`);
        if (mainParticipant?.srcObject && !miniParticipant.srcObject) {
          // Clone the tracks to the mini view
          const stream = new MediaStream();
          for (const track of mainParticipant.srcObject.getTracks()) {
            stream.addTrack(track);
          }
          miniParticipant.srcObject = stream;
          console.log(`[MiniCallIndicator] Cloned stream for ${info.peerId} to mini view`);
        }
      }
    }
  },
};

export default MiniCallIndicatorHook;

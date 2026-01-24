import Sortable from 'sortablejs';
import * as GaussianSplats3D from '@mkkellogg/gaussian-splats-3d';

let Hooks = {};

// Lobby Preferences Hook - persists lobby mode to localStorage
Hooks.LobbyPreferences = {
    mounted() {
        // Restore saved lobby mode on mount
        const savedMode = localStorage.getItem('lobby_mode');
        if (savedMode && ['media', 'call', 'object3d'].includes(savedMode)) {
            this.pushEvent('restore_lobby_mode', { mode: savedMode });
        }

        // Listen for mode changes to save them
        this.handleEvent('save_lobby_mode', ({ mode }) => {
            localStorage.setItem('lobby_mode', mode);
        });
    }
};

// 3D Gaussian Splat Viewer Hook for coral reef visualization
Hooks.GaussianSplatViewer = {
    mounted() {
        this.viewer = null;
        this.isLoading = false;
        this.loadError = null;

        // Get configuration from data attributes
        this.splatUrl = this.el.dataset.splatUrl;
        this.initialPosition = this.parseVector(this.el.dataset.cameraPosition, [0, -5, 10]);
        this.initialLookAt = this.parseVector(this.el.dataset.cameraLookAt, [0, 0, 0]);
        this.cameraUp = this.parseVector(this.el.dataset.cameraUp, [0, 1, 0]);

        // Initialize viewer when element is ready
        this.initViewer();

        // Handle window resize
        this.handleResize = () => {
            if (this.viewer && this.viewer.renderer) {
                const rect = this.el.getBoundingClientRect();
                this.viewer.renderer.setSize(rect.width, rect.height);
            }
        };
        window.addEventListener('resize', this.handleResize);

        // Handle LiveView events
        this.handleEvent("load_splat", (data) => {
            this.loadSplat(data.url, data.position, data.rotation, data.scale);
        });

        this.handleEvent("reset_camera", () => {
            this.resetCamera();
        });

        this.handleEvent("center_object", () => {
            this.centerObject();
        });
    },

    parseVector(str, defaultVal) {
        if (!str) return defaultVal;
        try {
            const parts = str.split(',').map(s => parseFloat(s.trim()));
            if (parts.length >= 3 && parts.every(n => !isNaN(n))) {
                return parts.slice(0, 3);
            }
        } catch (e) {
            console.warn('[SplatViewer] Error parsing vector:', str);
        }
        return defaultVal;
    },

    async initViewer() {
        if (this.viewer) return;

        const container = this.el;
        const rect = container.getBoundingClientRect();

        if (rect.width === 0 || rect.height === 0) {
            // Container not visible yet, retry
            setTimeout(() => this.initViewer(), 100);
            return;
        }

        try {
            this.viewer = new GaussianSplats3D.Viewer({
                cameraUp: this.cameraUp,
                initialCameraPosition: this.initialPosition,
                initialCameraLookAt: this.initialLookAt,
                rootElement: container,
                selfDrivenMode: true,
                useBuiltInControls: true,
                dynamicScene: true,
                // Rendering options for better quality
                antialiased: true,
                focalAdjustment: 1.0,
                // Disable SharedArrayBuffer which requires CORS headers
                sharedMemoryForWorkers: false,
            });

            console.log('[SplatViewer] Viewer initialized');

            // Fix canvas positioning - make it fill the container
            // Use MutationObserver to catch canvas when it's added
            const fixCanvasPosition = (canvas) => {
                if (canvas) {
                    canvas.style.position = 'absolute';
                    canvas.style.top = '0';
                    canvas.style.left = '0';
                    canvas.style.width = '100%';
                    canvas.style.height = '100%';
                    canvas.style.zIndex = '10';
                }
            };

            const existingCanvas = container.querySelector('canvas');
            fixCanvasPosition(existingCanvas);

            // Watch for canvas being added dynamically
            const observer = new MutationObserver((mutations) => {
                for (const mutation of mutations) {
                    for (const node of mutation.addedNodes) {
                        if (node.tagName === 'CANVAS') {
                            fixCanvasPosition(node);
                        }
                    }
                }
            });
            observer.observe(container, { childList: true });
            this.canvasObserver = observer;

            this.pushEvent("viewer_ready", {});

            // Load initial splat if URL provided
            if (this.splatUrl) {
                this.loadSplat(this.splatUrl);
            }
        } catch (error) {
            console.error('[SplatViewer] Error initializing viewer:', error);
            this.pushEvent("viewer_error", { message: error.message });
        }
    },

    async loadSplat(url, position = [0, 0, 0], rotation = [0, 0, 0, 1], scale = [1, 1, 1]) {
        if (!this.viewer) {
            console.warn('[SplatViewer] Viewer not initialized');
            return;
        }

        if (this.isLoading) {
            console.warn('[SplatViewer] Already loading a splat');
            return;
        }

        this.isLoading = true;
        this.pushEvent("loading_started", { url });

        try {
            // Remove existing splats
            if (this.viewer.getSplatSceneCount && this.viewer.getSplatSceneCount() > 0) {
                // Clear existing scenes
                await this.viewer.removeSplatScenes();
            }

            console.log('[SplatViewer] Loading splat:', url);

            await this.viewer.addSplatScene(url, {
                splatAlphaRemovalThreshold: 5,
                showLoadingUI: true,
                position: position,
                rotation: rotation,
                scale: scale,
                progressiveLoad: true
            });

            this.viewer.start();

            // Hide the loading placeholder once loaded
            const placeholder = this.el.querySelector('.absolute.inset-0');
            if (placeholder) {
                placeholder.style.display = 'none';
            }

            console.log('[SplatViewer] Splat loaded successfully');
            this.pushEvent("loading_complete", { url });

        } catch (error) {
            console.error('[SplatViewer] Error loading splat:', error);
            this.loadError = error.message;
            this.pushEvent("loading_error", { message: error.message, url });
        } finally {
            this.isLoading = false;
        }
    },

    resetCamera() {
        if (this.viewer && this.viewer.camera) {
            this.viewer.camera.position.set(...this.initialPosition);
            this.viewer.camera.lookAt(...this.initialLookAt);
        }
    },

    centerObject() {
        if (this.viewer) {
            // Try to center camera on the scene
            // The orbit controls should auto-center when we reset to look at origin
            if (this.viewer.camera) {
                this.viewer.camera.position.set(0, 0, 5);
                this.viewer.camera.lookAt(0, 0, 0);
            }
            // If the viewer has orbit controls, reset them
            if (this.viewer.controls) {
                this.viewer.controls.target.set(0, 0, 0);
                this.viewer.controls.update();
            }
        }
    },

    destroyed() {
        window.removeEventListener('resize', this.handleResize);

        if (this.canvasObserver) {
            this.canvasObserver.disconnect();
            this.canvasObserver = null;
        }

        if (this.viewer) {
            try {
                this.viewer.dispose();
            } catch (e) {
                console.warn('[SplatViewer] Error disposing viewer:', e);
            }
            this.viewer = null;
        }
    }
};

Hooks.SensorDataAccumulator = {
    mounted() {},
    updated() {},
};

Hooks.SystemMetricsRefresh = {
    mounted() {
        this.interval = setInterval(() => {
            this.pushEvent("refresh", {});
        }, 5000);
    },
    destroyed() {
        if (this.interval) {
            clearInterval(this.interval);
        }
    },
};

Hooks.PulsatingLogo = {
    mounted() {
        this.currentMultiplier = 1.0;
        this.beatInterval = null;

        this.updateFromMetrics();

        this.observer = new MutationObserver(() => {
            this.updateFromMetrics();
        });

        const metricsEl = document.querySelector('[id="system-metrics"]');
        if (metricsEl) {
            this.observer.observe(metricsEl, { childList: true, subtree: true, characterData: true });
        }

        this.refreshInterval = setInterval(() => this.updateFromMetrics(), 2000);
    },

    updateFromMetrics() {
        const metricsEl = document.querySelector('[id="system-metrics"]');
        if (!metricsEl) return;

        const multiplierText = metricsEl.textContent || '';
        const match = multiplierText.match(/x\s*([\d.]+)/);
        if (match) {
            const newMultiplier = parseFloat(match[1]);
            if (!isNaN(newMultiplier) && newMultiplier !== this.currentMultiplier) {
                this.currentMultiplier = newMultiplier;
                this.startPulsating(newMultiplier);
            }
        }
    },

    startPulsating(multiplier) {
        if (this.beatInterval) {
            clearInterval(this.beatInterval);
            this.beatInterval = null;
        }

        // Always pulsate, but at different rates based on load
        // When multiplier <= 1.0, pulsate very slowly (every 10 seconds)
        // When multiplier > 1.0, pulsate faster based on load
        const baseInterval = multiplier <= 1.0 ? 10000 : 2000;
        const msPerBeat = multiplier <= 1.0 ? baseInterval : baseInterval / multiplier;

        this.triggerPulse();

        this.beatInterval = setInterval(() => {
            this.triggerPulse();
        }, msPerBeat);
    },

    triggerPulse() {
        this.el.classList.add('pulsing');
        setTimeout(() => {
            this.el.classList.remove('pulsing');
        }, 200);
    },

    destroyed() {
        if (this.beatInterval) {
            clearInterval(this.beatInterval);
        }
        if (this.refreshInterval) {
            clearInterval(this.refreshInterval);
        }
        if (this.observer) {
            this.observer.disconnect();
        }
    },
};

// YouTube IFrame API loading state
let youtubeAPILoaded = false;
let youtubeAPILoading = false;
const youtubeAPICallbacks = [];

function loadYouTubeAPI() {
    // Check if YT API is already fully loaded (e.g., from previous page or cached)
    if (typeof YT !== 'undefined' && typeof YT.Player === 'function') {
        youtubeAPILoaded = true;
        return Promise.resolve();
    }

    if (youtubeAPILoaded) return Promise.resolve();
    if (youtubeAPILoading) {
        return new Promise((resolve) => youtubeAPICallbacks.push(resolve));
    }

    youtubeAPILoading = true;

    return new Promise((resolve) => {
        youtubeAPICallbacks.push(resolve);

        // Define global callback for YouTube API
        window.onYouTubeIframeAPIReady = () => {
            youtubeAPILoaded = true;
            youtubeAPILoading = false;
            youtubeAPICallbacks.forEach(cb => cb());
            youtubeAPICallbacks.length = 0;
        };

        // Load the YouTube IFrame API script
        const tag = document.createElement('script');
        tag.src = 'https://www.youtube.com/iframe_api';
        const firstScriptTag = document.getElementsByTagName('script')[0];
        firstScriptTag.parentNode.insertBefore(tag, firstScriptTag);
    });
}

Hooks.MediaPlayerHook = {
    // Robust media player synchronization
    // Design principle: User actions are KING during grace period, then server is authoritative
    mounted() {
        this.player = null;
        this.roomId = this.el.dataset.roomId;
        this.currentVideoId = null;
        this.isReady = false;
        this.lastKnownPosition = 0;
        this.lastReportedPosition = 0;

        // Grace period tracking - when set, sync is IGNORED
        this.userActionUntil = 0; // Timestamp until which user has control
        this.USER_ACTION_GRACE_MS = 3000; // 3 seconds of user control after any action

        // Sync-triggered seek cooldown - prevents seek loops when buffering
        this.lastSyncSeekAt = 0;
        this.SYNC_SEEK_COOLDOWN_MS = 5000; // 5 seconds after a sync seek before allowing another

        // Track programmatic vs user-initiated state changes
        this.expectingStateChange = false;

        // Load YouTube API and initialize player
        loadYouTubeAPI().then(() => {
            requestAnimationFrame(() => {
                this.initializePlayer();
            });
        });

        // Handle sync events from server - this is the primary sync mechanism
        this.handleEvent("media_sync", (data) => {
            this.handleSync(data);
        });

        // Handle explicit video load commands
        this.handleEvent("media_load_video", (data) => {
            this.loadVideo(data.video_id, data.start_seconds || 0);
        });

        // Listen for user action events (play/pause clicks) to set grace period
        this.handleEvent("media_user_action", () => {
            this.grantUserControl();
        });

        // Handle seek commands from progress bar
        this.handleEvent("seek_to", (data) => {
            if (this.isReady && this.player) {
                this.grantUserControl();
                this.player.seekTo(data.position, true);
                this.lastKnownPosition = data.position;
                this.lastReportedPosition = data.position;
            }
        });

        // Intercept clicks on play/pause buttons - grant user control BEFORE the event fires
        this.el.addEventListener('click', (e) => {
            const target = e.target.closest('[phx-click="play"], [phx-click="pause"], [phx-click="next"], [phx-click="previous"]');
            if (target) {
                this.grantUserControl();
            }
        }, true); // Use capture phase to run before phx-click

        // Watch for player container being removed (e.g., section collapsed)
        this.setupObserver();
    },

    updated() {
        // Check if video changed via data-current-video-id attribute on the hook element
        // This is the primary mechanism for video switching since push_event may not reach hooks reliably
        const newVideoId = this.el.dataset.currentVideoId;
        if (newVideoId && newVideoId !== this.currentVideoId && this.isReady && this.player) {
            this.loadVideo(newVideoId, 0);
        }

        // NOTE: Do NOT call handleSync from updated() with data attributes!
        // The data-player-state and data-position attributes can be stale when
        // the updated() hook fires. This causes a race condition where clicking
        // pause triggers updated() with the OLD state before the server responds,
        // immediately resuming playback.
        // Sync should ONLY come from the "media_sync" event handler.

        // If player not initialized, try to init (e.g., after collapse toggle)
        if (!this.player && !this.isReady) {
            this.initializePlayer();
        }
    },

    destroyed() {
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
        }
        if (this.observer) {
            this.observer.disconnect();
        }
        if (this.player) {
            try {
                this.player.destroy();
            } catch (e) {
                // Ignore destroy errors
            }
        }
    },

    setupObserver() {
        // Only watch for player element removal (collapsed section)
        this.observer = new MutationObserver(() => {
            const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"])');
            if (!playerEl && this.player) {
                try {
                    this.player.destroy();
                } catch (e) {
                    // Ignore
                }
                this.player = null;
                this.isReady = false;
            } else if (playerEl && !this.player && !this.isReady) {
                // Player element reappeared
                this.initializePlayer();
            }
        });

        this.observer.observe(this.el, {
            childList: true,
            subtree: true
        });
    },

    initializePlayer(retryCount = 0) {
        // Select the actual player div (where YT.Player will be initialized)
        // Use more specific selector to avoid matching wrapper or container
        const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"]):not([id*="container"])');

        if (!playerEl) {
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        // Read video ID from the hook element (this.el) which is updated by LiveView
        // The wrapper element is inside phx-update="ignore" so its data attributes are stale
        const videoId = this.el.dataset.currentVideoId;
        if (!videoId) {
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        this.currentVideoId = videoId;

        // Read state/position from hook element as well
        const autoplay = this.el.dataset.playerState === 'playing';
        const startSeconds = parseInt(this.el.dataset.position) || 0;

        // Track if we need to autoplay - will start muted to comply with Chrome's autoplay policy
        this.pendingAutoplay = autoplay;

        this.player = new YT.Player(playerEl.id, {
            height: '100%',
            width: '100%',
            videoId: videoId,
            playerVars: {
                autoplay: autoplay ? 1 : 0,
                controls: 1,
                rel: 0,
                modestbranding: 1,
                start: startSeconds,
                enablejsapi: 1,
                origin: window.location.origin
            },
            events: {
                onReady: (event) => this.onPlayerReady(event),
                onStateChange: (event) => this.onPlayerStateChange(event),
                onError: (event) => this.onPlayerError(event)
            }
        });
    },

    onPlayerReady(event) {
        this.isReady = true;

        // If we need to autoplay but Chrome blocked it, try muted playback
        if (this.pendingAutoplay) {
            const state = this.player.getPlayerState();
            // -1 = unstarted, meaning autoplay was blocked
            if (state === YT.PlayerState.UNSTARTED || state === YT.PlayerState.CUED) {
                console.log('[MediaPlayer] Autoplay was blocked, trying muted playback');
                this.player.mute();
                this.player.playVideo();
                // Show a notice that video is muted
                this.showMutedNotice();
            }
            this.pendingAutoplay = false;
        }

        // Report duration to server
        const duration = this.player.getDuration();
        if (duration > 0) {
            this.pushEvent("report_duration", { duration: duration });
        }

        // Request current state from server to sync up
        this.pushEventTo(this.el, "request_media_sync", {});

        // Start sync interval - poll server every second for multi-tab sync
        this.startSyncInterval();
    },

    startSyncInterval() {
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
        }
        // Sync interval (500ms) - slower is more reliable, server pushes are the primary sync
        this.syncInterval = setInterval(() => {
            if (!this.isReady || !this.player) return;

            // NEVER sync during user control period
            if (this.isUserInControl()) {
                this.lastKnownPosition = this.player.getCurrentTime() || 0;
                return;
            }

            const currentPosition = this.player.getCurrentTime() || 0;
            const positionDelta = Math.abs(currentPosition - this.lastKnownPosition);
            const timeSinceLastSyncSeek = Date.now() - this.lastSyncSeekAt;

            // Detect if user seeked via YouTube controls (position jumped > 3 seconds)
            // BUT ignore if we recently did a sync seek (that's expected position change)
            if (positionDelta > 3 && timeSinceLastSyncSeek > this.SYNC_SEEK_COOLDOWN_MS) {
                this.grantUserControl();
                this.lastReportedPosition = currentPosition;
                this.pushEventTo(this.el, "client_seek", { position: currentPosition });
            }

            this.lastKnownPosition = currentPosition;

            // Report position for UI updates (every 1 second of change)
            if (Math.abs(currentPosition - this.lastReportedPosition) > 1) {
                this.lastReportedPosition = currentPosition;
                this.pushEventTo(this.el, "position_update", { position: currentPosition });
            }

            // Request sync from server
            this.pushEventTo(this.el, "request_media_sync", {});
        }, 500);
    },

    onPlayerStateChange(event) {
        // Report video ended so server can advance playlist
        if (event.data === YT.PlayerState.ENDED) {
            this.pushEventTo(this.el, "video_ended", {});
            return;
        }

        // Report duration when playing starts
        if (event.data === YT.PlayerState.PLAYING) {
            const duration = this.player.getDuration();
            if (duration > 0) {
                this.pushEventTo(this.el, "report_duration", { duration: duration });
            }
        }

        // If we're expecting this state change (programmatic), just clear the flag
        if (this.expectingStateChange) {
            this.expectingStateChange = false;
            return;
        }

        // This was a USER action (YouTube controls or our buttons already granted control)
        // Forward to server
        if (event.data === YT.PlayerState.PLAYING) {
            this.grantUserControl();
            this.pushEventTo(this.el, "play", {});
        } else if (event.data === YT.PlayerState.PAUSED) {
            this.grantUserControl();
            this.pushEventTo(this.el, "pause", {});
        }
    },

    onPlayerError(event) {
        const errorCodes = {
            2: 'Invalid video ID',
            5: 'HTML5 player error',
            100: 'Video not found',
            101: 'Embedding not allowed',
            150: 'Embedding not allowed'
        };
        console.error('[MediaPlayer] Error:', errorCodes[event.data] || 'Unknown error');
    },

    loadVideo(videoId, startSeconds = 0) {
        this.currentVideoId = videoId;

        if (!this.isReady || !this.player) {
            // Not ready yet - reinitialize
            const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"]):not([id*="container"])');
            if (playerEl && youtubeAPILoaded) {
                if (this.player) {
                    try {
                        this.player.destroy();
                    } catch (e) {
                        // Ignore
                    }
                }
                this.player = null;
                this.isReady = false;
                this.initializePlayer();
            }
            return;
        }

        // Load and autoplay the video
        this.player.loadVideoById({
            videoId: videoId,
            startSeconds: startSeconds
        });
    },

    handleSync(data) {
        if (!this.isReady || !this.player) {
            return;
        }

        // CRITICAL: If user is in control, COMPLETELY IGNORE sync
        // This is the key to reliable playback - user actions are never overridden
        if (this.isUserInControl()) {
            return;
        }

        const serverPosition = data.position_seconds || 0;
        const serverState = data.state;
        const currentPosition = this.player.getCurrentTime() || 0;
        const playerState = this.player.getPlayerState();

        const isPlaying = playerState === YT.PlayerState.PLAYING;
        const isBuffering = playerState === YT.PlayerState.BUFFERING;
        const isUnstarted = playerState === YT.PlayerState.UNSTARTED;
        const isCued = playerState === YT.PlayerState.CUED;
        const shouldPlay = serverState === 'playing';

        // 1. Handle play/pause state synchronization
        if (shouldPlay && !isPlaying && !isBuffering) {
            this.expectingStateChange = true;
            this.player.playVideo();

            // Handle Chrome autoplay blocking
            if ((isUnstarted || isCued) && !this._mutedPlaybackAttempted) {
                this._mutedPlaybackAttempted = true;
                setTimeout(() => {
                    if (!this.player) return;
                    const newState = this.player.getPlayerState();
                    if (newState === YT.PlayerState.UNSTARTED || newState === YT.PlayerState.CUED) {
                        console.log('[MediaPlayer] Autoplay blocked, trying muted playback');
                        this.expectingStateChange = true;
                        this.player.mute();
                        this.player.playVideo();
                        this.showMutedNotice();
                    }
                }, 500);
            }
        } else if (!shouldPlay && isPlaying) {
            this.expectingStateChange = true;
            this.player.pauseVideo();
        }

        // 2. Correct position drift (only when playing and drift > 2 seconds)
        // Larger threshold = less jarring, more tolerant
        const drift = Math.abs(currentPosition - serverPosition);
        const timeSinceLastSyncSeek = Date.now() - this.lastSyncSeekAt;

        // Only seek if:
        // - Playing and drift > 2 seconds
        // - Not currently buffering (would just cause another buffer)
        // - Haven't done a sync seek recently (prevents seek loops)
        if (shouldPlay && drift > 2 && !isBuffering) {
            if (timeSinceLastSyncSeek > this.SYNC_SEEK_COOLDOWN_MS) {
                console.log(`[MediaPlayer] Sync seek: drift=${drift.toFixed(1)}s, server=${serverPosition.toFixed(1)}, client=${currentPosition.toFixed(1)}`);
                this.lastSyncSeekAt = Date.now();
                this.player.seekTo(serverPosition, true);
                this.lastKnownPosition = serverPosition;
                this.lastReportedPosition = serverPosition;
            } else {
                console.log(`[MediaPlayer] Skipping sync seek (cooldown): drift=${drift.toFixed(1)}s, cooldown remaining=${((this.SYNC_SEEK_COOLDOWN_MS - timeSinceLastSyncSeek) / 1000).toFixed(1)}s`);
            }
        }
    },

    // Show a notice that video is muted due to autoplay policy
    showMutedNotice() {
        // Create muted notice overlay
        const notice = document.createElement('div');
        notice.id = 'muted-notice-' + this.roomId;
        notice.className = 'absolute top-2 left-2 right-2 bg-amber-600/90 text-white px-3 py-2 rounded-lg text-sm flex items-center justify-between z-20 cursor-pointer';
        notice.innerHTML = `
            <span class="flex items-center gap-2">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z" />
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2" />
                </svg>
                Click to unmute
            </span>
        `;
        notice.onclick = () => {
            if (this.player && this.player.isMuted()) {
                this.player.unMute();
                notice.remove();
            }
        };

        // Find the player container and add the notice
        const container = this.el.querySelector('.relative.aspect-video');
        if (container) {
            // Remove any existing notice
            const existing = container.querySelector('#muted-notice-' + this.roomId);
            if (existing) existing.remove();
            container.appendChild(notice);
        }

        // Auto-remove notice when user unmutes via YouTube controls
        this._mutedCheckInterval = setInterval(() => {
            if (this.player && !this.player.isMuted()) {
                notice.remove();
                clearInterval(this._mutedCheckInterval);
            }
        }, 500);
    },

    // Grant user control for the grace period - sync will be IGNORED during this time
    grantUserControl() {
        this.userActionUntil = Date.now() + this.USER_ACTION_GRACE_MS;
    },

    // Check if user is currently in control (grace period active)
    isUserInControl() {
        return Date.now() < this.userActionUntil;
    }
};

// SeekBar hook for progress bar seeking
Hooks.SeekBar = {
    mounted() {
        this.duration = parseFloat(this.el.dataset.duration) || 0;
        this.canSeek = this.el.dataset.canSeek === 'true';

        if (this.canSeek && this.duration > 0) {
            this.el.addEventListener('click', (e) => this.handleClick(e));
        }
    },

    updated() {
        this.duration = parseFloat(this.el.dataset.duration) || 0;
        this.canSeek = this.el.dataset.canSeek === 'true';
    },

    handleClick(e) {
        if (!this.canSeek || this.duration <= 0) return;

        const rect = this.el.getBoundingClientRect();
        const clickX = e.clientX - rect.left;
        const percentage = Math.max(0, Math.min(1, clickX / rect.width));
        const seekPosition = percentage * this.duration;

        this.pushEventTo(this.el, "seek_to_position", { position: seekPosition.toFixed(2) });
    }
};

Hooks.BottomNav = {
    mounted() {
        this.updateActiveState();

        window.addEventListener('popstate', () => this.updateActiveState());

        window.addEventListener('phx:page-loading-stop', () => {
            setTimeout(() => this.updateActiveState(), 50);
        });
    },

    updateActiveState() {
        const currentPath = window.location.pathname;
        const navItems = this.el.querySelectorAll('.bottom-nav-item');

        navItems.forEach(item => {
            const itemPath = item.dataset.path;
            const isActive = this.isPathActive(currentPath, itemPath);

            item.classList.remove('text-blue-400', 'text-gray-400');

            if (isActive) {
                item.classList.add('text-blue-400');
            } else {
                item.classList.add('text-gray-400');
            }
        });
    },

    isPathActive(currentPath, itemPath) {
        if (itemPath === '/') {
            return currentPath === '/';
        }
        return currentPath === itemPath || currentPath.startsWith(itemPath + '/');
    },

    destroyed() {
        window.removeEventListener('popstate', () => this.updateActiveState());
        window.removeEventListener('phx:page-loading-stop', () => this.updateActiveState());
    }
};

Hooks.FooterToolbar = {
    mounted() {
        const toggle = this.el.querySelector('#footer-toggle');
        const content = this.el.querySelector('#footer-content-mobile');
        const chevron = this.el.querySelector('.footer-chevron');

        if (toggle && content) {
            toggle.addEventListener('click', () => {
                const isExpanded = toggle.getAttribute('aria-expanded') === 'true';
                toggle.setAttribute('aria-expanded', !isExpanded);
                content.classList.toggle('hidden');
                if (chevron) {
                    chevron.classList.toggle('rotate-180');
                }
            });
        }
    }
};

Hooks.MobileMenu = {
    mounted() {
        const button = this.el.querySelector('#mobile-menu-button');
        const dropdown = this.el.querySelector('#mobile-menu-dropdown');

        if (button && dropdown) {
            this.isOpen = false;
            this.justOpened = false;

            this.handleButtonClick = (e) => {
                e.stopPropagation();
                e.preventDefault();
                this.isOpen = !this.isOpen;
                if (this.isOpen) {
                    dropdown.classList.remove('hidden');
                    this.justOpened = true;
                    setTimeout(() => { this.justOpened = false; }, 100);
                } else {
                    dropdown.classList.add('hidden');
                }
            };

            this.handleDocumentClick = (e) => {
                if (this.justOpened) return;
                if (this.isOpen && !this.el.contains(e.target)) {
                    this.isOpen = false;
                    dropdown.classList.add('hidden');
                }
            };

            button.addEventListener('click', this.handleButtonClick);
            document.addEventListener('click', this.handleDocumentClick);
        }
    },

    destroyed() {
        if (this.handleDocumentClick) {
            document.removeEventListener('click', this.handleDocumentClick);
        }
    }
};

Hooks.UserMenu = {
    mounted() {
        const button = this.el.querySelector('#user-menu-button');
        const dropdown = this.el.querySelector('#user-menu-dropdown');

        if (button && dropdown) {
            this.isOpen = false;
            this.justOpened = false;

            this.handleButtonClick = (e) => {
                e.stopPropagation();
                e.preventDefault();
                this.isOpen = !this.isOpen;
                if (this.isOpen) {
                    dropdown.classList.remove('hidden');
                    // Prevent immediate close on mobile touch devices
                    this.justOpened = true;
                    setTimeout(() => { this.justOpened = false; }, 100);
                } else {
                    dropdown.classList.add('hidden');
                }
            };

            this.handleDocumentClick = (e) => {
                // Skip if we just opened (prevents mobile touch double-fire)
                if (this.justOpened) return;
                if (this.isOpen && !this.el.contains(e.target)) {
                    this.isOpen = false;
                    dropdown.classList.add('hidden');
                }
            };

            // Handle touchend to prevent ghost clicks on mobile
            this.handleTouchEnd = (e) => {
                if (this.isOpen && !this.el.contains(e.target)) {
                    // Small delay to allow link clicks to register
                    setTimeout(() => {
                        if (this.isOpen && !this.el.contains(document.activeElement)) {
                            this.isOpen = false;
                            dropdown.classList.add('hidden');
                        }
                    }, 50);
                }
            };

            button.addEventListener('click', this.handleButtonClick);
            document.addEventListener('click', this.handleDocumentClick);
            document.addEventListener('touchend', this.handleTouchEnd);
        }
    },

    destroyed() {
        if (this.handleDocumentClick) {
            document.removeEventListener('click', this.handleDocumentClick);
        }
        if (this.handleTouchEnd) {
            document.removeEventListener('touchend', this.handleTouchEnd);
        }
    }
};

Hooks.ResizeDetection = {
    mounted() {
        this.handleResize = () => {
            const isMobile = window.innerWidth < 768;
            this.pushEvent('viewport_changed', { is_mobile: isMobile, width: window.innerWidth });
        };

        window.addEventListener('resize', this.handleResize);
        this.handleResize();
    },

    destroyed() {
        window.removeEventListener('resize', this.handleResize);
    }
};

Hooks.GlobalSearch = {
    mounted() {
        this.handleKeyDown = (e) => {
            if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
                e.preventDefault();
                this.pushEvent('open', {});
            }
        };

        this.handleOpenSearch = () => {
            this.pushEvent('open', {});
        };

        document.addEventListener('keydown', this.handleKeyDown);
        document.addEventListener('open-search', this.handleOpenSearch);
    },

    destroyed() {
        document.removeEventListener('keydown', this.handleKeyDown);
        document.removeEventListener('open-search', this.handleOpenSearch);
    }
};

Hooks.SearchPaletteInput = {
    mounted() {
        this.handleEvent('focus-search-input', () => {
            setTimeout(() => this.el.focus(), 50);
        });

        setTimeout(() => this.el.focus(), 100);
    }
};

Hooks.SortablePlaylist = {
    mounted() {
        this.isDragging = false;
        this.pendingReinit = false;
        this.initSortable();
    },

    updated() {
        // Don't destroy/recreate Sortable during an active drag - it will cancel the drag
        if (this.isDragging) {
            this.pendingReinit = true;
            return;
        }
        // Only reinit if items actually changed (check item count)
        const currentItems = this.el.querySelectorAll('[data-item-id]').length;
        if (this.lastItemCount !== currentItems) {
            this.lastItemCount = currentItems;
            if (this.sortable) {
                this.sortable.destroy();
            }
            this.initSortable();
        }
    },

    destroyed() {
        if (this.sortable) {
            this.sortable.destroy();
        }
    },

    initSortable() {
        this.lastItemCount = this.el.querySelectorAll('[data-item-id]').length;
        try {
            this.sortable = new Sortable(this.el, {
                animation: 150,
                handle: '.drag-handle',
                ghostClass: 'opacity-50',
                chosenClass: 'bg-gray-600',
                dragClass: 'shadow-lg',
                forceFallback: true,
                fallbackClass: 'sortable-fallback',
                fallbackOnBody: true,
                onStart: () => {
                    this.isDragging = true;
                },
                onEnd: () => {
                    this.isDragging = false;
                    const itemIds = Array.from(this.el.querySelectorAll('[data-item-id]'))
                        .map(el => el.dataset.itemId);
                    // Use pushEventTo to target the component, not the parent LiveView
                    this.pushEventTo(this.el, 'reorder_playlist', { item_ids: itemIds });

                    // Handle any pending reinit after drag completes
                    if (this.pendingReinit) {
                        this.pendingReinit = false;
                        setTimeout(() => {
                            if (this.sortable) {
                                this.sortable.destroy();
                            }
                            this.initSortable();
                        }, 100);
                    }
                }
            });
            this.el._sortableInstance = this.sortable;
        } catch (e) {
            console.error('[SortablePlaylist] Error initializing Sortable:', e);
        }
    }
};

// Object3D Player Hook - Synchronized 3D Gaussian Splat viewer with playlist support
Hooks.Object3DPlayerHook = {
    async mounted() {
        this.viewer = null;
        this.isLoading = false;
        this.loadError = null;
        this.roomId = this.el.dataset.roomId;
        this.isController = false;
        this.controllerId = null;
        this.canControl = true; // Initially true since no controller is set
        this.currentUserId = this.el.dataset.currentUserId;
        this.lastCameraSyncTime = 0;
        this.cameraSyncThrottle = 200; // Sync camera every 200ms max
        this.gracePeriod = 500; // Ignore incoming syncs for 500ms after user action
        this.lastUserActionTime = 0;
        this.currentItemId = null;
        this.viewerReady = false;

        // Camera state
        this.cameraPosition = { x: 0, y: 0, z: 5 };
        this.cameraTarget = { x: 0, y: 0, z: 0 };

        // Handle window resize
        this.handleResize = () => {
            if (this.viewer && this.viewer.renderer) {
                const rect = this.el.getBoundingClientRect();
                this.viewer.renderer.setSize(rect.width, rect.height);
            }
        };
        window.addEventListener('resize', this.handleResize);

        // Handle sync events from server
        this.handleEvent("object3d_sync", (data) => {
            this.handleSync(data);
        });

        this.handleEvent("object3d_load", (data) => {
            this.loadSplat(data.url, data.camera_position, data.camera_target);
        });

        this.handleEvent("object3d_camera_sync", (data) => {
            this.handleCameraSync(data);
        });

        this.handleEvent("object3d_reset_camera", () => {
            this.resetCamera();
        });

        this.handleEvent("object3d_center_object", () => {
            this.centerObject();
        });

        this.handleEvent("object3d_controller_changed", (data) => {
            this.controllerId = data.controller_user_id;
            this.isController = this.controllerId === this.currentUserId;
            this.canControl = this.isController || !this.controllerId;
            console.log('[Object3DPlayer] Controller changed:', this.controllerId, 'isController:', this.isController, 'canControl:', this.canControl);
        });

        // Initialize viewer first, then request sync
        // This ensures the viewer is ready before we try to load content
        await this.initViewer();

        // Request initial state from server now that viewer is ready
        console.log('[Object3DPlayer] Requesting initial sync from server');
        this.pushEventTo(this.el, "request_object3d_sync", {});

        // Start camera sync interval for controller
        this.startCameraSyncInterval();
    },

    parseVector(str, defaultVal) {
        if (!str) return defaultVal;
        try {
            const parts = str.split(',').map(s => parseFloat(s.trim()));
            if (parts.length >= 3 && parts.every(n => !isNaN(n))) {
                return { x: parts[0], y: parts[1], z: parts[2] };
            }
        } catch (e) {
            console.warn('[Object3DPlayer] Error parsing vector:', str);
        }
        return defaultVal;
    },

    async initViewer() {
        if (this.viewer) return;

        const container = this.el.querySelector('[data-object3d-viewer]') || this.el;
        const rect = container.getBoundingClientRect();

        if (rect.width === 0 || rect.height === 0) {
            // Wait for container to have dimensions
            await new Promise(resolve => setTimeout(resolve, 100));
            return this.initViewer();
        }

        try {
            const initialPosition = [this.cameraPosition.x, this.cameraPosition.y, this.cameraPosition.z];
            const initialLookAt = [this.cameraTarget.x, this.cameraTarget.y, this.cameraTarget.z];

            // Store container reference for later
            this.viewerContainer = container;

            this.viewer = new GaussianSplats3D.Viewer({
                cameraUp: [0, -1, 0],
                initialCameraPosition: initialPosition,
                initialCameraLookAt: initialLookAt,
                rootElement: container,
                selfDrivenMode: true,
                useBuiltInControls: true,
                dynamicScene: true,
                antialiased: true,
                focalAdjustment: 1.0,
                sharedMemoryForWorkers: false,
            });

            console.log('[Object3DPlayer] Viewer initialized');

            // Configure controls (may not be available until viewer starts)
            this.configureControls();

            // Setup canvas events when canvas is added
            const existingCanvas = container.querySelector('canvas');
            if (existingCanvas) {
                this.setupCanvasEvents(existingCanvas);
            }

            const observer = new MutationObserver((mutations) => {
                for (const mutation of mutations) {
                    for (const node of mutation.addedNodes) {
                        if (node.tagName === 'CANVAS') {
                            this.setupCanvasEvents(node);
                            // Also try to configure controls when canvas appears
                            setTimeout(() => this.configureControls(), 100);
                        }
                    }
                }
            });
            observer.observe(container, { childList: true });
            this.canvasObserver = observer;

            this.viewerReady = true;
            this.pushEventTo(this.el, "viewer_ready", {});

            // NOTE: Do NOT load from data-splat-url here
            // Let handleSync handle all loading to avoid race conditions
        } catch (error) {
            console.error('[Object3DPlayer] Error initializing viewer:', error);
            this.pushEventTo(this.el, "viewer_error", { message: error.message });
        }
    },

    async loadSplat(url, cameraPosition, cameraTarget) {
        console.log('[Object3DPlayer] loadSplat called with:', { url, cameraPosition, cameraTarget });

        if (this.isLoading) {
            console.warn('[Object3DPlayer] Already loading a splat, queueing...');
            this.pendingLoad = { url, cameraPosition, cameraTarget };
            return;
        }

        // Wait for viewer to be ready
        if (!this.viewerReady || !this.viewer) {
            console.log('[Object3DPlayer] Viewer not ready, waiting...');
            await new Promise(resolve => setTimeout(resolve, 200));
            if (!this.viewerReady || !this.viewer) {
                console.warn('[Object3DPlayer] Viewer still not ready, reinitializing...');
                await this.initViewer();
            }
        }

        this.isLoading = true;
        this._fadeInFixed = false; // Reset for new load
        this.pushEventTo(this.el, "loading_started", { url });

        const container = this.viewerContainer || this.el.querySelector('[data-object3d-viewer]') || this.el;

        // Update camera position/target if provided
        if (cameraPosition) {
            this.cameraPosition = cameraPosition;
        }
        if (cameraTarget) {
            this.cameraTarget = cameraTarget;
        }

        try {
            // ALWAYS dispose and recreate the viewer when loading a new model
            // This is the most reliable way to clear previous scenes - removeSplatScenes()
            // has proven unreliable and can leave ghost models
            if (this.viewer) {
                console.log('[Object3DPlayer] Disposing viewer before loading new model');
                try {
                    this.viewer.dispose();
                } catch (e) {
                    console.warn('[Object3DPlayer] Error disposing viewer:', e);
                }
                this.viewer = null;
                this.viewerReady = false;
            }
            await this.initViewer();

            console.log('[Object3DPlayer] Calling addSplatScene with URL:', url);

            // Use a timeout to catch hanging promises
            const loadPromise = this.viewer.addSplatScene(url, {
                splatAlphaRemovalThreshold: 5,
                showLoadingUI: true,
                position: [0, 0, 0],
                rotation: [0, 0, 0, 1],
                scale: [1, 1, 1],
                progressiveLoad: true
            });

            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error('addSplatScene timed out after 30s')), 30000);
            });

            await Promise.race([loadPromise, timeoutPromise]);
            console.log('[Object3DPlayer] addSplatScene completed');

        } catch (error) {
            console.error('[Object3DPlayer] Error in addSplatScene:', error);
            this.loadError = error.message;
            this.pushEventTo(this.el, "loading_error", { message: error.message, url });
            this.isLoading = false;
            return;
        }

        // Post-loading setup (separated from try/catch to ensure it runs)
        try {
            console.log('[Object3DPlayer] Starting post-load setup');

            // Start the viewer
            this.viewer.start();
            console.log('[Object3DPlayer] viewer.start() called');

            // Wait a bit for the viewer to fully initialize
            await new Promise(resolve => setTimeout(resolve, 300));

            // WORKAROUND: GaussianSplats3D sometimes doesn't properly add splatMesh to scene
            if (this.viewer.splatMesh && this.viewer.threeScene) {
                if (!this.viewer.splatMesh.parent) {
                    console.log('[Object3DPlayer] Adding splatMesh to scene (workaround)');
                    this.viewer.threeScene.add(this.viewer.splatMesh);
                }
                this.viewer.splatMesh.visible = true;

                // Force material update and fix fadeInComplete uniform
                if (this.viewer.splatMesh.material) {
                    this.viewer.splatMesh.material.needsUpdate = true;

                    // WORKAROUND: fadeInComplete uniform stays at 0, making splats invisible
                    if (this.viewer.splatMesh.material.uniforms?.fadeInComplete) {
                        console.log('[Object3DPlayer] Setting fadeInComplete to 1 (workaround)');
                        this.viewer.splatMesh.material.uniforms.fadeInComplete.value = 1;
                    }
                }
            }

            // WORKAROUND: Ensure render loop is actually running
            this.startRenderLoop();

            // Update camera position after loading
            if (this.viewer.camera) {
                this.viewer.camera.position.set(
                    this.cameraPosition.x,
                    this.cameraPosition.y,
                    this.cameraPosition.z
                );
                this.viewer.camera.lookAt(
                    this.cameraTarget.x,
                    this.cameraTarget.y,
                    this.cameraTarget.z
                );
            }

            // Configure controls AFTER splat has loaded
            await new Promise(resolve => setTimeout(resolve, 100));
            this.configureControls();

            // Setup canvas events
            const loadedCanvas = container.querySelector('canvas');
            if (loadedCanvas) {
                this.setupCanvasEvents(loadedCanvas);
            }

            console.log('[Object3DPlayer] Splat loaded successfully');
            this.pushEventTo(this.el, "loading_complete", { url });

        } catch (error) {
            console.error('[Object3DPlayer] Error in post-load setup:', error);
        }

        // Always reset loading state
        this.isLoading = false;

        // Process any pending load
        if (this.pendingLoad) {
            const pending = this.pendingLoad;
            this.pendingLoad = null;
            console.log('[Object3DPlayer] Processing pending load');
            setTimeout(() => {
                this.loadSplat(pending.url, pending.cameraPosition, pending.cameraTarget);
            }, 100);
        }
    },

    startRenderLoop() {
        if (this._renderLoopRunning) {
            console.log('[Object3DPlayer] Render loop already running');
            return;
        }

        this._renderLoopRunning = true;
        this._renderFrameCount = 0;
        this._fadeInFixed = false;

        const renderLoop = () => {
            if (!this._renderLoopRunning || !this.viewer) {
                console.log('[Object3DPlayer] Render loop stopped');
                return;
            }

            try {
                // WORKAROUND: Keep checking fadeInComplete until it's fixed
                // The splatMesh material might not be ready immediately after addSplatScene
                if (!this._fadeInFixed && this.viewer.splatMesh?.material?.uniforms?.fadeInComplete) {
                    const fadeUniform = this.viewer.splatMesh.material.uniforms.fadeInComplete;
                    if (fadeUniform.value < 1) {
                        fadeUniform.value = 1;
                        this.viewer.splatMesh.material.needsUpdate = true;
                        console.log('[Object3DPlayer] Fixed fadeInComplete in render loop');
                    }
                    this._fadeInFixed = true;
                }

                if (this.viewer.update) {
                    this.viewer.update();
                }
                if (this.viewer.render) {
                    this.viewer.render();
                }

                this._renderFrameCount++;
                if (this._renderFrameCount === 1 || this._renderFrameCount === 10) {
                    console.log('[Object3DPlayer] Render frame:', this._renderFrameCount);
                }
            } catch (e) {
                console.error('[Object3DPlayer] Error in render loop:', e);
            }

            this._renderFrameId = requestAnimationFrame(renderLoop);
        };

        renderLoop();
        console.log('[Object3DPlayer] Started manual render loop');
    },

    handleSync(data) {
        // Update controller status
        this.controllerId = data.controller_user_id;
        // User can control if they're the controller OR if no controller is set (anyone can control)
        this.isController = this.controllerId === this.currentUserId;
        this.canControl = this.isController || !this.controllerId;
        console.log('[Object3DPlayer] Sync received:', {
            controllerId: this.controllerId,
            currentUserId: this.currentUserId,
            isController: this.isController,
            canControl: this.canControl,
            hasCurrentItem: !!data.current_item,
            currentItemId: data.current_item?.id,
            thisCurrentItemId: this.currentItemId,
            splatUrl: data.current_item?.splat_url
        });

        // Update current item
        if (data.current_item && data.current_item.id !== this.currentItemId) {
            console.log('[Object3DPlayer] New item detected, loading splat');
            this.currentItemId = data.current_item.id;
            if (data.current_item.splat_url) {
                this.loadSplat(
                    data.current_item.splat_url,
                    data.camera_position,
                    data.camera_target
                );
            } else {
                console.warn('[Object3DPlayer] No splat_url in current_item');
            }
        } else if (!data.current_item) {
            console.log('[Object3DPlayer] No current_item in sync data');
        } else {
            console.log('[Object3DPlayer] Same item, skipping load');
        }
    },

    handleCameraSync(data) {
        // Ignore if we're the controller (we're sending, not receiving)
        if (this.isController) return;

        // If no controller is set, don't apply any sync - allow free movement
        if (!this.controllerId) return;

        // Ignore if in grace period (user just interacted)
        const now = Date.now();
        if (now - this.lastUserActionTime < this.gracePeriod) return;

        // Apply camera position from controller
        if (this.viewer && this.viewer.camera && data.camera_position && data.camera_target) {
            this.cameraPosition = data.camera_position;
            this.cameraTarget = data.camera_target;

            this.viewer.camera.position.set(
                data.camera_position.x,
                data.camera_position.y,
                data.camera_position.z
            );
            this.viewer.camera.lookAt(
                data.camera_target.x,
                data.camera_target.y,
                data.camera_target.z
            );

            // Also update orbit controls if present
            const controls = this.viewer.perspectiveControls || this.viewer.orthographicControls;
            if (controls) {
                controls.target.set(
                    data.camera_target.x,
                    data.camera_target.y,
                    data.camera_target.z
                );
                controls.update();
            }
        }
    },

    startCameraSyncInterval() {
        this.cameraSyncInterval = setInterval(() => {
            // Only sync if we can control (controller or no controller set)
            if (!this.canControl || !this.viewer || !this.viewer.camera) return;

            const now = Date.now();
            if (now - this.lastCameraSyncTime < this.cameraSyncThrottle) return;

            const pos = this.viewer.camera.position;
            const controls = this.viewer.perspectiveControls ||
                            this.viewer.orthographicControls ||
                            this.viewer.controls ||
                            this.viewer.orbitControls;
            const target = controls ? controls.target : { x: 0, y: 0, z: 0 };

            // Check if camera actually moved
            const posDelta = Math.abs(pos.x - this.cameraPosition.x) +
                            Math.abs(pos.y - this.cameraPosition.y) +
                            Math.abs(pos.z - this.cameraPosition.z);

            if (posDelta > 0.01) {
                this.cameraPosition = { x: pos.x, y: pos.y, z: pos.z };
                this.cameraTarget = { x: target.x, y: target.y, z: target.z };

                this.pushEventTo(this.el, "camera_moved", {
                    position: this.cameraPosition,
                    target: this.cameraTarget
                });

                this.lastCameraSyncTime = now;
            }
        }, 100);
    },

    configureControls() {
        if (!this.viewer) return;

        // Try multiple control property names that GaussianSplats3D might use
        const controls = this.viewer.perspectiveControls ||
                         this.viewer.orthographicControls ||
                         this.viewer.controls ||
                         this.viewer.orbitControls;

        if (controls) {
            controls.minPolarAngle = 0;
            controls.maxPolarAngle = Math.PI;
            controls.enableRotate = true;
            controls.enableZoom = true;
            controls.enablePan = true;
            controls.enabled = true;

            // Safari fix: Ensure the controls are listening to the correct DOM element
            // Sometimes OrbitControls don't properly attach in Safari
            if (controls.domElement) {
                // Ensure the dom element is the canvas
                const canvas = this.viewerContainer ? this.viewerContainer.querySelector('canvas') : null;
                if (canvas && controls.domElement !== canvas) {
                    console.log('[Object3DPlayer] Reconnecting controls to canvas');
                    // Re-enable event listeners by calling dispose and then enabling
                    if (typeof controls.connect === 'function') {
                        controls.connect();
                    }
                }
            }

            // Force update
            if (typeof controls.update === 'function') {
                controls.update();
            }

            console.log('[Object3DPlayer] Controls configured successfully:', {
                enabled: controls.enabled,
                enableRotate: controls.enableRotate,
                enableZoom: controls.enableZoom,
                enablePan: controls.enablePan,
                domElement: controls.domElement ? controls.domElement.tagName : 'none'
            });
        } else {
            console.warn('[Object3DPlayer] No controls found on viewer. Available properties:',
                Object.keys(this.viewer).filter(k => k.toLowerCase().includes('control')));

            // Retry after a short delay - controls might be created asynchronously
            if (!this._controlRetryCount) this._controlRetryCount = 0;
            if (this._controlRetryCount < 5) {
                this._controlRetryCount++;
                setTimeout(() => this.configureControls(), 200);
            }
        }
    },

    setupCanvasEvents(canvas) {
        if (!canvas) return;

        // Critical styles for event handling across all browsers including Safari
        canvas.style.position = 'absolute';
        canvas.style.top = '0';
        canvas.style.left = '0';
        canvas.style.width = '100%';
        canvas.style.height = '100%';
        canvas.style.zIndex = '50';
        canvas.style.pointerEvents = 'auto';
        canvas.style.touchAction = 'none';
        canvas.style.userSelect = 'none';
        canvas.style.webkitUserSelect = 'none';
        canvas.tabIndex = 0;

        // Prevent default touch behavior on the canvas for Safari
        canvas.addEventListener('touchstart', (e) => {
            this.markUserAction();
        }, { passive: true });

        canvas.addEventListener('touchmove', (e) => {
            e.preventDefault();
        }, { passive: false });

        canvas.addEventListener('gesturestart', (e) => {
            e.preventDefault();
        }, { passive: false });

        canvas.addEventListener('gesturechange', (e) => {
            e.preventDefault();
        }, { passive: false });

        // Mouse events
        canvas.addEventListener('mousedown', () => this.markUserAction());
        canvas.addEventListener('wheel', () => this.markUserAction(), { passive: true });

        // Pointer events (modern browsers)
        canvas.addEventListener('pointerdown', () => this.markUserAction());

        console.log('[Object3DPlayer] Canvas events configured');
    },

    markUserAction() {
        this.lastUserActionTime = Date.now();
    },

    resetCamera() {
        this.markUserAction();
        if (this.viewer && this.viewer.camera) {
            this.viewer.camera.position.set(0, 0, 5);
            this.viewer.camera.lookAt(0, 0, 0);
            if (this.viewer.controls) {
                this.viewer.controls.target.set(0, 0, 0);
                this.viewer.controls.update();
            }
            this.cameraPosition = { x: 0, y: 0, z: 5 };
            this.cameraTarget = { x: 0, y: 0, z: 0 };
        }
    },

    centerObject() {
        this.markUserAction();
        if (!this.viewer || !this.viewer.camera) return;

        try {
            // Try to get the splat mesh bounding box for proper centering
            let center = { x: 0, y: 0, z: 0 };
            let distance = 5;

            // Check if the viewer has scene data we can use
            if (this.viewer.splatMesh && this.viewer.splatMesh.geometry) {
                const geometry = this.viewer.splatMesh.geometry;
                geometry.computeBoundingBox();
                const box = geometry.boundingBox;

                if (box) {
                    center = {
                        x: (box.min.x + box.max.x) / 2,
                        y: (box.min.y + box.max.y) / 2,
                        z: (box.min.z + box.max.z) / 2
                    };

                    // Calculate appropriate viewing distance based on object size
                    const size = Math.max(
                        box.max.x - box.min.x,
                        box.max.y - box.min.y,
                        box.max.z - box.min.z
                    );
                    distance = size * 1.5;
                }
            }

            // Position camera to look at center from a good viewing angle
            const cameraPos = {
                x: center.x,
                y: center.y + distance * 0.3,
                z: center.z + distance
            };

            this.viewer.camera.position.set(cameraPos.x, cameraPos.y, cameraPos.z);
            this.viewer.camera.lookAt(center.x, center.y, center.z);

            if (this.viewer.controls) {
                this.viewer.controls.target.set(center.x, center.y, center.z);
                this.viewer.controls.update();
            }

            this.cameraPosition = cameraPos;
            this.cameraTarget = center;

            console.log('[Object3DPlayer] Centered on object at:', center, 'distance:', distance);
        } catch (error) {
            console.warn('[Object3DPlayer] Error centering object, using default position:', error);
            this.resetCamera();
        }
    },

    destroyed() {
        window.removeEventListener('resize', this.handleResize);

        // Stop manual render loop
        this._renderLoopRunning = false;
        if (this._renderFrameId) {
            cancelAnimationFrame(this._renderFrameId);
            this._renderFrameId = null;
        }

        if (this.cameraSyncInterval) {
            clearInterval(this.cameraSyncInterval);
        }

        if (this.canvasObserver) {
            this.canvasObserver.disconnect();
            this.canvasObserver = null;
        }

        if (this.viewer) {
            try {
                this.viewer.dispose();
            } catch (e) {
                console.warn('[Object3DPlayer] Error disposing viewer:', e);
            }
            this.viewer = null;
        }

        this.viewerReady = false;
    }
};

// DraggableBallsHook - Presence-tracked draggable balls for sign-in page
Hooks.DraggableBallsHook = {
    mounted() {
        this.balls = new Map();
        this.ownBallId = null;
        this.isDragging = false;
        this.lastUpdateTime = 0;
        this.userActionUntil = 0;
        this.THROTTLE_MS = 50;
        this.GRACE_PERIOD_MS = 500;

        // Get or create session ID for anonymous users
        let sessionId = localStorage.getItem('sensocto_ball_session');
        if (!sessionId) {
            sessionId = 'sess_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            localStorage.setItem('sensocto_ball_session', sessionId);
        }

        // Join with session ID
        this.pushEvent('ball_join', { session_id: sessionId });

        // Handle full sync from server
        this.handleEvent('ball_sync', ({ balls, own_id }) => {
            this.ownBallId = own_id;
            this.balls = new Map(Object.entries(balls));
            this.render();
        });

        // Handle updates from server
        this.handleEvent('ball_update', ({ balls }) => {
            const now = Date.now();
            Object.entries(balls).forEach(([id, ball]) => {
                // Skip own ball updates during grace period to prevent rubber-banding
                if (id === this.ownBallId && now < this.userActionUntil) {
                    return;
                }
                this.balls.set(id, ball);
            });
            this.render();
        });

        // Handle vibration broadcast from any dragging ball
        this.handleEvent('vibrate', () => {
            if (navigator.vibrate) {
                navigator.vibrate(50);
            }
        });

        // Global mouse/touch handlers for drag
        this.onMouseMove = this.handleDragMove.bind(this);
        this.onMouseUp = this.handleDragEnd.bind(this);
        this.onTouchMove = this.handleTouchMove.bind(this);
        this.onTouchEnd = this.handleDragEnd.bind(this);

        document.addEventListener('mousemove', this.onMouseMove);
        document.addEventListener('mouseup', this.onMouseUp);
        document.addEventListener('touchmove', this.onTouchMove, { passive: false });
        document.addEventListener('touchend', this.onTouchEnd);
    },

    destroyed() {
        document.removeEventListener('mousemove', this.onMouseMove);
        document.removeEventListener('mouseup', this.onMouseUp);
        document.removeEventListener('touchmove', this.onTouchMove);
        document.removeEventListener('touchend', this.onTouchEnd);
    },

    render() {
        // Clear existing balls
        this.el.innerHTML = '';

        this.balls.forEach((ball, id) => {
            const div = document.createElement('div');
            div.className = 'absolute rounded-full cursor-grab active:cursor-grabbing';
            div.style.width = '32px';
            div.style.height = '32px';
            div.style.backgroundColor = ball.color;
            div.style.left = `calc(${ball.x}% - 16px)`;
            div.style.top = `calc(${ball.y}% - 16px)`;
            div.style.pointerEvents = 'auto';
            div.style.boxShadow = '0 4px 12px rgba(0,0,0,0.4)';
            div.style.transition = 'box-shadow 0.2s ease, opacity 0.2s ease';
            div.style.opacity = '0.7';

            // Highlight own ball with white border, glow, and hand icon
            if (id === this.ownBallId) {
                div.style.border = '2px solid white';
                div.style.boxShadow = '0 0 15px rgba(255,255,255,0.4), 0 4px 12px rgba(0,0,0,0.4)';
                div.style.zIndex = '10';
                div.style.display = 'flex';
                div.style.alignItems = 'center';
                div.style.justifyContent = 'center';
                div.style.fontSize = '16px';
                div.style.fontWeight = 'bold';
                div.style.color = 'white';
                div.style.textShadow = '0 1px 2px rgba(0,0,0,0.8)';
                div.innerHTML = '✋';
                div.title = 'Drag me!';

                // Add drag handlers to own ball only
                div.addEventListener('mousedown', (e) => this.handleDragStart(e));
                div.addEventListener('touchstart', (e) => this.handleTouchStart(e), { passive: false });
            }

            this.el.appendChild(div);
        });
    },

    handleDragStart(e) {
        e.preventDefault();
        this.isDragging = true;
        this.userActionUntil = Date.now() + this.GRACE_PERIOD_MS;
        // Broadcast drag start to all tabs for synchronized vibration
        this.pushEvent('ball_drag_start', {});
    },

    handleTouchStart(e) {
        e.preventDefault();
        this.isDragging = true;
        this.userActionUntil = Date.now() + this.GRACE_PERIOD_MS;
        // Broadcast drag start to all tabs for synchronized vibration
        this.pushEvent('ball_drag_start', {});
    },

    handleDragMove(e) {
        if (!this.isDragging) return;
        this.updatePosition(e.clientX, e.clientY);
    },

    handleTouchMove(e) {
        if (!this.isDragging) return;
        e.preventDefault();
        const touch = e.touches[0];
        this.updatePosition(touch.clientX, touch.clientY);
    },

    updatePosition(clientX, clientY) {
        const now = Date.now();

        // Throttle updates to server
        if (now - this.lastUpdateTime < this.THROTTLE_MS) return;
        this.lastUpdateTime = now;

        // Extend grace period during active drag
        this.userActionUntil = now + this.GRACE_PERIOD_MS;

        // Calculate percentage position relative to viewport
        const x = Math.max(2, Math.min(98, (clientX / window.innerWidth) * 100));
        const y = Math.max(2, Math.min(98, (clientY / window.innerHeight) * 100));

        // Update local state immediately for responsiveness
        if (this.ownBallId && this.balls.has(this.ownBallId)) {
            const ball = this.balls.get(this.ownBallId);
            ball.x = x;
            ball.y = y;
            this.render();
        }

        // Send position to server
        this.pushEvent('ball_move', { x: x, y: y });
    },

    handleDragEnd() {
        this.isDragging = false;
    }
};

// GuestCredentials hook - Store and restore guest credentials in localStorage
Hooks.GuestCredentials = {
    mounted() {
        // Listen for store-guest-credentials event from LiveView
        this.handleEvent('store-guest-credentials', ({ guest_id, token }) => {
            console.log('[GuestCredentials] Storing guest credentials in localStorage');
            localStorage.setItem('guest_id', guest_id);
            localStorage.setItem('guest_token', token);
            localStorage.setItem('guest_stored_at', Date.now().toString());
        });

        // On mount, check if we have stored guest credentials
        const guestId = localStorage.getItem('guest_id');
        const guestToken = localStorage.getItem('guest_token');
        const storedAt = localStorage.getItem('guest_stored_at');

        if (guestId && guestToken && storedAt) {
            // Check if credentials are not too old (7 days)
            const age = Date.now() - parseInt(storedAt);
            const maxAge = 7 * 24 * 60 * 60 * 1000; // 7 days in milliseconds

            if (age < maxAge) {
                console.log('[GuestCredentials] Found stored guest credentials, pushing to LiveView');
                this.pushEvent('restore_guest_credentials', {
                    guest_id: guestId,
                    guest_token: guestToken
                });
            } else {
                console.log('[GuestCredentials] Guest credentials expired, clearing');
                this.clearStoredCredentials();
            }
        }
    },

    clearStoredCredentials() {
        localStorage.removeItem('guest_id');
        localStorage.removeItem('guest_token');
        localStorage.removeItem('guest_stored_at');
    }
};

export default Hooks;
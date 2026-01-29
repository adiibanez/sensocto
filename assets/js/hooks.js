import Sortable from 'sortablejs';
import * as GaussianSplats3D from '@mkkellogg/gaussian-splats-3d';
import WhiteboardHook from './hooks/whiteboard_hook';
import ClientHealthHook from './hooks/client_health_hook';

let Hooks = {};

// Whiteboard Hook
Hooks.WhiteboardHook = WhiteboardHook;

// Client Health Hook - monitors client performance and reports to server
Hooks.ClientHealthHook = ClientHealthHook;

// Lobby Preferences Hook - persists lobby mode and min_attention to localStorage
Hooks.LobbyPreferences = {
    mounted() {
        // Restore saved lobby mode on mount
        const savedMode = localStorage.getItem('lobby_mode');
        if (savedMode && ['media', 'call', 'object3d'].includes(savedMode)) {
            this.pushEvent('restore_lobby_mode', { mode: savedMode });
        }

        // Restore saved min_attention on mount
        const savedMinAttention = localStorage.getItem('lobby_min_attention');
        if (savedMinAttention !== null) {
            const minAttention = parseInt(savedMinAttention, 10);
            if (!isNaN(minAttention) && minAttention >= 0 && minAttention <= 3) {
                this.pushEvent('restore_min_attention', { min_attention: minAttention });
            }
        }

        // Listen for mode changes to save them
        this.handleEvent('save_lobby_mode', ({ mode }) => {
            localStorage.setItem('lobby_mode', mode);
        });

        // Listen for min_attention changes to save them
        this.handleEvent('save_min_attention', ({ min_attention }) => {
            localStorage.setItem('lobby_min_attention', min_attention.toString());
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

// ============================================================================
// MediaPlayerHook - State Machine Based YouTube Player Sync
// ============================================================================
//
// States:
//   INIT        - Waiting for YouTube API and player element
//   LOADING     - YouTube player is loading
//   READY       - Player ready, waiting for sync
//   SYNCING     - Executing a sync command (play/pause/seek)
//   PLAYING     - Video is playing, following server
//   PAUSED      - Video is paused, following server
//   USER_CONTROL- User interacted, ignoring server for grace period
//   BLOCKED     - Autoplay blocked, showing overlay
//   ERROR       - Player error state
//
// Transitions are explicit and logged for debugging.
// ============================================================================

Hooks.MediaPlayerHook = {
    // === CONFIGURATION ===
    CONFIG: {
        USER_GRACE_MS: 1500,        // How long user keeps control after action (was 3000)
        SYNC_COOLDOWN_MS: 250,      // Min time between sync operations (was 500)
        SEEK_DRIFT_THRESHOLD: 1,    // Seconds of drift before seeking (was 3)
        POSITION_REPORT_INTERVAL: 0.5, // Report position every N seconds of change (was 1)
        POLL_INTERVAL_MS: 250,      // How often to poll player state (was 500)
        AUTOPLAY_RETRY_MS: 5000,    // How long to wait before retrying autoplay
        MAX_INIT_RETRIES: 5,        // Max retries for player initialization
    },

    // === STATE MACHINE ===
    STATES: {
        INIT: 'INIT',
        LOADING: 'LOADING',
        READY: 'READY',
        SYNCING: 'SYNCING',
        PLAYING: 'PLAYING',
        PAUSED: 'PAUSED',
        USER_CONTROL: 'USER_CONTROL',
        BLOCKED: 'BLOCKED',
        ERROR: 'ERROR',
    },

    mounted() {
        this.roomId = this.el.dataset.roomId;
        this.player = null;
        this.currentVideoId = null;

        // State machine
        this.state = this.STATES.INIT;
        this.previousState = null;

        // Timers and tracking
        this.userControlUntil = 0;
        this.lastSyncAt = 0;
        this.lastAutoplayAttemptAt = 0;
        this.lastPosition = 0;
        this.lastReportedPosition = 0;
        this.pollInterval = null;

        // Initialize
        this.log('Mounted, starting initialization');
        this.setupEventHandlers();
        this.loadYouTubeAndInit();
    },

    // === STATE TRANSITIONS ===

    transition(newState, reason = '') {
        if (this.state === newState) return;

        this.previousState = this.state;
        this.state = newState;
        this.log(`${this.previousState} → ${newState}${reason ? ` (${reason})` : ''}`);

        // Handle state entry actions
        this.onStateEnter(newState);
    },

    onStateEnter(state) {
        switch (state) {
            case this.STATES.BLOCKED:
                this.showClickToPlayOverlay();
                break;
            case this.STATES.PLAYING:
            case this.STATES.PAUSED:
            case this.STATES.USER_CONTROL:
                this.hideClickToPlayOverlay();
                break;
            case this.STATES.ERROR:
                this.hideClickToPlayOverlay();
                break;
        }
    },

    // === EVENT HANDLERS SETUP ===

    setupEventHandlers() {
        // Server sync events
        this.handleEvent("media_sync", (data) => this.onServerSync(data));
        this.handleEvent("media_load_video", (data) => this.loadVideo(data.video_id, data.start_seconds || 0));
        this.handleEvent("seek_to", (data) => this.onSeekCommand(data.position));
        this.handleEvent("media_user_action", () => this.enterUserControl('server event'));

        // Intercept UI clicks before they fire
        this.el.addEventListener('click', (e) => {
            const target = e.target.closest('[phx-click="play"], [phx-click="pause"], [phx-click="next"], [phx-click="previous"]');
            if (target) this.enterUserControl('UI click');
        }, true);

        // Watch for player element changes
        this.setupObserver();
    },

    // === INITIALIZATION ===

    loadYouTubeAndInit() {
        loadYouTubeAPI().then(() => {
            requestAnimationFrame(() => this.initializePlayer());
        });
    },

    initializePlayer(retryCount = 0) {
        const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"]):not([id*="container"])');
        const videoId = this.el.dataset.currentVideoId;

        if (!playerEl || !videoId) {
            if (retryCount < this.CONFIG.MAX_INIT_RETRIES) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        this.transition(this.STATES.LOADING, 'creating player');
        this.currentVideoId = videoId;

        const autoplay = this.el.dataset.playerState === 'playing';
        const startSeconds = parseInt(this.el.dataset.position) || 0;

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
                onReady: () => this.onPlayerReady(autoplay),
                onStateChange: (e) => this.onYouTubeStateChange(e),
                onError: (e) => this.onPlayerError(e)
            }
        });

        // Expose for debugging
        window.__mediaPlayer = this.player;
        window.__mediaHook = this;
    },

    // === PLAYER EVENTS ===

    onPlayerReady(wantAutoplay) {
        this.log('Player ready');

        // Test event push to verify connectivity
        console.log(`[MediaPlayer:${this.roomId}] Testing pushEventTo - el.id=${this.el.id}`);
        this.pushEventTo(this.el, "test_hook_connection", { test: "from_hook" });
        console.log(`[MediaPlayer:${this.roomId}] pushEventTo called`);

        // Sync initial position if needed
        const serverPos = parseFloat(this.el.dataset.position) || 0;
        const playerPos = this.player.getCurrentTime() || 0;

        if (Math.abs(serverPos - playerPos) > this.CONFIG.SEEK_DRIFT_THRESHOLD) {
            this.log(`Initial seek: ${playerPos.toFixed(1)} → ${serverPos.toFixed(1)}`);
            this.player.seekTo(serverPos, true);
        }

        this.lastPosition = serverPos;
        this.lastReportedPosition = serverPos;

        // Report duration
        const duration = this.player.getDuration();
        if (duration > 0) {
            this.pushEvent("report_duration", { duration });
        }

        // Check autoplay status
        const ytState = this.player.getPlayerState();
        if (wantAutoplay && (ytState === YT.PlayerState.UNSTARTED || ytState === YT.PlayerState.CUED)) {
            this.log('Autoplay blocked, trying muted');
            this.player.mute();
            this.player.playVideo();
            this.showMutedNotice();
        }

        // Determine initial state
        this.transition(this.STATES.READY, 'player ready');

        // Start polling
        this.startPolling();

        // Request sync from server
        this.pushEventTo(this.el, "request_media_sync", {});
    },

    onYouTubeStateChange(event) {
        const ytState = event.data;
        const stateName = this.ytStateToName(ytState);

        console.log(`[MediaPlayer:${this.roomId}] YT state change: ${stateName} (current state: ${this.state})`);

        // Handle video ended
        if (ytState === YT.PlayerState.ENDED) {
            this.log('Video ended');
            this.pushEventTo(this.el, "video_ended", {});
            return;
        }

        // If we're in SYNCING state, we expected this change
        if (this.state === this.STATES.SYNCING) {
            this.log(`Sync complete: ${stateName}`);
            if (ytState === YT.PlayerState.PLAYING) {
                this.transition(this.STATES.PLAYING, 'sync complete');
            } else if (ytState === YT.PlayerState.PAUSED) {
                this.transition(this.STATES.PAUSED, 'sync complete');
            }
            // Report duration when playing starts
            if (ytState === YT.PlayerState.PLAYING) {
                const duration = this.player.getDuration();
                if (duration > 0) {
                    this.pushEventTo(this.el, "report_duration", { duration });
                }
            }
            return;
        }

        // If we're in USER_CONTROL, forward to server
        if (this.state === this.STATES.USER_CONTROL) {
            console.log(`[MediaPlayer:${this.roomId}] In USER_CONTROL, forwarding ${stateName} to server`);
            if (ytState === YT.PlayerState.PLAYING) {
                console.log(`[MediaPlayer:${this.roomId}] >>> PUSHING PLAY EVENT <<<`);
                this.pushEventTo(this.el, "play", {});
                const duration = this.player.getDuration();
                if (duration > 0) {
                    this.pushEventTo(this.el, "report_duration", { duration });
                }
            } else if (ytState === YT.PlayerState.PAUSED) {
                console.log(`[MediaPlayer:${this.roomId}] >>> PUSHING PAUSE EVENT <<<`);
                this.pushEventTo(this.el, "pause", {});
            }
            return;
        }

        // Unexpected state change - user interaction via YouTube controls
        if (ytState === YT.PlayerState.PLAYING || ytState === YT.PlayerState.PAUSED) {
            console.log(`[MediaPlayer:${this.roomId}] Unexpected ${stateName}, entering USER_CONTROL`);
            this.enterUserControl('YouTube controls');
            if (ytState === YT.PlayerState.PLAYING) {
                console.log(`[MediaPlayer:${this.roomId}] Pushing play event to server`);
                this.pushEventTo(this.el, "play", {});
            } else {
                console.log(`[MediaPlayer:${this.roomId}] Pushing pause event to server`);
                this.pushEventTo(this.el, "pause", {});
            }
        }
    },

    onPlayerError(event) {
        const errors = { 2: 'Invalid ID', 5: 'HTML5 error', 100: 'Not found', 101: 'Embed blocked', 150: 'Embed blocked' };
        this.log(`Error: ${errors[event.data] || 'Unknown'}`);
        this.transition(this.STATES.ERROR, errors[event.data]);
    },

    // === SERVER SYNC ===

    onServerSync(data) {
        const serverState = data.state;
        const serverPosition = data.position_seconds || 0;
        const now = Date.now();

        console.log(`[MediaPlayer:${this.roomId}] onServerSync: server=${serverState}, hook=${this.state}, userControlUntil=${this.userControlUntil}, now=${now}`);

        // Ignore if not ready
        if (!this.player || this.state === this.STATES.INIT || this.state === this.STATES.LOADING) {
            console.log(`[MediaPlayer:${this.roomId}] Ignoring sync - not ready`);
            return;
        }

        // Ignore if user is in control
        if (this.state === this.STATES.USER_CONTROL && now < this.userControlUntil) {
            console.log(`[MediaPlayer:${this.roomId}] Ignoring sync - user in control (${this.userControlUntil - now}ms remaining)`);
            return;
        } else if (this.state === this.STATES.USER_CONTROL && now >= this.userControlUntil) {
            // Grace period expired, exit user control
            this.log('User control grace period expired');
        }

        // Ignore if in BLOCKED state (waiting for user click)
        if (this.state === this.STATES.BLOCKED) {
            return;
        }

        // Rate limit syncs
        if (now - this.lastSyncAt < this.CONFIG.SYNC_COOLDOWN_MS) {
            return;
        }
        this.lastSyncAt = now;

        const ytState = this.player.getPlayerState();
        const currentPos = this.player.getCurrentTime() || 0;
        const shouldPlay = serverState === 'playing';
        const isPlaying = ytState === YT.PlayerState.PLAYING;
        const isBuffering = ytState === YT.PlayerState.BUFFERING;
        const isBlocked = ytState === YT.PlayerState.UNSTARTED || ytState === YT.PlayerState.CUED;

        // Handle autoplay blocked
        if (shouldPlay && isBlocked) {
            if (now - this.lastAutoplayAttemptAt > this.CONFIG.AUTOPLAY_RETRY_MS) {
                this.lastAutoplayAttemptAt = now;
                this.log('Attempting autoplay');
                this.transition(this.STATES.SYNCING, 'autoplay attempt');
                this.player.playVideo();

                // Check if it worked after a short delay
                setTimeout(() => {
                    if (!this.player) return;
                    const newState = this.player.getPlayerState();
                    if (newState === YT.PlayerState.UNSTARTED || newState === YT.PlayerState.CUED) {
                        this.log('Autoplay still blocked');
                        this.transition(this.STATES.BLOCKED, 'autoplay blocked');
                    }
                }, 1000);
            }
            return;
        }

        // Handle play/pause sync
        if (shouldPlay && !isPlaying && !isBuffering) {
            this.log('Server says play');
            this.transition(this.STATES.SYNCING, 'play');
            this.player.playVideo();
        } else if (!shouldPlay && isPlaying) {
            this.log('Server says pause');
            this.transition(this.STATES.SYNCING, 'pause');
            this.player.pauseVideo();
        } else {
            // State matches, update our tracking
            if (isPlaying && this.state !== this.STATES.PLAYING) {
                this.transition(this.STATES.PLAYING, 'state match');
            } else if (!isPlaying && !isBuffering && this.state !== this.STATES.PAUSED) {
                this.transition(this.STATES.PAUSED, 'state match');
            }
        }

        // Handle position drift (only when playing)
        if (shouldPlay && isPlaying) {
            const drift = Math.abs(currentPos - serverPosition);
            if (drift > this.CONFIG.SEEK_DRIFT_THRESHOLD) {
                this.log(`Position drift: ${drift.toFixed(1)}s, seeking`);
                this.transition(this.STATES.SYNCING, 'seek');
                this.player.seekTo(serverPosition, true);
                this.lastPosition = serverPosition;
            }
        }
    },

    // === USER CONTROL ===

    enterUserControl(reason) {
        this.userControlUntil = Date.now() + this.CONFIG.USER_GRACE_MS;
        console.log(`[MediaPlayer:${this.roomId}] enterUserControl: grace until ${this.userControlUntil}, reason: ${reason}`);
        this.transition(this.STATES.USER_CONTROL, reason);
    },

    onSeekCommand(position) {
        if (!this.player) return;
        this.enterUserControl('seek command');
        this.player.seekTo(position, true);
        this.lastPosition = position;
        this.lastReportedPosition = position;
    },

    // === POLLING ===

    startPolling() {
        if (this.pollInterval) clearInterval(this.pollInterval);

        this.pollInterval = setInterval(() => {
            if (!this.player) return;

            try {
                const currentPos = this.player.getCurrentTime() || 0;
                const now = Date.now();

                // Check if user control expired
                if (this.state === this.STATES.USER_CONTROL && now >= this.userControlUntil) {
                    this.pushEventTo(this.el, "request_media_sync", {});
                }

                // Detect user seek via YouTube controls
                const posDelta = Math.abs(currentPos - this.lastPosition);
                if (posDelta > this.CONFIG.SEEK_DRIFT_THRESHOLD && this.state !== this.STATES.SYNCING) {
                    this.enterUserControl('detected seek');
                    this.pushEventTo(this.el, "client_seek", { position: currentPos });
                }

                this.lastPosition = currentPos;

                // Report position updates
                if (Math.abs(currentPos - this.lastReportedPosition) > this.CONFIG.POSITION_REPORT_INTERVAL) {
                    this.lastReportedPosition = currentPos;
                    this.pushEventTo(this.el, "position_update", { position: currentPos });
                }

                // Check for stuck BLOCKED state recovery
                if (this.state === this.STATES.BLOCKED) {
                    const ytState = this.player.getPlayerState();
                    if (ytState === YT.PlayerState.PLAYING || ytState === YT.PlayerState.PAUSED) {
                        this.transition(ytState === YT.PlayerState.PLAYING ? this.STATES.PLAYING : this.STATES.PAUSED, 'recovered');
                    }
                }
            } catch (e) {
                // Player might have been destroyed
            }
        }, this.CONFIG.POLL_INTERVAL_MS);
    },

    // === UI OVERLAYS ===

    showClickToPlayOverlay() {
        if (this.el.querySelector('#click-to-play-overlay-' + this.roomId)) return;

        const overlay = document.createElement('div');
        overlay.id = 'click-to-play-overlay-' + this.roomId;
        overlay.className = 'absolute inset-0 bg-black/70 flex flex-col items-center justify-center z-20 cursor-pointer';
        overlay.innerHTML = `
            <svg class="w-16 h-16 text-white mb-2" fill="currentColor" viewBox="0 0 24 24">
                <path d="M8 5v14l11-7z"/>
            </svg>
            <span class="text-white text-lg font-medium">Click to Play</span>
            <span class="text-gray-300 text-sm mt-1">Autoplay was blocked by your browser</span>
        `;
        overlay.onclick = () => {
            this.enterUserControl('overlay click');
            this.player.playVideo();
            overlay.remove();
        };

        const container = this.el.querySelector('.relative.aspect-video');
        if (container) container.appendChild(overlay);
    },

    hideClickToPlayOverlay() {
        const overlay = this.el.querySelector('#click-to-play-overlay-' + this.roomId);
        if (overlay) overlay.remove();
    },

    showMutedNotice() {
        if (this.el.querySelector('#muted-notice-' + this.roomId)) return;

        const notice = document.createElement('div');
        notice.id = 'muted-notice-' + this.roomId;
        notice.className = 'absolute top-2 left-2 right-2 bg-amber-600/90 text-white px-3 py-2 rounded-lg text-sm flex items-center justify-between z-20 cursor-pointer';
        notice.innerHTML = `
            <span class="flex items-center gap-2">
                <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5.586 15H4a1 1 0 01-1-1v-4a1 1 0 011-1h1.586l4.707-4.707C10.923 3.663 12 4.109 12 5v14c0 .891-1.077 1.337-1.707.707L5.586 15z"/>
                    <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M17 14l2-2m0 0l2-2m-2 2l-2-2m2 2l2 2"/>
                </svg>
                Video is muted - click to unmute
            </span>
        `;
        notice.onclick = () => {
            if (this.player) {
                this.player.unMute();
                notice.remove();
            }
        };

        const container = this.el.querySelector('.relative.aspect-video');
        if (container) container.appendChild(notice);

        // Auto-hide after 10 seconds
        setTimeout(() => notice.remove(), 10000);
    },

    // === VIDEO LOADING ===

    loadVideo(videoId, startSeconds = 0) {
        this.log(`Loading video: ${videoId}`);
        this.currentVideoId = videoId;
        this.lastAutoplayAttemptAt = 0;

        if (!this.player) {
            this.initializePlayer();
            return;
        }

        this.transition(this.STATES.LOADING, 'new video');
        this.player.loadVideoById({ videoId, startSeconds });
    },

    // === UTILITIES ===

    log(msg) {
        console.log(`[MediaPlayer:${this.roomId}] [${this.state}] ${msg}`);
    },

    ytStateToName(state) {
        const names = { [-1]: 'UNSTARTED', 0: 'ENDED', 1: 'PLAYING', 2: 'PAUSED', 3: 'BUFFERING', 5: 'CUED' };
        return names[state] || 'UNKNOWN';
    },

    setupObserver() {
        this.observer = new MutationObserver(() => {
            const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"])');
            if (!playerEl && this.player) {
                try { this.player.destroy(); } catch (e) {}
                this.player = null;
                this.transition(this.STATES.INIT, 'player removed');
            } else if (playerEl && !this.player && this.state === this.STATES.INIT) {
                this.initializePlayer();
            }
        });
        this.observer.observe(this.el, { childList: true, subtree: true });
    },

    // === LIFECYCLE ===

    updated() {
        const newVideoId = this.el.dataset.currentVideoId;
        if (newVideoId && newVideoId !== this.currentVideoId && this.player) {
            this.loadVideo(newVideoId, 0);
        }
        if (!this.player && this.state === this.STATES.INIT) {
            this.initializePlayer();
        }
    },

    destroyed() {
        this.log('Destroyed');
        if (this.pollInterval) clearInterval(this.pollInterval);
        if (this.observer) this.observer.disconnect();
        if (this.player) {
            try { this.player.destroy(); } catch (e) {}
        }
    },
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

// Object3DPlayerHook - State Machine Based 3D Gaussian Splat Viewer Sync
// ============================================================================
//
// States:
//   INIT        - Waiting for container and viewer element
//   LOADING     - 3D viewer is loading a splat
//   READY       - Viewer ready, waiting for content or sync
//   SYNCED      - Following controller's camera movements
//   USER_CONTROL- User interacted, ignoring server sync for grace period
//   ERROR       - Viewer error state
//
// Transitions are explicit and logged for debugging.
// ============================================================================

Hooks.Object3DPlayerHook = {
    // === CONFIGURATION ===
    CONFIG: {
        USER_GRACE_MS: 500,         // How long user keeps control after action
        CAMERA_SYNC_THROTTLE_MS: 200, // Min time between camera sync sends
        CAMERA_SYNC_POLL_MS: 100,   // How often to poll camera position
        CAMERA_MOVE_THRESHOLD: 0.01, // Min camera movement to trigger sync
        LOAD_TIMEOUT_MS: 30000,     // Max time to wait for splat load
        INIT_RETRY_MS: 100,         // Retry interval for container init
        MAX_INIT_RETRIES: 50,       // Max retries for container init
    },

    // === STATE MACHINE ===
    STATES: {
        INIT: 'INIT',
        LOADING: 'LOADING',
        READY: 'READY',
        SYNCED: 'SYNCED',
        USER_CONTROL: 'USER_CONTROL',
        ERROR: 'ERROR',
    },

    mounted() {
        this.roomId = this.el.dataset.roomId;
        this.currentUserId = this.el.dataset.currentUserId;
        this.viewer = null;
        this.viewerContainer = null;

        // State machine
        this.state = this.STATES.INIT;
        this.previousState = null;

        // Controller tracking
        this.controllerId = null;

        // Content tracking
        this.currentItemId = null;
        this.currentSplatUrl = null;

        // Camera state
        this.cameraPosition = { x: 0, y: 0, z: 5 };
        this.cameraTarget = { x: 0, y: 0, z: 0 };

        // Timers and tracking
        this.userControlUntil = 0;
        this.lastCameraSyncTime = 0;
        this.cameraPollInterval = null;
        this.initRetryCount = 0;

        // Initialize
        this.log('Mounted, starting initialization');
        this.setupEventHandlers();
        this.initializeViewer();
    },

    // === LOGGING ===
    log(msg, data = null) {
        const prefix = `[Object3D:${this.roomId}]`;
        if (data) {
            console.log(`${prefix} ${msg}`, data);
        } else {
            console.log(`${prefix} ${msg}`);
        }
    },

    // === STATE TRANSITIONS ===
    transition(newState, reason = '') {
        if (this.state === newState) return;

        this.previousState = this.state;
        this.state = newState;
        this.log(`${this.previousState} → ${newState}${reason ? ` (${reason})` : ''}`);

        // Handle state entry actions
        this.onStateEnter(newState);
    },

    onStateEnter(state) {
        switch (state) {
            case this.STATES.READY:
                // Request initial sync from server
                this.pushEventTo(this.el, "request_object3d_sync", {});
                break;
            case this.STATES.SYNCED:
                // Start camera polling when synced
                this.startCameraPoll();
                break;
            case this.STATES.USER_CONTROL:
                // Keep polling in user control mode
                this.startCameraPoll();
                break;
            case this.STATES.ERROR:
                this.stopCameraPoll();
                break;
        }
    },

    // === EVENT HANDLERS SETUP ===
    setupEventHandlers() {
        // Server sync events
        this.handleEvent("object3d_sync", (data) => this.onServerSync(data));
        this.handleEvent("object3d_load", (data) => this.onLoadCommand(data));
        this.handleEvent("object3d_camera_sync", (data) => this.onCameraSync(data));
        this.handleEvent("object3d_reset_camera", () => this.resetCamera());
        this.handleEvent("object3d_center_object", () => this.centerObject());
        this.handleEvent("object3d_controller_changed", (data) => this.onControllerChanged(data));

        // Handle window resize
        this.handleResize = () => {
            if (this.viewer && this.viewer.renderer) {
                const container = this.viewerContainer || this.el;
                const rect = container.getBoundingClientRect();
                this.viewer.renderer.setSize(rect.width, rect.height);
            }
        };
        window.addEventListener('resize', this.handleResize);
    },

    // === INITIALIZATION ===
    initializeViewer() {
        const container = this.el.querySelector('[data-object3d-viewer]') || this.el;
        const rect = container.getBoundingClientRect();

        if (rect.width === 0 || rect.height === 0) {
            // Container not ready yet
            this.initRetryCount++;
            if (this.initRetryCount < this.CONFIG.MAX_INIT_RETRIES) {
                setTimeout(() => this.initializeViewer(), this.CONFIG.INIT_RETRY_MS);
            } else {
                this.transition(this.STATES.ERROR, 'container never became visible');
            }
            return;
        }

        this.viewerContainer = container;

        try {
            this.createViewer();
            this.transition(this.STATES.READY, 'viewer initialized');
        } catch (error) {
            this.log('Error initializing viewer:', error);
            this.transition(this.STATES.ERROR, error.message);
            this.pushEventTo(this.el, "viewer_error", { message: error.message });
        }
    },

    createViewer() {
        const initialPosition = [this.cameraPosition.x, this.cameraPosition.y, this.cameraPosition.z];
        const initialLookAt = [this.cameraTarget.x, this.cameraTarget.y, this.cameraTarget.z];

        this.viewer = new GaussianSplats3D.Viewer({
            cameraUp: [0, -1, 0],
            initialCameraPosition: initialPosition,
            initialCameraLookAt: initialLookAt,
            rootElement: this.viewerContainer,
            selfDrivenMode: true,
            useBuiltInControls: true,
            dynamicScene: true,
            antialiased: true,
            focalAdjustment: 1.0,
            sharedMemoryForWorkers: false,
        });

        this.log('Viewer created');

        // Setup canvas when it appears
        this.setupCanvasObserver();
        this.pushEventTo(this.el, "viewer_ready", {});
    },

    setupCanvasObserver() {
        const existingCanvas = this.viewerContainer.querySelector('canvas');
        if (existingCanvas) {
            this.setupCanvas(existingCanvas);
        }

        this.canvasObserver = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) {
                    if (node.tagName === 'CANVAS') {
                        this.setupCanvas(node);
                    }
                }
            }
        });
        this.canvasObserver.observe(this.viewerContainer, { childList: true });
    },

    setupCanvas(canvas) {
        // Style for proper event handling
        canvas.style.position = 'absolute';
        canvas.style.top = '0';
        canvas.style.left = '0';
        canvas.style.width = '100%';
        canvas.style.height = '100%';
        canvas.style.zIndex = '50';
        canvas.style.pointerEvents = 'auto';
        canvas.style.touchAction = 'none';
        canvas.tabIndex = 0;

        // User interaction events
        canvas.addEventListener('mousedown', () => this.markUserAction());
        canvas.addEventListener('wheel', () => this.markUserAction(), { passive: true });
        canvas.addEventListener('touchstart', () => this.markUserAction(), { passive: true });
        canvas.addEventListener('pointerdown', () => this.markUserAction());

        // Prevent default touch behavior
        canvas.addEventListener('touchmove', (e) => e.preventDefault(), { passive: false });

        this.log('Canvas configured');
        this.configureControls();
    },

    configureControls() {
        if (!this.viewer) return;

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
            if (typeof controls.update === 'function') {
                controls.update();
            }
            this.log('Controls configured');
        }
    },

    // === SERVER EVENT HANDLERS ===
    onServerSync(data) {
        this.log('Server sync received', {
            itemId: data.current_item?.id,
            controllerId: data.controller_user_id,
            currentState: this.state
        });

        // Update controller
        this.controllerId = data.controller_user_id;

        // Ignore if in user control grace period
        if (this.state === this.STATES.USER_CONTROL && Date.now() < this.userControlUntil) {
            this.log('Ignoring sync - user in control');
            return;
        }

        // Check if we need to load a new item
        if (data.current_item && data.current_item.id !== this.currentItemId) {
            this.currentItemId = data.current_item.id;
            if (data.current_item.splat_url) {
                this.loadSplat(data.current_item.splat_url, data.camera_position, data.camera_target);
            }
        } else if (data.current_item && this.state === this.STATES.READY) {
            // Same item but we're ready - transition to synced
            this.transition(this.STATES.SYNCED, 'sync received');
        }
    },

    onLoadCommand(data) {
        this.log('Load command received', data);
        this.loadSplat(data.url, data.camera_position, data.camera_target);
    },

    onCameraSync(data) {
        // Ignore if we're the controller
        if (this.isController()) {
            return;
        }

        // Ignore if no controller set (free movement mode)
        if (!this.controllerId) {
            return;
        }

        // Ignore if in user control grace period
        if (this.state === this.STATES.USER_CONTROL && Date.now() < this.userControlUntil) {
            return;
        }

        // Apply camera position from controller
        this.applyCameraPosition(data.camera_position, data.camera_target);
    },

    onControllerChanged(data) {
        const wasController = this.isController();
        this.controllerId = data.controller_user_id;
        const isNowController = this.isController();

        this.log('Controller changed', {
            controllerId: this.controllerId,
            isController: isNowController
        });

        // If we became controller, transition to synced (we'll be sending)
        if (!wasController && isNowController && this.state !== this.STATES.LOADING) {
            this.transition(this.STATES.SYNCED, 'became controller');
        }
    },

    // === LOADING ===
    async loadSplat(url, cameraPosition, cameraTarget) {
        if (this.state === this.STATES.LOADING) {
            this.log('Already loading, queueing new load');
            this.pendingLoad = { url, cameraPosition, cameraTarget };
            return;
        }

        this.transition(this.STATES.LOADING, 'loading splat');
        this.currentSplatUrl = url;
        this.pushEventTo(this.el, "loading_started", { url });

        // Update camera targets
        if (cameraPosition) this.cameraPosition = cameraPosition;
        if (cameraTarget) this.cameraTarget = cameraTarget;

        try {
            // Dispose old viewer and create fresh one
            await this.recreateViewer();

            // Load the splat with timeout
            const loadPromise = this.viewer.addSplatScene(url, {
                splatAlphaRemovalThreshold: 5,
                showLoadingUI: true,
                position: [0, 0, 0],
                rotation: [0, 0, 0, 1],
                scale: [1, 1, 1],
                progressiveLoad: true
            });

            const timeoutPromise = new Promise((_, reject) => {
                setTimeout(() => reject(new Error('Load timeout')), this.CONFIG.LOAD_TIMEOUT_MS);
            });

            await Promise.race([loadPromise, timeoutPromise]);

            // Start viewer and apply workarounds
            this.viewer.start();
            await this.applyPostLoadWorkarounds();

            // Set camera position
            this.applyCameraPosition(this.cameraPosition, this.cameraTarget);

            this.log('Splat loaded successfully');
            this.pushEventTo(this.el, "loading_complete", { url });
            this.transition(this.STATES.SYNCED, 'load complete');

            // Process any pending load
            if (this.pendingLoad) {
                const pending = this.pendingLoad;
                this.pendingLoad = null;
                setTimeout(() => this.loadSplat(pending.url, pending.cameraPosition, pending.cameraTarget), 100);
            }

        } catch (error) {
            this.log('Error loading splat:', error);
            this.pushEventTo(this.el, "loading_error", { message: error.message, url });
            this.transition(this.STATES.ERROR, error.message);
        }
    },

    async recreateViewer() {
        // Dispose existing viewer
        if (this.viewer) {
            try {
                this.viewer.dispose();
            } catch (e) {
                this.log('Error disposing viewer:', e);
            }
            this.viewer = null;
        }

        // Create fresh viewer
        this.createViewer();
        await new Promise(resolve => setTimeout(resolve, 100));
    },

    async applyPostLoadWorkarounds() {
        // Wait for viewer to stabilize
        await new Promise(resolve => setTimeout(resolve, 300));

        // Workaround: Ensure splatMesh is in scene
        if (this.viewer.splatMesh && this.viewer.threeScene) {
            if (!this.viewer.splatMesh.parent) {
                this.viewer.threeScene.add(this.viewer.splatMesh);
            }
            this.viewer.splatMesh.visible = true;

            // Workaround: Fix fadeInComplete uniform
            if (this.viewer.splatMesh.material?.uniforms?.fadeInComplete) {
                this.viewer.splatMesh.material.uniforms.fadeInComplete.value = 1;
                this.viewer.splatMesh.material.needsUpdate = true;
            }
        }

        this.configureControls();
    },

    // === CAMERA ===
    applyCameraPosition(position, target) {
        if (!this.viewer || !this.viewer.camera) return;

        if (position) {
            this.cameraPosition = position;
            this.viewer.camera.position.set(position.x, position.y, position.z);
        }

        if (target) {
            this.cameraTarget = target;
            this.viewer.camera.lookAt(target.x, target.y, target.z);

            // Update orbit controls target
            const controls = this.getControls();
            if (controls) {
                controls.target.set(target.x, target.y, target.z);
                controls.update();
            }
        }
    },

    getControls() {
        if (!this.viewer) return null;
        return this.viewer.perspectiveControls ||
               this.viewer.orthographicControls ||
               this.viewer.controls ||
               this.viewer.orbitControls;
    },

    startCameraPoll() {
        if (this.cameraPollInterval) return;

        this.cameraPollInterval = setInterval(() => {
            this.pollCameraAndSync();
        }, this.CONFIG.CAMERA_SYNC_POLL_MS);
    },

    stopCameraPoll() {
        if (this.cameraPollInterval) {
            clearInterval(this.cameraPollInterval);
            this.cameraPollInterval = null;
        }
    },

    pollCameraAndSync() {
        if (!this.viewer || !this.viewer.camera) return;

        // Only send camera updates if we can control
        if (!this.canControl()) return;

        const now = Date.now();
        if (now - this.lastCameraSyncTime < this.CONFIG.CAMERA_SYNC_THROTTLE_MS) return;

        const pos = this.viewer.camera.position;
        const controls = this.getControls();
        const target = controls ? controls.target : { x: 0, y: 0, z: 0 };

        // Check if camera moved
        const posDelta = Math.abs(pos.x - this.cameraPosition.x) +
                        Math.abs(pos.y - this.cameraPosition.y) +
                        Math.abs(pos.z - this.cameraPosition.z);

        if (posDelta > this.CONFIG.CAMERA_MOVE_THRESHOLD) {
            this.cameraPosition = { x: pos.x, y: pos.y, z: pos.z };
            this.cameraTarget = { x: target.x, y: target.y, z: target.z };

            this.pushEventTo(this.el, "camera_moved", {
                position: this.cameraPosition,
                target: this.cameraTarget
            });

            this.lastCameraSyncTime = now;
        }
    },

    resetCamera() {
        this.markUserAction();
        this.applyCameraPosition({ x: 0, y: 0, z: 5 }, { x: 0, y: 0, z: 0 });
    },

    centerObject() {
        this.markUserAction();

        if (!this.viewer?.splatMesh?.geometry) {
            this.resetCamera();
            return;
        }

        try {
            const geometry = this.viewer.splatMesh.geometry;
            geometry.computeBoundingBox();
            const box = geometry.boundingBox;

            if (box) {
                const center = {
                    x: (box.min.x + box.max.x) / 2,
                    y: (box.min.y + box.max.y) / 2,
                    z: (box.min.z + box.max.z) / 2
                };

                const size = Math.max(
                    box.max.x - box.min.x,
                    box.max.y - box.min.y,
                    box.max.z - box.min.z
                );
                const distance = size * 1.5;

                const cameraPos = {
                    x: center.x,
                    y: center.y + distance * 0.3,
                    z: center.z + distance
                };

                this.applyCameraPosition(cameraPos, center);
                this.log('Centered on object');
            }
        } catch (error) {
            this.log('Error centering, using default:', error);
            this.resetCamera();
        }
    },

    // === USER CONTROL ===
    markUserAction() {
        const wasInUserControl = this.state === this.STATES.USER_CONTROL;
        this.userControlUntil = Date.now() + this.CONFIG.USER_GRACE_MS;

        if (!wasInUserControl && this.state !== this.STATES.LOADING && this.state !== this.STATES.INIT) {
            this.transition(this.STATES.USER_CONTROL, 'user interaction');
        }

        // Schedule return to synced state
        setTimeout(() => {
            if (this.state === this.STATES.USER_CONTROL && Date.now() >= this.userControlUntil) {
                this.transition(this.STATES.SYNCED, 'grace period ended');
            }
        }, this.CONFIG.USER_GRACE_MS + 50);
    },

    // === HELPERS ===
    isController() {
        return this.controllerId && this.controllerId === this.currentUserId;
    },

    canControl() {
        // User can control if they're the controller OR if no controller is set
        return this.isController() || !this.controllerId;
    },

    // === CLEANUP ===
    destroyed() {
        window.removeEventListener('resize', this.handleResize);
        this.stopCameraPoll();

        if (this.canvasObserver) {
            this.canvasObserver.disconnect();
            this.canvasObserver = null;
        }

        if (this.viewer) {
            try {
                this.viewer.dispose();
            } catch (e) {
                this.log('Error disposing viewer:', e);
            }
            this.viewer = null;
        }

        this.log('Destroyed');
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

    updated() {
        // Re-render balls after LiveView patches the DOM
        // This ensures balls remain visible when other parts of the page update
        this.render();
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

// Countdown Timer Hook - displays a live countdown from data-seconds
// Used for control request timeouts in Object3DPlayerComponent
Hooks.CountdownTimer = {
    mounted() {
        this.startCountdown();
    },

    updated() {
        // Restart countdown when the element is updated with new seconds
        this.stopCountdown();
        this.startCountdown();
    },

    destroyed() {
        this.stopCountdown();
    },

    startCountdown() {
        const seconds = parseInt(this.el.dataset.seconds, 10);
        if (isNaN(seconds) || seconds <= 0) {
            this.el.textContent = '0s';
            return;
        }

        this.remaining = seconds;
        this.updateDisplay();

        this.interval = setInterval(() => {
            this.remaining = Math.max(0, this.remaining - 1);
            this.updateDisplay();

            if (this.remaining <= 0) {
                this.stopCountdown();
            }
        }, 1000);
    },

    stopCountdown() {
        if (this.interval) {
            clearInterval(this.interval);
            this.interval = null;
        }
    },

    updateDisplay() {
        this.el.textContent = `${this.remaining}s`;
    }
};

// Color Picker Portal Hook - positions color picker above its anchor button
Hooks.ColorPickerPortal = {
    mounted() {
        this.position();
        window.addEventListener('resize', this.position.bind(this));
        window.addEventListener('scroll', this.position.bind(this), true);
    },

    updated() {
        this.position();
    },

    destroyed() {
        window.removeEventListener('resize', this.position.bind(this));
        window.removeEventListener('scroll', this.position.bind(this), true);
    },

    position() {
        const anchorId = this.el.dataset.anchorId;
        const anchor = document.getElementById(anchorId);
        if (!anchor) return;

        const anchorRect = anchor.getBoundingClientRect();
        const pickerRect = this.el.getBoundingClientRect();

        // Position above the button, aligned to left edge
        let top = anchorRect.top - pickerRect.height - 8;
        let left = anchorRect.left;

        // If it would go off the top, show below instead
        if (top < 8) {
            top = anchorRect.bottom + 8;
        }

        // Keep within viewport horizontally
        if (left + pickerRect.width > window.innerWidth - 8) {
            left = window.innerWidth - pickerRect.width - 8;
        }
        if (left < 8) {
            left = 8;
        }

        this.el.style.top = `${top}px`;
        this.el.style.left = `${left}px`;
    }
};

export default Hooks;
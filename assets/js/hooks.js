import Sortable from 'sortablejs';
import * as GaussianSplats3D from '@mkkellogg/gaussian-splats-3d';

let Hooks = {};

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
    // KISS implementation - simple, reliable YouTube player synchronization
    mounted() {
        this.player = null;
        this.roomId = this.el.dataset.roomId;
        this.currentVideoId = null;
        this.isReady = false;
        this.lastKnownPosition = 0;
        this.lastSeekTime = 0;
        this.lastUserActionTime = 0;
        this.seekGracePeriod = 2000; // 2 seconds grace period after seeking
        this.userActionGracePeriod = 1500; // 1.5 seconds grace period after user action
        this.lastReportedPosition = 0;
        this.isUserSeeking = false; // Track if user is actively seeking

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
        // This prevents the sync from immediately overriding user actions
        this.handleEvent("media_user_action", () => {
            this.markUserAction();
        });

        // Handle seek commands from progress bar
        this.handleEvent("seek_to", (data) => {
            if (this.isReady && this.player) {
                this.isUserSeeking = true;
                this.lastSeekTime = Date.now();
                this.player.seekTo(data.position, true);
                this.lastKnownPosition = data.position;
                this.lastReportedPosition = data.position;
                setTimeout(() => { this.isUserSeeking = false; }, 500);
            }
        });

        // Also intercept clicks on play/pause buttons within this component
        this.el.addEventListener('click', (e) => {
            const target = e.target.closest('[phx-click="play"], [phx-click="pause"], [phx-click="next"], [phx-click="previous"]');
            if (target) {
                this.markUserAction();
            }
        });

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
        // Read video data from wrapper
        const wrapperEl = this.el.querySelector('[id^="youtube-player-wrapper-"]');

        if (!playerEl || !wrapperEl) {
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        const videoId = wrapperEl.dataset.videoId;
        if (!videoId) {
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        this.currentVideoId = videoId;

        const autoplay = wrapperEl.dataset.autoplay === '1';
        const startSeconds = parseInt(wrapperEl.dataset.start) || 0;

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
        // Request sync from server every 1 second
        // Also detect if user has seeked in YouTube and report to server
        this.syncInterval = setInterval(() => {
            if (this.isReady && this.player) {
                const currentPosition = this.player.getCurrentTime() || 0;
                const positionDelta = Math.abs(currentPosition - this.lastKnownPosition);
                const now = Date.now();

                // Detect seek: position jumped by more than 2 seconds (not normal playback)
                // But only if we're not actively seeking via our UI
                const inGracePeriod = (now - this.lastSeekTime) < this.seekGracePeriod;

                if (!inGracePeriod && !this.isUserSeeking && positionDelta > 2) {
                    // User seeked via YouTube controls - report to server immediately
                    this.lastSeekTime = now;
                    this.lastReportedPosition = currentPosition;
                    this.pushEventTo(this.el, "client_seek", { position: currentPosition });
                }

                this.lastKnownPosition = currentPosition;

                // Report current position periodically (for progress bar updates)
                // Only report if position changed significantly
                if (Math.abs(currentPosition - this.lastReportedPosition) > 0.5) {
                    this.lastReportedPosition = currentPosition;
                    this.pushEventTo(this.el, "position_update", { position: currentPosition });
                }

                this.pushEventTo(this.el, "request_media_sync", {});
            }
        }, 1000);
    },

    onPlayerStateChange(event) {
        // Report video ended so server can advance playlist
        if (event.data === YT.PlayerState.ENDED) {
            this.pushEventTo(this.el, "video_ended", {});
        }

        // When user clicks play/pause on YouTube controls, sync to server
        // This is the key fix - YouTube controls must update server state
        if (event.data === YT.PlayerState.PLAYING) {
            // User clicked play on YouTube - tell server
            this.markUserAction();
            this.pushEventTo(this.el, "play", {});

            // Report duration (more accurate than onReady)
            const duration = this.player.getDuration();
            if (duration > 0) {
                this.pushEventTo(this.el, "report_duration", { duration: duration });
            }
        } else if (event.data === YT.PlayerState.PAUSED) {
            // User clicked pause on YouTube - tell server
            this.markUserAction();
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
            const wrapperEl = this.el.querySelector('[id^="youtube-player-wrapper-"]');
            if (wrapperEl && youtubeAPILoaded) {
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

        const serverPosition = data.position_seconds || 0;
        const serverState = data.state;
        const currentPosition = this.player.getCurrentTime() || 0;
        const playerState = this.player.getPlayerState();

        const isPlaying = playerState === YT.PlayerState.PLAYING;
        const isPaused = playerState === YT.PlayerState.PAUSED;
        const isBuffering = playerState === YT.PlayerState.BUFFERING;
        const shouldPlay = serverState === 'playing';

        // Check if we're in a user action grace period
        const now = Date.now();
        const inActionGracePeriod = (now - (this.lastUserActionTime || 0)) < this.userActionGracePeriod;

        // 1. Handle play/pause state
        // Only auto-resume if NOT in grace period (prevents race condition when user clicks pause)
        if (shouldPlay && !isPlaying && !isBuffering && !inActionGracePeriod) {
            this.player.playVideo();
        } else if (!shouldPlay && (isPlaying || isBuffering)) {
            // Always allow pausing - this is the authoritative server state
            this.player.pauseVideo();
        }

        // 2. Skip position correction if user is actively seeking or in grace period
        const inSeekGracePeriod = (now - this.lastSeekTime) < this.seekGracePeriod;
        if (inSeekGracePeriod || this.isUserSeeking) {
            return;
        }

        // 3. Correct position drift if > 1.5 seconds (only when playing)
        const drift = Math.abs(currentPosition - serverPosition);
        if (shouldPlay && drift > 1.5 && !isBuffering) {
            this.player.seekTo(serverPosition, true);
            this.lastKnownPosition = serverPosition;
            this.lastReportedPosition = serverPosition;
        }
    },

    // Called when user initiates a play/pause action (to prevent sync race conditions)
    markUserAction() {
        this.lastUserActionTime = Date.now();
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
            button.addEventListener('click', (e) => {
                e.stopPropagation();
                dropdown.classList.toggle('hidden');
            });

            document.addEventListener('click', (e) => {
                if (!this.el.contains(e.target)) {
                    dropdown.classList.add('hidden');
                }
            });
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

export default Hooks;
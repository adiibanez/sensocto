import Sortable from 'sortablejs';

let Hooks = {};

Hooks.SensorDataAccumulator = {
    mounted() {
        console.log("mounted");
    },
    updated() {
        console.log("updated");
    },
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

        console.log('[MediaPlayer] Mounted for room:', this.roomId);

        // Load YouTube API and initialize player
        loadYouTubeAPI().then(() => {
            requestAnimationFrame(() => {
                this.initializePlayer();
            });
        });

        // Handle sync events from server - this is the primary sync mechanism
        this.handleEvent("media_sync", (data) => {
            console.log('[MediaPlayer] Sync event:', data);
            this.handleSync(data);
        });

        // Handle explicit video load commands
        this.handleEvent("media_load_video", (data) => {
            console.log('[MediaPlayer] Load video:', data);
            this.loadVideo(data.video_id, data.start_seconds || 0);
        });

        // Watch for player container being removed (e.g., section collapsed)
        this.setupObserver();
    },

    updated() {
        // Check if video ID changed in the DOM
        const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"])');
        if (playerEl) {
            const newVideoId = playerEl.dataset.videoId;
            if (newVideoId && newVideoId !== this.currentVideoId) {
                console.log('[MediaPlayer] Video ID changed:', this.currentVideoId, '->', newVideoId);
                this.loadVideo(newVideoId, parseInt(playerEl.dataset.start) || 0);
            }
        }
    },

    destroyed() {
        console.log('[MediaPlayer] Destroyed');
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
                console.log('[MediaPlayer] Player element removed, cleaning up');
                try {
                    this.player.destroy();
                } catch (e) {
                    // Ignore
                }
                this.player = null;
                this.isReady = false;
            } else if (playerEl && !this.player && !this.isReady) {
                // Player element reappeared
                console.log('[MediaPlayer] Player element reappeared, reinitializing');
                this.initializePlayer();
            }
        });

        this.observer.observe(this.el, {
            childList: true,
            subtree: true
        });
    },

    initializePlayer(retryCount = 0) {
        // Select the actual player div, not the wrapper
        const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"])');
        if (!playerEl) {
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        const videoId = playerEl.dataset.videoId;
        if (!videoId) {
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        console.log('[MediaPlayer] Initializing player with video:', videoId);
        this.currentVideoId = videoId;

        const autoplay = playerEl.dataset.autoplay === '1';
        const startSeconds = parseInt(playerEl.dataset.start) || 0;

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
        console.log('[MediaPlayer] Player ready');
        this.isReady = true;

        // Report duration to server
        const duration = this.player.getDuration();
        if (duration > 0) {
            this.pushEvent("report_duration", { duration: duration });
        }

        // Request current state from server to sync up
        // Use pushEventTo to target the LiveComponent (this.el)
        this.pushEventTo(this.el, "request_media_sync", {});

        // Start sync interval - poll server every second for multi-tab sync
        this.startSyncInterval();
    },

    startSyncInterval() {
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
        }
        // Request sync from server every 1 second
        // Use pushEventTo to target the LiveComponent (this.el) instead of parent LiveView
        this.syncInterval = setInterval(() => {
            if (this.isReady && this.player) {
                this.pushEventTo(this.el, "request_media_sync", {});
            }
        }, 1000);
    },

    onPlayerStateChange(event) {
        const states = {
            '-1': 'unstarted',
            '0': 'ended',
            '1': 'playing',
            '2': 'paused',
            '3': 'buffering',
            '5': 'cued'
        };
        console.log('[MediaPlayer] State changed:', states[event.data] || 'unknown');

        // Report video ended so server can advance playlist
        if (event.data === YT.PlayerState.ENDED) {
            console.log('[MediaPlayer] Video ended, notifying server');
            this.pushEvent("video_ended", {});
        }

        // Report duration when video starts playing (more accurate than onReady)
        if (event.data === YT.PlayerState.PLAYING) {
            const duration = this.player.getDuration();
            if (duration > 0) {
                this.pushEvent("report_duration", { duration: duration });
            }
        }
    },

    onPlayerError(event) {
        console.error('[MediaPlayer] Error:', event.data);
        const errorCodes = {
            2: 'Invalid video ID',
            5: 'HTML5 player error',
            100: 'Video not found',
            101: 'Embedding not allowed',
            150: 'Embedding not allowed'
        };
        console.error('[MediaPlayer] Error description:', errorCodes[event.data] || 'Unknown error');
    },

    loadVideo(videoId, startSeconds = 0) {
        console.log('[MediaPlayer] Loading video:', videoId, 'start:', startSeconds);
        this.currentVideoId = videoId;

        if (!this.isReady || !this.player) {
            // Not ready yet - reinitialize
            const playerEl = this.el.querySelector('[id^="youtube-player-"]:not([id*="wrapper"])');
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
            console.log('[MediaPlayer] Not ready for sync, ignoring');
            return;
        }

        const serverPosition = data.position_seconds || 0;
        const serverState = data.state;
        const currentPosition = this.player.getCurrentTime() || 0;
        const playerState = this.player.getPlayerState();

        const isPlaying = playerState === YT.PlayerState.PLAYING;
        const isBuffering = playerState === YT.PlayerState.BUFFERING;
        const shouldPlay = serverState === 'playing';

        console.log('[MediaPlayer] Sync - server state:', serverState, 'position:', serverPosition.toFixed(1),
                    '| local position:', currentPosition.toFixed(1), 'playing:', isPlaying);

        // 1. Handle play/pause state first
        if (shouldPlay && !isPlaying && !isBuffering) {
            console.log('[MediaPlayer] Playing video');
            this.player.playVideo();
        } else if (!shouldPlay && (isPlaying || isBuffering)) {
            console.log('[MediaPlayer] Pausing video');
            this.player.pauseVideo();
        }

        // 2. Correct position drift if > 1.5 seconds (only when playing)
        const drift = Math.abs(currentPosition - serverPosition);
        if (shouldPlay && drift > 1.5 && !isBuffering) {
            console.log('[MediaPlayer] Correcting drift of', drift.toFixed(1), 'seconds');
            this.player.seekTo(serverPosition, true);
        }
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
        console.log('[SortablePlaylist] mounted, element:', this.el.id);
        this.initSortable();
    },

    updated() {
        console.log('[SortablePlaylist] updated');
        // Re-initialize if DOM changed significantly
        if (this.sortable) {
            this.sortable.destroy();
        }
        this.initSortable();
    },

    destroyed() {
        console.log('[SortablePlaylist] destroyed');
        if (this.sortable) {
            this.sortable.destroy();
        }
    },

    initSortable() {
        console.log('[SortablePlaylist] initSortable called');
        try {
            this.sortable = new Sortable(this.el, {
                animation: 150,
                handle: '.drag-handle',
                ghostClass: 'opacity-50',
                chosenClass: 'bg-gray-600',
                dragClass: 'shadow-lg',
                onStart: (evt) => {
                    console.log('[SortablePlaylist] drag started', evt.oldIndex);
                },
                onEnd: (evt) => {
                    console.log('[SortablePlaylist] drag ended', evt.oldIndex, '->', evt.newIndex);
                    const itemIds = Array.from(this.el.querySelectorAll('[data-item-id]'))
                        .map(el => el.dataset.itemId);
                    console.log('[SortablePlaylist] new order:', itemIds);
                    this.pushEvent('reorder_playlist', { item_ids: itemIds });
                }
            });
            console.log('[SortablePlaylist] Sortable initialized successfully');
            // Store reference on element for debugging
            this.el._sortableInstance = this.sortable;
        } catch (e) {
            console.error('[SortablePlaylist] Error initializing Sortable:', e);
        }
    }
};

export default Hooks;
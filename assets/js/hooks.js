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
    mounted() {
        this.player = null;
        this.roomId = this.el.dataset.roomId;
        this.currentVideoId = null;
        this.syncInterval = null;
        this.isReady = false;
        this.pendingSeek = null;
        this.pendingPlay = false;
        this.lastKnownState = this.el.dataset.playerState || 'stopped';

        console.log('[MediaPlayer] Mounted for room:', this.roomId, 'initial state:', this.lastKnownState);

        // Load YouTube API and initialize player
        // Use requestAnimationFrame to ensure DOM is fully rendered before initializing
        loadYouTubeAPI().then(() => {
            requestAnimationFrame(() => {
                this.initializePlayer();
            });
        });

        // Handle sync events from server
        this.handleEvent("media_sync", (data) => {
            console.log('[MediaPlayer] Sync event:', data);
            this.handleSync(data);
        });

        this.handleEvent("media_load_video", (data) => {
            console.log('[MediaPlayer] Load video:', data);
            this.loadVideo(data.video_id, data.start_seconds || 0);
        });

        // Set up MutationObserver to detect player container changes
        this.setupObserver();

        // Set up MutationObserver to detect player state changes via data attributes
        // This is needed because updated() may not be called reliably for LiveComponents
        this.setupStateObserver();
    },

    updated() {
        // Check if video ID changed in the DOM
        const playerEl = this.el.querySelector('[id^="youtube-player-"]');
        if (playerEl) {
            const newVideoId = playerEl.dataset.videoId;
            if (newVideoId && newVideoId !== this.currentVideoId) {
                console.log('[MediaPlayer] Video ID changed:', this.currentVideoId, '->', newVideoId);
                const autoplay = playerEl.dataset.autoplay === '1';
                const startSeconds = parseInt(playerEl.dataset.start) || 0;
                this.loadVideo(newVideoId, startSeconds, autoplay);
            }
        }
        // Note: Player state changes are handled by setupStateObserver() MutationObserver
        // because updated() is not reliably called for LiveComponent attribute changes
    },

    destroyed() {
        console.log('[MediaPlayer] Destroyed');
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
        }
        if (this.observer) {
            this.observer.disconnect();
        }
        if (this.stateObserver) {
            this.stateObserver.disconnect();
        }
        if (this.player) {
            this.player.destroy();
        }
    },

    setupStateObserver() {
        // Watch for changes to data-player-state attribute on the hook element itself
        this.stateObserver = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                if (mutation.type === 'attributes' && mutation.attributeName === 'data-player-state') {
                    const newState = this.el.dataset.playerState;
                    console.log('[MediaPlayer] State attribute changed:', this.lastKnownState, '->', newState);

                    if (newState && newState !== this.lastKnownState) {
                        this.lastKnownState = newState;
                        this.applyPlayerState(newState);
                    }
                }
            }
        });

        this.stateObserver.observe(this.el, {
            attributes: true,
            attributeFilter: ['data-player-state', 'data-position']
        });
    },

    applyPlayerState(newState) {
        if (!this.isReady || !this.player) {
            console.log('[MediaPlayer] Player not ready, cannot apply state');
            return;
        }

        const playerState = this.player.getPlayerState();
        const isPlaying = playerState === YT.PlayerState.PLAYING;
        const shouldPlay = newState === 'playing';

        if (shouldPlay && !isPlaying) {
            console.log('[MediaPlayer] Playing video via state observer');
            this.player.playVideo();
        } else if (!shouldPlay && isPlaying) {
            console.log('[MediaPlayer] Pausing video via state observer');
            this.player.pauseVideo();
        }
    },

    setupObserver() {
        this.observer = new MutationObserver((mutations) => {
            for (const mutation of mutations) {
                if (mutation.type === 'childList' || mutation.type === 'attributes') {
                    this.checkForPlayerChanges();
                }
            }
        });

        this.observer.observe(this.el, {
            childList: true,
            subtree: true,
            attributes: true,
            attributeFilter: ['data-video-id']
        });
    },

    checkForPlayerChanges() {
        const playerEl = this.el.querySelector('[id^="youtube-player-"]');

        if (!playerEl && this.player) {
            console.log('[MediaPlayer] Player element removed (collapsed), cleaning up');
            try {
                this.player.destroy();
            } catch (e) {
                console.log('[MediaPlayer] Error destroying player:', e);
            }
            this.player = null;
            this.isReady = false;
        } else if (playerEl) {
            this.checkForNewVideo();
        }
    },

    checkForNewVideo() {
        const playerEl = this.el.querySelector('[id^="youtube-player-"]');
        if (playerEl) {
            const newVideoId = playerEl.dataset.videoId;
            const autoplay = playerEl.dataset.autoplay === '1';
            const startSeconds = parseInt(playerEl.dataset.start) || 0;

            if (newVideoId && newVideoId !== this.currentVideoId) {
                this.loadVideo(newVideoId, startSeconds, autoplay);
            } else if (newVideoId && !this.player) {
                console.log('[MediaPlayer] Player element reappeared, reinitializing');
                this.currentVideoId = null;
                this.isReady = false;
                this.initializePlayer();
            }
        }
    },

    initializePlayer(retryCount = 0) {
        const playerEl = this.el.querySelector('[id^="youtube-player-"]');
        if (!playerEl) {
            console.log('[MediaPlayer] No player element found, retry:', retryCount);
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        const videoId = playerEl.dataset.videoId;
        const autoplay = playerEl.dataset.autoplay === '1';
        const startSeconds = parseInt(playerEl.dataset.start) || 0;

        if (!videoId) {
            console.log('[MediaPlayer] No video ID, retry:', retryCount);
            if (retryCount < 5) {
                setTimeout(() => this.initializePlayer(retryCount + 1), 200);
            }
            return;
        }

        console.log('[MediaPlayer] Initializing player with video:', videoId);
        this.currentVideoId = videoId;

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

        // Report duration
        const duration = this.player.getDuration();
        if (duration > 0) {
            this.pushEvent("report_duration", { duration: duration });
        }

        // Apply any pending operations
        if (this.pendingSeek !== null) {
            this.player.seekTo(this.pendingSeek, true);
            this.pendingSeek = null;
        }

        if (this.pendingPlay) {
            this.player.playVideo();
            this.pendingPlay = false;
        }

        // Request current state from server to ensure sync
        // This is critical for new tabs that may have stale DOM state
        console.log('[MediaPlayer] Requesting sync from server');
        this.pushEvent("request_media_sync", {});

        // Start sync interval
        this.startSyncInterval();
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

        const stateName = states[event.data] || 'unknown';
        console.log('[MediaPlayer] State changed:', stateName);

        // Report video ended
        if (event.data === YT.PlayerState.ENDED) {
            this.pushEvent("video_ended", {});
        }

        // Report duration when video starts
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

    loadVideo(videoId, startSeconds = 0, autoplay = true) {
        console.log('[MediaPlayer] Loading video:', videoId, 'start:', startSeconds, 'autoplay:', autoplay);
        this.currentVideoId = videoId;

        if (!this.isReady || !this.player) {
            console.log('[MediaPlayer] Player not ready, will initialize');
            // Re-initialize player
            const playerEl = this.el.querySelector('[id^="youtube-player-"]');
            if (playerEl && youtubeAPILoaded) {
                // Destroy existing player if any
                if (this.player) {
                    this.player.destroy();
                }
                this.initializePlayer();
            }
            return;
        }

        if (autoplay) {
            this.player.loadVideoById({
                videoId: videoId,
                startSeconds: startSeconds
            });
        } else {
            this.player.cueVideoById({
                videoId: videoId,
                startSeconds: startSeconds
            });
        }
    },

    handleSync(data) {
        if (!this.isReady || !this.player) {
            console.log('[MediaPlayer] Not ready for sync');
            this.pendingSeek = data.position_seconds;
            this.pendingPlay = data.state === 'playing';
            return;
        }

        const serverPosition = data.position_seconds || 0;
        const currentPosition = this.player.getCurrentTime() || 0;
        const drift = Math.abs(currentPosition - serverPosition);

        console.log('[MediaPlayer] Sync - server:', serverPosition.toFixed(1), 'current:', currentPosition.toFixed(1), 'drift:', drift.toFixed(1));

        // Sync play/pause state FIRST (before seeking)
        const playerState = this.player.getPlayerState();
        const isPlaying = playerState === YT.PlayerState.PLAYING;
        const isBuffering = playerState === YT.PlayerState.BUFFERING;
        const shouldPlay = data.state === 'playing';

        // Correct drift if > 1 second (lowered from 2s for tighter sync)
        // Always seek if drift is significant, regardless of play state
        if (drift > 1) {
            console.log('[MediaPlayer] Correcting drift of', drift.toFixed(1), 'seconds');
            this.player.seekTo(serverPosition, true);
        }

        // Sync play/pause state (handle buffering state as "in progress")
        if (shouldPlay && !isPlaying && !isBuffering) {
            console.log('[MediaPlayer] Starting playback to sync');
            this.player.playVideo();
        } else if (!shouldPlay && (isPlaying || isBuffering)) {
            console.log('[MediaPlayer] Pausing to sync');
            this.player.pauseVideo();
        }
    },

    startSyncInterval() {
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
        }

        // Request sync from server every 5 seconds to stay synchronized
        // This ensures all tabs stay in sync even if PubSub events are missed
        this.syncInterval = setInterval(() => {
            if (this.isReady && this.player) {
                // Request current state from server
                this.pushEvent("request_media_sync", {});
            }
        }, 5000);
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
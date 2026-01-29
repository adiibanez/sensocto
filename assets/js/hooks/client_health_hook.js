/**
 * ClientHealthHook - Monitors client performance and reports to server
 *
 * This hook tracks various client health metrics:
 * - Frame rate (FPS) via requestAnimationFrame
 * - CPU pressure (Chrome's Compute Pressure API)
 * - Memory usage (Chrome's performance.memory)
 * - Battery status (Battery API)
 * - Network quality (Network Information API)
 * - Dropped frames and jank detection
 *
 * Reports are sent every 2 seconds to allow the server to adapt
 * the data stream quality based on client capabilities.
 *
 * Usage:
 * Add phx-hook="ClientHealthHook" to an element in your LiveView template.
 */

const ClientHealthHook = {
    mounted() {
        this.reportInterval = null;
        this.frameTimestamps = [];
        this.lastReportTime = performance.now();
        this.rafId = null;
        this.pressureObserver = null;

        this.metrics = {
            fps: 60,
            cpuPressure: 'nominal',
            memoryUsage: null,
            memoryPressure: 0,
            batteryLevel: null,
            batteryCharging: true,
            thermalState: 'nominal',
            networkType: null,
            networkEffectiveType: null,
            networkDownlink: null,
            networkRtt: null,
            saveData: false,
            renderLag: 0,
            droppedFrames: 0,
            jank: false
        };

        this.startMonitoring();
    },

    destroyed() {
        this.stopMonitoring();
    },

    startMonitoring() {
        // 1. Frame rate monitoring via requestAnimationFrame
        this.monitorFrameRate();

        // 2. Compute Pressure API (Chrome 115+)
        this.monitorComputePressure();

        // 3. Memory API
        this.monitorMemory();

        // 4. Battery API
        this.monitorBattery();

        // 5. Network Information API
        this.monitorNetwork();

        // 6. Report to server every 2 seconds
        this.reportInterval = setInterval(() => this.reportHealth(), 2000);

        // 7. Handle visibility changes
        this.visibilityHandler = () => {
            if (document.visibilityState === 'visible') {
                // Reset frame tracking after coming back from background
                this.frameTimestamps = [];
                setTimeout(() => this.reportHealth(), 500);
            }
        };
        document.addEventListener('visibilitychange', this.visibilityHandler);

        // Initial report after short delay
        setTimeout(() => this.reportHealth(), 1000);
    },

    stopMonitoring() {
        if (this.reportInterval) {
            clearInterval(this.reportInterval);
            this.reportInterval = null;
        }

        if (this.pressureObserver) {
            try {
                this.pressureObserver.disconnect();
            } catch (e) {}
            this.pressureObserver = null;
        }

        if (this.rafId) {
            cancelAnimationFrame(this.rafId);
            this.rafId = null;
        }

        if (this.visibilityHandler) {
            document.removeEventListener('visibilitychange', this.visibilityHandler);
        }

        if (this.memoryInterval) {
            clearInterval(this.memoryInterval);
            this.memoryInterval = null;
        }
    },

    // ─────────────────────────────────────────────────────────────
    // Frame Rate Monitoring
    // ─────────────────────────────────────────────────────────────
    monitorFrameRate() {
        const measureFrame = (timestamp) => {
            this.frameTimestamps.push(timestamp);

            // Keep only last 60 frames (1 second at 60fps)
            if (this.frameTimestamps.length > 60) {
                this.frameTimestamps.shift();
            }

            // Calculate FPS from frame times
            if (this.frameTimestamps.length >= 2) {
                const duration = timestamp - this.frameTimestamps[0];
                if (duration > 0) {
                    this.metrics.fps = Math.round((this.frameTimestamps.length - 1) / (duration / 1000));
                }

                // Detect jank (frame taking > 50ms)
                if (this.frameTimestamps.length >= 2) {
                    const lastFrameTime = timestamp - this.frameTimestamps[this.frameTimestamps.length - 2];
                    this.metrics.jank = lastFrameTime > 50;

                    if (lastFrameTime > 100) {
                        this.metrics.droppedFrames++;
                    }
                }
            }

            this.rafId = requestAnimationFrame(measureFrame);
        };

        this.rafId = requestAnimationFrame(measureFrame);
    },

    // ─────────────────────────────────────────────────────────────
    // Compute Pressure API (CPU pressure)
    // https://developer.chrome.com/docs/web-platform/compute-pressure
    // ─────────────────────────────────────────────────────────────
    monitorComputePressure() {
        if ('PressureObserver' in window) {
            try {
                this.pressureObserver = new PressureObserver((records) => {
                    const record = records[records.length - 1];
                    // state: "nominal", "fair", "serious", "critical"
                    this.metrics.cpuPressure = record.state;
                }, { sampleInterval: 1000 });

                this.pressureObserver.observe('cpu');
            } catch (e) {
                // Compute Pressure API not available or denied
            }
        }
    },

    // ─────────────────────────────────────────────────────────────
    // Memory Monitoring
    // ─────────────────────────────────────────────────────────────
    monitorMemory() {
        if (performance.memory) {
            // Chrome-only API
            this.memoryInterval = setInterval(() => {
                const mem = performance.memory;
                this.metrics.memoryUsage = {
                    used: Math.round(mem.usedJSHeapSize / 1024 / 1024),  // MB
                    total: Math.round(mem.totalJSHeapSize / 1024 / 1024),
                    limit: Math.round(mem.jsHeapSizeLimit / 1024 / 1024)
                };
                this.metrics.memoryPressure = mem.usedJSHeapSize / mem.jsHeapSizeLimit;
            }, 5000);
        }
    },

    // ─────────────────────────────────────────────────────────────
    // Battery API
    // ─────────────────────────────────────────────────────────────
    async monitorBattery() {
        if ('getBattery' in navigator) {
            try {
                const battery = await navigator.getBattery();

                const updateBattery = () => {
                    this.metrics.batteryLevel = Math.round(battery.level * 100);
                    this.metrics.batteryCharging = battery.charging;
                };

                updateBattery();
                battery.addEventListener('levelchange', updateBattery);
                battery.addEventListener('chargingchange', updateBattery);
            } catch (e) {
                // Battery API not available
            }
        }
    },

    // ─────────────────────────────────────────────────────────────
    // Network Information API
    // ─────────────────────────────────────────────────────────────
    monitorNetwork() {
        if ('connection' in navigator) {
            const conn = navigator.connection;

            const updateNetwork = () => {
                this.metrics.networkType = conn.type;  // wifi, cellular, etc.
                this.metrics.networkEffectiveType = conn.effectiveType;  // slow-2g, 2g, 3g, 4g
                this.metrics.networkDownlink = conn.downlink;  // Mbps estimate
                this.metrics.networkRtt = conn.rtt;  // Round-trip time ms
                this.metrics.saveData = conn.saveData;  // Data saver enabled
            };

            updateNetwork();
            conn.addEventListener('change', updateNetwork);
        }
    },

    // ─────────────────────────────────────────────────────────────
    // Thermal State Detection (heuristic-based)
    // ─────────────────────────────────────────────────────────────
    checkThermalState() {
        // iOS-specific heuristic: detect thermal throttling via frame drops
        // when CPU pressure is nominal but FPS is low
        if (this.metrics.fps < 30 && this.metrics.cpuPressure === 'nominal') {
            this.metrics.thermalState = 'throttled';
        } else if (this.metrics.fps >= 50) {
            this.metrics.thermalState = 'nominal';
        }
    },

    // ─────────────────────────────────────────────────────────────
    // Report to Server
    // ─────────────────────────────────────────────────────────────
    reportHealth() {
        // Skip if tab is hidden
        if (document.visibilityState === 'hidden') {
            return;
        }

        const now = performance.now();
        const timeSinceLastReport = now - this.lastReportTime;
        this.lastReportTime = now;

        // Calculate render lag (how long since we should have reported)
        this.metrics.renderLag = Math.max(0, timeSinceLastReport - 2000);

        this.checkThermalState();

        // Compute overall health score (0-100)
        const healthScore = this.calculateHealthScore();

        this.pushEvent("client_health", {
            ...this.metrics,
            healthScore,
            timestamp: Date.now(),
            viewport: {
                width: window.innerWidth,
                height: window.innerHeight
            }
        });

        // Reset per-period counters
        this.metrics.droppedFrames = 0;
        this.metrics.jank = false;
    },

    // ─────────────────────────────────────────────────────────────
    // Health Score Calculation (0-100)
    // ─────────────────────────────────────────────────────────────
    calculateHealthScore() {
        let score = 100;

        // FPS penalty (target 60fps)
        if (this.metrics.fps < 60) {
            score -= (60 - this.metrics.fps) * 1.5;
        }
        if (this.metrics.fps < 30) {
            score -= 20;  // Additional penalty for very low FPS
        }

        // CPU pressure penalty
        const cpuPenalty = {
            'nominal': 0,
            'fair': 10,
            'serious': 30,
            'critical': 50
        };
        score -= cpuPenalty[this.metrics.cpuPressure] || 0;

        // Memory pressure penalty
        if (this.metrics.memoryPressure > 0.8) score -= 20;
        if (this.metrics.memoryPressure > 0.9) score -= 30;

        // Battery penalty (only if not charging and low)
        if (!this.metrics.batteryCharging && this.metrics.batteryLevel !== null) {
            if (this.metrics.batteryLevel < 20) score -= 15;
            if (this.metrics.batteryLevel < 10) score -= 15;
        }

        // Network penalty
        const networkPenalty = {
            'slow-2g': 40,
            '2g': 30,
            '3g': 15,
            '4g': 0
        };
        score -= networkPenalty[this.metrics.networkEffectiveType] || 0;

        // Data saver penalty
        if (this.metrics.saveData) score -= 20;

        // Dropped frames penalty
        score -= this.metrics.droppedFrames * 2;

        // Thermal throttling penalty
        if (this.metrics.thermalState === 'throttled') score -= 25;

        return Math.max(0, Math.min(100, Math.round(score)));
    }
};

export default ClientHealthHook;

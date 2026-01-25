<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";
    import { Socket } from "phoenix";
    import { getCookie, setCookie, isMobile } from "./utils.js";
    import SensorService from "./SenseApp/SensorService.svelte";
    import BluetoothClient from "./SenseApp/BluetoothClient.svelte";
    import IMUClient from "./SenseApp/IMUClient.svelte";
    import GeolocationClient from "./SenseApp/GeolocationClient.svelte";
    import BatterystatusClient from "./SenseApp/BatterystatusClient.svelte";
    import PushButtonClient from "./SenseApp/PushButtonClient.svelte";
    import RichPresenceClient from "./SenseApp/RichPresenceClient.svelte";
    import PoseClient from "./SenseApp/PoseClient.svelte";
    import NetworkQualityMonitor from "./SenseApp/NetworkQualityMonitor.svelte";

    import { usersettings, autostart } from "./SenseApp/stores.js";

    import { logger } from "./logger_svelte.js";
    let loggerCtxName = "SenseApp";

    import Map from "./Map.svelte";

    export let live = null;
    export let bearerToken = null;
    let deviceName = null;
    let inputDeviceName = "";
    let sensorService = null;

    // Footer collapsed state
    let footerExpanded = false;

    // Info panel state - shows sensor explanations
    let showInfoPanel = false;
    let selectedSensorKey = null;
    $: selectedSensorInfo = selectedSensorKey ? sensorInfo[selectedSensorKey] : null;

    // Detect mobile/desktop
    const mobile = isMobile();

    // Ordered sensor keys for navigation
    const sensorKeys = ['bluetooth', 'geolocation', 'battery', 'imu', 'pose', 'presence'];

    // Sensor info definitions with intent and consequences
    const sensorInfo = {
        bluetooth: {
            name: "Bluetooth",
            icon: "bluetooth",
            description: "Connect to BLE devices like heart rate monitors, pressure sensors, and wearables.",
            dataCollected: ["Heart rate", "Device-specific measurements", "Battery level"],
            consequences: "Requires pairing with your BLE device. Data is streamed in real-time.",
            permissions: "Bluetooth access",
            platforms: ["desktop", "mobile"]
        },
        geolocation: {
            name: "Location",
            icon: "location",
            description: "Share your GPS location to enable location-based features and mapping.",
            dataCollected: ["Latitude & longitude", "Accuracy", "Altitude (if available)"],
            consequences: "Your location will be visible to other participants in the room.",
            permissions: "Location access",
            platforms: ["desktop", "mobile"]
        },
        battery: {
            name: "Battery",
            icon: "battery",
            description: "Monitor your device's battery level and charging status.",
            dataCollected: ["Battery percentage", "Charging state"],
            consequences: "Helps others know your device status. Useful for long sessions.",
            permissions: "None required",
            platforms: ["desktop", "mobile"]
        },
        imu: {
            name: "Motion (IMU)",
            icon: "imu",
            description: "Access accelerometer and gyroscope data for motion tracking and orientation.",
            dataCollected: ["Acceleration (x, y, z)", "Rotation rate", "Device orientation"],
            consequences: "Enables gesture recognition and 3D orientation. Requires device motion permission on iOS.",
            permissions: "Motion sensors access",
            platforms: ["mobile"]
        },
        pose: {
            name: "Pose Estimation",
            icon: "pose",
            description: "Use your camera for real-time body pose detection and skeleton tracking.",
            dataCollected: ["33 body landmarks", "Joint positions", "Pose confidence"],
            consequences: "Processes video locally using AI. Your skeleton data is shared, not video. Uses camera or call video.",
            permissions: "Camera access (if not in call)",
            platforms: ["desktop", "mobile"]
        },
        presence: {
            name: "Rich Presence",
            icon: "presence",
            description: "Share activity status, focus level, and availability with other participants.",
            dataCollected: ["Activity state", "Focus indicator", "Custom status"],
            consequences: "Others can see if you're active, idle, or away.",
            permissions: "None required",
            platforms: ["desktop", "mobile"]
        }
    };

    // Track if initial load is complete to avoid saving cookie on mount
    let initialLoadComplete = false;

    autostart.subscribe((value) => {
        logger.log(loggerCtxName, "Autostart update", value, autostart);
        if (initialLoadComplete) {
            setCookie("autostart", value);
        }
    });

    onMount(() => {
        console.log("initialize socket in SenseApp", live);
        socket = new Socket("/socket", {
            params: { user_token: "some_token" },
        });
        socket.connect();
        console.log("connected to socket", socket);

        deviceName = sensorService.getDeviceName();
        inputDeviceName = deviceName;
        console.log("Device name", deviceName, sensorService);

        cookieAutostart = getCookie("autostart");
        logger.log(loggerCtxName, "Cookie autostart", cookieAutostart);
        autostart.set(cookieAutostart == "true");
        initialLoadComplete = true;

        const savedExpanded = getCookie("footerExpanded");
        footerExpanded = savedExpanded === "true";

        usersettings.update((settings) => ({
            ...settings,
        }));
    });

    onDestroy(() => {
        console.log("Destroy SenseApp");
        socket.disconnect();
    });

    function toggleFooter() {
        footerExpanded = !footerExpanded;
        setCookie("footerExpanded", footerExpanded);
    }

    function toggleInfoPanel() {
        showInfoPanel = !showInfoPanel;
        if (!showInfoPanel) {
            selectedSensorInfo = null;
        }
    }

    function showSensorInfo(sensorKey) {
        selectedSensorKey = sensorKey;
        showInfoPanel = true;
    }

    function closeSensorInfo() {
        selectedSensorKey = null;
    }

    function navigateSensor(direction) {
        if (!selectedSensorKey) return;
        const currentIndex = sensorKeys.indexOf(selectedSensorKey);
        if (currentIndex === -1) return;

        let newIndex;
        if (direction === 'prev') {
            newIndex = currentIndex === 0 ? sensorKeys.length - 1 : currentIndex - 1;
        } else {
            newIndex = currentIndex === sensorKeys.length - 1 ? 0 : currentIndex + 1;
        }
        selectedSensorKey = sensorKeys[newIndex];
    }
</script>

<SensorService bind:live bind:this={sensorService} {bearerToken}>
    <div class="sense-footer" class:expanded={footerExpanded} class:mobile={mobile}>
        <!-- First row: Toggle + sensor icons -->
        <div class="footer-row-icons">
            <button
                class="footer-toggle"
                on:click={toggleFooter}
                title={footerExpanded ? "Collapse" : "Expand"}
            >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="toggle-icon" class:rotated={footerExpanded}>
                    <path fill-rule="evenodd" d="M5.23 7.21a.75.75 0 011.06.02L10 11.168l3.71-3.938a.75.75 0 111.08 1.04l-4.25 4.5a.75.75 0 01-1.08 0l-4.25-4.5a.75.75 0 01.02-1.06z" clip-rule="evenodd" />
                </svg>
            </button>

            <div class="sensor-icons">
                <!-- Bluetooth -->
                <div
                    class="sensor-wrapper"
                    class:info-highlight={showInfoPanel && selectedSensorKey === 'bluetooth'}
                    on:click|capture={(e) => { if (showInfoPanel) { e.stopPropagation(); showSensorInfo('bluetooth'); }}}
                    on:contextmenu|preventDefault={() => showSensorInfo('bluetooth')}
                >
                    <BluetoothClient compact={true} />
                </div>
                <!-- Geolocation -->
                <div
                    class="sensor-wrapper"
                    class:info-highlight={showInfoPanel && selectedSensorKey === 'geolocation'}
                    on:click|capture={(e) => { if (showInfoPanel) { e.stopPropagation(); showSensorInfo('geolocation'); }}}
                    on:contextmenu|preventDefault={() => showSensorInfo('geolocation')}
                >
                    <GeolocationClient compact={true} />
                </div>
                <!-- Battery -->
                <div
                    class="sensor-wrapper"
                    class:info-highlight={showInfoPanel && selectedSensorKey === 'battery'}
                    on:click|capture={(e) => { if (showInfoPanel) { e.stopPropagation(); showSensorInfo('battery'); }}}
                    on:contextmenu|preventDefault={() => showSensorInfo('battery')}
                >
                    <BatterystatusClient compact={true} />
                </div>
                <!-- IMU (mobile only) -->
                <div
                    class="sensor-wrapper"
                    class:info-highlight={showInfoPanel && selectedSensorKey === 'imu'}
                    on:click|capture={(e) => { if (showInfoPanel) { e.stopPropagation(); showSensorInfo('imu'); }}}
                    on:contextmenu|preventDefault={() => showSensorInfo('imu')}
                >
                    <IMUClient compact={true} />
                </div>
                <!-- Pose -->
                <div
                    class="sensor-wrapper"
                    class:info-highlight={showInfoPanel && selectedSensorKey === 'pose'}
                    on:click|capture={(e) => { if (showInfoPanel) { e.stopPropagation(); showSensorInfo('pose'); }}}
                    on:contextmenu|preventDefault={() => showSensorInfo('pose')}
                >
                    <PoseClient compact={true} />
                </div>
                <!-- Presence -->
                <div
                    class="sensor-wrapper"
                    class:info-highlight={showInfoPanel && selectedSensorKey === 'presence'}
                    on:click|capture={(e) => { if (showInfoPanel) { e.stopPropagation(); showSensorInfo('presence'); }}}
                    on:contextmenu|preventDefault={() => showSensorInfo('presence')}
                >
                    <RichPresenceClient compact={true} />
                </div>
            </div>

            <!-- Info button -->
            <button
                class="info-btn"
                on:click={toggleInfoPanel}
                title="Sensor info & help"
                class:active={showInfoPanel}
            >
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" class="w-3.5 h-3.5">
                    <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z" clip-rule="evenodd" />
                </svg>
            </button>
        </div>

        <!-- Info Panel - shows when info button clicked or sensor long-pressed -->
        {#if showInfoPanel}
            <div class="info-panel">
                {#if selectedSensorInfo}
                    <!-- Single sensor detail view -->
                    <div class="sensor-detail">
                        <div class="detail-header">
                            <h4>{selectedSensorInfo.name}</h4>
                            <span class="nav-hint">Click sensor icons above to navigate</span>
                        </div>
                        <p class="detail-desc">{selectedSensorInfo.description}</p>
                        <div class="detail-section">
                            <span class="detail-label">Data collected:</span>
                            <ul class="detail-list">
                                {#each selectedSensorInfo.dataCollected as item}
                                    <li>{item}</li>
                                {/each}
                            </ul>
                        </div>
                        <div class="detail-section">
                            <span class="detail-label">What this means:</span>
                            <p class="detail-text">{selectedSensorInfo.consequences}</p>
                        </div>
                        <div class="detail-meta">
                            <span class="meta-tag">{selectedSensorInfo.permissions}</span>
                            {#each selectedSensorInfo.platforms as platform}
                                <span class="meta-tag platform">{platform}</span>
                            {/each}
                        </div>
                    </div>
                {:else}
                    <!-- Overview of all sensors -->
                    <div class="info-overview">
                        <div class="info-header">
                            <span class="info-title">Sensor Connectors</span>
                            <span class="info-hint">{mobile ? 'Long-press' : 'Right-click'} any sensor for details</span>
                        </div>
                        <div class="sensor-grid">
                            {#each Object.entries(sensorInfo) as [key, info]}
                                <button
                                    class="sensor-card"
                                    on:click={() => showSensorInfo(key)}
                                    class:mobile-only={info.platforms.length === 1 && info.platforms[0] === 'mobile'}
                                >
                                    <span class="card-name">{info.name}</span>
                                    <span class="card-desc">{info.description.split('.')[0]}</span>
                                    {#if info.platforms.length === 1 && info.platforms[0] === 'mobile'}
                                        <span class="mobile-badge">Mobile</span>
                                    {/if}
                                </button>
                            {/each}
                        </div>
                    </div>
                {/if}
            </div>
        {/if}

        <!-- Second row: Expanded settings -->
        {#if footerExpanded}
            <div class="expanded-content">
                <!-- Connector name -->
                <div class="setting-row">
                    <label for="connector_name" class="setting-label">Name</label>
                    <input
                        type="text"
                        id="connector_name"
                        class="setting-input"
                        bind:value={inputDeviceName}
                        required
                    />
                    <button
                        class="setting-btn"
                        on:click={() => {
                            sensorService.setDeviceName(inputDeviceName);
                            deviceName = inputDeviceName;
                        }}>OK</button
                    >
                </div>

                <!-- Autostart -->
                <div class="setting-row">
                    <label for="autostart" class="setting-label">Auto</label>
                    <input
                        type="checkbox"
                        bind:checked={$autostart}
                        id="autostart"
                        class="setting-checkbox"
                    />
                </div>

                <!-- Push buttons -->
                <div class="setting-row buttons-row">
                    <PushButtonClient />
                </div>
            </div>
        {/if}
    </div>
</SensorService>

<style>
    .sense-footer {
        display: flex;
        flex-direction: column;
        gap: 0.25rem;
        padding: 0.25rem 0.5rem;
        background: rgba(31, 41, 55, 0.95);
        border-radius: 0.5rem;
        backdrop-filter: blur(4px);
        transition: all 0.2s ease;
    }

    .sense-footer.expanded {
        padding: 0.375rem 0.5rem;
    }

    .footer-row-icons {
        display: flex;
        align-items: center;
        gap: 0.375rem;
    }

    .footer-toggle {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.25rem;
        height: 1.25rem;
        border-radius: 0.25rem;
        background: transparent;
        color: #6b7280;
        border: none;
        cursor: pointer;
        transition: all 0.15s ease;
        flex-shrink: 0;
        padding: 0;
    }

    .footer-toggle:hover {
        background: rgba(75, 85, 99, 0.5);
        color: #d1d5db;
    }

    .toggle-icon {
        width: 0.875rem;
        height: 0.875rem;
        transition: transform 0.2s ease;
    }

    .toggle-icon.rotated {
        transform: rotate(180deg);
    }

    .sensor-icons {
        display: flex;
        align-items: center;
        gap: 0.25rem;
    }

    .sensor-wrapper {
        display: contents;
    }

    /* In info mode, highlight the selected sensor */
    .sensor-wrapper.info-highlight :global(button) {
        outline: 2px solid #60a5fa;
        outline-offset: 1px;
    }

    /* Info button */
    .info-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.25rem;
        height: 1.25rem;
        border-radius: 0.25rem;
        background: transparent;
        color: #6b7280;
        border: none;
        cursor: pointer;
        transition: all 0.15s ease;
        margin-left: 0.25rem;
    }

    .info-btn:hover, .info-btn.active {
        background: rgba(59, 130, 246, 0.2);
        color: #60a5fa;
    }

    /* Info Panel */
    .info-panel {
        padding: 0.5rem;
        margin-top: 0.25rem;
        background: rgba(17, 24, 39, 0.95);
        border-radius: 0.375rem;
        border: 1px solid rgba(75, 85, 99, 0.5);
    }

    .info-overview {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }

    .info-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
    }

    .info-title {
        font-size: 0.75rem;
        font-weight: 600;
        color: #e5e7eb;
    }

    .info-hint {
        font-size: 0.625rem;
        color: #6b7280;
    }

    .sensor-grid {
        display: grid;
        grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
        gap: 0.375rem;
    }

    .sensor-card {
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
        padding: 0.5rem;
        background: rgba(55, 65, 81, 0.5);
        border: 1px solid rgba(75, 85, 99, 0.3);
        border-radius: 0.375rem;
        cursor: pointer;
        transition: all 0.15s ease;
        text-align: left;
        position: relative;
    }

    .sensor-card:hover {
        background: rgba(55, 65, 81, 0.8);
        border-color: rgba(96, 165, 250, 0.3);
    }

    .sensor-card.mobile-only {
        opacity: 0.7;
    }

    .card-name {
        font-size: 0.6875rem;
        font-weight: 600;
        color: #e5e7eb;
    }

    .card-desc {
        font-size: 0.5625rem;
        color: #9ca3af;
        line-height: 1.3;
    }

    .mobile-badge {
        position: absolute;
        top: 0.25rem;
        right: 0.25rem;
        font-size: 0.5rem;
        padding: 0.0625rem 0.25rem;
        background: #7c3aed;
        color: white;
        border-radius: 0.25rem;
        text-transform: uppercase;
        letter-spacing: 0.025em;
    }

    /* Sensor Detail View */
    .sensor-detail {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }

    .detail-header {
        display: flex;
        justify-content: space-between;
        align-items: center;
        gap: 0.5rem;
    }

    .detail-header h4 {
        font-size: 0.875rem;
        font-weight: 600;
        color: #f3f4f6;
        margin: 0;
    }

    .nav-hint {
        font-size: 0.5rem;
        color: #6b7280;
        font-style: italic;
    }

    .close-btn {
        display: flex;
        align-items: center;
        justify-content: center;
        width: 1.25rem;
        height: 1.25rem;
        background: transparent;
        border: none;
        color: #9ca3af;
        cursor: pointer;
        border-radius: 0.25rem;
        transition: all 0.15s ease;
    }

    .close-btn:hover {
        background: rgba(75, 85, 99, 0.5);
        color: #f3f4f6;
    }

    .detail-desc {
        font-size: 0.6875rem;
        color: #d1d5db;
        line-height: 1.4;
        margin: 0;
    }

    .detail-section {
        display: flex;
        flex-direction: column;
        gap: 0.125rem;
    }

    .detail-label {
        font-size: 0.5625rem;
        font-weight: 600;
        color: #9ca3af;
        text-transform: uppercase;
        letter-spacing: 0.05em;
    }

    .detail-list {
        margin: 0;
        padding-left: 1rem;
        font-size: 0.625rem;
        color: #d1d5db;
    }

    .detail-list li {
        margin: 0.0625rem 0;
    }

    .detail-text {
        font-size: 0.625rem;
        color: #fbbf24;
        margin: 0;
        padding: 0.25rem 0.375rem;
        background: rgba(251, 191, 36, 0.1);
        border-radius: 0.25rem;
        border-left: 2px solid #fbbf24;
    }

    .detail-meta {
        display: flex;
        gap: 0.25rem;
        flex-wrap: wrap;
        margin-top: 0.25rem;
    }

    .meta-tag {
        font-size: 0.5rem;
        padding: 0.125rem 0.375rem;
        background: rgba(75, 85, 99, 0.5);
        color: #d1d5db;
        border-radius: 0.25rem;
    }

    .meta-tag.platform {
        background: rgba(34, 197, 94, 0.2);
        color: #86efac;
    }

    .expanded-content {
        display: flex;
        align-items: center;
        gap: 0.5rem;
        flex-wrap: wrap;
        width: 100%;
        padding-top: 0.25rem;
        border-top: 1px solid rgba(75, 85, 99, 0.4);
    }

    .setting-row {
        display: flex;
        align-items: center;
        gap: 0.25rem;
    }

    .buttons-row {
        margin-left: auto;
    }

    .setting-label {
        font-size: 0.625rem;
        font-weight: 500;
        color: #9ca3af;
        text-transform: uppercase;
        letter-spacing: 0.025em;
    }

    .setting-input {
        background: #374151;
        border: 1px solid #4b5563;
        color: white;
        font-size: 0.625rem;
        border-radius: 0.25rem;
        padding: 0.125rem 0.375rem;
        width: 5rem;
    }

    .setting-input:focus {
        outline: none;
        border-color: #3b82f6;
    }

    .setting-btn {
        background: #2563eb;
        color: white;
        font-size: 0.625rem;
        font-weight: 500;
        padding: 0.125rem 0.375rem;
        border-radius: 0.25rem;
        border: none;
        cursor: pointer;
        transition: background 0.15s ease;
    }

    .setting-btn:hover {
        background: #1d4ed8;
    }

    .setting-checkbox {
        width: 0.875rem;
        height: 0.875rem;
        border-radius: 0.25rem;
        background: #374151;
        border: 1px solid #4b5563;
        cursor: pointer;
    }

    /* Mobile-specific styling */
    .sense-footer.mobile {
        padding: 0.375rem 0.5rem;
    }

    .sense-footer.mobile .sensor-icons {
        gap: 0.5rem;
    }

    .sense-footer.mobile .info-panel {
        max-height: 50vh;
        overflow-y: auto;
    }

    .sense-footer.mobile .sensor-grid {
        grid-template-columns: repeat(2, 1fr);
    }

    /* Mobile */
    @media (max-width: 640px) {
        .sense-footer {
            padding: 0.25rem;
        }

        .expanded-content {
            flex-direction: column;
            align-items: flex-start;
            gap: 0.375rem;
        }

        .buttons-row {
            margin-left: 0;
        }

        .info-hint {
            display: none;
        }

        .sensor-grid {
            grid-template-columns: 1fr 1fr;
        }
    }
</style>

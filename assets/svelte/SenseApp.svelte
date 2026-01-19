<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";
    import { Socket } from "phoenix";
    import { getCookie, setCookie } from "./utils.js";
    import SensorService from "./SenseApp/SensorService.svelte";
    import BluetoothClient from "./SenseApp/BluetoothClient.svelte";
    import IMUClient from "./SenseApp/IMUClient.svelte";
    import GeolocationClient from "./SenseApp/GeolocationClient.svelte";
    import BatterystatusClient from "./SenseApp/BatterystatusClient.svelte";
    import PushButtonClient from "./SenseApp/PushButtonClient.svelte";
    import RichPresenceClient from "./SenseApp/RichPresenceClient.svelte";
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
</script>

<SensorService bind:live bind:this={sensorService} {bearerToken}>
    <div class="sense-footer" class:expanded={footerExpanded}>
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
                <BluetoothClient compact={true} />
                <GeolocationClient compact={true} />
                <BatterystatusClient compact={true} />
                <IMUClient compact={true} />
                <RichPresenceClient compact={true} />
            </div>
        </div>

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
    }
</style>

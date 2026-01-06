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
    let deviceName = null;
    let inputDeviceName = "";
    let sensorService = null;

    // Track if initial load is complete to avoid saving cookie on mount
    let initialLoadComplete = false;

    autostart.subscribe((value) => {
        logger.log(loggerCtxName, "Autostart update", value, autostart);
        // Save to cookie whenever value changes (but not on initial load)
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

        //SensorService.setupChannel("test", { sensor_type: "test" });

        cookieAutostart = getCookie("autostart");
        logger.log(loggerCtxName, "Cookie autostart", cookieAutostart);
        autostart.set(cookieAutostart == "true");
        initialLoadComplete = true;

        usersettings.update((settings) => ({
            ...settings,
        }));
    });

    onDestroy(() => {
        console.log("Destroy SenseApp");
        socket.disconnect();
        // Cookie is now saved in the subscribe callback, no need to save here
    });
</script>

<SensorService bind:live bind:this={sensorService}>
    <!--<NetworkQualityMonitor />-->
    <div class="sense-app-container">
        <!-- Connector name input - compact on desktop -->
        <div class="connector-name-section">
            <label
                for="connector_name"
                class="text-xs font-medium text-amber-400 whitespace-nowrap"
                >Name</label
            >
            <div class="flex items-center gap-1">
                <input
                    type="text"
                    id="connector_name"
                    class="bg-gray-700 border border-gray-600 text-white text-xs rounded px-2 py-1 w-28 focus:ring-blue-500 focus:border-blue-500"
                    bind:value={inputDeviceName}
                    required
                />
                <button
                    class="bg-blue-600 hover:bg-blue-700 text-white text-xs px-2 py-1 rounded"
                    on:click={() => {
                        sensorService.setDeviceName(inputDeviceName);
                        deviceName = inputDeviceName;
                    }}>Save</button
                >
            </div>
        </div>

        <!-- Autostart toggle -->
        <div class="autostart-section flex items-center gap-2">
            <label
                for="autostart"
                class="text-xs font-medium text-amber-400 whitespace-nowrap"
                >Autostart</label
            >
            <input
                type="checkbox"
                bind:checked={$autostart}
                id="autostart"
                class="w-4 h-4 rounded bg-gray-700 border-gray-600 text-blue-600 focus:ring-blue-500"
            />
        </div>

        <!-- Sensor clients - inline on desktop -->
        <div class="sensor-clients">
            <BluetoothClient />
            <IMUClient />
            <GeolocationClient />
            <BatterystatusClient />
            <PushButtonClient />
            <RichPresenceClient />
        </div>
    </div>
</SensorService>

<style>
    .sense-app-container {
        display: flex;
        flex-direction: column;
        gap: 1rem;
    }

    .sensor-clients {
        display: flex;
        flex-direction: column;
        gap: 0.5rem;
    }

    /* Desktop: horizontal layout */
    @media (min-width: 640px) {
        .sense-app-container {
            flex-direction: row;
            align-items: center;
            gap: 1.5rem;
            flex-wrap: wrap;
        }

        .connector-name-section {
            display: flex;
            align-items: center;
            gap: 0.5rem;
        }

        .sensor-clients {
            flex-direction: row;
            align-items: center;
            gap: 1rem;
            flex-wrap: wrap;
        }
    }
</style>

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
    <div>
        <label
            for="first_name"
            class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >Connector name</label
        >
        <input
            type="text"
            id="connector_name"
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 block w-full p-2.5 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
            bind:value={inputDeviceName}
            required
        />
        <button
            class="btn btn-blue text-xs"
            on:click={() => {
                sensorService.setDeviceName(inputDeviceName);
                deviceName = inputDeviceName;
            }}>Save</button
        >
    </div>
    <div>
        <label
            for="autostart"
            class="block mb-2 text-sm font-medium text-gray-900 dark:text-white"
            >Autostart</label
        >
        <input
            type="checkbox"
            bind:checked={$autostart}
            id="autostart"
            class="bg-gray-50 border border-gray-300 text-gray-900 text-sm rounded-lg focus:ring-blue-500 focus:border-blue-500 dark:bg-gray-700 dark:border-gray-600 dark:placeholder-gray-400 dark:text-white dark:focus:ring-blue-500 dark:focus:border-blue-500"
        />
        <!--<strong>{$autostart}</strong>-->
    </div>
    <BluetoothClient />
    <div>
        <IMUClient />
        <GeolocationClient />
        <BatterystatusClient />
        <PushButtonClient />
    </div>
</SensorService>

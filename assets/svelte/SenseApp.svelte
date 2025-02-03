<script>
    import { onMount } from "svelte";
    import { Socket } from "phoenix";
    import SensorService from "./SenseApp/SensorService.svelte";
    import BluetoothClient from "./SenseApp/BluetoothClient.svelte";
    import IMUClient from "./SenseApp/IMUClient.svelte";
    import GeolocationClient from "./SenseApp/GeolocationClient.svelte";
    import BatterystatusClient from "./SenseApp/BatterystatusClient.svelte";
    import PushButtonClient from "./SenseApp/PushButtonClient.svelte";
    import NetworkQualityMonitor from "./SenseApp/NetworkQualityMonitor.svelte";

    import Map from "./GoogleMaps/Map.svelte";
    /*import Sparkline from "./Sparkline.svelte";

    let timeMode = "absolute";
    //let timeWindow = 5 * 60 * 1000; // 5 minutes in milliseconds

    let timeWindow = 0.5 * 60 * 1000;
*/
    /* const moreTestData = []; // create some more.
    for (let i = 0; i < 1000; i++) {
        moreTestData.push({
            timestamp: Date.now() - 60 * 1000 + i * 1000,
            value: Math.random() * 50,
        });
    }

    // Data for relative mode testing (small dataset)
    const relativeTestData = generateTestData(Date.now() - 10000, 200, 20, 50); // From 10 seconds back, every 200ms
    const relativeTestDataWithGap = [
        ...generateTestData(Date.now() - 20000, 200, 1000, 50), // Gap data after the first 10.
        ...generateTestData(Date.now() - 3000, 200, 1000, 50), // Gap data after 3 seconds
    ]; // Added gap after 7 seconds

    // Data for absolute mode testing with a time window
    const absoluteTestData = generateTestData(Date.now() - 60000, 1000, 60, 50); // Data for the last 60 seconds.

    const absoluteTestDataWithGap = [
        ...generateTestData(Date.now() - 60000, 1000, 30, 50), // Last 60 seconds
        ...generateTestData(Date.now() - 30000, 2000, 10, 50), // gap after 30 sec.
    ];

    // Create denser data.  useful for debugging scaling issues.
    const denserTestData = [];
    for (let i = 0; i < 100; i++) {
        denserTestData.push({
            timestamp: Date.now() - 20 * 1000 + i * 200,
            value: Math.random() * 70,
        });
    }

    const combinedTest = [
        ...generateTestData(Date.now() - 5000, 100, 10, 50), // Data in last 5 sec.
        ...generateTestData(Date.now() - 20000, 1000, 5, 50), // gap data (10-20 seconds ago)
        ...generateTestData(Date.now() - 60000, 300, 10, 50), // some data far back (about a minute ago)
    ];

    const largeTestData = []; // Test more large datasets
    for (let i = 0; i < 300; i++) {
        largeTestData.push({
            timestamp: Date.now() - i * 100,
            value: Math.random() * 70,
        });
    }

    const evenMoreData = [];
    for (let i = 0; i < 1000; i++) {
        evenMoreData.push({
            timestamp: Date.now() - i * 100,
            value: Math.random() * 70,
        });
    }

    const lastFewMinutes = [];
    for (let i = 0; i < 200; i++) {
        lastFewMinutes.push({
            timestamp: Date.now() - 10 * 60 * 1000 + i * 1000,
            value: Math.random() * 50,
        });
    }

    let sparklineData = relativeTestDataWithGap;
    */
    //import DbAnalyzerClient from './DbAnalyzerClient.svelte';

    export let live;

    let socket = null;
    // ... other variables

    onMount(() => {
        // Initialize socket connection here
        console.log("initialize socket in SenseApp", live);
        socket = new Socket("/socket", {
            params: { user_token: "some_token" },
        });
        socket.connect();
        console.log("connected to socket", socket);

        //SensorService.setupChannel("test", { sensor_type: "test" });
    });

    function generateTestData(startTime, interval, count, valueRange) {
        const data = [];
        for (let i = 0; i < count; i++) {
            data.push({
                timestamp: startTime + i * interval,
                value: Math.random() * valueRange,
            });
        }
        return data;
    }
</script>

<!--<Sparkline bind:data={sparklineData} {timeMode} {timeWindow} />-->
<!-- bind:data -->

<SensorService bind:socket>
    <NetworkQualityMonitor />
    <BluetoothClient />
    <IMUClient />
    <GeolocationClient />
    <BatterystatusClient />
    <PushButtonClient />
</SensorService>

<!--<Map></Map>-->

<!--<textarea style="color:black">{JSON.stringify(sparklineData, null, 4)}</textarea
>

<button
    on:click={() =>
        (timeMode = timeMode === "absolute" ? "relative" : "absolute")}
>
    Toggle Time Mode: {timeMode}
</button>
-->

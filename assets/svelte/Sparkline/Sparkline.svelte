<svelte:options customElement="sensocto-sparkline" />
<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
/>

<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    import Canvas from "./Canvas.svelte";
    import ScaledPoints from "./ScaledPoints.svelte";
    import Point from "./Point.svelte";

    const eventDispatcher = createEventDispatcher();

    export let id;
    export let sensor_id;
    export let is_loading = true;
    export let live;

    export let debugFlag = false;
    export let canvas;
    export let scaledPoints;

    export let test = [];

    export let width = 100;
    export let height = 50;
    export let data = [];
    export let appenddata;
    export let timeMode = "relative";
    export let timeWindow = 0.5 * 60 * 1000;
    export let yPadding = 0.2;
    export let maxlength;
    export let points = [];

    $: width = Math.floor(parseFloat(width));
    $: height = Math.floor(parseFloat(height));

    $: if (appenddata?.length) {
        console.log("Sparkline: appenddata ", appenddata, typeof appenddata);
        appenddata = JSON.parse(appenddata);
    }

    $: if (points?.length) {
        //canvas.$set({ points: points });
        console.log("Sparkline scaledPoints changed");
    }

    $: if (data?.length) {
        if (debugFlag)
            console.log(
                "Sparkline: data changed, redrawing sparkline...",
                data,
            );
    }

    $: if (scaledPoints?.points) {
        console.log("Sparkline scaledPoints changed");
    }

    onMount(() => {
        console.log("Sparkline: onMount", window.livesocket, live);
        eventDispatcher('my-custom-window-event', { someData: "This is my payload from onMount", moreData: 123456});
        //LiveSocket.pushEvent("request-seed", sensor_id);
    });

    const transformEventData = (data) => {
        let transformedData = [];

        if (data && Array.isArray(data)) {
            // Verify data format.
            data.forEach((item) => {
                // Loop through each item in the array.
                if (
                    typeof item === "object" &&
                    item !== null &&
                    item.timestamp &&
                    item.payload
                ) {
                    // Type checks
                    transformedData.push({
                        timestamp: item.timestamp,
                        value: item.payload.value,
                    });
                } else {
                    // Output error for any malformed data
                    console.warn(
                        "Sparkline: malformed data detected, skipping item",
                        item,
                    );
                }
            });

            return transformedData;
        } else {
            console.warn(
                "Sparkline: Invalid data format or data is missing:",
                data,
            );
        }
    };

    const handleStorageWorkerEvent = (e) => {
        //const {type, eventData} = e.detail;

        console.log(
            "Sparkline: handleStorageWorkerEvent",
            sensor_id,
            e.detail.type,
            e.detail.data,
        );

        if (sensor_id === e?.detail?.data.id) {
            if (e?.detail?.type == "append-read-data-result") {
                data = transformEventData(e.detail.data.result);
                console.log("Sparkline: Data transformed", data.length, id); // Log processed data.
                if (data.length > 1) is_loading = false;
            }

            if (e?.detail?.type == "updated-read-data") {
            }
        }
    };

    const handleAccumulatorEvent = (e) => {
        //console.log("Sparkline: handleAccumulatorEvent", sensor_id, e?.detail?.id, e);

        eventDispatcher('my-custom-window-event', { someData: "This is my payload", moreData: 123456});
        console.log(
            "Sparkline: handleAccumulatorEvent",
            sensor_id,
            e.detail.id,
        );

        if (sensor_id === e?.detail?.id) {
            if (true)
                console.log(
                    "Sparkline handleAccumulatorEvent",
                    "loading: " + is_loading,
                    typeof e.detail,
                    e.detail,
                );

            if (e?.detail?.data?.timestamp && e?.detail?.data?.value) {
                const requestType = is_loading
                    ? "append-read-data"
                    : "append-data";

                console.log(
                    "Going to request storage worker: ",
                    requestType,
                    e.detail,
                    window.workerStorage,
                );

                eventDispatcher("storage-request-event", {
                    type: requestType,
                    data: {
                        id: sensor_id,
                        payload: e?.detail?.data,
                        maxLength: maxlength,
                    },
                });

                /*
                window.workerStorage.postMessage({
                    type: requestType,
                    data: {
                        id: sensor_id,
                        payload: e.detail.data,
                        maxLength: maxlength,
                    },
                });*/
            } else {
                console.warn(
                    "Sparkline handleAccumulatorEvent",
                    "something wrong",
                    e,
                );
            }
        }
    };
</script>
<div {width} {height} style="text-align:center">
    {#if is_loading}
        <img
            {height}
            alt="loading spinner"
            src="https://raw.githubusercontent.com/n3r4zzurr0/svg-spinners/refs/heads/main/svg-css/12-dots-scale-rotate.svg"
        /> Waiting for data ...
    {:else}
        <ScaledPoints
            bind:this={scaledPoints}
            bind:data
            bind:scaledPoints={test}
            {width}
            {height}
            {timeMode}
            {timeWindow}
            {yPadding}
            {debugFlag}
        ></ScaledPoints>

        <Canvas
            bind:this={canvas}
            bind:points={test}
            {width}
            {height}
            {debugFlag}
        ></Canvas>
        {#if true}<p>
                Sparkline DATA: maxLength: {maxlength}
                {data.length} Points: {test.length}
            </p>{/if}
    {/if}
</div>

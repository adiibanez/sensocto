<svelte:options customElement="sensocto-sparkline" />

<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";
    import { logger } from "../logger.js";

    import Canvas from "./Canvas.svelte";
    import ScaledPoints from "./ScaledPoints.svelte";
    import Point from "./Point.svelte";

    const dispatch = createEventDispatcher();

    let loggerCtxName = "Sparkline";

    export let id;
    export let sensor_id;
    export let is_loading = true;
    export let live;

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
    export let sampling_rate = 1;

    $: width = Math.floor(parseFloat(width));
    $: height = Math.floor(parseFloat(height));

    $: if(width) {
        maxLength = Math.floor(width / sampling_rate);
        logger.log(loggerCtxName, "Changed maxLength to", maxLength, sampling_rate);
    }

    $: if (appenddata?.length) {
        logger.log(
            loggerCtxName,
            "Sparkline: appenddata ",
            appenddata,
            typeof appenddata,
        );
        appenddata = JSON.parse(appenddata);
    }

    $: if (points?.length) {
        //canvas.$set({ points: points });
        logger.log(loggerCtxName, "Sparkline scaledPoints changed");
    }

    $: if (data?.length) {
        logger.log(
            loggerCtxName,
            "Sparkline: data changed, redrawing sparkline...",
            data,
        );
    }

    $: if (scaledPoints?.points) {
        logger.log(loggerCtxName, "Sparkline scaledPoints changed");
    }

    onMount(() => {
        logger.log(
            loggerCtxName,
            "Sparkline: onMount",
            window.livesocket,
            live,
        );
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

        logger.log(
            loggerCtxName,
            "Sparkline: handleStorageWorkerEvent",
            sensor_id,
            e.detail.type,
            e.detail.data,
        );

        if (sensor_id === e?.detail?.data.id) {
            logger.log(
                loggerCtxName,
                "Sparkline: handleStorageWorkerEvent - data received",
                e.detail.type,
                e.detail.data,
            );

            if (e?.detail?.type == "append-read-data-result") {
                logger.log(loggerCtxName, "Sparkline: Before transformed", id); // Log processed data.
                data = transformEventData(e.detail.data.result);

                logger.log(
                    loggerCtxName,
                    "Sparkline: Data transformed",
                    data.length,
                    id,
                ); // Log processed data.
                if (data.length > 1) is_loading = false;
            } else if (e?.detail?.type == "append-data-result") {
                logger.log(loggerCtxName, "Sparkline: Before transformed", id); // Log processed data.
                data = transformEventData(e.detail.data.result);
            }

            if (e?.detail?.type == "updated-read-data") {
            }
        }
    };

    const handleAccumulatorEvent = (e) => {
        //logger.log(loggerCtxName, "Sparkline: handleAccumulatorEvent", sensor_id, e?.detail?.id, e);

        logger.log(
            loggerCtxName,
            "Sparkline: handleAccumulatorEvent",
            sensor_id,
            e.detail.id,
        );

        if (sensor_id === e?.detail?.id) {
            logger.log(
                loggerCtxName,
                "Sparkline handleAccumulatorEvent",
                "loading: " + is_loading,
                typeof e.detail,
                e.detail,
            );

            if (e?.detail?.data?.timestamp && e?.detail?.data?.value) {
                const requestType = is_loading
                    ? "append-read-data"
                    : "append-data";

                logger.log(
                    loggerCtxName,
                    "Going to request storage worker: ",
                    requestType,
                    e.detail,
                    window.workerStorage,
                );

                //const myCustomEvent = new CustomEvent("storage-request-event", {
                const myCustomEvent = new CustomEvent(
                    "worker-requesthandler-event",
                    {
                        detail: {
                            type: requestType,
                            data: {
                                id: sensor_id,
                                payload: e?.detail?.data,
                                maxLength: maxlength,
                            },
                        },
                    },
                ); // Send the timestamp as data.
                window.dispatchEvent(myCustomEvent); // Dispatch on window

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

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
/>
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
        ></ScaledPoints>

        <Canvas bind:this={canvas} bind:points={test} {width} {height}></Canvas>
        {#if false}<p>
                Sparkline DATA: maxLength: {maxlength}
                {data.length} Points: {test.length}
            </p>{/if}
    {/if}
</div>

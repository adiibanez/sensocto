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
    export let identifier;
    export let is_loading = true;
    export let live;

    export let canvas;
    $: scaledPoints = [];

    export let test = [];

    export let width = 100;
    export let height = 15;
    $: data = [];
    export let appenddata;
    export let timemode = "relative";
    export let timewindow;
    // 0.5 * 60 * 1000
    export let yPadding = 0.2;

    export let points = [];
    export let samplingrate = 1;
    let resolution;
    let minTimestamp;
    let maxTimestamp;

    //$: width = Math.floor(parseFloat(width));
    //$: height = Math.floor(parseFloat(height));

    $: isResizing = () => {
        isResizing = document.querySelector(`body.resizing`) != "undefined";
        return isResizing;
    };

    $: if (width) {
        if (timemode == "absolute") {
            if (data.length > width) {
                resolution = 1;
            } else {
                resolution = 5; //width / data.length;
            }
            resolution = 3;
            // width / maxsamples;
        } else {
            if (data.length > width) {
                resolution = timewindow / 1000 / width;
            } else {
                resolution = width / data.length;
            }
            // Math.max(1,Math.round( maxsamples / width, 2));
        }

        resolution = Math.floor(resolution);
    }

    $: maxsamples = calculatemaxsamples({
        width,
        samplingrate,
        timewindow,
        timemode,
    });

    $: if (appenddata?.length) {
        logger.log(loggerCtxName, "appenddata ", appenddata, typeof appenddata);
        appenddata = JSON.parse(appenddata);
    }

    $: if (points?.length) {
        //canvas.$set({ points: points });
        logger.log(loggerCtxName, "scaledPoints changed");
    }

    $: if (data?.length) {
        logger.log(
            loggerCtxName,
            "data changed, redrawing sparkline...",
            maxsamples,
            data?.length,
        );

        const timestamps = data.map((point) => point.timestamp);
        minTimestamp = Math.min(...timestamps);
        maxTimestamp = Math.max(...timestamps);
    }

    $: if (scaledPoints?.points) {
        logger.log(loggerCtxName, "scaledPoints changed");
    }

    onMount(() => {
        logger.log(loggerCtxName, "onMount", window.livesocket, live);
        //LiveSocket.pushEvent("request-seed", identifier);

        if (timewindow == undefined) {
            timewindow = 0.5 * 60 * 1000;
        }
    });

    const transformStorageEventData = (data) => {
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
                        payload: item.payload.payload,
                    });
                } else {
                    // Output error for any malformed data
                    console.warn(
                        "malformed data detected, skipping item",
                        item,
                    );
                }
            });

            return transformedData;
        } else {
            console.warn("Invalid data format or data is missing:", data);
        }
    };

    const handleStorageWorkerEvent = (e) => {
        //const {type, eventData} = e.detail;
        if (identifier === e?.detail?.data.id) {
            logger.log(
                loggerCtxName,
                "handleStorageWorkerEvent",
                identifier,
                e?.detail?.type,
                e?.detail?.data?.length,
            );

            if (e?.detail?.type == "append-read-data-result") {
                newData = transformStorageEventData(e.detail.data.result);
                data = [];
                data = [...newData];

                logger.log(
                    loggerCtxName,
                    "handleStorageWorkerEvent: Data transformed",
                    data?.length,
                    id,
                ); // Log processed data.
                if (data?.length > 1) is_loading = false;
            } else if (e?.detail?.type == "append-data-result") {
                // TODO: clarify event handler
                data.push(e.detail.data.result.payload);
                logger.log(
                    loggerCtxName,
                    "handleStorageWorkerEvent: append-data-result. Nothing to do",
                    data,
                ); // Log processed data.
                //data = transformEventData(e.detail.data.result);
            } else {
                logger.log(
                    loggerCtxName,
                    "handleStorageWorkerEvent: Unknown storage event",
                    identifier,
                    e.detail,
                ); // Log processed data.
            }
        }
    };

    const handleSeedDataEvent = (e) => {
        console.log("Here", e?.detail?.data?.length);
        if (
            identifier ==
                e?.detail?.sensor_id + "_" + e?.detail?.attribute_id &&
            e?.detail?.data?.length > 0
        ) {
            logger.log(
                loggerCtxName,
                "handleSeedDataEvent",
                identifier,
                e?.detail?.data?.length,
                data?.length,
            );

            //let newData = e?.detail?.data;

            if (Array.isArray(e?.detail?.data) && e?.detail?.data?.length > 0) {
                let newData = e.detail.data;
                //test.slice(-maxsamples);
                console.log("Here2 ", test, maxsamples);
                //newData = newData.slice(-maxsamples);
                data = [];
                newData?.forEach((item) => {
                    data = [...data, item];
                });
            } else {
                logger.log(
                    loggerCtxName,
                    "handleSeedDataEvent",
                    "No data",
                    e?.detail,
                );
            }

            is_loading = false;
        }
    };

    const handleAccumulatorEvent = (e) => {
        console.log("Here", e?.detail?.id, identifier);
        if (identifier === e?.detail?.id) {
            logger.log(
                loggerCtxName,
                "handleAccumulatorEvent",
                "loading: " + is_loading,
                typeof e.detail,
                e.detail,
                e?.detail?.data,
                e?.detail?.data?.timestamp,
                e?.detail?.data?.payload,
            );

            if (e?.detail?.data?.timestamp && e?.detail?.data?.payload) {
                logger.log(
                    loggerCtxName,
                    "handleAccumulatorEvent",
                    identifier,
                    e.detail.data,
                    data?.length,
                );

                data = [...data.slice(-maxsamples), e.detail.data];
            }
        }
    };

    function calculatemaxsamples({
        width,
        samplingrate,
        timewindow,
        timemode,
    }) {
        if (!width || !samplingrate) {
            return 0; // Handle cases with missing information.
        }

        let maxsamples;

        /*if(width < 300) {
            timewindow = Math.min(2000, timewindow);
        }*/

        if (timemode === "absolute" && timewindow) {
            const timewindowInSeconds = timewindow / 1000; // Convert to seconds.
            maxsamples = Math.max(
                1,
                Math.floor(timewindowInSeconds * samplingrate * width),
            ); // calculate based on provided window and rate.
        } else {
            // relative or no time window.
            //maxsamples = Math.max(1, Math.floor(width / resolution)); // Compute based on width, and also using a base resolution value.

            maxsamples = width * samplingrate * (timewindow / 1000);
        }

        //maxsamples = ((timewindow / 1000) * width) / samplingrate;

        logger.log(
            loggerCtxName,
            "maxsamples:  width:",
            width,
            ", samplingrate:",
            samplingrate,
            ", timewindow:",
            timewindow,
            ", result:",
            maxsamples,
        );
        return maxsamples;
    }
</script>

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
    on:seeddata-event={handleSeedDataEvent}
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
            {timemode}
            {timewindow}
            {yPadding}
            {maxsamples}
            {isResizing}
            {resolution}
        ></ScaledPoints>

        <Canvas
            bind:this={canvas}
            bind:points={test}
            {width}
            {height}
            {isResizing}
        ></Canvas>

        <p>
            {new Date(minTimestamp).toLocaleTimeString("ch-DE")} - {new Date(
                maxTimestamp,
            ).toLocaleTimeString("ch-DE")}
        </p>
        {#if true}
            <p>
                Sparkline: width: {width} maxsamples: {maxsamples} timewindow: {timewindow}
                timemode:{timemode} samplingrate: {samplingrate}

                data: {data?.length} Points: {test?.length} Resolution: {resolution}

                {JSON.stringify(data)}
            </p>{/if}
    {/if}
</div>

<!--<svelte:options customElement="sensocto-sparkline-wasm-svelte" />-->

<script>
    // https://dustinpfister.github.io/2020/03/10/canvas-drag/
    import { onMount, onDestroy, tick } from "svelte";
    import { logger } from "./logger_svelte.js";
    import { Socket } from "phoenix";
    import {
        processStorageWorkerEvent,
        processAccumulatorEvent,
        processSeedDataEvent,
    } from "./services-sensor-data.js";

    import { writable } from "svelte/store";

    let wasmInitialized = false;

    export let id;
    export let live;
    export let width = 30;
    export let height = 30;
    export let sensor_id;
    export let attribute_id;
    export let samplingrate;
    export let timewindow;
    export let timemode;
    export let style;
    export let minvalue;
    export let maxvalue;
    let maxsamples = 1000;
    // export let initialParams;

    let loggerCtxName = "SparklineWasm";

    let canvas;
    let ctx;
    let isVisible = false;
    let observer;

    $: cntElement = document.getElementById(id);
    let cntElementOffsetWidth;
    let availableSize;

    let dataStore = writable([]);
    $: data = $dataStore;

    function checkSparklineWasm() {
        if (typeof window?.draw_sparkline == "function") {
            logger.log(
                loggerCtxName,
                "draw_sparkline found",
                window.draw_sparkline,
            );
            wasmInitialized = true;
        } else {
            logger.log(loggerCtxName, "draw_sparkline NOT found");
        }
    }

    onMount(() => {
        checkSparklineWasm();
        ctx = canvas.getContext("2d");
        logger.log(loggerCtxName, "onMount", sensor_id, attribute_id);

        const handleAccumulatorEvent = (e) => {
            logger.log(
                loggerCtxName,
                "handleAccumulatorEvent",
                sensor_id,
                attribute_id,
                e,
            );
            if (
                sensor_id == e?.detail?.sensor_id &&
                attribute_id == e?.detail?.attribute_id
            ) {
                logger.log(
                    loggerCtxName,
                    "handleAccumulatorEvent",
                    sensor_id,
                    attribute_id,
                    e?.detail,
                );
                processAccumulatorEvent(dataStore, sensor_id, attribute_id, e);
            }
        };

        const handleStorageWorkerEvent = (e) => {
            logger.log(
                loggerCtxName,
                "handleStorageWorkerEvent",
                e?.detail?.data?.sensor_id,
                e?.detail?.data?.attribute_id,
                e?.detail?.data?.result?.length,
                e,
            );
            if (
                sensor_id == e?.detail?.data?.sensor_id &&
                attribute_id == e?.detail?.data?.attribute_id
            ) {
                logger.log(
                    loggerCtxName,
                    "handleStorageWorkerEvent",
                    sensor_id,
                    attribute_id,
                    e?.detail,
                );
                processStorageWorkerEvent(
                    dataStore,
                    sensor_id,
                    attribute_id,
                    e,
                );
            }
        };
        const handleSeedDataEvent = (e) => {
            logger.log(
                loggerCtxName,
                "handleSeedDataEvent",
                sensor_id,
                attribute_id,
                e,
            );
            if (
                sensor_id == e?.detail?.sensor_id &&
                attribute_id == e?.detail?.attribute_id
            ) {
                logger.log(
                    loggerCtxName,
                    "handleSeedDataEvent",
                    sensor_id,
                    attribute_id,
                    e?.detail,
                );
                processSeedDataEvent(dataStore, sensor_id, attribute_id, e);
            }
        };

        window.addEventListener("resize", handleResizeEnd);
        window.addEventListener("resizeend", handleResizeEnd);
        window.addEventListener(
            "accumulator-data-event",
            handleAccumulatorEvent,
        );
        window.addEventListener(
            "storage-worker-event",
            handleStorageWorkerEvent,
        );
        window.addEventListener("seeddata-event", handleSeedDataEvent);
        window.addEventListener("resize", getAvailableSize);

        observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    isVisible = entry.isIntersecting;
                    if (isVisible) {
                        render();
                    }
                });
            },
            { threshold: 0.1 },
        );

        observer.observe(canvas);
        availableSize = getAvailableSize();
        width = availableSize.w;

        logger.log(loggerCtxName, "onMount", availableSize, width);
        render();

        return () => {
            window.removeEventListener("resizeend", handleResizeEnd);
            window.removeEventListener(
                "accumulator-data-event",
                handleAccumulatorEvent,
            );
            window.removeEventListener(
                "storage-worker-event",
                handleStorageWorkerEvent,
            );
            window.removeEventListener("seeddata-event", handleSeedDataEvent);
            window.removeEventListener("resize", handleResizeEnd);
            if (observer) {
                observer.unobserve(canvas);
            }
        };
    });

    $: if (data?.length && wasmInitialized) {
        tick().then(() => {
            if (isVisible) {
                logger.log(
                    loggerCtxName,
                    "data changed, redrawing sparkline...",
                    data?.length,
                );
                if (data.length == 0) {
                    return;
                }
                const timestamps = data.map((point) => point.timestamp);
                let minTimestamp = Math.min(...timestamps);
                let maxTimestamp = Math.max(...timestamps);
                render();
            }
        });
    }

    function render(timestamp) {
        if (wasmInitialized == false || !isVisible) {
            return;
        }
        logger.log(
            loggerCtxName,
            "Js args",
            //data.slice(-maxsamples),
            width,
            height,
            "#ffc107",
            1,
            20,
            2000,
            100,
            "relative",
            false,
            minvalue,
            maxvalue,
        );
        window.draw_sparkline(
            data.slice(-maxsamples),
            width,
            height,
            ctx,
            "#ffc107",
            1,
            20,
            2000,
            100,
            "relative",
            false,
            minvalue != 0 ? minvalue : undefined,
            maxvalue != 0 ? maxvalue : undefined,
        );
    }
    const handleResizeEnd = (e) => {
        cntElement = document.getElementById(id);
        availableSize = getAvailableSize();

        if (isVisible) {
            logger.log(loggerCtxName, "handleResizeEnd", e);
            render();
        }
    };
    //$: maxsamples = (timewindow / 1000) * samplingrate * width;
    $: if (timewindow && width && samplingrate) {
        maxsamples = (timewindow / 1000) * samplingrate * width;
    }

    $: if (availableSize) {
        availableSize = getAvailableSize();
        width = availableSize.w;

        logger.log(
            loggerCtxName,
            "Change in cntElement offsetWidth",
            availableSize,
        );
    }

    const getAvailableSize = () => {
        const element = document.getElementById(id);
        const computedStyle = getComputedStyle(element);

        // Get padding and margin values
        const paddingLeft = parseFloat(computedStyle.paddingLeft) || 0;
        const paddingRight = parseFloat(computedStyle.paddingRight) || 0;
        const paddingTop = parseFloat(computedStyle.paddingTop) || 0;
        const paddingBottom = parseFloat(computedStyle.paddingBottom) || 0;

        const marginLeft = parseFloat(computedStyle.marginLeft) || 0;
        const marginRight = parseFloat(computedStyle.marginRight) || 0;
        const marginTop = parseFloat(computedStyle.marginTop) || 0;
        const marginBottom = parseFloat(computedStyle.marginBottom) || 0;

        // Calculate the inner width and height by subtracting padding and margins.
        const elementWidth =
            element.offsetWidth -
            paddingLeft -
            paddingRight -
            marginLeft -
            marginRight;
        const elementHeight =
            element.offsetHeight -
            paddingTop -
            paddingBottom -
            marginTop -
            marginBottom;

        // Calculate the available with based on padding and margin
        const availableWidth = elementWidth;
        const availableHeight = elementHeight;

        return { w: availableWidth, h: availableHeight };
    };
</script>

<canvas class="resizeable_" bind:this={canvas} {width} {height}></canvas>

{#if true}
    <div class="text-xs">
        <!--Data points {data.length}, maxsamples: {maxsamples}, width: {width}-->
        width: {width} height: {height} timewindow: {timewindow}
        <!--<pre>{JSON.stringify(data, null, 2)}</pre>-->

        test: {id}
        {JSON.stringify(availableSize)}

        cntOffsetWidth: {cntElement?.offsetWidth}
    </div>
{/if}

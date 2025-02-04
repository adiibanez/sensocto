<svelte:options customElement="sensocto-sparkline-wasm-svelte" />

<script>
    import { onMount, onDestroy, tick } from "svelte";
    import { logger } from "../logger_svelte.js";
    import {
        processStorageWorkerEvent,
        processAccumulatorEvent,
        processSeedDataEvent,
    } from "../services-sensor-data.js";

    import { writable } from "svelte/store";

    import init, { draw_sparkline } from "../../js/wasm_sparkline.js";

    let wasmInitialized = false;

    export let id;

    export let width;
    export let height = 30;
    export let sensor_id;
    export let attribute_id;
    export let samplingrate;
    export let timewindow;
    export let timemode;
    export let style;
    export let minvalue;
    export let maxvalue;
    // export let initialParams;

    let loggerCtxName = "SparklineWasm";

    let canvas;
    let ctx;
    let isVisible = false;
    let observer;

    let dataStore = writable([]);
    $: data = $dataStore;

    async function initWasm() {
        await init("/assets/wasm_sparkline_bg.wasm");
        wasmInitialized = true;
        logger.log(loggerCtxName, "Wasm initialized, yippie", draw_sparkline);
    }

    onMount(() => {
        initWasm();
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
        // logger.log(
        //     loggerCtxName,
        //     "Js args",
        //     data.slice(-maxsamples),
        //     width,
        //     height,
        //     "#ffc107",
        //     1,
        //     20,
        //     2000,
        //     100,
        //     "relative",
        //     false,
        //     minvalue,
        //     maxvalue,
        // );
        draw_sparkline(
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
        if (isVisible) {
            logger.log(loggerCtxName, "handleResizeEnd", e);
            render();
        }
    };
    //$: maxsamples = (timewindow / 1000) * samplingrate * width;
    $: if (timewindow && width && samplingrate) {
        maxsamples = (timewindow / 1000) * samplingrate * width;
    }
</script>

<canvas class="resizeable" bind:this={canvas} {width} {height}></canvas>

{#if false}
    <div class="text-xs hidden">
        <!--Data points {data.length}, maxsamples: {maxsamples}, width: {width}-->
        width: {width} height: {height} timewindow: {timewindow}
        <!--<pre>{JSON.stringify(data, null, 2)}</pre>-->
    </div>
{/if}

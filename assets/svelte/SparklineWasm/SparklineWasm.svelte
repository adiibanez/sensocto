<svelte:options customElement="sensocto-sparkline-wasm-svelte" />

<script>
    import { onMount, onDestroy, tick } from "svelte";
    import { logger } from "../logger.js";
    import {
        processStorageWorkerEvent,
        processAccumulatorEvent,
        processSeedDataEvent,
    } from "../services-sensor-data.js";

    import { writable } from "svelte/store";

    import init, { draw_sparkline } from "../../js/wasm_sparkline.js";

    let wasmInitialized = false;

    export let is_loading;
    export let id;
    export let width;
    export let height = 30;
    export let identifier;
    export let samplingrate;
    export let timewindow;
    export let timemode;
    export let minvalue;
    export let maxvalue;
    export let initialParams;

    let loggerCtxName = "SparklineWasm";

    let canvas;
    let ctx;

    let dataStore = writable([]);
    $: data = $dataStore;

    // $: console.log("Data changed", data);

    async function initWasm() {
        await init("/assets/wasm_sparkline_bg.wasm");
        wasmInitialized = true;
        console.log("Wasm initialized, yippie", draw_sparkline);
    }

    onMount(() => {
        initWasm();
        ctx = canvas.getContext("2d");
        console.log("onMount");
        const handleAccumulatorEvent = (e) => {
            if (identifier == e.detail.id) {
                logger.log(
                    loggerCtxName,
                    "handleAccumulatorEvent",
                    identifier,
                    e?.detail?.id,
                );
                processAccumulatorEvent(dataStore, identifier, e);
            }
        };
        const handleStorageWorkerEvent = (e) => {
            if (identifier == e?.detail?.data?.id) {
                logger.log(
                    loggerCtxName,
                    "handleStorageWorkerEvent",
                    identifier,
                    e?.detail?.data?.id,
                );
                processStorageWorkerEvent(dataStore, identifier, e);
            }
        };
        const handleSeedDataEvent = (e) => {
            if (
                identifier ==
                e?.detail?.sensor_id + "_" + e?.detail?.attribute_id
            ) {
                logger.log(
                    loggerCtxName,
                    "handleSeedDataEvent",
                    identifier,
                    e?.detail?.sensor_id + "_" + e?.detail?.attribute_id,
                );
                processSeedDataEvent(dataStore, identifier, e);
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
        };
    });

    $: if (data?.length && wasmInitialized) {
        // console.log("data inside data check", data);
        tick().then(() => {
            // logger.log(
            //     loggerCtxName,
            //     "data changed, redrawing sparkline...",
            //     maxsamples,
            //     data?.length,
            // );
            // console.log("data before timestamps", data);
            if (data.length == 0) {
                return;
            }
            const timestamps = data.map((point) => point.timestamp);
            let minTimestamp = Math.min(...timestamps);
            let maxTimestamp = Math.max(...timestamps);
            render();
        });
    }

    function render(timestamp) {
        if (wasmInitialized == false) {
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
        //     null,
        //     null,
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
            null,
            null,
        );
    }

    const handleResizeEnd = (e) => {
        logger.log(loggerCtxName, "handleResizeEnd", e);
        render();
    };

    $: maxsamples = (timewindow / 1000) * samplingrate * width;
</script>

<canvas class="resizeable" bind:this={canvas} {width} {height}></canvas>

{#if false}
    <p class="text-xs hidden">
        Data points {data.length}, maxsamples: {maxsamples}, width: {width}
    </p>
{/if}

<svelte:options customElement="sensocto-sparkline-wasm-svelte" />

<script>
    import { onMount, onDestroy, tick } from "svelte";
    import { logger } from "../logger.js";
    import { getSensorDataStore } from "../services-sensor-data.js";
    import { derived } from "svelte/store";

    import init, {
        draw_sparkline,
    } from "../../../../wasm-sparkline/pkg-new/wasm_sparkline.js";

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

    let derivedDataStore;
    $: data = $derivedDataStore ? $derivedDataStore : [];

    $: console.log("Derived Datastore changed", $derivedDataStore);
    $: console.log("Data changed", data);

    async function initWasm() {
        await init("/assets/wasm_sparkline_bg.wasm");
        wasmInitialized = true;
        console.log("Wasm initialized, yippie", draw_sparkline);
    }

    onMount(() => {
        const dataStore = getSensorDataStore(identifier);
        console.log("dataStore initial", dataStore);
        if (!dataStore) {
            console.error("dataStore is null", identifier);
        }

        derivedDataStore = derived(dataStore, ($dataStore) => {
            return $dataStore;
        });
        console.log("dataStore is", dataStore);

        initWasm();
        ctx = canvas.getContext("2d");
        console.log("onMount");
    });

    $: if (data?.length && wasmInitialized) {
        console.log("data inside data check", data);
        tick().then(() => {
            logger.log(
                loggerCtxName,
                "data changed, redrawing sparkline...",
                maxsamples,
                data?.length,
            );
            console.log("data before timestamps", data);
            if (data.length == 0) {
                return;
            }
            const timestamps = data.map((point) => point.timestamp);
            let minTimestamp = Math.min(...timestamps);
            let maxTimestamp = Math.max(...timestamps);
            render();
        });
    }
    $: {
        console.log("Data changed:", data);
    }

    function render(timestamp) {
        if (wasmInitialized == false) {
            return;
        }

        logger.log(
            loggerCtxName,
            "Js args",
            data.slice(-maxsamples),
            width,
            height,
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

    $: maxsamples = (timeWindow / 1000) * samplingrate * width;
</script>

<canvas class="resizeable" bind:this={canvas} {width} {height}></canvas>
<p class="text-xs">
    Data points {data.length}, maxsamples: {maxsamples}, width: {width}
</p>

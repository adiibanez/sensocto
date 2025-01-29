<svelte:options customElement="sensocto-sparkline-wasm-svelte" />

<script>
    import { onMount } from "svelte";
    import { logger } from "../logger.js";
    import { sensorDataService } from "../services-sensor-data.js";
    import { get } from "svelte/store";

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
    //let data = [];

    let dataStore;
    $: data = $dataStore ? $dataStore : [];

    let params = { ...initialParams };
    let isVisible = false;
    let observer;

    let lineColor = "#ffc107";
    let lineWidth = 1;
    let smoothing = 20;
    let timeWindow = 2000;
    let burstThreshold = 100;
    let maxValue = null; //200;
    let minValue = null; //1;

    let operationMode = "relative";
    let drawScales = false;

    $: maxsamples = (timeWindow / 1000) * samplingrate * width; //canvas?.width || 500;

    async function initWasm() {
        //await init();
        await init("/assets/wasm_sparkline_bg.wasm");
        wasmInitialized = true;
        console.log("Wasm initialized, yippie", draw_sparkline);
    }

    onMount(() => {
        ctx = canvas.getContext("2d");

        initWasm();

        console.log("onMount");

        dataStore = sensorDataService.getSensorDataStore(identifier);
        console.log("dataStore", dataStore);

        observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    isVisible = entry.isIntersecting;
                    if (isVisible) {
                        render();
                        //requestAnimationFrame(render);
                    }
                });
            },
            { threshold: 0.1 },
        );

        observer.observe(canvas);

        //data = generateSampleDataBackInTime(10000);
    });

    $: if (data?.length && wasmInitialized) {
        logger.log(
            loggerCtxName,
            "data changed, redrawing sparkline...",
            maxsamples,
            data?.length,
        );

        const timestamps = data.map((point) => point.timestamp);
        minTimestamp = Math.min(...timestamps);
        maxTimestamp = Math.max(...timestamps);

        render();
    }

    $: if (dataStore && wasmInitialized) {
        logger.log(
            loggerCtxName,
            "dataStore changed, redrawing sparkline...",
            maxsamples,
            data?.length,
        );

        const timestamps = data.map((point) => point.timestamp);
        minTimestamp = Math.min(...timestamps);
        maxTimestamp = Math.max(...timestamps);

        render();
    }

    function handleInput(event) {
        const { target } = event;
        params[target.name] =
            target.type === "checkbox" ? target.checked : target.value;
    }

    let lastTime = 0;
    function render(timestamp) {
        if (wasmInitialized == false || !isVisible) {
            return;
            // requestAnimationFrame(render);
        }

        logger.log(
            loggerCtxName,
            "Js args",
            data.slice(-maxsamples),
            width,
            height,
            //ctx,
            lineColor,
            parseFloat(lineWidth),
            parseInt(smoothing),
            parseFloat(timeWindow),
            parseFloat(burstThreshold),
            operationMode,
            drawScales,
            minValue,
            maxValue,
        );

        draw_sparkline(
            data.slice(-maxsamples),
            width,
            height,
            ctx,
            lineColor,
            parseFloat(lineWidth),
            parseInt(smoothing),
            parseFloat(timeWindow),
            parseFloat(burstThreshold),
            operationMode,
            drawScales,
            minValue,
            maxValue,
        );
        //requestAnimationFrame(render);
    }

    function generateSampleDataBackInTime(timeWindowMs, sampleRate = 20) {
        const now = Date.now();
        const startTime = now - timeWindowMs; // Calculate the start of the window
        const dataPoints = [];
        let currentTime = now;

        while (currentTime > startTime) {
            const noise = (Math.random() - 0.5) * 2;
            const nextValue = Math.sin(currentTime / 1000) * 10 + 20 + noise; // Generate a new value using the current time
            dataPoints.push({ timestamp: currentTime, payload: nextValue }); // Add the new data point to array.

            //console.log(currentTime, nextValue);

            currentTime = currentTime - 1000 / (sampleRate * 5); // Move the current time a little bit backward (simulating the sampling rate)
        }

        return dataPoints;
    }

    const handleStorageWorkerEvent = (e) => {
        //const {type, eventData} = e.detail;
        if (identifier === e?.detail?.data.id) {
            sensorDataService.processStorageWorkerEvent(identifier, e);
        }
    };

    const handleSeedDataEvent = (e) => {
        if (
            identifier ==
            e?.detail?.sensor_id + "_" + e?.detail?.attribute_id
        ) {
            sensorDataService.processSeedDataEvent(identifier, e);
            is_loading = false;
        }
    };

    const handleAccumulatorEvent = (e) => {
        if (identifier === e?.detail?.id) {
            sensorDataService.processAccumulatorEvent(identifier, e);
        }
    };

    const handleResizeEnd = (e) => {
        logger.log(loggerCtxName, "handleResizeEnd", e);
        render();
    };
</script>

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
    on:seeddata-event={handleSeedDataEvent}
    on:resizeend={handleResizeEnd}
/>

<canvas class="resizeable" bind:this={canvas} {width} {height}></canvas>
<p class="text-xs">
    Data points {data.length}, maxsamples: {maxsamples}, width: {width}
</p>
{#if false}<div>
        <label>line color:</label><input
            name="lineColor"
            value={lineColor}
            on:input={handleInput}
        /><br />
        <label>line width:</label><input
            name="lineWidth"
            type="number"
            value={lineWidth}
            on:input={handleInput}
        /><br />
        <label>smoothing:</label><input
            name="smoothing"
            type="number"
            value={smoothing}
            on:input={handleInput}
        /><br />
        <label>Time window:</label><input
            name="timeWindow"
            type="number"
            value={timeWindow}
            on:input={handleInput}
        /><br />
        <label>Burst treshold:</label><input
            name="burstThreshold"
            type="number"
            value={burstThreshold}
            on:input={handleInput}
        /><br />
        <label>Min Value:</label><input
            name="minValue"
            type="number"
            value={minValue}
            on:input={handleInput}
        /><br />
        <label>Max Value:</label><input
            name="maxValue"
            type="number"
            value={maxValue}
            on:input={handleInput}
        /><br />
        <label>Operation Mode:</label>
        <select
            name="operationMode"
            value={operationMode}
            on:input={handleInput}
        >
            <option value="absolute">Absolute</option>
            <option value="relative">Relative</option>
        </select>
        <br />
        <label>Draw scales:</label>
        <input
            type="checkbox"
            name="drawScales"
            checked={drawScales}
            on:input={handleInput}
        />
    </div>
{/if}

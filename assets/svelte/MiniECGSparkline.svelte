<script>
    import { onMount, onDestroy, tick } from "svelte";
    import { writable } from "svelte/store";
    import { logger } from "./logger_svelte.js";
    import {
        processAccumulatorEvent,
        processSeedDataEvent,
    } from "./services-sensor-data.js";

    let loggerCtxName = "MiniECGSparkline";

    export let id;
    export let sensor_id;
    export let attribute_id;
    export let width = 80;
    export let height = 20;
    export let color = "#22c55e";
    export let backgroundColor = "transparent";
    export let samplingrate = 100;
    export let timewindow = 3000;
    export let showBackpressure = true;
    export let attentionLevel = "medium";
    export let batchWindow = 500;

    let canvas;
    let ctx;
    let isVisible = true;
    let observer;
    let currentAttention = attentionLevel;
    let currentBatchWindow = batchWindow;

    let dataStore = writable([]);
    $: data = $dataStore;

    $: maxSamples = Math.round((timewindow / 1000) * samplingrate);

    const minValue = -0.5;
    const maxValue = 2.0;

    const attentionColors = {
        high: "#22c55e",
        medium: "#eab308",
        low: "#f97316",
        none: "#6b7280"
    };

    const attentionLabels = {
        high: "H",
        medium: "M",
        low: "L",
        none: "-"
    };

    onMount(() => {
        ctx = canvas.getContext("2d");
        logger.log(loggerCtxName, "onMount", sensor_id, attribute_id);

        const handleAccumulatorEvent = (e) => {
            if (
                sensor_id == e?.detail?.sensor_id &&
                attribute_id == e?.detail?.attribute_id
            ) {
                processAccumulatorEvent(dataStore, sensor_id, attribute_id, e);
                if (e?.detail?.metadata) {
                    currentAttention = e.detail.metadata.attention_level || currentAttention;
                    currentBatchWindow = e.detail.metadata.batch_window || currentBatchWindow;
                }
            }
        };

        const handleSeedDataEvent = (e) => {
            if (
                sensor_id == e?.detail?.sensor_id &&
                attribute_id == e?.detail?.attribute_id
            ) {
                processSeedDataEvent(dataStore, sensor_id, attribute_id, e);
            }
        };

        const handleAttentionChange = (e) => {
            if (sensor_id == e?.detail?.sensor_id) {
                currentAttention = e.detail.attention_level || currentAttention;
                currentBatchWindow = e.detail.batch_window || currentBatchWindow;
                if (isVisible) render();
            }
        };

        window.addEventListener("accumulator-data-event", handleAccumulatorEvent);
        window.addEventListener("seeddata-event", handleSeedDataEvent);
        window.addEventListener("attention-change", handleAttentionChange);

        observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    isVisible = entry.isIntersecting;
                    if (isVisible && data.length > 0) {
                        render();
                    }
                });
            },
            { threshold: 0.1 }
        );

        observer.observe(canvas);

        return () => {
            window.removeEventListener("accumulator-data-event", handleAccumulatorEvent);
            window.removeEventListener("seeddata-event", handleSeedDataEvent);
            window.removeEventListener("attention-change", handleAttentionChange);
            if (observer) {
                observer.unobserve(canvas);
            }
        };
    });

    $: if (data?.length && isVisible) {
        tick().then(() => {
            render();
        });
    }

    function render() {
        if (!canvas || !ctx || data.length < 2) {
            return;
        }

        const drawData = data.slice(-maxSamples);
        const canvasWidth = canvas.width;
        const canvasHeight = canvas.height;

        ctx.clearRect(0, 0, canvasWidth, canvasHeight);

        if (backgroundColor !== "transparent") {
            ctx.fillStyle = backgroundColor;
            ctx.fillRect(0, 0, canvasWidth, canvasHeight);
        }

        const values = drawData.map((point) => point.payload);
        const timestamps = drawData.map((point) => point.timestamp);
        const range = maxValue - minValue;

        const minTimestamp = Math.min(...timestamps);
        const maxTimestamp = Math.max(...timestamps);
        const timeRange = maxTimestamp - minTimestamp;

        if (timeRange === 0) return;

        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 1;

        drawData.forEach((point, index) => {
            const normalizedValue = range === 0 ? 0.5 : (point.payload - minValue) / range;
            const y = canvasHeight - (normalizedValue * canvasHeight);
            const x = ((point.timestamp - minTimestamp) / timeRange) * canvasWidth;

            if (index === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });

        ctx.stroke();

        if (showBackpressure && batchWindow > 0) {
            const attentionColors = {
                high: "#22c55e",
                medium: "#eab308",
                low: "#f97316",
                none: "#6b7280"
            };

            ctx.fillStyle = attentionColors[attentionLevel] || attentionColors.none;
            ctx.fillRect(canvasWidth - 3, 0, 3, canvasHeight);
        }
    }
</script>

<span class="inline-flex items-center gap-0.5" style="vertical-align: middle;">
    <canvas
        bind:this={canvas}
        {width}
        {height}
        class="inline-block"
        style="vertical-align: middle;"
    ></canvas>
    {#if showBackpressure}
        <span
            class="inline-flex items-center justify-center text-[8px] font-bold rounded-sm"
            style="background-color: {attentionColors[currentAttention] || attentionColors.none}; color: black; width: 12px; height: 12px; vertical-align: middle;"
            title="Attention: {currentAttention}, Batch: {currentBatchWindow}ms"
        >
            {attentionLabels[currentAttention] || "-"}
        </span>
    {/if}
</span>

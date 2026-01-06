<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
        tick,
    } from "svelte";
    import { logger } from "./logger_svelte.js";
    let loggerCtxName = "PressureVisualization";

    import {
        processStorageWorkerEvent,
        processAccumulatorEvent,
        processSeedDataEvent,
    } from "./services-sensor-data.js";

    import { writable } from "svelte/store";

    export let id;
    export let sensor_id;
    export let attribute_id;

    export let timewindow = 60;
    export let width = 200;
    export let height = 100;
    export let color = "#8b5cf6";
    export let backgroundColor = "transparent";
    export let samplingrate = 1;
    export let highlighted_areas = [];

    let isVisible = false;
    let observer;

    let dataStore = writable([]);
    $: data = $dataStore;

    $: cntElement = document.getElementById(id);
    let cntElementOffsetWidth;
    let availableSize;

    let chartDimensions = calculateChartDimensions(timewindow, samplingrate, width);

    $: if (width && timewindow && samplingrate) {
        chartDimensions = calculateChartDimensions(timewindow, samplingrate, width);
    }

    $: keepsamples = 2000 / chartDimensions.dynamicResolution;

    export let minValue = 950;
    export let maxValue = 1050;

    let canvas;
    let ctx;

    $: if (canvas && data) {
        render(canvas, data, color, backgroundColor, highlighted_areas);
    }

    onMount(() => {
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
        window.addEventListener("resize", getAvailableSize);

        window.addEventListener(
            "accumulator-data-event",
            handleAccumulatorEvent,
        );
        window.addEventListener(
            "storage-worker-event",
            handleStorageWorkerEvent,
        );
        window.addEventListener("seeddata-event", handleSeedDataEvent);

        canvas.addEventListener("mousedown", handleMouseDown);

        observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    isVisible = entry.isIntersecting;
                    if (isVisible) {
                        render(
                            canvas,
                            data,
                            color,
                            backgroundColor,
                            highlighted_areas,
                        );
                    }
                });
            },
            { threshold: 0.1 },
        );

        availableSize = getAvailableSize();
        width = availableSize.w;
        observer.observe(canvas);

        return () => {
            window.removeEventListener("resizeend", handleResizeEnd);

            canvas.removeEventListener("mousedown", handleMouseDown);
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

    $: if (data?.length) {
        tick().then(() => {
            if (isVisible) {
                logger.log(
                    loggerCtxName,
                    "data changed, redrawing sparkline...",
                    chartDimensions.maxSamples,
                    data?.length,
                );
                if (data.length == 0) {
                    return;
                }
                const timestamps = data.map((point) => point.timestamp);
                let minTimestamp = Math.min(...timestamps);
                let maxTimestamp = Math.max(...timestamps);
                render(canvas, data, color, backgroundColor, highlighted_areas);
            }
        });
    }

    function calculateChartDimensions(
        timewindow,
        samplingRate,
        width,
        options = {},
    ) {
        const minHeight = options.minHeight || 30;
        const maxHeight = options.maxHeight || 200;
        const fixedAspectRatio = options.fixedAspectRatio || 0.5;
        const minResolution = options.minResolution || 1;

        const totalDataPoints = Math.round(timewindow * samplingRate);
        let dynamicResolution = width / totalDataPoints;
        dynamicResolution = Math.max(minResolution, dynamicResolution);

        const requiredHorizontalPixels = totalDataPoints * dynamicResolution;
        const desiredHeight = width * fixedAspectRatio;

        const height = Math.max(
            Math.min(Math.round(desiredHeight), maxHeight),
            minHeight,
        );

        const pixelsPerSecond = samplingRate * dynamicResolution;
        const maxSamples = Math.round(width / dynamicResolution);

        return {
            totalDataPoints: totalDataPoints,
            requiredHorizontalPixels: requiredHorizontalPixels,
            dynamicResolution: dynamicResolution,
            height: height,
            pixelsPerSecond: pixelsPerSecond,
            maxSamples: maxSamples,
        };
    }

    function render(canvas, data, color, backgroundColor, highlighted_areas) {
        if (!canvas || !data || data.length < 2) {
            return;
        }

        const drawData = data.slice(-chartDimensions.maxSamples);

        const ctx = canvas.getContext("2d");
        const canvasWidth = canvas.width;
        const canvasHeight = canvas.height;

        const values = drawData.map((point) => {
            const payload = point.payload;
            return typeof payload === 'object' && payload !== null ? payload.value : payload;
        });
        const timestamps = drawData.map((point) => point.timestamp);

        const dataMin = Math.min(...values);
        const dataMax = Math.max(...values);
        const dynamicMinValue = Math.min(minValue, dataMin - 5);
        const dynamicMaxValue = Math.max(maxValue, dataMax + 5);
        const range = dynamicMaxValue - dynamicMinValue;
        const padding = 40;

        ctx.fillStyle = backgroundColor;
        ctx.save();
        ctx.clearRect(0, 0, canvasWidth, canvasHeight);

        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.moveTo(padding, canvasHeight - padding);
        ctx.lineTo(canvasWidth - padding, canvasHeight - padding);
        ctx.stroke();

        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.moveTo(padding, canvasHeight - padding);
        ctx.lineTo(padding, padding);
        ctx.stroke();

        ctx.font = "10px sans-serif";

        ctx.fillStyle = color;
        ctx.fillText(`${dynamicMaxValue.toFixed(0)} hPa`, 0, padding + 5);

        ctx.fillStyle = color;
        ctx.fillText(`${dynamicMinValue.toFixed(0)} hPa`, 0, canvasHeight - padding);

        ctx.fillStyle = color;
        const minTimestamp = Math.min(...timestamps);
        const maxTimestamp = Math.max(...timestamps);
        ctx.fillText("Time", canvasWidth - (padding + 20), canvasHeight - 5);

        const midValue = (dynamicMinValue + dynamicMaxValue) / 2;
        ctx.fillStyle = "#6b7280";
        ctx.fillText(`${midValue.toFixed(0)}`, 0, canvasHeight / 2);

        ctx.beginPath();
        ctx.strokeStyle = "#374151";
        ctx.setLineDash([2, 2]);
        const midY = canvasHeight / 2;
        ctx.moveTo(padding, midY);
        ctx.lineTo(canvasWidth - padding, midY);
        ctx.stroke();
        ctx.setLineDash([]);

        if (drawData.length > 0) ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 2;

        drawData.forEach((point, index) => {
            const payload = point.payload;
            const value = typeof payload === 'object' && payload !== null ? payload.value : payload;
            let normalizedValue =
                range == 0 ? 1 : (value - dynamicMinValue) / range;
            let y =
                canvasHeight -
                (normalizedValue * (canvasHeight - padding * 2) + padding);

            let x =
                ((point.timestamp - minTimestamp) /
                    (maxTimestamp - minTimestamp)) *
                    (canvasWidth - padding * 2) +
                padding;

            if (index === 0) {
                ctx.moveTo(x, y);
            } else {
                ctx.lineTo(x, y);
            }
        });
        ctx.stroke();
        ctx.restore();
    }

    let isDragging = false;
    let startX;
    let initialTimewindow;

    function handleMouseDown(event) {
        isDragging = true;
        startX = event.clientX;
        initialTimewindow = timewindow;
        document.addEventListener("mousemove", handleMouseMove);
        document.addEventListener("mouseup", handleMouseUp);
    }

    function handleMouseMove(event) {
        if (isDragging) {
            const deltaX = event.clientX - startX;

            timewindow = Math.max(10, initialTimewindow + deltaX);

            console.log(
                "handle canvas drag ",
                timewindow,
                initialTimewindow,
                deltaX,
            );

            render();
        }
    }

    function handleMouseUp() {
        isDragging = false;
        document.removeEventListener("mousemove", handleMouseMove);
        document.removeEventListener("mouseup", handleMouseUp);
    }

    const handleResizeEnd = (e) => {
        cntElement = document.getElementById(id);
        availableSize = getAvailableSize();

        if (isVisible) {
            logger.log(loggerCtxName, "handleResizeEnd", e);
            render(canvas, data, color, backgroundColor, highlighted_areas);
        }
    };

    const getAvailableSize = () => {
        const element = document.getElementById(id);
        if (!element) return { w: width, h: height };

        const computedStyle = getComputedStyle(element);

        const paddingLeft = parseFloat(computedStyle.paddingLeft) || 0;
        const paddingRight = parseFloat(computedStyle.paddingRight) || 0;
        const paddingTop = parseFloat(computedStyle.paddingTop) || 0;
        const paddingBottom = parseFloat(computedStyle.paddingBottom) || 0;

        const marginLeft = parseFloat(computedStyle.marginLeft) || 0;
        const marginRight = parseFloat(computedStyle.marginRight) || 0;
        const marginTop = parseFloat(computedStyle.marginTop) || 0;
        const marginBottom = parseFloat(computedStyle.marginBottom) || 0;

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

        const availableWidth = elementWidth;
        const availableHeight = elementHeight;

        return { w: availableWidth, h: availableHeight };
    };
</script>

<div style="width:{width}px;height:{height}px; position: relative">
    <canvas bind:this={canvas} {width} {height}></canvas>
    <p class="text-xs hidden">
        Pressure {JSON.stringify(chartDimensions)}, data: {data.length} minValue: {minValue}
        maxValue: {maxValue} width: {width} height: {height} tw: {timewindow}
    </p>
</div>

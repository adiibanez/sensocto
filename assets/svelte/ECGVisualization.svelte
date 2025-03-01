<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
        tick,
    } from "svelte";
    import { logger } from "./logger_svelte.js";
    let loggerCtxName = "ECGVisualization";

    import {
        processStorageWorkerEvent,
        processAccumulatorEvent,
        processSeedDataEvent,
    } from "./services-sensor-data.js";

    import { writable } from "svelte/store";

    export let id;
    export let sensor_id;
    export let attribute_id;

    export let timewindow = 10;
    export let width = 200;
    export let height = 100;
    export let color;
    export let backgroundColor = "transparent";
    export let samplingrate;
    export let highlighted_areas = [];

    let isVisible = false;
    let observer;

    let dataStore = writable([]);
    $: data = $dataStore;

    $: cntElement = document.getElementById(id);
    let cntElementOffsetWidth;
    let availableSize;

    let ecgDimensions = calculateEcgDimensions(timewindow, samplingrate, width);

    $: if (width && timewindow && samplingrate) {
        ecgDimensions = calculateEcgDimensions(timewindow, samplingrate, width);
    }

    // make sure we can resize chart to larger window
    $: keepsamples = 2000 / ecgDimensions.dynamicResolution;

    export let minValue = -1.0;
    export let maxValue = 2;

    let canvas;

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
                    ecgDimensions.maxSamples,
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

    function calculateEcgDimensions(
        timewindow,
        samplingRate,
        width,
        options = {},
    ) {
        const minHeight = options.minHeight || 30;
        const maxHeight = options.maxHeight || 200;
        const fixedAspectRatio = options.fixedAspectRatio || 1;
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

        const drawData = data.slice(-ecgDimensions.maxSamples);

        const ctx = canvas.getContext("2d");
        const canvasWidth = canvas.width;
        const canvasHeight = canvas.height;
        const values = drawData.map((point) => point.payload);
        const timestamps = drawData.map((point) => point.timestamp);

        //minValue = Math.min(...values);
        //maxValue = Math.max(...values);
        const range = maxValue - minValue;
        const padding = 20;

        ctx.fillStyle = backgroundColor;
        //ctx.fillRect(0, 0, canvasWidth, canvasHeight);
        ctx.save();
        ctx.clearRect(0, 0, canvasWidth, canvasHeight); // Start with clearing.

        // Draw x axis line
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.moveTo(padding, canvasHeight - padding);
        ctx.lineTo(canvasWidth - padding, canvasHeight - padding);
        ctx.stroke();

        //Draw y axis line
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.moveTo(padding, canvasHeight - padding);
        ctx.lineTo(padding, padding);
        ctx.stroke();

        // Add time and voltage scales (for visual reference)
        ctx.font = "10px sans-serif";

        // Draw a text for the Y axis
        ctx.fillStyle = color;
        ctx.fillText(`${maxValue.toFixed(1)} mV`, 0, padding + 5);

        ctx.fillStyle = color;
        ctx.fillText(`${minValue.toFixed(1)} mV`, 0, canvasHeight - padding);

        // Draw a text for the X axis
        ctx.fillStyle = color;
        const minTimestamp = Math.min(...timestamps);
        const maxTimestamp = Math.max(...timestamps);
        ctx.fillText("Time", canvasWidth - (padding + 20), canvasHeight - 5);

        // Draw highlighted areas

        // for (const area of highlighted_areas) {
        //     const start_x =
        //         (area.start / maxsamples) * (canvasWidth - padding * 2) +
        //         padding;
        //     const end_x =
        //         (area.end / maxsamples) * (canvasWidth - padding * 2) +
        //         padding;
        //     ctx.fillStyle = area.color;
        //     ctx.fillRect(
        //         start_x,
        //         padding,
        //         end_x - start_x,
        //         canvasHeight - padding * 2,
        //     );
        // }

        if (drawData.length > 0) ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 1;

        drawData.forEach((point, index) => {
            let normalizedValue =
                range == 0 ? 1 : (point.payload - minValue) / range;
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

            /*logger.log(
                loggerCtxName,
                "render",
                x,
                y,
                point.payload,
                point.timestamp,
            );*/
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

            timewindow = Math.max(1000, initialTimewindow + deltaX * 100);

            console.log(
                "handle canvas drag ",
                timewindow,
                initialTimewindow,
                deltaX,
            );

            //width = initialWidth + deltaX;

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

<div style="width:{width}px;height:{height}px; position: relative">
    <canvas bind:this={canvas} {width} {height} />
    <p class="text-xs hidden">
        ECG {JSON.stringify(ecgDimensions)}, data: {data.length} minValue: {minValue}
        maxValue: {maxValue} width: {width} height: {height} tw: {timewindow}
    </p>
</div>

<!--<svelte:options customElement="sensocto-sparkline-wasm-svelte" />-->

<script lang="ts">
    import { run } from "svelte/legacy";

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

    let wasmInitialized = $state(false);

    interface Props {
        id: any;
        live: any;
        width?: number;
        height?: number;
        sensor_id: any;
        attribute_id: any;
        samplingrate: any;
        timewindow: any;
        timemode: any;
        style: any;
        minvalue: any;
        maxvalue: any;
    }

    let {
        id,
        live,
        width = $bindable(30),
        height = 30,
        sensor_id,
        attribute_id,
        samplingrate,
        timewindow = $bindable(),
        timemode,
        style,
        minvalue,
        maxvalue,
    }: Props = $props();
    let maxsamples = $state(1000);
    // export let initialParams;

    let loggerCtxName = "SparklineWasm";

    let canvas = $state();
    let ctx;
    let isVisible = $state(false);
    let observer;

    let cntElementOffsetWidth;
    let availableSize = $state();

    let dataStore = writable([]);

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
                render();
            }
        };

        canvas.addEventListener("mousedown", handleMouseDown);

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
            canvas.removeEventListener("mousedown", handleMouseDown);

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
    let cntElement = $state();
    run(() => {
        cntElement = document.getElementById(id);
    });
    let data = $derived($dataStore);
    run(() => {
        if (data?.length && wasmInitialized) {
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
    });
    run(() => {
        if (availableSize) {
            availableSize = getAvailableSize();
            width = availableSize.w;

            logger.log(
                loggerCtxName,
                "Change in cntElement offsetWidth",
                availableSize,
            );
        }
    });
    //$: maxsamples = (timewindow / 1000) * samplingrate * width;
    run(() => {
        if (timewindow && width && samplingrate) {
            maxsamples = (timewindow / 1000) * samplingrate * width;
        }
    });
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

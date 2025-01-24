<svelte:options customElement="sensocto-ecg-visualization" />

<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";
    import { logger } from "../logger.js";

    let loggerCtxName = "ECGVisualization";

    export let width = 200;
    export let height = 100;
    export let color;
    export let backgroundColor = "transparent";
    export let data = [];
    export let samplingrate = 1000;
    export let highlighted_areas = [];
    let maxsamples = samplingrate * 10;

    export let sensor_id;
    export let is_loading;

    let canvasElement;

    function drawEcg(canvas, data, color, backgroundColor, highlighted_areas) {
        if (!canvas || !data || data.length < 2) {
            return;
        }

        const ctx = canvas.getContext("2d");
        const canvasWidth = canvas.width;
        const canvasHeight = canvas.height;
        const values = data.map((point) => point.payload);
        const timestamps = data.map((point) => point.timestamp);

        const minValue = Math.min(...values);
        const maxValue = Math.max(...values);
        const range = maxValue - minValue;
        const padding = 20;

        ctx.fillStyle = backgroundColor;
        //ctx.fillRect(0, 0, canvasWidth, canvasHeight);
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

        for (const area of highlighted_areas) {
            const start_x =
                (area.start / maxsamples) * (canvasWidth - padding * 2) +
                padding;
            const end_x =
                (area.end / maxsamples) * (canvasWidth - padding * 2) +
                padding;
            ctx.fillStyle = area.color;
            ctx.fillRect(
                start_x,
                padding,
                end_x - start_x,
                canvasHeight - padding * 2,
            );
        }
        
       if(data.length > 0)
        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = 1;

       data.forEach((point, index) => {

         let normalizedValue = range == 0 ? 1 : (point.payload - minValue) / range
          let y =
            canvasHeight -
            (normalizedValue * (canvasHeight - padding * 2) + padding);

         let x =
             (point.timestamp - minTimestamp) / (maxTimestamp-minTimestamp) *
               (canvasWidth - padding * 2) +
              padding;

            if (index === 0) {
              ctx.moveTo(x, y);
            } else {
               ctx.lineTo(x, y);
            }

            logger.log(loggerCtxName, "drawEcg", x, y, point.payload, point.timestamp);
        });
        ctx.stroke();
    }

    $: if (canvasElement && data) {
        drawEcg(
            canvasElement,
            data,
            color,
            backgroundColor,
            highlighted_areas,
        );
    }

    const handleStorageWorkerEvent = (e) => {
        //const {type, eventData} = e.detail;
        if (sensor_id === e?.detail?.data.id) {
            logger.log(
                loggerCtxName,
                "handleStorageWorkerEvent",
                sensor_id,
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
                    sensor_id,
                    e.detail,
                ); // Log processed data.
            }
        }
    };

    const handleSeedDataEvent = (e) => {
        if (sensor_id == e?.detail?.sensor_id) {
            logger.log(
                loggerCtxName,
                "handleSeedDataEvent",
                sensor_id,
                e?.detail?.sensor_id,
                e?.detail?.data?.length,
                data?.length,
            );

            newData = e.detail.data;
            //newData = newData.slice(-maxsamples);
            data = [];
            newData.forEach((item) => {
                data = [...data, item];
            });

            is_loading = false;
        }
    };

    const handleAccumulatorEvent = (e) => {
        if (sensor_id === e?.detail?.id) {
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
                    sensor_id,
                    e.detail.data,
                    data?.length,
                );

                data = [...data.slice(-maxsamples), e.detail.data];
            }
        }
    };
</script>

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
    on:seeddata-event={handleSeedDataEvent}
/>
ECG
<div style="width:{width}px;height:{height}px; position: relative">
    <canvas bind:this={canvasElement} {width} {height} />
</div>
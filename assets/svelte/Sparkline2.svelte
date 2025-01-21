<svelte:options customElement="sparkline-element" />

<script>
    import { onMount } from "svelte";
    export let data = [];
    export let width = 200;
    export let height = 50;
    export let color = "#ffc107";
    export let lineWidth = 2;
    export let id = "sparkline";
    export let yPadding = 0.1; // 10% padding on top and bottom
    export let debug = false;

    let lastDraw = Date.now();
    let animationReqId = null;
    let isDrawing = false ;// $props(false);

    $: width = parseFloat(width) || 100;
    $: height = parseFloat(height) || 30;
    $: lineWidth = parseFloat(lineWidth) || 2;

    //$: data = JSON.parse(data) || [];

    let canvas, canvas2;
    let ctx, ctx2;

    $: if (canvas && data?.length) {
        if (debug)
            console.log("Sparkline2: data changed, redrawing sparkline...", id);
        ctx = canvas.getContext("2d");
        //ctx2 = canvas2.getContext("2d");
        if (ctx) {
            drawSparkline();
        }
    }

    onMount(() => {
        // Log the mounting.
        if (debug)
            console.log(
                "Sparkline2: onMount method is being triggered",
                id,
                canvas,
                canvas.parentElement,
            );

        if (typeof window !== "undefined") {
            // Only add event listener if in browser
            /*canvas.parentElement.addEventListener(
                "update-sparkline-data",
                handleDataUpdate,
            );*/
        }
        ctx2 = canvas2.getContext("2d");
        animationReqId = requestAnimationFrame(drawFrame);
    });

    function handleDataUpdate(event) {
        const newData = event.detail; // Get data from custom event.
        if (debug)
            console.log(
                "Sparkline2: Event 'data-update' received:",
                id,
                newData,
            );
        if (false && newData && Array.isArray(newData)) {
            // validate
            data = newData; // Update the data, that will trigger update of calculations, and redrawing
        }
    }

    const drawSparkline = () => {
        if (!ctx || !data?.length) {
            if (debug)
                console.log(
                    "Sparkline2: No context or data, skipping draw...",
                    id,
                );
            return; // Stop if no data or context is available.
        }

        if (typeof data === "string") {
            if (debug)
                console.log("Sparkline2: Data is a string, parsing...", id);
            data = JSON.parse(data);
        }

        if (debug)
            console.log(
                "Sparkline2: Drawing the data...",
                id,
                JSON.stringify(data),
            );

        isDrawing = true;

        ctx.clearRect(0, 0, width, height);
        ctx.beginPath(); // Start new path.
        ctx.strokeStyle = color;
        ctx.lineWidth = lineWidth;

        let minValue = Math.min(...data.map((d) => d.value));
        let maxValue = Math.max(...data.map((d) => d.value));

        // Calculate vertical padding:
        const verticalPadding = height * yPadding;

        // Adjust min/max for padding:
        const paddedMinValue = minValue - minValue * yPadding * 2;
        const paddedMaxValue = maxValue + maxValue * yPadding * 2;
        const valueRange = paddedMaxValue - paddedMinValue || 1; // Handle zero range

        const yScale = (height - 2 * verticalPadding) / valueRange;

        if (debug) {
            ctx.fillStyle = "#bbb";
            ctx.font = "10px Arial";
            ctx.fillText(`minValue: ${minValue.toFixed(2)}`, 10, 10);
            ctx.fillText(`maxValue: ${maxValue.toFixed(2)}`, 10, 25);
        }

        let x = 0;

        for (let i = 0; i < data.length; i++) {
            const item = data[i];

            if (
                typeof item !== "object" ||
                item === null ||
                !("value" in item)
            ) {
                console.error(
                    "Sparkline2: Invalid data point format detected",
                    item,
                    id,
                );
                continue;
            }

            const y = Math.floor(
                height -
                    (item.value - paddedMinValue) * yScale -
                    verticalPadding,
            ); // Correct y-coordinate calculation with padding
            if (i === 0) {
                ctx.moveTo(x, y); // move to first point.
            } else {
                ctx.lineTo(x, y); // Only use lineTo for other points, to prevent line at height/2
            }
            x += Math.floor(width / data.length);

            if (debug)
                console.log(
                    `Sparkline2:  x: ${x.toFixed(2)}, y: ${y.toFixed(2)}`,
                    id,
                );
        }
        ctx.stroke(); // draw the line.
        //ctx2.drawImage(ctx);
        isDrawing = false;
    };

    function drawFrame() {
        // Called to draw in the real canvas
        let elapsed = Date.now() - lastDraw;

        //console.log("check cancelAnimationFrame", elapsed, animationReqId, isDrawing, ctx2);
        if (isDrawing || elapsed < 1000) {
            //console.log("abort rendering", elapsed, animationReqId);
            cancelAnimationFrame(animationReqId);
        } else {
            //if (debug) console.log("Sparkline2: drawFrame");
            if (ctx2 && canvas2) {
                if (debug) console.log("Sparkline2: drawFrame");
                                ctx2.clearRect(0, 0, width, height);
                ctx2.save();
                ctx2.clearRect(0, 0, width, height);
                //ctx2.fillRect(0, 0, width, height);
                ctx2.drawImage(canvas, 0, 0, width, height);
                lastDraw = Date.now();
            }
        }

        animationReqId = requestAnimationFrame(drawFrame);
    }
</script>

<div {width} {height} on:dataupdate={handleDataUpdate}>
    <canvas {width} {height} style="display:none" bind:this={canvas}></canvas>
    <canvas
        style="background-color: transparent; display:block"
        {width}
        {height}
        bind:this={canvas2}
    ></canvas>
</div>

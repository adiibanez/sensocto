<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    import { logger } from "../logger.js";
    let loggerCtxName = 'Canvas';

    export let width = 300;
    export let height = 300;
    export let color = "#ffc107";

    export let drawingColor = "#ccc";
    export let drawingLineWidth = 2;

    export let background = "transparent";
    export let lineWidth = 2;

    export let points = [];

    export let isResizing = false;

    let canvas;
    let context;
    let isDrawing;
    let start;

    let renderId;
    export let lastRender;
    export let elapsed;

    let t, l;

    onMount(() => {
        context = canvas.getContext("2d");
        context.lineWidth = 3;

        handleSize();

        logger.log(loggerCtxName, "Canvas: onMount", points);
    });

    $: if (context) {
        context.strokeStyle = color;
    }

    $: if (points?.length) {
        logger.log(loggerCtxName, "Canvas points changed", points.length);
        // renderId = requestAnimationFrame(drawCanvas);
        drawCanvas();
        lastRender = Date.now();
    }

    /*$: if(typeof lastRender === "number" && lastRender > 0) {
        elapsed = Date.now() - lastRender;
        logger.log(loggerCtxName, "calculate elapsed", elapsed, lastRender, Date.now());
    }*/

    function drawCanvasRequestAnimationFrame() {
        // Draw using new data
        if (!context || !points?.length) {
            // validation
            logger.log(loggerCtxName, "CanvasLayer: No context or data to draw", id);
            return;
        }

        elapsed = Date.now() - lastRender;

        if (elapsed < 100) {
            logger.log(loggerCtxName, "Canvas abort rendering", elapsed, renderId);
            cancelAnimationFrame(renderId);
        } else {
            logger.log(loggerCtxName, "Canvas rendering", elapsed, renderId);
            context.save();
            context.clearRect(0, 0, width, height); // Start with clearing.
            context.strokeStyle = color; // set color
            context.lineWidth = lineWidth; // set line width
            context.beginPath(); // Begin path

            if (points.length > 0) {
                context.moveTo(points[0].x, points[0].y); // start at first point.

                for (let i = 1; i < points.length; i++) {
                    // iterate every other point to create a continuous path
                    context.lineTo(points[i].x, points[i].y); // draw line to current point.
                }
            }
            context.stroke(); // stroke the path.
            context.restore();
        }

        renderId = requestAnimationFrame(drawCanvas);
    }

    function drawCanvas() {

        if(document.querySelector(`body.resizing`) != undefined) {
            logger.log(loggerCtxName, "CanvasLayer: isResizing");
            return;
        }

        if (isDrawing === true) return;
        // Draw using new data
        if (!context || !points?.length) {
            // validation
            logger.log(loggerCtxName, "CanvasLayer: No context or data to draw");
            return;
        }

        // freeze canvas
        context.save();

        
        context.clearRect(0, 0, width, height); // Start with clearing.
        //context.rect(20, 20, 150, 100);
        //context.stroke();

        context.strokeStyle = color; // set color
        context.lineWidth = lineWidth; // set line width
        context.beginPath(); // Begin path

        if (points.length > 0) {
            context.moveTo(points[0].x, points[0].y); // start at first point.

            for (let i = 1; i < points.length; i++) {
                // iterate every other point to create a continuous path
                context.lineTo(points[i].x, points[i].y); // draw line to current point.
            }
        }
        context.stroke(); // stroke the path.

        // restore canvas
        context.restore();
        logger.log(loggerCtxName, 
            "CanvasLayer: Drawing",
            lastRender,
            Date.now(),
            Date.now() - lastRender,
        );
        lastRender = Date.now();
    }

    const handleStart = ({ offsetX: x, offsetY: y }) => {
        if (color === background) {
            context.clearRect(0, 0, width, height);
        } else {
            isDrawing = true;
            start = { x, y };
        }
    };

    const handleEnd = () => {
        isDrawing = false;
    };
    const handleMove = ({ offsetX: x1, offsetY: y1 }) => {
        if (!isDrawing) return;

        const { x, y } = start;
        context.strokeStyle = drawingColor; // set color
        context.lineWidth = drawingLineWidth; // set line width

        context.beginPath();
        context.moveTo(x, y);
        context.lineTo(x1, y1);
        context.closePath();
        context.stroke();

        start = { x: x1, y: y1 };
    };

    const handleSize = () => {
        const { top, left } = canvas.getBoundingClientRect();
        t = top;
        l = left;
    };
</script>

<svelte:window on:resize={handleSize} />

<canvas
    {width}
    {height}
    style:background
    bind:this={canvas}
    on:mousedown={handleStart}
    on:touchstart={(e) => {
        const { clientX, clientY } = e.touches[0];
        handleStart({
            offsetX: clientX - l,
            offsetY: clientY - t,
        });
    }}
    on:mouseup={handleEnd}
    on:touchend={handleEnd}
    on:mouseleave={handleEnd}
    on:mousemove={handleMove}
    on:touchmove={(e) => {
        const { clientX, clientY } = e.touches[0];
        handleMove({
            offsetX: clientX - l,
            offsetY: clientY - t,
        });
    }}
></canvas>
{#if false}<p {elapsed}>
        Canvas: {points.length}, width: {width}, height: {height}, elapsed: {elapsed}
        {lastRender}
    </p>{/if}

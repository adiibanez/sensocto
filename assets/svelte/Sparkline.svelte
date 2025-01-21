<script>
    import { onMount, afterUpdate } from "svelte";

    export let data = [];
    export let width = 100;
    export let height = 50;
    export let color = "#ffc107";
    export let lineWidth = 2;
    export let timeMode = "relative";
    export let timeWindow = null;
    export let debug = false;
    export let id = "sparkline";

    $: width = parseFloat(width) || 100;
    $: height = parseFloat(height) || 30;

    let canvas;
    let ctx;
    let minValue, maxValue, xScale, yScale;
    let minTimestamp;

    // Calculate minTimestamp reactively, handling empty data
    $: minTimestamp =
        timeMode === "absolute" && timeWindow
            ? Date.now() - timeWindow
            : data?.length > 0
              ? Math.min(...data.map((item) => item.timestamp))
              : 0;

    function setupCanvas() {
        if (canvas) {
            if (debug)
                console.log(
                    "Sparkline: Canvas mounted, getting context...",
                    id,
                );
            ctx = canvas.getContext("2d");

            if (data?.length) calculateScales();
        }
    }

    onMount(setupCanvas);
    afterUpdate(() => {
        if (data?.length && ctx) {
            if (debug)
                console.log(
                    "Sparkline: Component updated. Calling drawSparkline()",
                    id,
                );
            drawSparkline();
        }
    });

    function calculateScales() {
        if (!data?.length) {
            if (debug)
                console.log("Sparkline: No data to calculate scales for", id);
            return;
        }

        minValue = Math.min(...data.map((item) => item.value));
        maxValue = Math.max(...data.map((item) => item.value));

        const yRange = maxValue - minValue;

        yScale = height / (yRange || 1);

        if (timeMode === "relative") {
            const relativeTimestamps = data.map(
                (item) => item.timestamp - data[0]?.timestamp,
            );
            const maxRelativeTimestamp = Math.max(...relativeTimestamps);
            xScale = width / (maxRelativeTimestamp || 1);
        } else {
            const timeRange =
                timeWindow ||
                Math.max(...data.map((item) => item.timestamp)) - minTimestamp;
            xScale = width / (timeRange || 1);
        }

        if (debug) {
            console.log("Sparkline: Data:", data, id);
            console.log("Sparkline: Width:", width, typeof width, id);
            console.log("Sparkline: Height:", height, typeof height, id);
            console.log("Sparkline: Context:", ctx, id);
            console.log(
                "Sparkline: xScale:",
                xScale,
                "yScale:",
                yScale,
                "minValue:",
                minValue,
                "maxValue:",
                maxValue,
                id,
            );
        }
    }

    const drawSparkline = () => {
        if (!ctx || !data?.length) {
            console.log("Sparkline: No context or data, skipping draw...", id);
            return;
        }

        console.log("Sparkline: Drawing the data...", id);
        ctx.clearRect(0, 0, width, height);

        ctx.beginPath();
        ctx.strokeStyle = color;
        ctx.lineWidth = lineWidth;
        let prevX = 0;
        let firstPointDrawn = false;

        for (let index = 0; index < data.length; index++) {
            const item = data[index];

            if (
                typeof item !== "object" ||
                item === null ||
                !("timestamp" in item) ||
                !("value" in item)
            ) {
                console.error(
                    "Sparkline: Invalid data point format detected",
                    item,
                    id,
                );
                continue;
            }
            if (
                timeMode === "absolute" &&
                timeWindow &&
                item.timestamp < minTimestamp
            ) {
                console.log(
                    "Sparkline: skipping because outside time window",
                    item,
                    id,
                );
                continue;
            }

            let x;
            if (timeMode === "relative") {
                x = (item.timestamp - data[0]?.timestamp) * xScale;
            } else {
                x = (item.timestamp - minTimestamp) * xScale;
            }

            const y = height - (item.value - minValue) * yScale;

            if (!firstPointDrawn || Math.abs(x - prevX) > 2) {
                ctx.stroke(); // draw prev path.
                ctx.beginPath(); // Create a new path
                ctx.moveTo(x, y); // Move to current point.
                firstPointDrawn = true;
            } else {
                ctx.lineTo(x, y); // Add a new segment to current path
            }
            prevX = x;
            console.log(
                `Sparkline:  x: ${x.toFixed(2)}, y: ${y.toFixed(2)}`,
                id,
            );
        }

        ctx.stroke(); // Draw the entire path.
    };
</script>

<canvas bind:this={canvas} {width} {height}></canvas>
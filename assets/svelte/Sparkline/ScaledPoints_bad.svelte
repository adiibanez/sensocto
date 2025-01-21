<script>
    import { onDestroy, onMount } from "svelte";

    export let data = [];
    export let width = 100;
    export let height = 50;
    export let timeMode = "relative";
    export let timeWindow = null;
    export let yPadding = 0.1;
    export let id = "sparkline";
    export let scaledPoints = []; // export so that we can use bind:scaledPoints.
    export let debug = false;
    export let gapThreshold = 5000; // Default gap threshold.

    $: if (!data) {
        // Data must be an array.
        console.warn("Points.svelte: No data is provided", data);
        data = [];
    }

    $: if (Array.isArray(data)) {
        // Log when data changes.
        if (debug) console.log("Points: data changed", id, data);
    }

    $: if (data?.length) {
        // Ensure the data is a valid array, with elements
        if (typeof data[0] == "string") {
            data = JSON.parse(data); // handle JSON
        }
    }

    $: scaledPoints = (() => {
        // Reactive variable for updates.
        if (!data?.length) {
            // Important check.
            console.warn(
                "Points.svelte: No data to calculate scaled points",
                id,
            );
            return [];
        }
        if (debug) console.log("Points: Calculating scaled points:", id, data);

        let minValue = Math.min(...data.map((item) => item.value));
        let maxValue = Math.max(...data.map((item) => item.value));

        const valueRange = maxValue - minValue || 1; // Prevent division by 0.
        const verticalPadding = height * yPadding; // Calculate vertical padding.
        const yScale = (height - 2 * verticalPadding) / valueRange; // Y scaling.

        let minTimestamp;
        if (timeMode === "absolute" && timeWindow) {
            minTimestamp = Date.now() - timeWindow;
        } else {
            minTimestamp = data[0]?.timestamp || 0; // Set to zero if no time information present.
        }

        const calculatedPoints = [];
        let prevTimestamp = null;

        for (let i = 0; i < data.length; i++) {
            const item = data[i];

            if (
                typeof item !== "object" ||
                item === null ||
                !("timestamp" in item) ||
                !("value" in item)
            ) {
                console.error(
                    "Points.svelte: Invalid data point format detected",
                    item,
                    id,
                );
                continue; // Skip item
            }

            let x;

            if (timeMode === "relative") {
                x = item.timestamp - (data[0]?.timestamp || 0);
            } else {
                x = item.timestamp - minTimestamp;
            }
            const scaledX =
                (x /
                    (timeWindow ||
                        Math.max(...data.map((item) => item.timestamp)) -
                            minTimestamp ||
                        1)) *
                width;
            const y =
                height - (item.value - minValue) * yScale - verticalPadding;

            let gap = false;
            if (
                prevTimestamp !== null &&
                item.timestamp - prevTimestamp > gapThreshold
            ) {
                // Check gaps in timestamp
                gap = true; // Set flag to true.
            }

            calculatedPoints.push({ x: scaledX, y, gap: gap }); // add to point with the gap information
            prevTimestamp = item.timestamp; // Set this for the next value

            if (debug)
                console.log(
                    `Points: x: ${scaledX.toFixed(2)}, y: ${y.toFixed(2)}, gap: ${gap}, item:`,
                    item,
                    id,
                );
        }
        return calculatedPoints; // return calculated points.
    })();
</script>

<slot {scaledPoints} />

<script>
    import { onDestroy, onMount } from "svelte";

    export let data = [];
    export let width = 100;
    export let height = 50;
    export let timeMode = "relative";
    export let timeWindow = null;
    export let yPadding = 0.1;
    export let id = "sparkline";
    export let scaledPoints = []; // export, so that we can see it.
    export let debug = false;

    $: if (!data) {
        // Data must be array
        console.warn("Points.svelte: No data is provided");
        data = [];
    }
    $: if (Array.isArray(data)) {
        // Log when data changes
        if (debug) console.log("Points: data changed", data);
    }

    $: if (data?.length) {
        // Log when data changes
        try {
            if (typeof data[0] == "string") {
                data = JSON.parse(data);
            }
        } catch (e) {
            console.warn("Points.svelte: Error parsing data", e);
        }
    }

    $: scaledPoints = (() => {
        if (!data?.length) {
            // Important check if the component gets valid data.
            console.warn(
                "Points.svelte: No data to calculate scaled points",
                id,
            );
            return [];
        }
        if (debug) console.log("Points: Calculating scaled points:", id, data);

        const minValue = Math.min(...data.map((item) => item.value));
        const maxValue = Math.max(...data.map((item) => item.value));
        const valueRange = maxValue - minValue || 1; // prevent division by 0

        const verticalPadding = height * yPadding;
        const yScale = (height - 2 * verticalPadding) / valueRange;

        let minTimestamp;
        if (timeMode === "absolute" && timeWindow) {
            minTimestamp = Date.now() - timeWindow;
        } else {
            minTimestamp = data[0]?.timestamp || 0; // Prevent NaN values in relative mode.
        }

        const calculatedPoints = [];
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
                continue; // Skip invalid items
            }

            let x;
            if (timeMode === "relative") {
                x = item.timestamp - (data[0]?.timestamp || 0);
            } else {
                x = item.timestamp - minTimestamp;
            }

            const scaledX =
                (x /
                    (Math.max(...data.map((item) => item.timestamp)) -
                        minTimestamp || 1)) *
                width; // Scale x to fit width.
            const y =
                height - (item.value - minValue) * yScale - verticalPadding; // Scale y using min and max values
            calculatedPoints.push({ x: scaledX, y: y });

            if (debug)
                console.log(
                    `Points:  x: ${x.toFixed(2)}, scaledX: ${scaledX.toFixed(2)},  y: ${y.toFixed(2)}`,
                    id,
                    item,
                );
        }

        return calculatedPoints;
    })();
</script>

<!-- The canvas element will not be placed here -->

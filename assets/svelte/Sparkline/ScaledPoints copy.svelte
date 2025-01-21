<script>
    import {
        getContext,
        createEventDispatcher,
        onDestroy,
        onMount,
    } from "svelte";

    export let data = [];
    export let width = 100;
    export let height = 50;
    export let timeMode = "relative";
    export let timeWindow = null;
    export let yPadding = 0.1; // Default 10% vertical padding
    export let scaledPoints = [];

    export let debugFlag = false;

    onMount(() => {
        console.log("Points: onMount", data);
    });

    $: if (!data) {
        // data must be an array.
        console.warn("Points.svelte: No data is provided", data);
    }

    $: if (data?.length) {
        console.log("Points: data changed");
        data = JSON.parse(data);
    }

    $: scaledPoints = (() => {
        // Reactively create array based on changes.
        if (!data?.length) {
            console.warn("Points.svelte: No data to calculate scaled points");
            return []; // Handle empty data.
        }

        if (data?.length) {
            const minValue = Math.min(...data.map((item) => item.value));
            const maxValue = Math.max(...data.map((item) => item.value));

            const valueRange = maxValue - minValue || 1; // Set a default of 1 if range is zero

            const verticalPadding = height * yPadding;
            const yScale = (height - 2 * verticalPadding) / valueRange;

            let minTimestamp;
            if (timeMode === "absolute" && timeWindow) {
                minTimestamp = Date.now() - timeWindow;
            } else {
                minTimestamp = data[0]?.timestamp || 0; // Default value if undefined
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
                    );
                    continue; // Skip if not valid data.
                }

                let x;
                if (timeMode === "relative") {
                    x = item.timestamp - (data[0]?.timestamp || 0); // Important Null check
                } else {
                    x = item.timestamp - minTimestamp;
                }

                const scaledX =
                    (x /
                        (timeWindow ||
                            Math.max(...data.map((item) => item.timestamp)) -
                                minTimestamp ||
                            1)) *
                    width; // Scale x.
                const y =
                    height - (item.value - minValue) * yScale - verticalPadding; // Scale y correctly.
                calculatedPoints.push({
                    x: Math.floor(scaledX),
                    y: Math.floor(y),
                });
            }
            scaledPoints = calculatedPoints;
            return calculatedPoints;
        }
    })();
</script>

{#if false  }<div>
        Points: {scaledPoints.length}
    </div>
{/if}

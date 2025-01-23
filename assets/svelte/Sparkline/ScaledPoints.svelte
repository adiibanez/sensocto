<script>
    import { onDestroy, onMount } from "svelte";

    let loggerCtxName = "ScaledPoints";

    export let data = [];
    export let width = 100;
    export let height = 50;
    export let timemode = "relative";
    export let timewindow;
    export let maxsamples;
    export let yPadding = 0.1;
    export let id = "sparkline";
    export let scaledPoints = []; // export, so that we can see it.
    export let resolution;

    $: if (!data) {
        // Data must be array
        logger.log(loggerCtxName, "No data is provided");
        data = [];
    }
    $: if (Array.isArray(data)) {
        // Log when data changes
        logger.log(loggerCtxName, "data changed", data);
    }

    $: if (data?.length) {
        // Log when data changes
        try {
            if (typeof data[0] == "string") {
                data = JSON.parse(data);
            }
        } catch (e) {
            logger.log(loggerCtxName, "Error parsing data", e);
        }
    }

    $: scaledPoints = (() => {
        if (document.querySelector(`body.resizing`) != undefined) {
            logger.log(loggerCtxName, "isResizing", id);
            return;
        }

        let maxPoints =
            maxsamples > width ? Math.min(maxsamples, width) : maxsamples;

        slicedData = [...data];
        //slicedData.slice(-maxPoints);

        if (!slicedData?.length) {
            // Important check if the component gets valid data.
            logger.log(loggerCtxName, "No data to calculate scaled points", id);
            return [];
        }

        logger.log(
            loggerCtxName,
            "Calculating scaled points:",
            id,
            maxsamples,
            slicedData?.length,
            data?.length,
            maxPoints,
        );

        const minValue = Math.min(...slicedData.map((item) => item.payload));
        const maxValue = Math.max(...slicedData.map((item) => item.payload));
        const valueRange = maxValue - minValue || 1; // prevent division by 0

        const verticalPadding = height * yPadding;
        const yScale = (height - 2 * verticalPadding) / valueRange;

        let minTimestamp;
        if (timemode === "absolute" && timewindow) {
            minTimestamp = Date.now() - timewindow;
        } else {
            minTimestamp = slicedData[0]?.timestamp || 0; // Prevent NaN values in relative mode.
        }

        const calculatedPoints = [];
        for (let i = 0; i < Math.min(slicedData?.length, maxsamples); i++) {
            const item = slicedData[i];

            if (
                typeof item !== "object" ||
                item === null ||
                !("timestamp" in item) ||
                !("payload" in item)
            ) {
                logger.log(
                    loggerCtxName,
                    "Invalid data point format detected",
                    item,
                    id,
                    typeof item !== "object",
                    item === null,
                    !("timestamp" in item),
                    !("payload" in item),
                );
                continue; // Skip invalid items
            }

            let x;
            
            if (timemode === "relative") {
                x = item.timestamp - (slicedData[0]?.timestamp || 0);
            } else {
                x = item.timestamp - minTimestamp;
            }

            origX = x;

            const scaledX =
                (x /
                    (Math.max(...slicedData.map((item) => item.timestamp)) -
                        minTimestamp || 1)) * 0.8 *
                width; // Scale x to fit width.

            if(scaledX < 0) {
                logger.log(loggerCtxName, origX, x, scaledX, item.timestamp, minTimestamp, item.timestamp - minTimestamp );
                continue; // Skip invalid item
            }


            

            const y =
                height - (item.payload - minValue) * yScale - verticalPadding; // Scale y using min and max values

            let point = { x: Math.floor(scaledX), y: Math.floor(y) };

            logger.log(loggerCtxName, "points", point, scaledX);
            calculatedPoints.push(point);
        }

        return calculatedPoints;
    })();
</script>

<!-- The canvas element will not be placed here -->

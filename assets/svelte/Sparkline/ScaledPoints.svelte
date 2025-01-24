<script>
    import { onDestroy, onMount } from "svelte";

    let loggerCtxName = "ScaledPoints";

    export let data = [];
    export let width = 100;
    export let height = 50;
    export let resolution;

    export let scaledPoints = []; // export, so that we can see it.

    $: if (!data) {
        logger.log(loggerCtxName, "No data is provided");
        data = [];
    }

    $: if (Array.isArray(data)) {
        logger.log(loggerCtxName, "data changed", data);
    }

    $: if (data?.length) {
        try {
            if (typeof data[0] == "string") {
                data = JSON.parse(data);
            }
        } catch (e) {
            logger.log(loggerCtxName, "Error parsing data", e);
        }
    }

    $: scaledPoints = (() => {
        if (!data?.length) {
            logger.log(loggerCtxName, "No data to calculate scaled points");
            return [];
        }

        logger.log(loggerCtxName, "Calculating scaled points");

        // Basic calculations
        const minValue = Math.min(...data.map((item) => item.payload));
        const maxValue = Math.max(...data.map((item) => item.payload));
        const valueRange = maxValue - minValue || 1;

        // Define origin and data range
        const startTime = data[0].timestamp;
        const endTime = data[data.length - 1].timestamp;

        const dataRange = endTime - startTime || 1;

        const calculatedPoints = [];
        for (let i = 0; i < data.length; i++) {
            const item = data[i];
            const x = ((item.timestamp - startTime) / dataRange) * width * resolution;
            const y =
                height - ((item.payload - minValue) / valueRange) * height;
            let point = { x: Math.floor(x), y: Math.floor(y) };
            calculatedPoints.push(point);
        }

        return calculatedPoints;
    })();
</script>

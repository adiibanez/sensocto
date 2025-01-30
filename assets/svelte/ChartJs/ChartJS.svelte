<svelte:options customElement="sensocto-chartjs" />

<script>
    // https://medium.com/@jonnyeberhardt7/building-dynamic-dashboards-in-phoenix-liveview-chart-js-integration-and-interactive-drag-and-drop-6b76c45ee412
    // https://www.chartjs.org/docs/latest/configuration/animations.html#looping-tension-[property]
    // https://www.npmjs.com/package/svelte-chartjs
    import { onMount, afterUpdate } from "svelte";
    import Chart from "chart.js/auto";
    import { format } from "date-fns";

    export let data = [];
    export let width = 200;
    export let height = 60;
    export let is_loading;

    export let samplingrate;
    export let timewindow;
    export let timemode;

    export let identifier;

    let isMounted = false;

    let loggerCtxName = "ChartJS";

    let canvas;
    let chart;
    export let color = "#007bff";
    export let showAxis = true;
    export let xFormat = "HH:mm:ss";
    export let label = "";

    afterUpdate(() => {
        if (isMounted) {
            updateChart();
        }
    });

    onMount(() => {
        console.log("Component Mounting");
        // SciChartSurface.configure({
        //     wasmUrl: wasmPath,
        // });

        createChart();
        isMounted = true;
    });

    $: maxsamples = calculatemaxsamples({
        width,
        samplingrate,
        timewindow,
        timemode,
    });

    $: if (data?.length) {
        logger.log(
            loggerCtxName,
            "data changed, redrawing sparkline...",
            maxsamples,
            data?.length,
        );

        const timestamps = data.map((point) => point.timestamp);
        minTimestamp = Math.min(...timestamps);
        maxTimestamp = Math.max(...timestamps);

        //createChart();
    }

    function calculatemaxsamples({
        width,
        samplingrate,
        timewindow,
        timemode,
    }) {
        if (!width || !samplingrate) {
            return 0; // Handle cases with missing information.
        }

        let maxsamples;

        /*if(width < 300) {
            timewindow = Math.min(2000, timewindow);
        }*/

        if (timemode === "absolute" && timewindow) {
            const timewindowInSeconds = timewindow / 1000; // Convert to seconds.

            maxsamples = width / 2;
            /*maxsamples = Math.max(
                1,
                Math.floor(timewindowInSeconds * samplingrate * width),
            ); // calculate based on provided window and rate.
            */
        } else {
            // relative or no time window.
            //maxsamples = Math.max(1, Math.floor(width / resolution)); // Compute based on width, and also using a base resolution value.

            maxsamples = width * samplingrate * (timewindow / 1000);
        }

        //maxsamples = ((timewindow / 1000) * width) / samplingrate;

        logger.log(
            loggerCtxName,
            "maxsamples:  width:",
            width,
            ", samplingrate:",
            samplingrate,
            ", timewindow:",
            timewindow,
            ", result:",
            maxsamples,
        );
        return maxsamples;
    }

    function createChart() {
        if (!canvas) return;
        if (chart) {
            chart.destroy();
        }

        chart = new Chart(canvas, {
            type: "line",
            data: {
                labels: data.map((d) => format(new Date(d.timestamp), xFormat)),
                datasets: [
                    {
                        label: label,
                        data: data.map((d) => d.payload),
                        borderColor: color,
                        borderWidth: 2,
                        fill: true,
                        pointRadius: 0,
                        tension: 0.2,
                    },
                ],
            },
            options: {
                responsive: true,
                maintainAspectRatio: true,
                scales: {
                    x: {
                        display: showAxis,
                        title: {
                            display: showAxis,
                            text: "Time",
                        },
                    },
                    y: {
                        //suggestedMin: 20,
                        //suggestedMax: 180,
                        display: showAxis,
                        title: {
                            display: showAxis,
                            text: "Value",
                        },
                        ticks: {
                            beginAtZero: true,
                            //steps: 100,
                            //stepValue: 1,
                        },
                    },
                },
                plugins: {
                    legend: {
                        display: false,
                    },
                },
                layout: {
                    padding: 0,
                    margin: 0,
                },
            },
        });
    }

    function updateChart() {
        // !document.querySelector(".resizing") &&
        if (chart) {
            chart.data.datasets[0].data = data.map((d) => d.payload);
            chart.data.labels = data.map((d) =>
                format(new Date(d.timestamp), xFormat),
            );
            chart.update();
        }
    }

    const transformStorageEventData = (data) => {
        let transformedData = [];

        if (data && Array.isArray(data)) {
            // Verify data format.
            data.forEach((item) => {
                // Loop through each item in the array.
                if (
                    typeof item === "object" &&
                    item !== null &&
                    item.timestamp &&
                    item.payload
                ) {
                    // Type checks
                    transformedData.push({
                        timestamp: item.timestamp,
                        payload: item.payload.payload,
                    });
                } else {
                    // Output error for any malformed data
                    console.warn(
                        "malformed data detected, skipping item",
                        item,
                    );
                }
            });

            return transformedData;
        } else {
            console.warn("Invalid data format or data is missing:", data);
        }
    };

    const handleStorageWorkerEvent = (e) => {
        //const {type, eventData} = e.detail;
        if (identifier === e?.detail?.data.id) {
            logger.log(
                loggerCtxName,
                "handleStorageWorkerEvent",
                identifier,
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
                    identifier,
                    e.detail,
                ); // Log processed data.
            }
        }
    };

    const handleSeedDataEvent = (e) => {
        if (
            identifier ==
            e?.detail?.sensor_id + "_" + e?.detail?.attribute_id
        ) {
            // e?.detail?.data?.length > 0
            logger.log(
                loggerCtxName,
                "handleSeedDataEvent",
                identifier,
                e?.detail?.data?.length,
                data?.length,
            );

            //let newData = e?.detail?.data;

            if (Array.isArray(e?.detail?.data) && e?.detail?.data?.length > 0) {
                let newData = e.detail.data;

                //newData = newData.slice(-maxsamples);
                data = [];
                newData?.forEach((item) => {
                    data = [...data, item];
                });
            } else if (
                Array.isArray(e?.detail?.data) &&
                e?.detail?.data?.length == 0
            ) {
                // reset data
                data = [...[]];
            } else {
                logger.log(
                    loggerCtxName,
                    "handleSeedDataEvent",
                    "No data",
                    e?.detail,
                );
            }

            is_loading = false;
        }
    };

    const handleAccumulatorEvent = (e) => {
        if (identifier === e?.detail?.id) {
            logger.log(
                loggerCtxName,
                "handleAccumulatorEvent",
                "loading: " + is_loading,
                e,
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
                    identifier,
                    e.detail.data,
                    data?.length,
                );

                data = [...data.slice(-maxsamples), e.detail.data];
            }
        }
    };

    const handleResizeEnd = (e) => {
        logger.log(loggerCtxName, "handleResizeEnd", e);
        createChart();
    };
</script>

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
    on:seeddata-event={handleSeedDataEvent}
    on:resizeend={handleResizeEnd}
/>

<!--<div bind:this={chartDiv} style="width: {width}px; height: {height}px;"></div>-->
<canvas bind:this={canvas} {width} {height}></canvas>
<input type="button" on:click={createChart} value="createChart" />
<p>
    timewindow: {timewindow}, samplingrate: {samplingrate}, max: {maxsamples},
    data: {data?.length}
</p>
<p>{width} {height}</p>
<!--
<div>{JSON.stringify(data)}</div>
-->

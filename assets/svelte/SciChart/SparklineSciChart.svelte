<svelte:options customElement="sensocto-sparkline-scichart" />

<script>
    import { onMount, afterUpdate } from "svelte";
    import {
        libraryVersion,
        SciChartDefaults,
        SciChartSurface,
        NumericAxis,
        DateTimeAxis,
        FastLineRenderableSeries,
        XyDataSeries,
        NumberRange,
        parseColorToUInt,
        Thickness,
    } from "scichart";

    // import * as scichart from "scichart";
    import { format } from "date-fns";

    import { logger } from "../logger.js";

    export let data = [];
    export let width = 200;
    export let height = 80;
    export let labelFrequencyX = 2;
    export let labelFrequencyY = 2;
    export let xAxisLabel = "Time";
    export let yAxisLabel = "Value";
    export let xFormat = "HH:mm:ss";
    export let stroke = "#007bff";
    export let axisTextColor = "#999";
    export let is_loading;

    let isMounted = false;

    export let wasmPath = "/assets/_wasm";

    export let samplingrate;
    export let timewindow;
    export let timemode;

    export let identifier;

    let loggerCtxName = "SparklineSciChart";

    let sciChartSurface;
    let chartDiv;

    // Load Wasm & Data files from URL
    // This URL can be anything, but for example purposes we are loading from JSDelivr CDN
    SciChartSurface.configure({
        dataUrl: `https://cdn.jsdelivr.net/npm/scichart@${libraryVersion}/_wasm/scichart2d.data`,
        wasmUrl: `https://cdn.jsdelivr.net/npm/scichart@${libraryVersion}/_wasm/scichart2d.wasm`,
    });

    SciChartSurface.UseCommunityLicense();

    // export const SetSciChartSurface = () => {
    //     // SciChartSurface.setRuntimeLicenseKey(window.REACT_APP_SCICHART_KEY);
    //     SciChartSurface.configure({
    //         wasmUrl: "/assets/_wasm", // Corrected: base directory, without file name
    //     });

    //     SciChartDefaults.useSharedCache = true;

    //     return SciChartSurface;
    // };

    afterUpdate(() => {
        if (isMounted) {
            //updateChart();
            createChart();
        }
    });

    onMount(() => {
        console.log("Component Mounting");
        // SciChartSurface.configure({
        //     wasmUrl: wasmPath,
        // });

        createChart();
        isMounted = true;
        //     // SciChart.SciChartSurface.configure({
        //     //     dataUrl: `/assets/_wasm/scichart2d.data`,
        //     //     wasmUrl: `/assets/_wasm/scichart2d.wasm`,
        //     //     wasmPath: "/assets/_wasm",
        //     // });

        //     SetSciChartSurface();

        //     SciChartSurface.create(divElement, {
        //         theme: new SciChartDarkTheme(),
        //     }).then((sciChartSurface) => {
        //         // Use sciChartSurface
        //     });

        //     createChart();
        //     isMounted = true;
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
            maxsamples = Math.max(
                1,
                Math.floor(timewindowInSeconds * samplingrate * width),
            ); // calculate based on provided window and rate.
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

    async function createChart() {
        SciChartSurface.create(chartDiv, {})
            .then((surface) => {
                console.log("SciChartSurface created successfully", surface);
                sciChartSurface = surface;

                const xAxis = new NumericAxis();
                sciChartSurface.xAxes.add(xAxis);

                const yAxis = new NumericAxis();
                sciChartSurface.yAxes.add(yAxis);

                const xyDataSeries = new XyDataSeries({
                    xValues: [0, 1, 2, 3],
                    yValues: [2, 3, 4, 2],
                });

                const lineSeries = new FastLineRenderableSeries({
                    dataSeries: xyDataSeries,
                });
                sciChartSurface.renderableSeries.add(lineSeries);

                wasmLoaded = true;
                console.log("SciChart WASM loaded");
            })
            .catch((err) => console.error("Error during initialization", err));
    }

    // async function _createChart() {
    //     console.log("createChart started");

    //     if (!chartDiv) {
    //         console.log("chartDiv not available, exiting");
    //         return;
    //     }
    //     if (sciChartSurface) {
    //         console.log("deleting previous chart");
    //         try {
    //             if (
    //                 sciChartSurface &&
    //                 typeof sciChartSurface.delete === "function"
    //             ) {
    //                 console.log("deleting sciChartSurface");
    //                 sciChartSurface.delete();
    //             } else {
    //                 console.error(
    //                     "sciChartSurface.delete is not a function, cannot delete",
    //                 );
    //             }
    //         } catch (e) {
    //             console.error("Error during deletion", e);
    //         }
    //     }

    //     console.log("creating scichart surface");
    //     scichart.SciChartSurface.create(chartDiv, {
    //         theme: {
    //             sciChartBackground: "transparent",
    //             axisBorders: {
    //                 showBorders: true,
    //                 borderLeft: "transparent",
    //                 borderBottom: "transparent",
    //             },
    //             gridLines: {
    //                 majorGridLineStroke: "transparent",
    //                 minorGridLineStroke: "transparent",
    //             },
    //         },
    //     }).then((surface) => {
    //         console.log("scichart surface created", surface);
    //         sciChartSurface = surface;

    //         const xAxis = new scichart.DateTimeAxis();
    //         xAxis.axisAlignment = "Bottom";
    //         xAxis.labelProvider.formatLabel = (date) => {
    //             return format(date, xFormat);
    //         };

    //         xAxis.labelProvider.getLabelForAxisItem = (index, axisItem) => {
    //             if (labelFrequencyX > 0 && index % labelFrequencyX == 0) {
    //                 return format(new Date(axisItem.date), xFormat);
    //             }
    //             return "";
    //         };
    //         xAxis.axisBorderThickness = new scichart.Thickness(0, 0, 1, 0);
    //         xAxis.labelStyle = { color: axisTextColor };
    //         xAxis.title = xAxisLabel;
    //         xAxis.titleStyle = { color: axisTextColor };
    //         sciChartSurface.xAxes.add(xAxis);

    //         const yAxis = new scichart.NumericAxis();
    //         yAxis.axisAlignment = "Right";
    //         yAxis.growBy = new scichart.NumberRange(0.1, 0.1);
    //         yAxis.labelProvider.getLabelForAxisItem = (index, axisItem) => {
    //             if (labelFrequencyY > 0 && index % labelFrequencyY == 0) {
    //                 return axisItem.value.toFixed(2);
    //             }
    //             return "";
    //         };
    //         yAxis.axisBorderThickness = new scichart.Thickness(0, 0, 0, 1);
    //         yAxis.labelStyle = { color: axisTextColor };
    //         yAxis.title = yAxisLabel;
    //         yAxis.titleStyle = { color: axisTextColor };
    //         sciChartSurface.yAxes.add(yAxis);

    //         const xyDataSeries = new scichart.XyDataSeries({
    //             xValues: data.map((d) => new Date(d.time)),
    //             yValues: data.map((d) => d.value),
    //         });

    //         const lineSeries = new scichart.FastLineRenderableSeries({
    //             dataSeries: xyDataSeries,
    //             stroke: stroke,
    //             strokeThickness: 2,
    //         });
    //         sciChartSurface.renderableSeries.add(lineSeries);

    //         console.log(
    //             "sciChartSurface creation completed successfully:",
    //             sciChartSurface,
    //         );
    //     });
    //     console.log("createChart ended");
    // }

    // async function updateChart() {
    //     console.log("updateChart function started");
    //     if (sciChartSurface) {
    //         console.log("sciChartSurface to be updated:", sciChartSurface);
    //         createChart();
    //     } else {
    //         console.log("sciChartSurface not initialized");
    //     }
    //     console.log("updateChart function ended");
    // }

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
        console.log("Here", e?.detail?.data?.length);
        if (
            identifier ==
                e?.detail?.sensor_id + "_" + e?.detail?.attribute_id &&
            e?.detail?.data?.length > 0
        ) {
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
        console.log("Here", e?.detail?.id, identifier);
        if (identifier === e?.detail?.id) {
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
                    identifier,
                    e.detail.data,
                    data?.length,
                );

                data = [...data.slice(-maxsamples), e.detail.data];
            }
        }
    };

    console.log("Here");
</script>

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
    on:seeddata-event={handleSeedDataEvent}
/>

<div bind:this={chartDiv} style="width: {width}px; height: {height}px;"></div>

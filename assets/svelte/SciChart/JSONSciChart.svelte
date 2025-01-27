<svelte:options customElement="sensocto-json-scichart" />

<script>
    import { onMount, afterUpdate } from "svelte";
    import {
        SciChartSurface,
        chartBuilder,
        EAxisType,
        ELabelProviderType,
        EAxisAlignment,
        NumberRange,
        ESeriesType,
        GradientParams,
        EPointMarkerType,
        EAnnotationType,
        ECoordinateMode,
        EHorizontalAnchorPoint,
        EVerticalAnchorPoint,
        EChart2DModifierType,
        Point,
    } from "scichart";

    export let is_loading;

    export let wasmPath = "/assets/_wasm";

    export let samplingrate;
    export let timewindow;
    export let timemode;

    export let identifier;

    let loggerCtxName = "SparklineSciChart";

    let sciChartSurface;
    let chartDiv;

    SciChartSurface.configure({
        dataUrl: `https://cdn.jsdelivr.net/npm/scichart@${libraryVersion}/_wasm/scichart2d.data`,
        wasmUrl: `https://cdn.jsdelivr.net/npm/scichart@${libraryVersion}/_wasm/scichart2d.wasm`,
    });

    SciChartSurface.UseCommunityLicense();

    //import { appTheme } from "../../theme";

    const appTheme = { ...new SciChartJSLightTheme() };

    afterUpdate(() => {
        if (isMounted) {
            //updateChart();
            drawExample(chartDiv);
            console.log("Update");
        }
    });

    onMount(() => {
        console.log("Component Mounting");
        // SciChartSurface.configure({
        //     wasmUrl: wasmPath,
        // });

        drawExample(chartDiv);
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

    export const drawExample = async (rootElement) => {
        // Create a chart using the Builder-API, an api that allows defining a chart
        // with javascript-objects or JSON
        return await chartBuilder.build2DChart(rootElement, {
            // Set theme
            surface: {
                //    theme: appTheme.SciChartJsTheme
            },
            // Add XAxis
            xAxes: [
                {
                    type: EAxisType.CategoryAxis,
                    options: {
                        axisTitle: "X Axis Title",
                        labelProvider: {
                            type: ELabelProviderType.Text,
                            options: {
                                labels: {
                                    1: "one",
                                    2: "two",
                                    3: "three",
                                    4: "four",
                                    5: "five",
                                },
                            },
                        },
                    },
                },
            ],
            // Add multiple Y-Axis
            yAxes: [
                {
                    type: EAxisType.NumericAxis,
                    options: {
                        id: "y1",
                        axisTitle: "Left Axis",
                        axisAlignment: EAxisAlignment.Left,
                        visibleRange: new NumberRange(0, 20),
                        zoomExtentsToInitialRange: true,
                    },
                },
                {
                    type: EAxisType.NumericAxis,
                    options: {
                        id: "y2",
                        axisTitle: "Right Axis",
                        axisAlignment: EAxisAlignment.Right,
                        visibleRange: new NumberRange(0, 800),
                        labelPrecision: 0,
                        zoomExtentsToInitialRange: true,
                    },
                },
            ],
            // Add series. More than one can be set in an array
            series: [
                {
                    // each series has type, options in the builder-API
                    type: ESeriesType.SplineMountainSeries,
                    options: {
                        yAxisId: "y1",
                        stroke: appTheme.VividSkyBlue,
                        strokeThickness: 5,
                        fillLinearGradient: new GradientParams(
                            new Point(0, 0),
                            new Point(0, 1),
                            [
                                { color: appTheme.VividTeal, offset: 0.2 },
                                { color: "Transparent", offset: 1 },
                            ],
                        ),
                    },
                    xyData: {
                        xValues: [1, 2, 3, 4, 5],
                        yValues: [8, 6, 7, 2, 16],
                    },
                },
                {
                    type: ESeriesType.BubbleSeries,
                    options: {
                        yAxisId: "y2",
                        pointMarker: {
                            type: EPointMarkerType.Ellipse,
                            options: {
                                width: 100,
                                height: 100,
                                strokeThickness: 10,
                                fill: appTheme.PaleSkyBlue,
                                stroke: appTheme.VividSkyBlue,
                            },
                        },
                    },
                    xyzData: {
                        xValues: [1, 2, 3, 4, 5],
                        yValues: [320, 240, 280, 80, 640],
                        zValues: [20, 40, 20, 30, 35],
                    },
                },
            ],
            // Add annotations
            annotations: [
                {
                    type: EAnnotationType.SVGTextAnnotation,
                    options: {
                        text: "Labels",
                        yAxisId: "y1",
                        x1: 0,
                        y1: 10,
                        yCoordinateMode: ECoordinateMode.DataValue,
                    },
                },
                {
                    type: EAnnotationType.SVGTextAnnotation,
                    options: {
                        text: "can be placed",
                        yAxisId: "y1",
                        x1: 1,
                        y1: 8,
                        yCoordinateMode: ECoordinateMode.DataValue,
                    },
                },
                {
                    type: EAnnotationType.SVGTextAnnotation,
                    options: {
                        text: "on the chart",
                        yAxisId: "y1",
                        x1: 2,
                        y1: 9,
                        yCoordinateMode: ECoordinateMode.DataValue,
                    },
                },
                {
                    type: EAnnotationType.SVGTextAnnotation,
                    options: {
                        text: "Builder API Demo",
                        x1: 0.5,
                        y1: 0.5,
                        opacity: 0.33,
                        yCoordShift: -52,
                        xCoordinateMode: ECoordinateMode.Relative,
                        yCoordinateMode: ECoordinateMode.Relative,
                        horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
                        verticalAnchorPoint: EVerticalAnchorPoint.Center,
                        fontSize: 42,
                        fontWeight: "Bold",
                    },
                },
                {
                    type: EAnnotationType.SVGTextAnnotation,
                    options: {
                        text: "Create SciChart charts with JSON Objects",
                        x1: 0.5,
                        y1: 0.5,
                        yCoordShift: 0,
                        opacity: 0.33,
                        xCoordinateMode: ECoordinateMode.Relative,
                        yCoordinateMode: ECoordinateMode.Relative,
                        horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
                        verticalAnchorPoint: EVerticalAnchorPoint.Center,
                        fontSize: 36,
                        fontWeight: "Bold",
                    },
                },
            ],
            // Add interaction (zooming, panning, tooltips)
            modifiers: [
                {
                    type: EChart2DModifierType.Rollover,
                    options: {
                        yAxisId: "y1",
                        rolloverLineStroke: appTheme.VividTeal,
                    },
                },
                { type: EChart2DModifierType.MouseWheelZoom },
                { type: EChart2DModifierType.ZoomExtents },
            ],
        });
    };

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
</script>

<svelte:window
    on:storage-worker-event={handleStorageWorkerEvent}
    on:accumulator-data-event={handleAccumulatorEvent}
    on:seeddata-event={handleSeedDataEvent}
/>

<!--<div bind:this={chartDiv} style="width: {width}px; height: {height}px;"></div>-->
<div bind:this={chartDiv} style="width: 800px; height: 400px;"></div>

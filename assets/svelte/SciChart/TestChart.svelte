<svelte:options customElement="sensocto-testchart" />

<script type="ts">
    import { onMount } from "svelte";
    import {
        libraryVersion,
        SciChartSurface,
        // SciChartJsNavyTheme,
        NumberRange,
        NumericAxis,
        EAxisAlignment,
        CustomAnnotation,
    } from "scichart";
    import chartConfig from "./chartConfig.json";
    import { createSpectralData, Radix2FFT } from "./utils";

    import {
        Point,
        GradientParams,
        FastLineRenderableSeries,
        FastMountainRenderableSeries,
        XyDataSeries,
        LegendModifier,
        EAutoRange,
        Thickness,
        EXyDirection,
        ZoomPanModifier,
        MouseWheelZoomModifier,
        ZoomExtentsModifier,
        SeriesSelectionModifier,
        AnnotationDragDeltaEventArgs,
        EHorizontalAnchorPoint,
        EVerticalAnchorPoint,
    } from "scichart";
    export let width = 600;
    export let height = 400;
    let chartDiv;
    let sciChartSurface;
    let wasmContext;
    let mainChartSelectionModifier;
    let crossSectionPaletteProvider;
    let dragMeAnnotation;

    let crossSectionSelectedSeries;
    let crossSectionHoveredSeries;
    let crossSectionSliceSeries;
    let crossSectionLegendModifier;

    onMount(async () => {
        console.log(
            "Test: ",
            document.getElementById("test-chartdiv"),
            chartDiv,
        );

        SciChartSurface.configure({
            dataUrl: `https://cdn.jsdelivr.net/npm/scichart@${libraryVersion}/_wasm/scichart2d.data`,
            wasmUrl: `https://cdn.jsdelivr.net/npm/scichart@${libraryVersion}/_wasm/scichart2d.wasm`,
        });

        SciChartSurface.UseCommunityLicense();

        initChart();
    });

    const initChart = async () => {
        const { wasmContext, sciChartSurface } = await SciChartSurface.create(
            chartDiv,
            chartConfig,
        );
        //createSeries();
        //addDragAnnotation();
        //addInteraction();
        //configureAfterInit();
    };

    const createSeries = () => {
        const seriesCount = 50;
        for (let i = 0; i < seriesCount; i++) {
            // Create one yAxis per series

            const yAxis = new NumericAxis(wasmContext, {
                id: "Y" + i,
                axisAlignment: EAxisAlignment.Left,
                maxAutoTicks: 5,
                drawMinorGridLines: false,
                visibleRange: new NumberRange(-60, 60),
                isVisible: i === seriesCount - 1,
                overrideOffset: 3 * -i,
            });
            sciChartSurface.yAxes.add(yAxis);

            // Create a shared, default xaxis
            const xAxis = new NumericAxis(wasmContext, {
                id: "X" + i,
                axisAlignment: EAxisAlignment.Bottom,
                maxAutoTicks: 5,
                drawMinorGridLines: false,
                growBy: new NumberRange(0, 0.2),
                isVisible: i === seriesCount - 1,
                overrideOffset: 2 * i,
            });
            sciChartSurface.xAxes.add(xAxis);

            // Create some data for the example
            const { xValues, yValues } = createSpectralData(i);
            crossSectionPaletteProvider = new CrossSectionPaletteProvider();
            sciChartSurface.rendered.subscribe(() => {
                // Don't recalculate the palette unless the selected index changes
                crossSectionPaletteProvider.shouldUpdate = false;
            });
            const lineSeries = new FastLineRenderableSeries({
                id: "S" + i,
                xAxisId: "X" + i,
                yAxisId: "Y" + i,
                stroke: "#64BAE4",
                strokeThickness: 1,
                dataSeries: new XyDataSeries({
                    xValues,
                    yValues,
                    dataSeriesName: `Spectra ${i}`,
                }),
                paletteProvider: crossSectionPaletteProvider,
            });
            sciChartSurface.renderableSeries.add(lineSeries);
        }
    };

    const addDragAnnotation = () => {
        dragMeAnnotation = new CustomAnnotation({
            svgString: `<svg xmlns="http://www.w3.org/2000/svg" width="100" height="82">
                  <g>
                    <line x1="50%" y1="10" x2="50%" y2="40" stroke="#FFBE93" stroke-dasharray="2,2" />
                    <circle cx="50%" cy="10" r="5" fill="#FFBE93" />
                    <rect x="2" y="40" rx="10" ry="10" width="96" height="40" fill="#64BAE433" stroke="#64BAE4" stroke-width="2" />
                    <text x="50%" y="60" fill="White" text-anchor="middle" alignment-baseline="middle" >Drag me!</text>
                  </g>
                </svg>`,
            x1: 133,
            y1: -25,
            xAxisId: "X0",
            yAxisId: "Y0",
            isEditable: true,
            annotationsGripsFill: "Transparent",
            annotationsGripsStroke: "Transparent",
            selectionBoxStroke: "Transparent",
            horizontalAnchorPoint: EHorizontalAnchorPoint.Center,
            verticalAnchorPoint: EVerticalAnchorPoint.Top,
        });
        sciChartSurface.annotations.add(dragMeAnnotation);
    };

    const addInteraction = () => {
        mainChartSelectionModifier = sciChartSurface.chartModifiers.get(3);

        const updateSeriesSelectionState = (series) => {
            series.stroke = series.isSelected
                ? "White"
                : series.isHovered
                  ? "#FFBE93"
                  : "#64BAE4";
            series.strokeThickness =
                series.isSelected || series.isHovered ? 3 : 1;
        };

        let prevSelectedSeries = sciChartSurface.renderableSeries.get(0);
        // Add selection behaviour
        mainChartSelectionModifier.onSelectionChanged = (args) => {
            if (args.selectedSeries.length > 0) {
                prevSelectedSeries = args.selectedSeries[0];
                args.allSeries.forEach(updateSeriesSelectionState);
            } else {
                prevSelectedSeries.isSelected = true;
            }
        };

        mainChartSelectionModifier.onHoverChanged = (args) => {
            args.allSeries.forEach(updateSeriesSelectionState);
        };
    };

    const configureAfterInit = () => {
        // Link interactions together
        mainChartSelectionModifier.selectionChanged.subscribe((args) => {
            const selectedSeries = args.selectedSeries[0]?.dataSeries;
            if (selectedSeries) {
                crossSectionSelectedSeries.dataSeries = selectedSeries;
            }
            crossSectionLegendModifier.isEnabled = true;
            crossSectionLegendModifier.sciChartLegend?.invalidateLegend();
        });
        mainChartSelectionModifier.hoverChanged.subscribe((args) => {
            const hoveredSeries = args.hoveredSeries[0]?.dataSeries;
            if (hoveredSeries) {
                crossSectionHoveredSeries.dataSeries = hoveredSeries;
            }
            crossSectionLegendModifier.sciChartLegend?.invalidateLegend();
        });

        // Add a function to update drawing the cross-selection when the drag annotation is dragged
        const updateDragAnnotation = () => {
            // Don't allow to drag vertically, only horizontal
            dragMeAnnotation.y1 = -25;

            // Find the index to the x-values that the axis marker is on
            // Note you could just loop getNativeXValues() here but the wasmContext.NumberUtil function does it for you
            const dataIndex =
                sciChartSurface.webAssemblyContext2D.NumberUtil.FindIndex(
                    sciChartSurface.renderableSeries
                        .get(0)
                        .dataSeries.getNativeXValues(),
                    dragMeAnnotation.x1,
                    sciChartSurface.webAssemblyContext2D.SCRTFindIndexSearchMode
                        .Nearest,
                    true,
                );

            crossSectionPaletteProvider.selectedIndex = dataIndex;
            crossSectionPaletteProvider.shouldUpdate = true;
            sciChartSurface.invalidateElement();
            crossSectionSliceSeries.clear();
            for (let i = 0; i < sciChartSurface.renderableSeries.size(); i++) {
                crossSectionSliceSeries.append(
                    i,
                    sciChartSurface.renderableSeries
                        .get(i)
                        .dataSeries.getNativeYValues()
                        .get(dataIndex),
                );
            }
        };

        // Run it once
        updateDragAnnotation();

        //Run it when user drags the annotation
        dragMeAnnotation.dragDelta.subscribe((args) => {
            // Removed the type annotation
            updateDragAnnotation();
        });
        sciChartSurface.renderableSeries.get(0).isSelected = true;
    };

    const initCrossSectionLeft = async () => {
        const { sciChartSurface, wasmContext } = await SciChartSurface.create(
            chartDiv,
            {
                disableAspect: true,
                // theme: "SciChartJsNavyTheme",
            },
        );

        sciChartSurface.xAxes.add(
            new NumericAxis(wasmContext, {
                autoRange: EAutoRange.Always,
                drawMinorGridLines: false,
            }),
        );
        sciChartSurface.yAxes.add(
            new NumericAxis(wasmContext, {
                autoRange: EAutoRange.Never,
                axisAlignment: EAxisAlignment.Left,
                visibleRange: new NumberRange(-30, 5),
                drawMinorGridLines: false,
            }),
        );

        crossSectionSelectedSeries = new FastLineRenderableSeries(wasmContext, {
            stroke: "#ff6600",
            strokeThickness: 3,
        });
        sciChartSurface.renderableSeries.add(crossSectionSelectedSeries);
        crossSectionHoveredSeries = new FastMountainRenderableSeries(
            wasmContext,
            {
                stroke: "#64BAE477",
                strokeThickness: 3,
                strokeDashArray: [2, 2],
                fillLinearGradient: new GradientParams(
                    new Point(0, 0),
                    new Point(0, 1),
                    [
                        { color: "#64BAE455", offset: 0 },
                        { color: "#64BAE400", offset: 1 },
                    ],
                ),
                dataSeries: crossSectionSliceSeries,
                zeroLineY: -999,
            },
        );
        sciChartSurface.renderableSeries.add(crossSectionHoveredSeries);

        // Add a legend to the bottom left chart
        crossSectionLegendModifier = new LegendModifier({
            showCheckboxes: false,
            orientation: "Horizontal",
        });
        crossSectionLegendModifier.isEnabled = false;
        sciChartSurface.chartModifiers.add(crossSectionLegendModifier);

        return { sciChartSurface };
    };

    const initCrossSectionRight = async () => {
        const { sciChartSurface, wasmContext } = await SciChartSurface.create(
            chartDiv,
            {
                disableAspect: true,
                //theme: "SciChartJsNavyTheme",
                title: "Cross Section Slice",
                titleStyle: {
                    fontSize: 13,
                    padding: Thickness.fromNumber(10),
                },
            },
        );

        sciChartSurface.xAxes.add(
            new NumericAxis(wasmContext, {
                autoRange: EAutoRange.Always,
                drawMinorGridLines: false,
            }),
        );
        sciChartSurface.yAxes.add(
            new NumericAxis(wasmContext, {
                autoRange: EAutoRange.Never,
                axisAlignment: EAxisAlignment.Left,
                visibleRange: new NumberRange(-30, 5),
                drawMinorGridLines: false,
            }),
        );

        crossSectionSliceSeries = new XyDataSeries(wasmContext);
        sciChartSurface.renderableSeries.add(
            new FastMountainRenderableSeries(wasmContext, {
                stroke: "#64BAE4",
                strokeThickness: 3,
                strokeDashArray: [2, 2],
                fillLinearGradient: new GradientParams(
                    new Point(0, 0),
                    new Point(0, 1),
                    [
                        { color: "#64BAE477", offset: 0 },
                        { color: "#64BAE433", offset: 1 },
                    ],
                ),
                dataSeries: crossSectionSliceSeries,
                zeroLineY: -999,
            }),
        );
        return { sciChartSurface };
    };

    /*(async () => {
        const { sciChartSurface: leftSurface } = await initCrossSectionLeft();
        const { sciChartSurface: rightSurface } = await initCrossSectionRight();
    })();*/
</script>

{@debug chartDiv}
{@debug sciChartSurface}
<div
    id="test-chartdiv"
    bind:this={chartDiv}
    style="width: {width}px; height: {height}px;"
></div>

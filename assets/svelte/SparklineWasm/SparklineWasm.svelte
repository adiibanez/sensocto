<svelte:options customElement="sensocto-sparkline-wasm-svelte" />

<script>
    import { onMount } from "svelte";
    // import init, {
    //     draw_sparkline,
    // } from "../../../wasm-sparkline/pkg/sparkline.js";

    //import wasm from "../../../wasm-sparkline/Cargo.toml";

    // last init
    import init, {
        draw_sparkline,
    } from "../../../wasm-sparkline/pkg/sparkline.js"; //sparkline_bg.wasm";

    // import init, {
    //     draw_sparkline,
    // } from "../../../wasm-sparkline/pkg/sparkline_bg.wasm"; //sparkline_bg.wasm";

    //console.log("Wasm", draw_sparkline);

    /*const init = async () => {
        const bindings = await wasm();
        const app = new App({
            target: document.body,
            props: {
                bindings,
            },
        });
    };

    init();

    */

    export let canvasId;
    export let initialParams;

    //const sparkline = import("../../../wasm-sparkline/pkg/sparkline.js");
    //console.log(sparkline);
    //import { wasm } from "../../../wasm-sparkline/pkg/sparkline_bg.wasm";
    // const wasm = require("../../../wasm-sparkline/pkg/sparkline_bg.wasm");

    //const wasm = require("../../../wasm-sparkline/pkg/sparkline_bg.wasm");

    let canvas;
    let ctx;
    let data = [];
    let params = { ...initialParams };
    let isVisible = false;
    let observer;

    // const test = import("../../../wasm-sparkline/pkg/sparkline.js").then(
    //     (module) => {
    //         console.log("MODULE", module);
    //         module.default("/assets/sparkline_bg.wasm"); // call the default exported function to start the module
    //     },
    // );

    /*import("../../../wasm-sparkline/pkg/sparkline.js").then((module) => {
        console.log("MODULE", module);
        module.default("/assets/sparkline_bg.wasm"); // call the default exported function to start the module
        moduleExports = module;
    });

    async function initWasm() {
        import("../../../wasm-sparkline/pkg/sparkline.js").then((module) => {
            console.log("MODULE", module);
            module.default("/assets/sparkline_bg.wasm"); // call the default exported function to start the module
            moduleExports = module;
        });

        // const module = await import(
        //     "../../../wasm-sparkline/pkg/sparkline.js"
        // ).then((module) => {
        //     console.log(module);
        //     module.default("/assets/sparkline_bg.wasm");
        //     moduleExports = module;
        // });

        if (isVisible) {
            requestAnimationFrame(render);
        }
    }
        */

    async function initWasm() {
        console.log("Here");
        try {
            // await init(
            //     "/assets/sparkline_bg.wasm",
            //     "/assets/sparkline_bg.wasm.d.ts",
            // );

            ctx = canvas.getContext("2d");

            /*maxSamples = calculateMaxSamples(
                canvas.width,
                timeWindow,
                sampleRate,
                resolution,
            );*/

            //startRenderLoop();
        } catch (error) {
            console.error("Error initializing WASM:", error);
        }
    }

    onMount(() => {
        console.log("test");

        initWasm();

        observer = new IntersectionObserver(
            (entries) => {
                entries.forEach((entry) => {
                    isVisible = entry.isIntersecting;
                    if (isVisible) {
                        requestAnimationFrame(render);
                    }
                });
            },
            { threshold: 0.1 },
        );

        observer.observe(canvas);
    });
    function handleInput(event) {
        const { target } = event;
        params[target.name] =
            target.type === "checkbox" ? target.checked : target.value;
    }

    let lastTime = 0;
    function render(timestamp) {
        if (!isVisible) return;

        if (lastTime === 0) {
            lastTime = timestamp;
            requestAnimationFrame(render);
            return;
        }
        const delta = timestamp - lastTime;
        const sampleRate = 20;
        // Simulate real-time data
        if (delta > 1000 / sampleRate) {
            lastTime = timestamp;
            const noise = (Math.random() - 0.5) * 2;
            const timestamp = Date.now();
            const nextValue = Math.sin(timestamp / 1000) * 10 + 20 + noise;
            data = [...data, { timestamp: timestamp, payload: nextValue }];
        }

        draw_sparkline(
            data,
            canvas.width,
            canvas.height,
            ctx,
            params.lineColor,
            parseFloat(params.lineWidth),
            parseInt(params.smoothing),
            parseFloat(params.timeWindow),
            parseFloat(params.burstThreshold),
            params.operationMode,
            params.drawScales,
            params.minValue,
            params.maxValue,
        );
        requestAnimationFrame(render);
    }
</script>

<div>
    <canvas bind:this={canvas} id={canvasId} width="400" height="100"></canvas>

    <label>line color:</label><input
        name="lineColor"
        value={params.lineColor}
        on:input={handleInput}
    /><br />
    <label>line width:</label><input
        name="lineWidth"
        type="number"
        value={params.lineWidth}
        on:input={handleInput}
    /><br />
    <label>smoothing:</label><input
        name="smoothing"
        type="number"
        value={params.smoothing}
        on:input={handleInput}
    /><br />
    <label>Time window:</label><input
        name="timeWindow"
        type="number"
        value={params.timeWindow}
        on:input={handleInput}
    /><br />
    <label>Burst treshold:</label><input
        name="burstThreshold"
        type="number"
        value={params.burstThreshold}
        on:input={handleInput}
    /><br />
    <label>Min Value:</label><input
        name="minValue"
        type="number"
        value={params.minValue}
        on:input={handleInput}
    /><br />
    <label>Max Value:</label><input
        name="maxValue"
        type="number"
        value={params.maxValue}
        on:input={handleInput}
    /><br />
    <label>Operation Mode:</label>
    <select
        name="operationMode"
        value={params.operationMode}
        on:input={handleInput}
    >
        <option value="absolute">Absolute</option>
        <option value="relative">Relative</option>
    </select>
    <br />
    <label>Draw scales:</label>
    <input
        type="checkbox"
        name="drawScales"
        checked={params.drawScales}
        on:input={handleInput}
    />
</div>

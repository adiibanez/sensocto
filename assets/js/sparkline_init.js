//<script type="module" src="./index.js"></script>

import init, { draw_sparkline } from "/assets/sparkline-new.js";

const runWasm = async () => {
    // Instantiate our wasm module
    const wasm = await init("/assets/sparkline-new_bg.wasm");
    window.draw_sparkline = draw_sparkline;
    console.log("Sparkline initialized", draw_sparkline);
};
runWasm();
const esbuild = require("esbuild");
const sveltePlugin = require("esbuild-svelte");
const importGlobPlugin = require("esbuild-plugin-import-glob").default;
const sveltePreprocess = require("svelte-preprocess");
//const { wasmLoader } = require('esbuild-plugin-wasm');

const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const watch = args.includes("--watch");
const deploy = args.includes("--deploy");

let optsClient = {
    entryPoints: [
        "js/app.js",
        "js/worker-storage.js",
        "js/indexeddb.js",
        // "js/sparkline-wasm-element.js",
        //"js/wasm_sparkline_bg.js",
        // "js/wasm_sparkline_bg.wasm",
        // ... add any other custom entry points ...
    ],
    bundle: true,
    minify: deploy,
    // target: "es2017",
    conditions: ["svelte", "browser"],
    outdir: "../priv/static/assets",
    logLevel: "info",
    sourcemap: watch ? "inline" : false,
    tsconfig: "./tsconfig.json",
    plugins: [
        importGlobPlugin(),

        sveltePlugin({
            preprocess: sveltePreprocess(),
            compilerOptions: { dev: !deploy, hydratable: true, css: "injected", customElement: true },
        }),

        /*wasmLoader(
            {
                // (Default) Deferred mode copies the WASM binary to the output directory,
                // and then `fetch()`s it at runtime. This is the default mode.
                mode: 'deferred'

                // Embedded mode embeds the WASM binary in the javascript bundle as a
                // base64 string. Note this will greatly bloat the resulting bundle
                // (the binary will take up about 30% more space this way)
                //  mode: 'embedded'
            })*/

    ],
    assetNames: "/js/[name]", // New: Create /js subdirectory inside /assets.
    //loader: {
    //'.wasm': 'file'
    //},
    target: 'es2022',
    format: 'esm'
};

// let optsServer = {
//     entryPoints: ["js/server.js"],
//     platform: "node",
//     bundle: true,
//     minify: false,
//     target: "node19.6.1",
//     conditions: ["svelte"],
//     outdir: "../priv/svelte",
//     logLevel: "info",
//     sourcemap: true, // Enable source maps
//     tsconfig: "./tsconfig.json",
//     plugins: [
//         importGlobPlugin(),
//         sveltePlugin({
//             preprocess: sveltePreprocess(),
//             compilerOptions: { dev: !deploy, hydratable: true, generate: "ssr", customElement: true },
//         }),
//     ],
//     assetNames: "[name]",
// };

async function buildAndCopy() {
    try {
        await esbuild.build(optsClient);
        // await esbuild.build(optsServer);
        console.log("Build and minification completed.");
    } catch (e) {
        console.error("Build error:", e);
        process.exit(1);
    }
}

if (watch) {
    esbuild
        .context(optsClient)
        .then(ctx => ctx.watch())
        .catch(_error => process.exit(1))

    // esbuild
    //     .context(optsServer)
    //     .then(ctx => ctx.watch())
    //     .catch(_error => process.exit(1))

    buildAndCopy();
} else {
    buildAndCopy();
}
const esbuild = require("esbuild");
const sveltePlugin = require("esbuild-svelte");
const importGlobPlugin = require("esbuild-plugin-import-glob").default;
// svelte-preprocess removed - Svelte 5 has built-in TypeScript support
//const { wasmLoader } = require('esbuild-plugin-wasm');

const fs = require('fs');
const path = require('path');

// Plugin to externalize Three.js and use global THREE from CDN
const threeExternalPlugin = {
    name: 'three-external',
    setup(build) {
        // Intercept imports of 'three' and return the global THREE object
        build.onResolve({ filter: /^three$/ }, args => ({
            path: args.path,
            namespace: 'three-external'
        }));

        build.onLoad({ filter: /.*/, namespace: 'three-external' }, () => ({
            contents: 'module.exports = window.THREE;',
            loader: 'js'
        }));
    }
};

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
    // Output CSS to a different file to avoid overwriting Tailwind's app.css
    outExtension: { ".css": ".bundle.css" },
    logLevel: "info",
    sourcemap: watch ? "inline" : false,
    // Suppress Svelte 5 source map warnings (known compiler issue)
    logOverride: {
        'invalid-source-mappings': 'silent'
    },
    tsconfig: "./tsconfig.json",
    // Add node_modules to resolution path for deps folder imports
    nodePaths: [path.resolve(__dirname, "node_modules")],
    external: [
        "/fonts/*",
        "/images/*",
        // SSR is handled by Elixir, not needed in browser bundle
        "svelte/server"
    ],
    plugins: [
        // Three.js external plugin - uses global THREE from CDN (~2MB bundle savings)
        threeExternalPlugin,

        importGlobPlugin(),

        sveltePlugin({
            compilerOptions: { dev: !deploy, css: "injected" },
            filterWarnings: (warning) => !warning.code?.startsWith('a11y'),
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
    target: 'es2020',
    format: 'iife'
};

function copyFile(source, target) {
    const targetDir = path.dirname(target);

    if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
    }
    fs.copyFileSync(source, target);
    console.log(`Copied file from: ${source} to: ${target}`)
}

function copyAssets() {
    // copyFile('./js/wasm_sparkline_bg.js', '../priv/static/assets/wasm_sparkline_bg.js');
    // copyFile('./js/wasm_sparkline_bg.wasm', '../priv/static/assets/wasm_sparkline_bg.wasm');

    copyFile('./js/sparkline_init.js', '../priv/static/assets/sparkline_init.js');
    copyFile('./js/sparkline-new.js', '../priv/static/assets/sparkline-new.js');
    copyFile('./js/sparkline-new_bg.wasm', '../priv/static/assets/sparkline-new_bg.wasm');

    const imagesDir = path.join(__dirname, './images');
    const destImagesDir = path.join(__dirname, '../priv/static/images');

    console.log("images:", imagesDir);

    if (fs.existsSync(imagesDir)) {
        console.log(`Copying images from: ${imagesDir} to: ${destImagesDir}`)
        fs.readdirSync(imagesDir).forEach(file => {
            const sourceFile = path.join(imagesDir, file);
            const destFile = path.join(destImagesDir, file);
            if (fs.statSync(sourceFile).isFile()) {
                copyFile(sourceFile, destFile)
            }
        })

    } else {
        console.log(`No images directory found. ${imagesDir}`)
    }

    const fontsDir = path.join(__dirname, './fonts');
    const destFontsDir = path.join(__dirname, '../priv/static/fonts');

    console.log("fonts:", fontsDir);

    if (fs.existsSync(fontsDir)) {
        console.log(`Copying fonts from: ${fontsDir} to: ${destFontsDir}`)
        fs.readdirSync(fontsDir).forEach(file => {
            const sourceFile = path.join(fontsDir, file);
            const destFile = path.join(destFontsDir, file);
            if (fs.statSync(sourceFile).isFile()) {
                copyFile(sourceFile, destFile)
            }
        })

    } else {
        console.log(`No fonts directory found. ${fontsDir}`)
    }
}

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

if (watch) {
    console.log("esbuild Watching...");
    copyAssets();
    esbuild
        .context(optsClient)
        .then(ctx => ctx.watch())
        .catch(_error => process.exit(1))

} else if (deploy) {
    console.log("esbuild Deploying...");
    copyAssets();
    esbuild.build(optsClient)
    // .context(optsClient)
    // .then(process.exit(0))
    // .catch(_error => process.exit(1))
}
// esbuild
//     .context(optsServer)
//     .then(ctx => ctx.watch())
//     .catch(_error => process.exit(1))


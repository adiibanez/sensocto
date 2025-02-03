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
    external: [
        "/fonts/*",
        "/images/*"
    ],
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

function copyFile(source, target) {
    const targetDir = path.dirname(target);

    if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
    }
    fs.copyFileSync(source, target);
    console.log(`Copied file from: ${source} to: ${target}`)
}

function copyAssets() {
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

    esbuild
        .context(optsClient)
        .then(process.exit(0))
        .catch(_error => process.exit(1))
}
// esbuild
//     .context(optsServer)
//     .then(ctx => ctx.watch())
//     .catch(_error => process.exit(1))


const esbuild = require("esbuild");
const sveltePlugin = require("esbuild-svelte");
const importGlobPlugin = require("esbuild-plugin-import-glob").default;
const sveltePreprocess = require("svelte-preprocess");
const fs = require('fs');
const path = require('path');

const args = process.argv.slice(2);
const watch = args.includes("--watch");
const deploy = args.includes("--deploy");

let optsClient = {
    entryPoints: [
        "js/app.js",
        //"js/sparkline-element.js",
        // ... add any other custom entry points ...
    ],
    bundle: true,
    minify: deploy,
    target: "es2017",
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
    ],
    assetNames: "/js/[name]", // New: Create /js subdirectory inside /assets.
};

let optsServer = {
    entryPoints: ["js/server.js"],
    platform: "node",
    bundle: true,
    minify: false,
    target: "node19.6.1",
    conditions: ["svelte"],
    outdir: "../priv/svelte",
    logLevel: "info",
    sourcemap: watch ? "inline" : false,
    tsconfig: "./tsconfig.json",
    plugins: [
        importGlobPlugin(),
        sveltePlugin({
            preprocess: sveltePreprocess(),
            compilerOptions: { dev: !deploy, hydratable: true, generate: "ssr" },
        }),
    ],
    assetNames: "[name]",
};

function copyFile(source, target) {
    const targetDir = path.dirname(target);

    if (!fs.existsSync(targetDir)) {
        fs.mkdirSync(targetDir, { recursive: true });
    }
    fs.copyFileSync(source, target);
    console.log(`Copied file from: ${source} to: ${target}`)
}


async function buildAndCopy() {
    try {
        await esbuild.build(optsClient);
        await esbuild.build(optsServer);
        copyFile("js/worker-storage.js", "../priv/static/assets/worker-storage.js");
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

    esbuild
        .context(optsServer)
        .then(ctx => ctx.watch())
        .catch(_error => process.exit(1))

    buildAndCopy();


} else {
    buildAndCopy();
}
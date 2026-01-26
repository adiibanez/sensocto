import { defineConfig } from "tsup";

export default defineConfig([
  // Main entry point
  {
    entry: ["src/index.ts"],
    format: ["cjs", "esm"],
    dts: true,
    sourcemap: true,
    clean: true,
    splitting: false,
    external: ["three"],
    outDir: "dist",
  },
  // Three.js integration (separate entry)
  {
    entry: ["src/three/index.ts"],
    format: ["cjs", "esm"],
    dts: true,
    sourcemap: true,
    splitting: false,
    external: ["three"],
    outDir: "dist/three",
  },
]);

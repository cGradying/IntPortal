import { defineConfig } from "vite";
import { sveltekit } from "@sveltejs/kit/vite";
// @ts-expect-error type error without @types/node package
import process from "node:process";
// @ts-expect-error type error without @types/node package
import { readFileSync } from "node:fs";
const version = JSON.parse(readFileSync(new URL("./package.json", import.meta.url), "utf8")).version;
const host = process.env.TAURI_DEV_HOST;

// https://vite.dev/config/
export default defineConfig(() => ({
  plugins: [sveltekit()],
  // The website (site/) runs its own tests with its own config.
  test: { include: ["src/**/*.test.ts"] },
  // Review builds (tauri --debug) show the demo-data entry on sign-in.
  define: { __WEB__: JSON.stringify(process.env.INTPORTAL_WEB === "1"), __APP_VERSION__: JSON.stringify(version), __REVIEW__: JSON.stringify(process.env.TAURI_ENV_DEBUG === "true" || process.env.NODE_ENV !== "production") },

  // Vite options tailored for Tauri development and only applied in `tauri dev` or `tauri build`
  //
  // 1. prevent Vite from obscuring rust errors
  clearScreen: false,
  // 2. tauri expects a fixed port, fail if that port is not available
  server: {
    port: 1420,
    strictPort: true,
    host: host || "127.0.0.1",
    hmr: host
      ? {
          protocol: "ws",
          host,
          port: 1421,
        }
      : undefined,
    watch: {
      // 3. tell Vite to ignore watching `src-tauri`
      ignored: ["**/src-tauri/**"],
    },
  },
}));

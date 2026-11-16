import { sveltekit } from "@sveltejs/kit/vite";
// @ts-expect-error no @types/node here, as in the app
import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

/** @param {string} p */
const here = (p) => fileURLToPath(new URL(p, import.meta.url));

export default defineConfig({
  plugins: [sveltekit()],
  resolve: {
    // The app's LAR reads the student's theme from the app's store; the site has
    // no student, so it gets a stand-in that always answers "the SIS portal".
    alias: [{ find: /^\.\.\/state\.svelte$/, replacement: here("./src/lib/appState.ts") }],
  },
  server: { fs: { allow: [here("..")] } },
  test: { include: ["src/**/*.test.ts"] },
});

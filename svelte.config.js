// Tauri doesn't have a Node.js server to do proper SSR
// so we use adapter-static with a fallback to index.html to put the site in SPA mode
// See: https://svelte.dev/docs/kit/single-page-apps
// See: https://v2.tauri.app/start/frontend/sveltekit/ for more info
import adapter from "@sveltejs/adapter-static";
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** @type {import('@sveltejs/kit').Config} */
const config = {
  preprocess: vitePreprocess(),
  kit: {
    // The browser demo (spec 052, scripts/web.sh) is built into the website at /app.
    adapter: adapter(process.env.INTPORTAL_WEB === "1" ? { pages: "site/static/app", assets: "site/static/app", fallback: "index.html" } : { fallback: "index.html" }),
    paths: { base: process.env.INTPORTAL_WEB === "1" ? "/app" : "" },
  },
};

export default config;

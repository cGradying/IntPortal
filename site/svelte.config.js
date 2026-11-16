import adapter from "@sveltejs/adapter-static";
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** Every page is prerendered to plain files, so any static host serves it (051 C1). */
export default {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({ pages: "build", assets: "build", fallback: "404.html", strict: true }),
    alias: { $app_lib: "../src/lib" },
    prerender: { handleHttpError: "fail", handleMissingId: "fail" },
  },
};

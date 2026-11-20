import adapter from "@sveltejs/adapter-static";
import { vitePreprocess } from "@sveltejs/vite-plugin-svelte";

/** Every page is prerendered to plain files, so any static host serves it (051 C1). */
export default {
  preprocess: vitePreprocess(),
  kit: {
    adapter: adapter({ pages: "build", assets: "build", fallback: "404.html", strict: true }),
    alias: { $app_lib: "../src/lib" },
    // 060 C22: small stylesheets go in the page, one round trip fewer.
    inlineStyleThreshold: 8192,
    prerender: {
      // /app is the browser demo, a folder of plain files (spec 052), not a page of this site.
      handleHttpError: ({ path, message }) => {
        if (!path.startsWith("/app")) throw new Error(message);
      },
      handleMissingId: "fail",
    },
  },
};

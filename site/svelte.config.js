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
    // Written into each prerendered page as a <meta> CSP, with hashes for SvelteKit's own inline
    // script. GitHub Pages sends no headers of its own, so this is the policy that applies there.
    csp: {
      mode: "hash",
      directives: {
        "default-src": ["self"],
        "script-src": ["self", "wasm-unsafe-eval"],
        "style-src": ["self", "unsafe-inline"],
        "img-src": ["self", "data:", "blob:"],
        "media-src": ["self"],
        "font-src": ["self", "data:"],
        "connect-src": ["self", "https://api.github.com"],
        "frame-src": ["self"],
        "worker-src": ["self"],
        "object-src": ["none"],
        "base-uri": ["self"],
        "form-action": ["none"],
      },
    },
    prerender: {
      // /app is the browser demo, a folder of plain files (spec 052), not a page of this site.
      handleHttpError: ({ path, message }) => {
        if (!path.startsWith("/app")) throw new Error(message);
      },
      handleMissingId: "fail",
    },
  },
};

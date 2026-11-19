/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />
// Spec 058 C7: pages you've opened still load with no signal. The pages a
// student needs first are saved on install, with the code and styles each one
// names (a page whose code is missing reloads itself forever offline) and the
// Latin fonts. Every other page and file is saved the first time it loads. The
// 3D hero is only ever imported, never named in a page, so nobody downloads it
// just because the worker installed. The browser demo, the reel, videos and downloads never are.
import { build, prerendered, version } from "$service-worker";

const sw = self as unknown as ServiceWorkerGlobalScope;
const CACHE = `site-${version}`;
const FIRST = ["/", "/help", "/features", "/download", "/search.json"];
const SHELL = prerendered.filter((p) => FIRST.includes(p));
const never = (u: URL) => u.origin !== sw.location.origin || /^\/(app|reel)(\/|$)/.test(u.pathname) || /\.(mp4|apk|ipa|dmg|msi|deb|AppImage|wasm)$/.test(u.pathname);

sw.addEventListener("install", (e) => {
  e.waitUntil(
    caches.open(CACHE).then(async (c) => {
      await c.addAll(SHELL);
      // The static adapter's fallback page renders any route from the saved
      // code; absent in dev, so it may fail.
      await c.add("/404.html").catch(() => {});
      // The code the first pages and the offline fallback name, the error
      // page's own code (shown offline for unsaved pages), and everything those
      // import statically. Dynamic import() is left out, which keeps the hero out.
      const named = new Set(build.filter((f) => /-latin-[\w-]*normal\.[\w-]+\.woff2$|\/nodes\/1\.[\w-]+\.js$|\/assets\/1\.[\w-]+\.css$/.test(f)));
      for (const page of [...SHELL, "/404.html"]) {
        const hit = await c.match(page);
        if (!hit) continue;
        for (const m of (await hit.text()).matchAll(/["'](\.{0,2}\/?[^"']*_app\/immutable\/[^"']+)["']/g)) {
          const path = new URL(m[1], new URL(page, sw.location.origin)).pathname;
          if (build.includes(path)) named.add(path);
        }
      }
      const queue = [...named].filter((f) => f.endsWith(".js"));
      while (queue.length) {
        const f = queue.pop()!;
        const text = await (await fetch(f)).text();
        for (const m of text.matchAll(/(?:from|import)\s*["']([^"']+\.js)["']/g)) {
          const path = new URL(m[1], new URL(f, sw.location.origin)).pathname;
          if (build.includes(path) && !named.has(path)) {
            named.add(path);
            queue.push(path);
          }
        }
      }
      await c.addAll([...named]);
      await sw.skipWaiting();
    }),
  );
});

sw.addEventListener("activate", (e) => {
  e.waitUntil(
    caches.keys().then(async (keys) => {
      await Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)));
      await sw.clients.claim();
    }),
  );
});

sw.addEventListener("fetch", (e) => {
  const req = e.request;
  const url = new URL(req.url);
  if (req.method !== "GET" || never(url)) return;
  e.respondWith(
    (async () => {
      const cache = await caches.open(CACHE);
      // Hashed build files never change: the saved copy is the copy.
      if (build.includes(url.pathname)) {
        const hit = await cache.match(url.pathname);
        if (hit) return hit;
      }
      try {
        const res = await fetch(req);
        if (res.ok && res.type === "basic") cache.put(req, res.clone());
        return res;
      } catch (err) {
        const hit = await cache.match(req, { ignoreSearch: true });
        if (hit) return hit;
        if (req.mode === "navigate") {
          const shell = await cache.match("/404.html");
          if (shell) return shell;
        }
        throw err;
      }
    })(),
  );
});

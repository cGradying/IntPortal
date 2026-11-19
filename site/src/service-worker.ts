/// <reference types="@sveltejs/kit" />
/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />
// Spec 058 C7: pages you've opened still load with no signal. The pages a
// student needs first are saved on install (prerendered HTML reads without its
// scripts); code, fonts and every other page are saved the first time they load,
// so nobody downloads the 3D hero who never runs it. The browser demo, the reel, videos and downloads never are.
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
      // The static adapter's fallback page renders any route from the cached
      // code; absent in dev, so it may fail.
      await c.add("/404.html").catch(() => {});
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

// 051 C3: the built site calls no third party. Lists every absolute URL host in
// build/ and fails on any outside the allow list (GitHub for releases and source).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import { gzipSync } from "node:zlib";

// altstore.io and sidestore.io are link targets in the iPhone steps (060 C2), never loads.
const ALLOW = new Set(["github.com", "api.github.com", "www.w3.org", "svelte.dev", "altstore.io", "sidestore.io"]);
const files = [];
const walk = (d) => readdirSync(d).forEach((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : files.push(join(d, f))));
walk(fileURLToPath(new URL("../build", import.meta.url)));
const bad = new Map();
// build/app is the app itself (spec 052): its code names the PUP hosts the phone app
// talks to, but the browser demo sends nothing (052 C7).
for (const f of files.filter((f) => /\.(html|js|css|json)$/.test(f) && !/[\\/]build[\\/]app[\\/]/.test(f))) {
  for (const m of readFileSync(f, "utf8").matchAll(/https?:\/\/([a-z0-9.-]+\.[a-z]{2,})/gi)) {
    if (!ALLOW.has(m[1].toLowerCase())) bad.set(m[1], f);
  }
}
// 057 C1: Three.js only in the hero's chunk, reached by a dynamic import(): no page's HTML preloads
// it and no other script imports it statically, so no other page loads it.
const chunks = files.filter((f) => /[\\/]_app[\\/]immutable[\\/].*\.js$/.test(f));
const three = chunks.filter((f) => readFileSync(f, "utf8").includes("isWebGLRenderer"));
for (const t of three) {
  const name = t.split(/[\\/]/).pop();
  for (const f of files.filter((f) => f !== t && /\.(html|js)$/.test(f))) {
    const text = readFileSync(f, "utf8");
    const named = text.includes(name);
    if (named && f.endsWith(".html")) bad.set(`three (${name}) preloaded`, f);
    else if (named && new RegExp(`(?:from|import)\\s*["'][^"']*${name.replace(/\./g, "\\.")}["']`).test(text)) bad.set(`three (${name}) imported statically`, f);
  }
}
if (three.length > 1) bad.set(`three in ${three.length} chunks`, three.join(", "));

// 058 C4: the search index stays small enough to fetch on weak data.
const idx = files.find((f) => /[\\/]build[\\/]search\.json$/.test(f));
if (!idx) bad.set("search.json missing", "build/");
else {
  const raw = readFileSync(idx);
  const gz = gzipSync(raw).length;
  if (raw.length > 48 * 1024 || gz > 16 * 1024) bad.set(`search.json is ${raw.length} B, ${gz} B gzip (max 48 KB, 16 KB)`, idx);
}

// 060 C22: the site's CSS (files, or inlined in pages) carries only Latin Pixelify. Its
// Cyrillic files are small enough to inline as data: URIs, so look for the range too.
for (const f of files.filter((f) => /\.(html|css)$/.test(f) && !/[\\/]build[\\/]app[\\/]/.test(f))) {
  if (/pixelify-sans-cyrillic|U\+0400-045F/i.test(readFileSync(f, "utf8"))) bad.set("Cyrillic Pixelify font", f);
}

if (bad.size) {
  for (const [what, f] of bad) console.error(`${what.includes(" ") ? what : `third-party host ${what}`} in ${f}`);
  process.exit(1);
}
console.log(`${files.length} files, no third-party hosts; three in ${three.length ? "the hero's chunk only" : "no chunk yet"}.`);

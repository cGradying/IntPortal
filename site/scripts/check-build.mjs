// 051 C3: the built site calls no third party. Lists every absolute URL host in
// build/ and fails on any outside the allow list (GitHub for releases and source).
import { readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const ALLOW = new Set(["github.com", "api.github.com", "www.w3.org", "svelte.dev"]);
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
if (bad.size) {
  for (const [host, f] of bad) console.error(`third-party host ${host} in ${f}`);
  process.exit(1);
}
console.log(`${files.length} files, no third-party hosts.`);

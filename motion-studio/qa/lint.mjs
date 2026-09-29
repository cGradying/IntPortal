// node qa/lint.mjs — enforces the render contract.
// 1. No clocks or randomness in film code: Math.random, Date.now, performance.now,
//    setTimeout, setInterval, requestAnimationFrame, CSS transition/animation.
// 2. Frames are a pure function of t: seeking the same t after different
//    histories (forward, backward, random order) produces identical pixels.
import { execFileSync } from "node:child_process";
import { mkdirSync, readdirSync, readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { chromium } from "playwright";
import { CHROME_ARGS, openFilm, serve } from "../lib/serve.mjs";

const BANNED = [/Math\.random/, /Date\.now/, /performance\.now/, /setTimeout/, /setInterval/, /requestAnimationFrame/, /(^|[;{\s])transition\s*:/, /(^|[;{\s])animation\s*:/, /new Date\(\)/];
const files = [];
const walk = (d) => readdirSync(d).forEach((f) => (statSync(join(d, f)).isDirectory() ? walk(join(d, f)) : /\.(js|css|html)$/.test(f) && files.push(join(d, f))));
walk("film");
let bad = 0;
for (const f of files) {
  readFileSync(f, "utf8").split("\n").forEach((line, i) => {
    const code = line.replace(/\/\/.*$/, "");
    for (const re of BANNED) if (re.test(code)) { console.log(`${f}:${i + 1}: banned ${re}`); bad++; }
  });
}
console.log(`static: ${files.length} files, ${bad} violations`);

const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await openFilm(browser, url);
const D = await page.evaluate(() => window.DURATION);
mkdirSync("out/qa/lint", { recursive: true });
let n = 0;
const shot = async () => { const f = `out/qa/lint/${n++}.png`; await page.screenshot({ path: f, type: "png" }); return f; };
// Frames must match to within rasterizer noise: under 50 pixels off by more than 8 levels, and <= 0.05% of pixels differing at all.
const same = (a, b) => execFileSync("python3", ["-c", `
import numpy as np, sys
from PIL import Image
a=np.asarray(Image.open(sys.argv[1]).convert('RGB')).astype(int); b=np.asarray(Image.open(sys.argv[2]).convert('RGB')).astype(int)
d=np.abs(a-b).max(2); print(int(d.max()), float((d>0).mean()), int((d>8).sum()))`, a, b]).toString().trim().split(" ").map(Number);
const probes = [0.3, 4.1, 9.7, 14.2, 23.5, 36.1, 47.3, 58.9, 72.4, 80.8, 88.2, D - 1].filter((t) => t < D);
const first = [];
for (const t of probes) { await page.evaluate((t) => window.seek(t), t); first.push(await shot(t)); }
let mism = 0;
const order = [...probes.keys()].reverse();
for (const k of order) {
  await page.evaluate((t) => window.seek(t), probes[(k + 5) % probes.length] * 0.5); // disturb history
  await page.evaluate((t) => window.seek(t), probes[k]);
  const h = await shot(probes[k]);
  const [mx, frac, big] = same(h, first[k]);
  if (big >= 50 || frac > 0.0005) { console.log(`frame mismatch at t=${probes[k]}: max ${mx}, ${(frac * 100).toFixed(3)}% px`); mism++; }
}
await browser.close();
server.close();
console.log(`determinism: ${probes.length} probes, ${mism} mismatches`);
process.exit(bad || mism ? 1 : 0);

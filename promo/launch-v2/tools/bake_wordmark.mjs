// Bakes the "IntPortal" wordmark (brand font: Pixelify Sans) into a bitmap for the voxel assembly.
// usage: node tools/bake_wordmark.mjs [fontPx] -> prints ASCII art + writes composition/assets/lib/wordmark.js
import fs from "node:fs";
import path from "node:path";
import url from "node:url";
const here = path.dirname(url.fileURLToPath(import.meta.url));
const font = path.resolve(here, "../composition/assets/fonts/PixelifySans.ttf");
const px = +(process.argv[2] || 20), weight = +(process.argv[3] || 700), text = process.argv[4] || "IntPortal", write = process.argv[5] !== "nowrite";
const { chromium } = await import(process.env.PLAYWRIGHT_PATH || "playwright");   // npm i playwright (or point PLAYWRIGHT_PATH at an install)
const b = await chromium.launch(); const p = await b.newPage();
const tmp = path.resolve(process.env.TMPDIR || "/tmp", "wm_bake.html");
fs.writeFileSync(tmp, `<style>@font-face{font-family:P;src:url(file://${font});font-weight:400 700}</style><canvas id=c width=600 height=120></canvas><span style="font-family:P">x</span>`);
await p.goto("file://" + tmp);
await p.evaluate(() => document.fonts.ready);
const rows = await p.evaluate(async ({ px, weight, text }) => {
  await document.fonts.load(`${weight} ${px}px P`);
  const c = document.getElementById("c"), g = c.getContext("2d", { willReadFrequently: true });
  g.clearRect(0, 0, 600, 120); g.fillStyle = "#000"; g.textBaseline = "alphabetic"; g.font = `${weight} ${px}px P`;
  // no anti-aliasing tricks available on canvas text; threshold instead
  g.fillText(text, 4, 80);
  const d = g.getImageData(0, 0, 600, 120).data; const W = 600, H = 120;
  let minX = W, maxX = 0, minY = H, maxY = 0;
  const on = (x, y) => d[(y * W + x) * 4 + 3] > 127;
  for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) if (on(x, y)) { if (x < minX) minX = x; if (x > maxX) maxX = x; if (y < minY) minY = y; if (y > maxY) maxY = y; }
  const out = [];
  for (let y = minY; y <= maxY; y++) { let r = ""; for (let x = minX; x <= maxX; x++) r += on(x, y) ? "#" : "."; out.push(r); }
  return out;
}, { px, weight, text });
console.log(rows.join("\n")); console.log(`\n${rows[0].length} x ${rows.length}`);
if (write) fs.writeFileSync(path.resolve(here, "../composition/assets/lib/wordmark.js"), `/* baked by tools/bake_wordmark.mjs (${px}px, ${weight}) */\nwindow.IP = window.IP || {};\nwindow.IP.WORDMARK = ${JSON.stringify(rows)};\n`);
await b.close();

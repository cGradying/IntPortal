// node scripts/stills.mjs 0 1.5 7 ...  -> out/stills/b<beat>.png (beats, fractional ok)
// node scripts/stills.mjs --range 0 27 1   (from, to, step)
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import { mkdirSync, readFileSync } from "node:fs";
import path from "node:path";

const args = process.argv.slice(2);
let beats = [];
if (args[0] === "--range") {
  const [a, b, s] = args.slice(1).map(Number);
  for (let x = a; x <= b + 1e-9; x += s) beats.push(+x.toFixed(3));
} else beats = args.map(Number);
const FRAMES = 5428, FPS = 60, NB = 196;
const grid = JSON.parse(readFileSync("beats.json", "utf8")).beats;
const tOf = (b) => (grid?.length ? grid[Math.floor(b)] + (grid[Math.floor(b) + 1] - grid[Math.floor(b)]) * (b % 1) : (b * FRAMES) / FPS / NB);
mkdirSync("out/stills", { recursive: true });
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const browserExecutable = "/root/.cache/hyperframes/chrome/chrome-headless-shell/linux-152.0.7977.30/chrome-headless-shell-linux64/chrome-headless-shell";
const composition = await selectComposition({ serveUrl, id: "Main", browserExecutable });
for (const b of beats) {
  const frame = Math.min(FRAMES - 1, Math.round(tOf(b) * FPS));
  await renderStill({ composition, serveUrl, frame, output: `out/stills/b${String(b).padStart(5, "0")}.png`, browserExecutable, chromiumOptions: { gl: "swangle" } });
  process.stdout.write(`${b} `);
}
console.log("done");

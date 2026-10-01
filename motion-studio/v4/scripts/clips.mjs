// node scripts/clips.mjs [name...]  -> public/clips/<name>.webm (VP9 with alpha)
// Writes hyperframes/grid.js from the film's beat grid first, so the clips'
// beats match Remotion's exactly; sets each composition's duration from it.
import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
const FRAMES = 5428, FPS = 60, NB = 196, NOMINAL = FRAMES / FPS / NB;
const j = JSON.parse(readFileSync("beats.json", "utf8"));
const beats = j.beats?.length ? j.beats : Array.from({ length: NB + 1 }, (_, i) => i * NOMINAL);
writeFileSync("hyperframes/grid.js", `window.GRID = ${JSON.stringify({ nominal: NOMINAL, beats })};\n`);
const B = (b) => { const i = Math.floor(b); return beats[i] + (beats[i + 1] - beats[i]) * (b - i); };
export const CLIPS = { pixel: [115.5, 120.4], ascii: [119.5, 124.4], obsidian: [123.5, 128.4], halftone: [137.5, 140.4] };
mkdirSync("public/clips", { recursive: true });
const names = process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(CLIPS);
for (const n of names) {
  const [a, b] = CLIPS[n];
  const dur = (B(b) - B(a)).toFixed(4);
  const f = `hyperframes/${n}.html`;
  writeFileSync(f, readFileSync(f, "utf8").replace(/data-duration="[\d.]+"/, `data-duration="${dur}"`));
  execFileSync("npx", ["hyperframes", "render", "hyperframes", "-c", `${n}.html`, "--format", "webm", "--fps", "60", "--quiet", "-o", `public/clips/${n}.webm`], { stdio: "inherit" });
  console.log(n, dur);
}
writeFileSync("src/clips.json", JSON.stringify(CLIPS));

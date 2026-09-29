// node qa/contact.mjs [--from beat] [--to beat] [--step 1] [--offset 0.12] [--tag name]
// One frame per beat (a beat + offset seconds, so hits have landed), tiled
// into contact sheets: out/qa/<tag>-NN.png (8 x 6 cells at 400 px — about the
// size the film is watched at on a phone).
import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { chromium } from "playwright";
import { CHROME_ARGS, openFilm, serve } from "../lib/serve.mjs";

const arg = (k, d) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : d;
};
const beats = JSON.parse(readFileSync("beats.json", "utf8")).beats;
const b0 = Number(arg("from", 0)), b1 = Number(arg("to", beats.length - 1));
const step = Number(arg("step", 1)), offset = Number(arg("offset", 0.12)), tag = arg("tag", "sheet");
const dir = `out/qa/${tag}`;
rmSync(dir, { recursive: true, force: true });
mkdirSync(dir, { recursive: true });

const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await openFilm(browser, url);
const list = [];
for (let b = b0; b <= b1; b += step) {
  const i = Math.floor(b), fr = b - i;
  const t = beats[i] + (beats[Math.min(i + 1, beats.length - 1)] - beats[i]) * fr + offset;
  await page.evaluate((t) => window.seek(t), t);
  const f = `${dir}/b${String(b.toFixed(2)).padStart(7, "0")}.jpg`;
  await page.screenshot({ path: f, type: "jpeg", quality: 85 });
  list.push({ f, label: `b${b} ${t.toFixed(2)}s` });
}
await browser.close();
server.close();

const per = 48;
for (let p = 0; p * per < list.length; p++) {
  const chunk = list.slice(p * per, (p + 1) * per);
  writeFileSync(`${dir}/list.txt`, chunk.map((c) => `file '${c.f.split("/").pop()}'`).join("\n"));
  const rows = Math.ceil(chunk.length / 8);
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", `${dir}/list.txt`,
    "-vf", `scale=400:225,drawtext=text='%{eif\\:n+${b0 + p * per * step}\\:d}':x=6:y=4:fontsize=16:fontcolor=white:box=1:boxcolor=black@0.6,tile=8x${rows}:padding=4:color=0x333333`,
    "-frames:v", "1", `out/qa/${tag}-${String(p).padStart(2, "0")}.png`]);
}
console.log(`${list.length} frames → out/qa/${tag}-*.png`);

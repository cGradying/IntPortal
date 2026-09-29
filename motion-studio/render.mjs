// node render.mjs [--from s] [--to s] [--fps 60] [--workers 4] [--out out/intportal-launch.mp4] [--scale 1]
// Pure function of time: every frame is window.seek(t) then a screenshot, piped
// into ffmpeg (H.264, yuv420p, CRF 16). Workers render contiguous ranges, the
// segments are concatenated losslessly and muxed with audio/mix.wav.
import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { chromium } from "playwright";
import { CHROME_ARGS, openFilm, serve } from "./lib/serve.mjs";

const arg = (k, d) => {
  const i = process.argv.indexOf(`--${k}`);
  return i > 0 ? process.argv[i + 1] : d;
};
const TL = JSON.parse(readFileSync("timeline.json", "utf8"));
const fps = Number(arg("fps", TL.fps));
const workers = Number(arg("workers", 4));
const scale = Number(arg("scale", 1));
const out = arg("out", "out/intportal-launch.mp4");
const W = Math.round(TL.width * scale), H = Math.round(TL.height * scale);

const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const probe = await openFilm(browser, url);
const duration = await probe.evaluate(() => window.DURATION);
await probe.close();
const t0 = Number(arg("from", 0)), t1 = Number(arg("to", duration));
const f0 = Math.round(t0 * fps), f1 = Math.round(t1 * fps);
const total = f1 - f0;
mkdirSync("out/seg", { recursive: true });
console.log(`render ${t0}s→${t1}s  ${total} frames @${fps}fps  ${W}x${H}  ${workers} workers`);

const started = Date.now();
let done = 0;
async function worker(i) {
  const a = f0 + Math.floor((total * i) / workers), b = f0 + Math.floor((total * (i + 1)) / workers);
  const seg = `out/seg/seg${i}.mp4`;
  const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "image2pipe", "-framerate", String(fps), "-c:v", "mjpeg", "-i", "-",
    ...(scale !== 1 ? ["-vf", `scale=${W}:${H}:flags=lanczos`] : []),
    "-c:v", "libx264", "-preset", "medium", "-crf", "16", "-pix_fmt", "yuv420p", "-r", String(fps), "-movflags", "+faststart", seg], { stdio: ["pipe", "inherit", "inherit"] });
  const page = await openFilm(browser, url);
  for (let f = a; f < b; f++) {
    await page.evaluate((t) => window.seek(t), f / fps);
    const buf = await page.screenshot({ type: "jpeg", quality: 97 });
    if (!ff.stdin.write(buf)) await new Promise((r) => ff.stdin.once("drain", r));
    done++;
    if (i === 0 && done % 120 === 0) {
      const el = (Date.now() - started) / 1000;
      console.log(`${done}/${total}  ${(done / el).toFixed(1)} fps  eta ${((total - done) / (done / el) / 60).toFixed(1)} min`);
    }
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  await page.close();
  return seg;
}
const segs = await Promise.all(Array.from({ length: workers }, (_, i) => worker(i)));
await browser.close();
server.close();

writeFileSync("out/seg/list.txt", segs.map((s) => `file '${s.replace("out/seg/", "")}'`).join("\n"));
const hasAudio = existsSync("audio/mix.wav") && !process.argv.includes("--silent");
const ff = spawn("ffmpeg", ["-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", "out/seg/list.txt",
  ...(hasAudio ? ["-ss", String(t0), "-t", String(t1 - t0), "-i", "audio/mix.wav", "-map", "0:v", "-map", "1:a", "-c:a", "aac", "-b:a", "320k", "-shortest"] : []),
  "-c:v", "copy", "-movflags", "+faststart", out], { stdio: "inherit" });
await new Promise((r) => ff.on("close", r));
rmSync("out/seg", { recursive: true, force: true });
console.log(`wrote ${out} in ${((Date.now() - started) / 60000).toFixed(1)} min`);

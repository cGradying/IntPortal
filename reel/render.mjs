// @ts-nocheck
// Renders the reel (spec 054): a Vite server for film.html, then window.seek(t)
// per frame in Chrome, piped into ffmpeg. Adapted from the October film's engine.
//   node reel/render.mjs --w 1080 --h 1920 [--from 0 --to 46] [--out reel/out/silent-9x16.mp4]
//   node reel/render.mjs --w 1080 --h 1920 --sheet 1,6,13,20,25,30,37,43   (a contact sheet)
// Needs PLAYWRIGHT (playwright-core/index.mjs), CHROME (a Chrome with GPU) and ffmpeg.
import { spawn } from "node:child_process";
import { mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { createServer } from "vite";

const arg = (k, d) => {
  const i = process.argv.indexOf("--" + k);
  return i > 0 ? process.argv[i + 1] : d;
};
const W = Number(arg("w", 1080));
const H = Number(arg("h", 1920));
const FPS = Number(arg("fps", 30));
const root = fileURLToPath(new URL("..", import.meta.url));
const out = arg("out", `reel/out/silent-${W > H ? "16x9" : "9x16"}.mp4`);
mkdirSync(fileURLToPath(new URL("./out/", import.meta.url)), { recursive: true });

const server = await createServer({ configFile: false, root, logLevel: "error", server: { port: 5199, strictPort: false, fs: { strict: false } } });
await server.listen();
const pw = await import(process.env.PLAYWRIGHT ?? "playwright-core");
const browser = await pw.chromium.launch({ executablePath: process.env.CHROME, args: ["--use-angle=metal", "--enable-gpu", "--ignore-gpu-blocklist"] });
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
page.on("pageerror", (e) => console.error("page error:", e.message));
page.on("console", (m) => m.type() === "error" && console.error("console:", m.text()));
await page.goto(`http://localhost:${server.config.server.port}/reel/film.html`);
await page.waitForFunction(() => typeof window.seek === "function", null, { timeout: 60000 });
const dur = await page.evaluate(() => window.DUR);
const seek = (t) => page.evaluate((t) => window.seek(t), t);

const sheet = arg("sheet");
if (sheet) {
  const times = sheet.split(",").map(Number);
  const ff = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-i", "-", "-vf", `scale=${Math.round(W / 4)}:-1,tile=${times.length}x1`, "-frames:v", "1", arg("out", "reel/out/sheet.png")], { stdio: ["pipe", "inherit", "inherit"] });
  for (const t of times) {
    await seek(t);
    ff.stdin.write(await page.screenshot({ type: "png" }));
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
} else {
  const from = Number(arg("from", 0));
  const to = Number(arg("to", dur));
  const ff = spawn("ffmpeg", ["-v", "error", "-y", "-f", "image2pipe", "-framerate", String(FPS), "-i", "-", "-c:v", "libx264", "-preset", "slow", "-crf", "18", "-pix_fmt", "yuv420p", "-movflags", "+faststart", out], { stdio: ["pipe", "inherit", "inherit"] });
  const n = Math.round((to - from) * FPS);
  for (let i = 0; i < n; i++) {
    await seek(from + i / FPS);
    ff.stdin.write(await page.screenshot({ type: "jpeg", quality: 95 }));
    if (i % 150 === 0) console.log(`frame ${i}/${n}`);
  }
  ff.stdin.end();
  await new Promise((r) => ff.on("close", r));
  console.log(`wrote ${out}`);
}
await browser.close();
await server.close();

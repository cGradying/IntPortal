// @ts-nocheck
// Dev only: writes docs/images/banner.png, day.gif (one day over Sta. Mesa) and
// scenes.gif (every hand-drawn campus) from the app's own shader renderer.
// Needs ffmpeg. Run: PLAYWRIGHT=/path/to/playwright-core/index.mjs CHROME=/path/to/chrome-headless-shell node scripts/readme-media.mjs
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createServer } from "vite";

const pw = await import(process.env.PLAYWRIGHT ?? "playwright-core");
const server = await createServer({ configFile: false, root: process.cwd(), logLevel: "error", server: { port: 5198, strictPort: false, fs: { strict: false } } });
await server.listen();
const url = `http://localhost:${server.config.server.port}/scripts/readme-media/index.html`;
const browser = await pw.chromium.launch({ executablePath: process.env.CHROME, args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });
const out = "docs/images";
mkdirSync(out, { recursive: true });

function gif(dir, count, fps, width, file) {
  const filters = `fps=${fps},scale=${width}:-1:flags=neighbor`;
  const pal = join(dir, "pal.png");
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", String(fps), "-i", join(dir, "f%03d.png"), "-vf", `${filters},palettegen=max_colors=96:stats_mode=full`, pal]);
  execFileSync("ffmpeg", ["-y", "-loglevel", "error", "-framerate", String(fps), "-i", join(dir, "f%03d.png"), "-i", pal, "-lavfi", `${filters}[x];[x][1:v]paletteuse=dither=none`, "-loop", "0", file]);
}
const save = (dir, urls, from = 0) => urls.forEach((u, i) => writeFileSync(join(dir, `f${String(from + i).padStart(3, "0")}.png`), Buffer.from(u.split(",")[1], "base64")));

try {
  const page = await browser.newPage({ viewport: { width: 1600, height: 500 } });
  await page.goto(url);
  await page.waitForFunction(() => typeof window.banner === "function");
  await page.evaluate(() => window.banner());
  await page.waitForTimeout(500);
  await page.screenshot({ path: `${out}/banner.png`, clip: { x: 0, y: 0, width: 1600, height: 500 } });
  console.log("banner");

  // One day: 24 h in 72 frames, the jeepney crossing the street meanwhile.
  const day = mkdtempSync(join(tmpdir(), "day-"));
  const shots = Array.from({ length: 72 }, (_, i) => ({ hour: i / 3, ms: 2000 + i * 180 }));
  save(day, await page.evaluate(([n, s]) => window.frames(n, s), ["Sta. Mesa", shots]));
  gif(day, shots.length, 12, 576, `${out}/day.gif`);
  console.log("day.gif");

  // Every hand-drawn campus, at the golden hour, half a second each.
  const names = ["Sta. Mesa", "San Juan", "Parañaque", "Taguig", "Quezon City", "Caloocan", "Sto. Tomas", "Ragay", "Mariveles"];
  const sc = mkdtempSync(join(tmpdir(), "scenes-"));
  let n = 0;
  for (const name of names) {
    const urls = await page.evaluate(([nm, s]) => window.frames(nm, s), [name, Array.from({ length: 6 }, (_, i) => ({ hour: 17.6 + i * 0.1, ms: 3000 + i * 250 }))]);
    save(sc, urls, n);
    n += urls.length;
  }
  gif(sc, n, 6, 576, `${out}/scenes.gif`);
  console.log("scenes.gif");
} finally {
  await browser.close();
  await server.close();
}

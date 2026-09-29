// node qa/frames.mjs b1 b2 ... — full-res JPEGs at given beats → out/qa/f-<beat>.jpg
import { chromium } from "playwright";
import { readFileSync, mkdirSync } from "node:fs";
import { CHROME_ARGS, openFilm, serve } from "../lib/serve.mjs";
const beats = JSON.parse(readFileSync("beats.json", "utf8")).beats;
const tb = (n) => { const i = Math.floor(n); return beats[i] + (beats[i + 1] - beats[i]) * (n - i); };
mkdirSync("out/qa", { recursive: true });
const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await openFilm(browser, url);
for (const a of process.argv.slice(2)) {
  await page.evaluate((t) => window.seek(t), tb(Number(a)));
  await page.screenshot({ path: `out/qa/f-${a}.jpg`, type: "jpeg", quality: 88 });
}
await browser.close(); server.close();

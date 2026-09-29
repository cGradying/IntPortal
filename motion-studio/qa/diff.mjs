// node qa/diff.mjs t prevT — render t fresh, then after seeking prevT, compare.
import { chromium } from "playwright";
import { CHROME_ARGS, openFilm, serve } from "../lib/serve.mjs";
const [t, prev] = process.argv.slice(2).map(Number);
const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await openFilm(browser, url);
await page.evaluate((t) => window.seek(t), t);
await page.screenshot({ path: "out/qa/da.png" });
await page.evaluate((t) => window.seek(t), prev);
await page.evaluate((t) => window.seek(t), t);
await page.screenshot({ path: "out/qa/db.png" });
await browser.close(); server.close();

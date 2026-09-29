// node qa/sheet-isko.mjs → out/qa/isko-sheet.png
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import { CHROME_ARGS, serve } from "../lib/serve.mjs";
mkdirSync("out/qa", { recursive: true });
const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("pageerror", (e) => console.error("[page]", e.message));
await page.goto(`${url}/film/sheet-isko.html`);
await page.waitForFunction(() => window.__ready === true);
await page.screenshot({ path: "out/qa/isko-sheet.png" });
await browser.close(); server.close();

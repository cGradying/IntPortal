// node qa/isko-sprites.mjs -> v4/public/isko/<expr>.png (transparent, 4 css px per sprite px)
import { chromium } from "playwright";
import { mkdirSync } from "node:fs";
import { CHROME_ARGS, serve } from "../lib/serve.mjs";
mkdirSync("v4/public/isko", { recursive: true });
const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await browser.newPage({ viewport: { width: 1000, height: 420 } });
page.on("pageerror", (e) => console.error("[page]", e.message));
await page.goto(`${url}/film/isko-sprites.html`);
await page.waitForFunction(() => window.__ready === true);
for (const e of ["open", "blink", "happy", "wow", "wink", "focus"])
  await page.locator(`#c-${e}`).screenshot({ path: `v4/public/isko/${e}.png`, omitBackground: true });
await browser.close(); server.close();

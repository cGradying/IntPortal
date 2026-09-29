// node qa/lab.mjs [page] → out/qa/lab.png
import { chromium } from "playwright";
import { CHROME_ARGS, serve } from "../lib/serve.mjs";
const { server, url } = await serve();
const browser = await chromium.launch({ args: CHROME_ARGS });
const page = await browser.newPage({ viewport: { width: 1920, height: 1080 } });
page.on("pageerror", (e) => console.error("[page]", e.message));
page.on("console", (m) => m.type() === "error" && console.error("[console]", m.text()));
await page.goto(`${url}/film/${process.argv[2] || "lab.html"}`);
await page.waitForFunction(() => window.__ready === true, null, { timeout: 60000 });
await page.screenshot({ path: `out/qa/${process.argv[3] || "lab"}.png` });
await browser.close(); server.close();

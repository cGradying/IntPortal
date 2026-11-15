// @ts-nocheck
// Dev only: renders every campus scene at 06:00, 12:00, 18:30 and 22:00 in
// headless Chromium, writes docs/images/campus/<scene>.png (four hours side by
// side, 2x) and contact-sheet.png, and times shader compile + first frame
// under a 4x CPU throttle.
// Run: PLAYWRIGHT=/path/to/node_modules/playwright-core node scripts/campus-sheet.mjs [--perf]
import { mkdirSync, writeFileSync } from "node:fs";
import { createServer } from "vite";

const pw = await import(process.env.PLAYWRIGHT ?? "playwright-core");
const server = await createServer({ configFile: false, root: process.cwd(), logLevel: "error", server: { port: 5199, strictPort: false } });
await server.listen();
const url = `http://localhost:${server.config.server.port}/scripts/campus-sheet/index.html`;
const browser = await pw.chromium.launch({ args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"] });

try {
  if (process.argv.includes("--perf")) {
    for (const force of ["webgl2", "webgl"]) {
      const runs = [];
      for (let i = 0; i < 5; i++) {
        const page = await browser.newPage();
        const cdp = await page.context().newCDPSession(page);
        await page.goto(url);
        await page.waitForFunction(() => typeof window.perf === "function");
        await cdp.send("Emulation.setCPUThrottlingRate", { rate: 4 });
        runs.push(await page.evaluate((f) => window.perf(f), force));
        await page.close();
      }
      const med = (k) => runs.map((r) => r[k]).sort((a, b) => a - b)[2].toFixed(1);
      console.log(`${runs[0].mode}: build ${med("buildMs")} ms, compile + first frame ${med("firstFrameMs")} ms (median of 5, 4x CPU throttle)`);
    }
  } else {
    const page = await browser.newPage({ viewport: { width: 1720, height: 900 } });
    await page.goto(url);
    await page.waitForFunction(() => typeof window.sheet === "function");
    const rows = await page.evaluate(() => window.sheet());
    const dir = "docs/images/campus";
    mkdirSync(dir, { recursive: true });
    // One strip per scene: the four hours side by side, each 2x.
    for (const { id, urls } of rows) {
      const strip = await browser.newPage({ viewport: { width: 4 * 384 + 24, height: 160 } });
      await strip.setContent(`<body style="margin:0;background:#0b0710;display:flex;gap:8px">${urls.map((u) => `<img src="${u}" style="width:384px;height:160px;image-rendering:pixelated">`).join("")}</body>`);
      writeFileSync(`${dir}/${id}.png`, await strip.screenshot());
      await strip.close();
    }
    await page.screenshot({ path: `${dir}/contact-sheet.png`, fullPage: true });
    console.log(`${rows.length} scenes written to ${dir}`);
  }
} finally {
  await browser.close();
  await server.close();
}

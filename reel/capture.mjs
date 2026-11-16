// @ts-nocheck
// The reel's footage (spec 054): the real app, in the browser demo (spec 052),
// driven through a day by Playwright and recorded with Chrome's screencast.
// Demo data only. Writes footage/<clip>.mp4 at 30 fps, 1170x2532.
// Run with the site served (cd site && pnpm build && pnpm preview):
//   PLAYWRIGHT=/path/to/playwright-core/index.mjs CHROME=/path/to/chrome-headless-shell SITE=http://localhost:4173 node reel/capture.mjs [clip...]
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { fileURLToPath } from "node:url";

const pw = await import(process.env.PLAYWRIGHT ?? "playwright-core");
const SITE = process.env.SITE ?? "http://localhost:4173";
const OUT = fileURLToPath(new URL("./footage/", import.meta.url));
mkdirSync(OUT, { recursive: true });
// Real GPU WebGL (Metal on a Mac): software WebGL draws a couple of frames a second.
const browser = await pw.chromium.launch({ executablePath: process.env.CHROME, headless: true, args: (process.env.GL ?? "--use-angle=metal --enable-gpu --ignore-gpu-blocklist").split(" ") });

/** A fresh demo at a fixed morning, so every take shows the same day. */
async function open(clock = "2026-11-17T10:12:00+08:00") {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true, timezoneId: "Asia/Manila" });
  const page = await ctx.newPage();
  await page.clock.install({ time: new Date(clock) });
  await page.clock.resume();
  // The night room, the brand's own look, whatever the hour.
  await page.addInitScript(() => localStorage.setItem("room", "night"));
  page.on("pageerror", (e) => console.error("page error:", e.message));
  return page;
}

async function record(page, name, script) {
  const cdp = await page.context().newCDPSession(page);
  const frames = [];
  cdp.on("Page.screencastFrame", async ({ data, metadata, sessionId }) => {
    frames.push({ data, t: metadata.timestamp });
    await cdp.send("Page.screencastFrameAck", { sessionId }).catch(() => {});
  });
  await cdp.send("Page.startScreencast", { format: "jpeg", quality: 94, maxWidth: 1170, maxHeight: 2532 });
  await script(page);
  await cdp.send("Page.stopScreencast");
  const dir = mkdtempSync(join(tmpdir(), `reel-${name}-`));
  let list = "ffconcat version 1.0\n";
  frames.forEach((f, i) => {
    writeFileSync(join(dir, `${i}.jpg`), Buffer.from(f.data, "base64"));
    const next = frames[i + 1]?.t ?? f.t + 1 / 30;
    list += `file ${i}.jpg\nduration ${Math.max(0.001, next - f.t).toFixed(4)}\n`;
  });
  writeFileSync(join(dir, "list.txt"), list);
  execFileSync("ffmpeg", ["-v", "error", "-y", "-f", "concat", "-safe", "0", "-i", join(dir, "list.txt"), "-vf", "fps=30,scale=1170:2532,format=yuv420p", "-c:v", "libx264", "-crf", "14", "-preset", "slow", join(OUT, `${name}.mp4`)]);
  console.log(`${name}: ${frames.length} frames, ${(frames.at(-1).t - frames[0].t).toFixed(1)} s`);
}

const tab = (page, name) => page.getByRole("button", { name, exact: true }).last().click();
const wait = (page, ms) => page.waitForTimeout(ms);

const CLIPS = {
  // The portal builds and the dive lands on Today.
  dive: async () => {
    const page = await open();
    await record(page, "dive", async (p) => {
      await p.goto(`${SITE}/app/`);
      await wait(p, 9000);
    });
    return page;
  },
  // Today: the class up next, then a deadline ticked Done.
  today: async () => {
    const page = await open();
    await page.goto(`${SITE}/app/`);
    await wait(page, 9000);
    await record(page, "today", async (p) => {
      await wait(p, 1200);
      await p.getByRole("button", { name: /^Mark .* done$/ }).first().click();
      await wait(p, 2600);
      await p.mouse.wheel(0, 420);
      await wait(p, 2200);
    });
    return page;
  },
  // Schedule, the day and then the week.
  schedule: async () => {
    const page = await open();
    await page.goto(`${SITE}/app/`);
    await wait(page, 9000);
    await record(page, "schedule", async (p) => {
      await wait(p, 400);
      await tab(p, "Schedule");
      await wait(p, 2200);
      await p.getByRole("tab", { name: "Week", exact: true }).first().click();
      await wait(p, 2600);
    });
    return page;
  },
  // Grades and the trend drawing itself.
  grades: async () => {
    const page = await open();
    await page.goto(`${SITE}/app/`);
    await wait(page, 9000);
    await record(page, "grades", async (p) => {
      await wait(p, 400);
      await tab(p, "Grades");
      await wait(p, 3600);
    });
    return page;
  },
  // Study: the decks with what's known and due, then a card reviewed.
  study: async () => {
    const page = await open();
    await page.goto(`${SITE}/app/`);
    await wait(page, 9000);
    await record(page, "study", async (p) => {
      await wait(p, 400);
      await tab(p, "Study");
      await wait(p, 2000);
      await p.locator("button.tile").first().click();
      await wait(p, 1500);
      await p.getByRole("button", { name: /^Review \d+ due$/ }).first().click();
      await wait(p, 1400);
      await p.locator(".session .flipper").click();
      await wait(p, 1400);
      await p.getByRole("button", { name: /^Good/ }).first().click();
      await wait(p, 1600);
    });
    return page;
  },
};

for (const name of process.argv.slice(2).length ? process.argv.slice(2) : Object.keys(CLIPS)) {
  const page = await CLIPS[name]();
  await page.context().close();
}
await browser.close();

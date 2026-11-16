// @ts-nocheck
// Dev only: writes the README screenshots (docs/images/*.png) from the real
// interface on the sample student, at phone size, 3x.
// Run with a dev server up (pnpm vite dev --port 5301):
//   PLAYWRIGHT=/path/to/playwright-core/index.mjs CHROME=/path/to/chrome-headless-shell node scripts/readme-shots.mjs [url]
import { mkdirSync } from "node:fs";

const pw = await import(process.env.PLAYWRIGHT ?? "playwright-core");
const url = process.argv[2] ?? "http://localhost:5301/";
const browser = await pw.chromium.launch({
  executablePath: process.env.CHROME,
  args: ["--use-angle=swiftshader", "--enable-unsafe-swiftshader"],
});
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 3, hasTouch: true, isMobile: true });
// 10:20 on a Monday, so a class is in session.
await page.clock.setFixedTime(new Date("2026-11-16T10:20:00+08:00"));
const dir = "docs/images";
mkdirSync(dir, { recursive: true });
const shot = async (name) => {
  await page.waitForTimeout(1600);
  await page.screenshot({ path: `${dir}/${name}.png` });
  console.log("wrote", name);
};
const tap = (name) => page.getByRole("button", { name, exact: false }).first().click();

await page.goto(url);
await page.waitForTimeout(2500);
await shot("talk");
await tap("Skip to sign in");
await shot("landing");
await page.getByText("Look around first").first().click();
await page.waitForTimeout(3000);
const hello = page.getByRole("button", { name: /step through|skip|continue/i }).first();
if (await hello.count()) await hello.click().catch(() => {});
await shot("today");
for (const tab of ["Schedule", "Grades", "Study"]) {
  await page.getByRole("button", { name: tab, exact: true }).last().click();
  await shot(tab.toLowerCase());
}
await browser.close();

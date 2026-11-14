// @ts-expect-error type error without @types/node package
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";
import { holdsStill } from "./quiet";

describe("nothing draws where nobody is looking (#189)", () => {
  it("a hidden app holds everything still", () => {
    expect(holdsStill({ hidden: true, covered: false, inShell: false })).toBe(true);
    expect(holdsStill({ hidden: true, covered: false, inShell: true })).toBe(true);
  });
  it("LAR's window stills the screens behind it, not LAR himself", () => {
    expect(holdsStill({ hidden: false, covered: true, inShell: true })).toBe(true);
    expect(holdsStill({ hidden: false, covered: true, inShell: false })).toBe(false);
  });
  it("in plain view, things move", () => {
    expect(holdsStill({ hidden: false, covered: false, inShell: true })).toBe(false);
  });
  it("the CSS pauses every animation under the same two attributes", () => {
    const css = readFileSync(new URL("./app.css", import.meta.url), "utf8");
    expect(css).toMatch(/:root\[data-hidden\] \*,[\s\S]*?:root\[data-behind\] \.shell \*[\s\S]*?animation-play-state: paused !important;/);
  });
});

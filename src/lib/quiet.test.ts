import css from "./app.css?raw";
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
    expect(css).toMatch(/:root\[data-hidden\] \*,[\s\S]*?:root\[data-behind\] \.shell \*[\s\S]*?animation-play-state: paused !important;/);
  });
});

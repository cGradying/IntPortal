import { describe, expect, it } from "vitest";
import { PALETTES, contrast, derive } from "./rooms";
// @ts-expect-error type error without @types/node package
import { readFileSync } from "node:fs";

const css = readFileSync(new URL("./app.css", import.meta.url), "utf8");

describe("derived rooms", () => {
  for (const [id, p] of Object.entries(PALETTES)) {
    it(`${id} keeps text readable on its cards`, () => {
      const r = derive(p);
      expect(contrast(r["--ink"], r["--card"])).toBeGreaterThanOrEqual(7);
      expect(contrast(r["--ink-2"], r["--card"])).toBeGreaterThanOrEqual(4.5);
      expect(contrast(r["--ink-3"], r["--card"])).toBeGreaterThanOrEqual(3);
      expect(contrast(r["--gold"], r["--card"])).toBeGreaterThanOrEqual(3);
      expect(contrast(r["--on-gold"], r["--gold"])).toBeGreaterThanOrEqual(3);
      for (let i = 1; i <= 6; i++) expect(contrast(r[`--s${i}`], r["--card"])).toBeGreaterThanOrEqual(3);
    });
  }

  it("light and dark rooms get the matching scheme", () => {
    expect(derive(PALETTES.ivory)["color-scheme"]).toBe("light");
    expect(derive(PALETTES.dracula)["color-scheme"]).toBe("dark");
  });

  it("contrast is the WCAG ratio", () => {
    expect(contrast("#000000", "#ffffff")).toBeCloseTo(21, 5);
    expect(contrast("#777777", "#ffffff")).toBeCloseTo(4.48, 2);
  });
});

describe("app.css", () => {
  it("c21_reduce_motion_stops_loops", () => {
    const reduce = css.slice(css.indexOf("prefers-reduced-motion: reduce"));
    expect(reduce.slice(0, reduce.indexOf("}"))).toContain("animation-iteration-count: 1 !important");
  });

  it("c6_controls_take_the_room_accent", () => {
    expect(css).toContain("accent-color: var(--gold)");
  });
});

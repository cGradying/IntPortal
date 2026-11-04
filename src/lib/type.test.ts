import { describe, expect, it } from "vitest";
// @ts-expect-error: node's fs, read at test time only; the app itself doesn't use it.
import { readFileSync } from "node:fs";
import { drawable, pixels } from "./pixelNum";

const css: string = readFileSync("src/lib/app.css", "utf8");

describe("Pixel-bridged type (spec 045 C8)", () => {
  it("reads in the phone's face and labels in Pixelify", () => {
    expect(css).toMatch(/--font-display: var\(--font-ui\)/);
    expect(css).toMatch(/--font-body: var\(--font-ui\)/);
    expect(css).toMatch(/--font-label: var\(--font-pixel\)/);
  });
  it("keeps Montserrat and Source Sans as the Classic text style", () => {
    const classic = css.slice(css.indexOf(':root[data-type="classic"]'));
    expect(classic).toMatch(/--font-display: "Montserrat Variable"/);
    expect(classic).toMatch(/--font-body: "Source Sans 3 Variable"/);
  });
  it("c9_no_pixel_font_on_times: a label that holds data reads in the phone's face", () => {
    expect(css).toMatch(/\.label\.data \{[^}]*font-family: var\(--font-data\)/);
  });
});

describe("Pixel numerals (spec 045 C10)", () => {
  it("draws every hero number the app shows", () => {
    for (const n of ["0123456789", "7:30AM", "12PM", "1.28", "100%", "—"]) expect(drawable(n)).toBe(true);
  });
  it("leaves anything else as text", () => {
    expect(drawable("n/a")).toBe(false);
    expect(drawable("")).toBe(false);
  });
  it("is tabular: digits are all five art pixels wide", () => {
    for (const d of "0123456789") expect(pixels(d).w).toBe(5);
    expect(pixels("10").w).toBe(11);
  });
  it("keeps every pixel inside its box", () => {
    const { w, h, on } = pixels("7:30AM");
    expect(on.length).toBeGreaterThan(0);
    expect(on.every(([x, y]) => x >= 0 && x < w && y >= 0 && y < h)).toBe(true);
  });
});

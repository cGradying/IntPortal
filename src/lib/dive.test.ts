import { describe, expect, it } from "vitest";
import { rgbOf, styleOf } from "./dive";

describe("rgbOf", () => {
  it("reads the forms the rooms use, and drops alpha", () => {
    expect(rgbOf(" #f4f2ef ")).toBe(0xf4f2ef);
    expect(rgbOf("#abc")).toBe(0xaabbcc);
    expect(rgbOf("rgba(245, 178, 39, 0.07)")).toBe(0xf5b227);
    expect(rgbOf("rgb(122 17 40 / 0.07)")).toBe(0x7a1128);
  });
  it("falls back on anything else", () => {
    expect(rgbOf("", 7)).toBe(7);
    expect(rgbOf("color-mix(in srgb, red, blue)", 9)).toBe(9);
  });
});

describe("styleOf", () => {
  it("unpacks 0xRRGGBBAA, even when the top bit makes the int negative", () => {
    expect(styleOf(0xf5b227ff | 0)).toBe("rgba(245,178,39,1.000)");
    expect(styleOf(0x00000000)).toBe("rgba(0,0,0,0.000)");
  });
});

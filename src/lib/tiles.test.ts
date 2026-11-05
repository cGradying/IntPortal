import { describe, expect, it } from "vitest";
import { FALLBACK_SIS } from "./portals";
import { fpsFor, hex, packPortal, stageFor } from "./tiles";

describe("stageFor", () => {
  it("connects while signing in, opens once signed in, rests otherwise", () => {
    expect(stageFor({ busy: false, open: false })).toBe("rest");
    expect(stageFor({ busy: true, open: false })).toBe("connecting");
    expect(stageFor({ busy: false, open: true })).toBe("open");
  });
});

describe("fpsFor (spec 010 C22)", () => {
  it("runs 60 fps while the frame forms", () => {
    expect(fpsFor(0.3, "rest", null)).toBe(60);
  });
  it("drops to 30 fps at rest, and back to 60 while swiping", () => {
    expect(fpsFor(5, "rest", null)).toBe(30);
    expect(fpsFor(5, "rest", null, true)).toBe(60);
  });
  it("runs 60 fps for the connecting pulse", () => {
    expect(fpsFor(5, "connecting", null)).toBe(60);
  });
  it("runs 60 fps through the opening wave, then settles", () => {
    expect(fpsFor(5.2, "open", 5)).toBe(60);
    expect(fpsFor(8, "open", 5)).toBe(30);
  });
});

describe("hex", () => {
  it("formats 0xRRGGBB as a CSS colour", () => {
    expect(hex(0x1a1622)).toBe("#1a1622");
    expect(hex(0x060607)).toBe("#060607");
  });
});

describe("packPortal", () => {
  it("packs shape, corner, motif, ramp and accent in the scene's order", () => {
    expect(packPortal(FALLBACK_SIS)).toEqual([6, 8, 0, 0, 0x3b1220, 0x7a1c2c, 0xb5412a, 0xe08a35, 0xf3cf6a, 0xe8b04a]);
    expect(packPortal({ ...FALLBACK_SIS, shape: { cols: 7, rows: 7, corner: "cut" }, motif: "aurora" }).slice(0, 4)).toEqual([7, 7, 1, 5]);
  });
});

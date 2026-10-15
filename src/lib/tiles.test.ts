import { describe, expect, it } from "vitest";
import { fpsFor, hex, stageFor } from "./tiles";

describe("stageFor", () => {
  it("connects while signing in, opens once signed in, rests otherwise", () => {
    expect(stageFor({ busy: false, open: false })).toBe("rest");
    expect(stageFor({ busy: true, open: false })).toBe("connecting");
    expect(stageFor({ busy: false, open: true })).toBe("open");
  });
});

describe("fpsFor (spec 010 C22)", () => {
  it("runs 30 fps while the frame forms", () => {
    expect(fpsFor(0.3, "rest", null)).toBe(30);
  });
  it("drops to 15 fps at rest", () => {
    expect(fpsFor(5, "rest", null)).toBe(15);
  });
  it("runs 30 fps for the connecting pulse", () => {
    expect(fpsFor(5, "connecting", null)).toBe(30);
  });
  it("runs 30 fps through the opening wave, then settles", () => {
    expect(fpsFor(5.2, "open", 5)).toBe(30);
    expect(fpsFor(8, "open", 5)).toBe(15);
  });
});

describe("hex", () => {
  it("formats 0xRRGGBB as a CSS colour", () => {
    expect(hex(0x1a1622)).toBe("#1a1622");
    expect(hex(0x060607)).toBe("#060607");
  });
});

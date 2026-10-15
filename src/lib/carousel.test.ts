import { describe, expect, it } from "vitest";
import { release, settle, step } from "./carousel";

describe("release (spec 010 C13)", () => {
  it("snaps to the nearest portal when let go slowly", () => {
    expect(release(1.3, 0, 6)).toBe(1);
    expect(release(1.6, 0, 6)).toBe(2);
  });
  it("a flick moves one portal even when barely dragged", () => {
    expect(release(1.1, 2.5, 6)).toBe(2);
    expect(release(1.9, -2.5, 6)).toBe(1);
  });
  it("never skips more than one portal or leaves the ends", () => {
    expect(release(1.2, 40, 6)).toBe(2);
    expect(release(0.1, -5, 6)).toBe(0);
    expect(release(5.2, 5, 6)).toBe(5);
  });
});

describe("step and settle", () => {
  it("springs to the target without overshooting far, then settles", () => {
    let s = { pos: 1, vel: 0 };
    let peak = 1;
    for (let i = 0; i < 120; i++) {
      s = step(s, 2, 1 / 60);
      peak = Math.max(peak, s.pos);
    }
    expect(peak).toBeLessThan(2.06);
    expect(settle(s, 2)).toBe(true);
  });
  it("is not settled mid-flight", () => {
    expect(settle(step({ pos: 1, vel: 0 }, 2, 1 / 60), 2)).toBe(false);
  });
  it("survives a long frame without exploding", () => {
    const s = step({ pos: 0, vel: 0 }, 3, 0.5);
    expect(Math.abs(s.pos)).toBeLessThan(6);
  });
});

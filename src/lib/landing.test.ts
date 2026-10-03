import { describe, expect, it } from "vitest";
import { PIECES } from "./pentomino";
import { DIVE, landingAt, restAt } from "./landing";

const first = { returning: false, reduce: false, steppedAt: null };

describe("landingAt", () => {
  it("opens dark, assembles piece by piece, ignites, lets LAR through, glimpses, then rests", () => {
    const seen: string[] = [];
    for (let t = 0; t <= restAt(first) + 0.5; t += 0.05) {
      const p = landingAt(t, first).phase;
      if (seen.at(-1) !== p) seen.push(p);
    }
    expect(seen).toEqual(["dark", "assembling", "igniting", "arrival", "glimpse", "rest"]);
  });

  it("lands every piece, one after another, before the swirl ignites", () => {
    const placed: number[] = [];
    let t = 0;
    while (landingAt(t, first).phase !== "igniting") {
      placed.push(landingAt(t, first).placed);
      t += 0.02;
    }
    expect(placed[0]).toBe(0);
    expect(placed.at(-1)).toBe(PIECES.length);
    expect(placed).toEqual([...placed].sort((a, b) => a - b));
  });

  it("skips the build for a student coming back: the frame is already standing", () => {
    const back = { ...first, returning: true };
    expect(restAt(back)).toBeLessThan(restAt(first) / 2);
    for (let t = 0; t < restAt(back); t += 0.05) {
      expect(landingAt(t, back).phase).not.toBe("assembling");
      expect(landingAt(t, back).placed).toBe(PIECES.length);
    }
  });

  it("starts at rest under Reduce Motion", () => {
    expect(landingAt(0, { ...first, reduce: true })).toMatchObject({ phase: "rest", placed: PIECES.length });
  });

  it("dives only after stepping through, and only from rest", () => {
    const early = { ...first, steppedAt: 1 };
    expect(landingAt(1.2, early).phase).toBe("assembling");
    expect(landingAt(restAt(first) + 0.01, early).phase).toBe("stepping");
    const at = restAt(first) + 3;
    const go = { ...first, steppedAt: at };
    expect(landingAt(at - 0.01, go).phase).toBe("rest");
    const mid = landingAt(at + DIVE / 2, go);
    expect(mid.phase).toBe("stepping");
    expect(mid.k).toBeCloseTo(0.5);
    expect(landingAt(at + DIVE, go).phase).toBe("entered");
  });
});

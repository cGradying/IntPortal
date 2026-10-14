import { describe, expect, it } from "vitest";
import { DIVE, FORM, landingAt, restAt } from "./landing";

const first = { returning: false, reduce: false, steppedAt: null };

describe("landingAt", () => {
  it("forms the frame, then rests under the form", () => {
    expect(landingAt(0, first).phase).toBe("forming");
    expect(landingAt(FORM / 2, first)).toEqual({ phase: "forming", k: 0.5 });
    expect(landingAt(FORM, first).phase).toBe("rest");
  });

  it("skips the build for a returning student and under Reduce Motion (spec 010 C8)", () => {
    expect(landingAt(0, { ...first, returning: true }).phase).toBe("rest");
    expect(landingAt(0, { ...first, reduce: true }).phase).toBe("rest");
  });

  it("steps through over DIVE seconds, then enters", () => {
    const o = { ...first, steppedAt: 2 };
    expect(landingAt(1.9, o).phase).toBe("rest");
    expect(landingAt(2 + DIVE / 2, o).phase).toBe("stepping");
    expect(landingAt(2 + DIVE / 2, o).k).toBeCloseTo(0.5);
    expect(landingAt(2 + DIVE, o).phase).toBe("entered");
  });

  it("waits for the frame before stepping, and enters at once under Reduce Motion", () => {
    expect(landingAt(0.1, { ...first, steppedAt: 0 }).phase).toBe("forming");
    expect(landingAt(0, { ...first, reduce: true, steppedAt: 0 }).phase).toBe("entered");
  });

  it("is reachable once the frame stands", () => {
    expect(restAt(first)).toBe(FORM);
  });
});

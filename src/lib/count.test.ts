import { describe, expect, it } from "vitest";
import { between, startOf } from "./count.svelte";

describe("hero numbers (spec 045 C14)", () => {
  it("c14_counts_from_the_last_seen_value, not from zero", () => {
    expect(startOf(1.62, 1.28)).toBe(1.62);
    expect(startOf(undefined, 1.28)).toBe(1.28);
  });
  it("lands exactly and stays there", () => {
    expect(between(1.62, 1.28, 0)).toBe(1.62);
    expect(between(1.62, 1.28, 1)).toBeCloseTo(1.28);
    expect(between(1.62, 1.28, 3)).toBeCloseTo(1.28);
  });
});

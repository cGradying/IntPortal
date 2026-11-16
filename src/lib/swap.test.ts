import { describe, expect, it } from "vitest";
import { direction, isNew } from "./swap";

describe("swap", () => {
  it("arrives from the side it lies on", () => {
    expect(direction(2, 5)).toBe(1);
    expect(direction(5, 2)).toBe(-1);
    expect(direction(3, 3)).toBe(0);
  });
  it("plays a one-time moment only for a signature not yet seen", () => {
    expect(isNew(null, "1.75|2.00")).toBe(true);
    expect(isNew("1.75|2.00", "1.75|2.00")).toBe(false);
    expect(isNew("1.75|2.00", "1.50|1.75|2.00")).toBe(true);
  });
});

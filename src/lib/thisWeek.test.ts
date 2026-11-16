import { describe, expect, it } from "vitest";
import { inThisWeek } from "./thisWeek";

describe("050 C12 this week in a syllabus", () => {
  const wed = new Date(2026, 10, 18, 15, 0);
  it("holds Monday through Sunday", () => {
    expect(inThisWeek("2026-11-16", wed)).toBe(true);
    expect(inThisWeek("2026-11-22", wed)).toBe(true);
  });
  it("leaves out the weeks around it and undated rows", () => {
    expect(inThisWeek("2026-11-15", wed)).toBe(false);
    expect(inThisWeek("2026-11-23", wed)).toBe(false);
    expect(inThisWeek(null, wed)).toBe(false);
  });
  it("counts a Sunday as the end of its own week", () => {
    expect(inThisWeek("2026-11-16", new Date(2026, 10, 22))).toBe(true);
  });
});

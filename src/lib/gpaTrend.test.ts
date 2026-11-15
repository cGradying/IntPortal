import { describe, expect, it } from "vitest";
import { plot, spoken, type TermPoint } from "./gpaTrend";

const pt = (v: number, term = "1st Semester 2024-2025"): TermPoint => ({ label: "x", term, v });

describe("the GPA trend", () => {
  it("says the change from the term before, where lower is better", () => {
    expect(spoken([pt(2.0, "2nd Semester 2025-2026"), pt(1.75)])).toBe("GPA 1.75, up from 2.00 in 2nd Semester 2025-2026");
    expect(spoken([pt(1.5, "1st Semester 2025-2026"), pt(1.75)])).toBe("GPA 1.75, down from 1.50 in 1st Semester 2025-2026");
    expect(spoken([pt(1.5, "Summer 2025"), pt(1.5)])).toBe("GPA 1.50, same as 1.50 in Summer 2025");
    expect(spoken([pt(1.25)])).toBe("GPA 1.25");
    expect(spoken([])).toBe("");
  });

  it("draws better grades higher, on a scale that always holds the guides", () => {
    const { points, guides } = plot([pt(2.0), pt(1.5), pt(1.75)]);
    expect(points.map((p) => p.x)).toEqual([4, 50, 96]);
    expect(guides.map((g) => g.v)).toEqual([1, 1.5, 2]);
    expect(guides[0].y).toBe(4);
    expect(points[1].y).toBe(guides[1].y);
    expect(points[0].y).toBe(guides[2].y);
    expect(points[1].y).toBeLessThan(points[2].y);
  });

  it("stretches the scale for a grade past the guides", () => {
    const { points } = plot([pt(1.0), pt(3.0)]);
    expect([points[0].y, points[1].y]).toEqual([4, 36]);
  });
});

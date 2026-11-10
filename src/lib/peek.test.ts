import { describe, expect, it } from "vitest";
import { PAGES, isTap, nextPage } from "./peek";

describe("peek", () => {
  it("c37_the_peek_shows_today_schedule_grades_study_then_closes", () => {
    expect(PAGES.map((p) => p.id)).toEqual(["today", "schedule", "grades", "study"]);
    expect(nextPage(0)).toBe(1);
    expect(nextPage(PAGES.length - 1)).toBeNull();
  });
  it("c36_a_tap_is_short_and_still_a_swipe_is_not", () => {
    expect(isTap(3, 2, 120)).toBe(true);
    expect(isTap(40, 0, 120)).toBe(false);
    expect(isTap(0, 0, 900)).toBe(false);
  });
});

import { describe, expect, it } from "vitest";
import { barSegments, comboText, nextRun, noteHz, tierOf } from "./doneRun";

describe("a run of dones (spec 045 C18)", () => {
  it("c18_combo_climbs_within_4s_and_resets", () => {
    let r = nextRun(null, 1000);
    expect(r.step).toBe(0);
    r = nextRun(r, 3000);
    expect(r.step).toBe(1);
    r = nextRun(r, 6999);
    expect(r.step).toBe(2);
    r = nextRun(r, 11000);
    expect(r.step).toBe(0);
  });
  it("tiers: the first nudges, the next two shake, then harder", () => {
    expect([0, 1, 2, 3, 9].map(tierOf)).toEqual(["nudge", "shake", "shake", "hard", "hard"]);
  });
  it("shows a count from the second on", () => {
    expect(comboText(0)).toBe("");
    expect(comboText(2)).toBe("×3");
  });
  it("climbs in pitch and stops at the top of the scale", () => {
    expect(noteHz(1)).toBeGreaterThan(noteHz(0));
    expect(noteHz(40)).toBe(noteHz(9));
  });
  it("keeps the bar to a row's width", () => {
    expect(barSegments(3, 2)).toBe(5);
    expect(barSegments(20, 2)).toBe(8);
  });
});

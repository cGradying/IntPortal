import { describe, expect, it } from "vitest";
import { barSegments, noteHz } from "./doneRun";

describe("the done pluck and bar (spec 045 C18)", () => {
  it("c18_note_is_the_first_of_the_scale", () => {
    expect(noteHz(0)).toBeCloseTo(523.25);
    expect(noteHz(1)).toBeGreaterThan(noteHz(0));
    expect(noteHz(40)).toBe(noteHz(9));
  });
  it("c18_bar_segments_cap_at_eight", () => {
    expect(barSegments(3, 2)).toBe(5);
    expect(barSegments(20, 2)).toBe(8);
  });
});

import { describe, expect, it } from "vitest";
import { bezier, dismissed, ms, pageMove, rubber, still, tabDir, TAB_ORDER, tokens } from "./motion";

describe("motion vocabulary (spec 045 C29-C33)", () => {
  it("c29_tab_direction_follows_tab_order", () => {
    expect(tabDir("today", "grades")).toBe(1);
    expect(tabDir("you", "study")).toBe(-1);
    expect(tabDir("study", "study")).toBe(1);
    expect(TAB_ORDER).toEqual(["today", "schedule", "grades", "study", "you"]);
  });

  it("c29_page_leaves_one_way_and_arrives_from_the_other", () => {
    const out = pageMove(1, false, false);
    const into = pageMove(1, true, false);
    expect(out.x).toBe(-into.x);
    expect(Math.abs(into.x)).toBeGreaterThanOrEqual(8);
    expect(Math.abs(into.x)).toBeLessThanOrEqual(16);
    expect(out.ms).toBeLessThan(into.ms); // leaving is quicker than arriving
  });

  it("c31_reduce_motion_keeps_the_fade_and_drops_the_travel", () => {
    const t = tokens();
    const m = pageMove(-1, true, true);
    expect(m.x).toBe(0);
    expect(m.y).toBe(0);
    expect(m.ms).toBeLessThanOrEqual(t.quick);
    expect(still({ x: 0, y: 300, ms: 360 }, t.quick, false).y).toBe(300);
  });

  it("tokens_fall_back_to_the_css_defaults_outside_a_browser", () => {
    const t = tokens();
    expect([t.quick, t.move, t.flow, t.exit]).toEqual([160, 320, 360, 200]);
    expect(ms("0.32s", 0)).toBe(320);
    expect(ms("120ms", 0)).toBe(120);
    expect(ms("", 7)).toBe(7);
  });

  it("bezier_is_monotone_and_hits_its_ends", () => {
    const e = bezier("cubic-bezier(0.22, 1, 0.36, 1)");
    expect(e(0)).toBe(0);
    expect(e(1)).toBe(1);
    expect(e(0.1)).toBeGreaterThan(0.3); // fast start, slow settle
    let last = 0;
    for (let i = 1; i <= 20; i++) {
      const y = e(i / 20);
      expect(y).toBeGreaterThanOrEqual(last);
      last = y;
    }
    expect(bezier("nonsense")(0.4)).toBe(0.4);
    const s = bezier("cubic-bezier(0.32, 1.2, 0.5, 1)");
    const peak = Math.max(...Array.from({ length: 100 }, (_, i) => s((i + 1) / 100)));
    expect(peak).toBeGreaterThan(1.01); // a hair of overshoot
    expect(peak).toBeLessThan(1.06); // never a bounce
  });

  it("c33_rubber_resists_and_never_passes_its_limit", () => {
    expect(rubber(-10, 144)).toBe(0);
    expect(rubber(144, 144)).toBeCloseTo(72); // about 144 px of finger arms the 72 px pull
    expect(rubber(40, 144)).toBeGreaterThan(rubber(40, 144, 0.5));
    expect(rubber(5000, 144)).toBeLessThan(144);
    expect(rubber(200, 144) - rubber(100, 144)).toBeLessThan(rubber(100, 144) - rubber(0, 144));
  });

  it("c30_a_sheet_goes_on_distance_or_speed", () => {
    expect(dismissed(100, 0)).toBe(true);
    expect(dismissed(30, 0)).toBe(false);
    expect(dismissed(30, 0.8)).toBe(true); // a flick
    expect(dismissed(4, 0.9)).toBe(false); // a tremor
  });
});

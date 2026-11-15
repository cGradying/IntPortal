import { describe, expect, it } from "vitest";
import { luminance } from "../rooms";
import { CLASS, CLOCK, LOOKS, PAGES, RATINGS, SIGNIN, TERMS, campusLine, clock, countdown, fillName, helloLine, showFirstRun, step, swipe, todayAt } from "./intro";

const page = (id: string) => PAGES.find((p) => p.id === id)!;

describe("the intro (spec 049)", () => {
  it("c1_nine_pages_one_feature_each_sign_in_last", () => {
    expect(PAGES.map((p) => p.id)).toEqual(["hello", "school", "today", "deadlines", "study", "offline", "look", "reminders", "signin"]);
    expect(SIGNIN).toBe(8);
    for (const p of PAGES) expect(p.title.length).toBeGreaterThan(0);
  });

  it("c7_each_page_fires_its_own_act_on_the_stage", () => {
    expect(page("hello").acts).toEqual(["say", "cheer"]);
    expect(page("school").acts).toContain("wall");
    expect(page("school").acts).toContain("ring");
    expect(page("today").acts).toEqual(["mouth"]);
    expect(PAGES.filter((p) => p.acts.includes("mouth")).map((p) => p.id)).toEqual(["today"]);
    expect(page("look").acts).toContain("room");
    expect(page("reminders").acts).toEqual(["remind"]);
    expect(page("signin").acts).toEqual(["demo"]);
  });

  it("c6_lar_waits_beside_or_under_the_portal_never_on_it", () => {
    for (const p of PAGES) expect(["left", "right", "below"]).toContain(p.spot);
    // Turning a page moves him somewhere new more often than not.
    const moves = PAGES.slice(1).filter((p, i) => p.spot !== PAGES[i].spot).length;
    expect(moves).toBeGreaterThanOrEqual(PAGES.length - 3);
  });

  it("c2_back_and_next_stay_inside_the_intro", () => {
    expect(step(0, -1)).toBe(0);
    expect(step(0, 1)).toBe(1);
    expect(step(SIGNIN, 1)).toBe(SIGNIN);
  });

  it("c2_a_swipe_is_a_long_flat_drag", () => {
    expect(swipe(-80, 10)).toBe(1);
    expect(swipe(80, 10)).toBe(-1);
    expect(swipe(30, 0)).toBe(0);
    expect(swipe(-80, 70)).toBe(0);
  });

  it("c8_lar_uses_the_name_and_iskolar_without_one", () => {
    expect(helloLine("  Jan ")).toBe("Hi, Jan! Ako si LAR.");
    expect(helloLine("  ")).toBe("");
    expect(fillName("Tara, {you}.", "Jan")).toBe("Tara, Jan.");
    expect(fillName("Tara, {you}.", "")).toBe("Tara, iskolar.");
    expect(campusLine("Sta. Mesa")).toBe("PUP Sta. Mesa! Kilala ko 'yan.");
    for (const p of PAGES) expect(fillName(p.lar, "Maria Clara de los S").length).toBeLessThan(80);
  });

  it("c9_the_clock_turns_up_next_into_in_session_and_counts_down", () => {
    expect(todayAt(CLASS.start - 35 * 60 - 12)).toMatchObject({ phase: "next", label: "Up next", left: 35 * 60 + 12 });
    expect(todayAt(CLASS.start)).toMatchObject({ phase: "now", label: "In session", left: 90 * 60 });
    expect(todayAt(CLASS.end)).toMatchObject({ phase: "over", left: 0 });
    expect(countdown(35 * 60 + 12)).toBe("35:12");
    expect(countdown(3930)).toBe("1:05:30");
    expect(countdown(-5)).toBe("0:00");
    expect(clock(CLOCK.start)).toBe("7:15 AM");
    expect(clock(13 * 3600)).toBe("1:00 PM");
    expect(CLOCK.from).toBeLessThan(CLASS.start);
    expect(CLOCK.to).toBeGreaterThan(CLASS.end);
    expect(todayAt(CLOCK.start).phase).toBe("next");
  });

  it("c11_ratings_say_when_the_card_comes_back", () => {
    expect(RATINGS.map((r) => [r.label, r.short])).toEqual([["Again", "10m"], ["Good", "3d"], ["Easy", "8d"]]);
    expect(TERMS.at(-1)!.v).toBeLessThan(TERMS[0].v);
  });

  it("c13_offers_only_the_six_dark_looks", () => {
    expect(LOOKS.map((l) => l.room)).toEqual(["night", "maroon", "astraMoon", "tokyoNight", "dracula", "nord"]);
    for (const l of LOOKS) expect(luminance(l.swatch[0])).toBeLessThan(0.1);
  });

  it("c16_first_run_is_only_the_ai_choice", () => {
    expect(showFirstRun(false, { id: "chat" })).toBe(true);
    expect(showFirstRun(false, undefined)).toBe(false);
    expect(showFirstRun(true, { id: "chat" })).toBe(false);
  });
});

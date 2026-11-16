import { describe, expect, it } from "vitest";
import { luminance } from "../rooms";
import { CLASS, CLOCK, FOCUS, LOOKS, RATINGS, STEPS, TERMS, clock, countdown, fill, isDarkLook, play, route, showFirstRun, todayAt, type Answer, type Item } from "./intro";

const A = (reply: string, value?: string): Answer => ({ reply, value });
/** Every answer of one whole talk, the short way through. */
const WHOLE = [A("named", "Jan"), A("pup", "Sta. Mesa"), A("picked", "deadlines,study"), A("next"), A("next"), A("next"), A("next"), A("next"), A("worn", "Nord"), A("allow"), A("ok")];
const lar = (items: Item[]) => items.filter((i) => i.who === "lar").map((i) => (i as { text: string }).text);
const you = (items: Item[]) => items.filter((i) => i.who === "you").map((i) => (i as { text: string }).text);

describe("the talk with LAR (spec 049)", () => {
  it("c1_lar_opens_by_asking_what_to_call_you", () => {
    const t = play([]);
    expect(t.step.id).toBe("name");
    expect(t.items).toEqual(STEPS.name.lar.map((text) => ({ who: "lar", text })));
    expect(t.items.at(-1)).toMatchObject({ text: expect.stringContaining("what should I call you?") });
    expect(t.done).toBe(false);
  });

  it("c1_the_steps_run_in_order_and_end_at_the_portal", () => {
    expect(route()).toEqual(["name", "campus", "focus", "today", "deadlines", "grades", "study", "offline", "look", "reminders", "privacy", "bye"]);
    const t = play(WHOLE);
    expect(t.done).toBe(true);
    expect(t.step.id).toBe("bye");
    expect(lar(t.items).at(-1)).toBe("Tara, Jan, pasok na tayo!");
    expect(t).toMatchObject({ name: "Jan", campus: "Sta. Mesa", focus: ["deadlines", "study"], wall: false });
    expect(you(t.items)).toEqual(["Jan", "Sta. Mesa", "Deadlines, Studying", "Tapos!", "Gets", "Ayos", "Nice", "Solid", "Nord", "Allow reminders", "Got it"]);
  });

  it("c2_back_is_one_answer_fewer_and_the_thread_before_it_is_unchanged", () => {
    for (let n = 1; n <= WHOLE.length; n++) {
      const [now, before] = [play(WHOLE.slice(0, n)), play(WHOLE.slice(0, n - 1))];
      expect(now.items.slice(0, before.items.length)).toEqual(before.items);
      expect(now.items.length).toBeGreaterThan(before.items.length);
    }
    expect(play([A("named", "Jan"), A("nonsense"), A("pup", "Taguig")]).step.id).toBe("campus");
  });

  it("c3_every_step_has_one_gold_action_and_real_words", () => {
    for (const s of Object.values(STEPS)) {
      expect(s.lar.length, s.id).toBeGreaterThan(0);
      for (const line of [...s.lar, ...s.replies.flatMap((r) => r.says)]) expect(fill(line, "Maria Clara de los S", "Sto. Tomas").length, line).toBeLessThan(110);
      // The campus is the answer itself, and the focus shows one of its two golds.
      const gold = s.replies.filter((r) => r.gold).length;
      expect(gold, s.id).toBe(s.id === "bye" || s.id === "campus" ? 0 : s.id === "focus" ? 2 : 1);
      for (const r of s.replies) if (s.ask === "chips") expect(r.label.length, s.id).toBeGreaterThan(0);
    }
  });

  it("c5_lar_answers_by_name_and_says_iskolar_without_one", () => {
    expect(lar(play([A("named", "  Jan ")]).items)).toContain("Hi, Jan! Tanda ko na 'yan.");
    expect(lar(play([A("named", "Jan")]).items).at(-1)).toBe("Saan ka nag-aaral, Jan?");
    const shy = play([A("skip")]);
    expect(shy.name).toBe("");
    expect(you(shy.items)).toEqual(["Iskolar na lang"]);
    expect(lar(shy.items).at(-1)).toBe("Saan ka nag-aaral, iskolar?");
    expect(fill("Tara, {you}.", "")).toBe("Tara, iskolar.");
  });

  it("c6_a_campus_is_greeted_and_another_school_opens_the_wall_later", () => {
    const pup = play([A("skip"), A("pup", "Sta. Mesa")]);
    expect(lar(pup.items)).toContain("PUP Sta. Mesa! Kilala ko 'yan.");
    expect(pup).toMatchObject({ wall: false, act: "cheer" });
    const other = play([A("skip"), A("other")]);
    expect(other).toMatchObject({ wall: true, act: "wall", campus: "" });
    expect(you(other.items).at(-1)).toBe("Another school");
    expect(other.step.id).toBe("focus");
  });

  it("c7_what_they_care_about_orders_the_demos", () => {
    expect(FOCUS.map((f) => [f.id, f.step])).toEqual([["classes", "today"], ["deadlines", "deadlines"], ["grades", "grades"], ["study", "study"]]);
    expect(route(["study", "grades"]).slice(3, 7)).toEqual(["study", "grades", "today", "deadlines"]);
    expect(route(["grades", "grades", "nope"]).slice(3, 7)).toEqual(["grades", "today", "deadlines", "study"]);
    const t = play([A("skip"), A("other"), A("picked", "grades")]);
    expect(t.step.id).toBe("grades");
    expect(t.items.at(-1)).toEqual({ who: "card", card: "grades", step: "grades" });
    expect(play([A("skip"), A("other"), A("all")])).toMatchObject({ focus: [], step: { id: "today" } });
    expect(you(play([A("skip"), A("other"), A("all")]).items).at(-1)).toBe("Lahat");
  });

  it("c8_every_demo_and_the_nudge_is_shown_once", () => {
    const cards = play(WHOLE).items.filter((i) => i.who === "card").map((i) => (i as { card: string }).card);
    expect([...cards].sort()).toEqual(["deadlines", "grades", "nudge", "offline", "study", "today"]);
  });

  it("c10_reminders_are_asked_and_either_answer_goes_on", () => {
    const upTo = WHOLE.slice(0, 9);
    expect(play(upTo).step.id).toBe("reminders");
    expect(play([...upTo, A("allow")])).toMatchObject({ act: "remind", step: { id: "privacy" } });
    expect(play([...upTo, A("later")])).toMatchObject({ act: "quiet", step: { id: "privacy" } });
  });

  it("c11_privacy_is_one_exchange_and_paano_adds_one_more", () => {
    const upTo = WHOLE.slice(0, 10);
    expect(lar(play(upTo).items).at(-1)).toMatch(/keychain.*PUP SIS/);
    const how = play([...upTo, A("how")]);
    expect(how).toMatchObject({ act: "think", step: { id: "how" }, done: false });
    expect(lar(how.items).join(" ")).toMatch(/Walang IntPortal account, walang server/);
    expect(play([...upTo, A("how"), A("ok")]).done).toBe(true);
    expect(play([...upTo, A("ok")]).done).toBe(true);
  });

  it("c8_the_clock_turns_up_next_into_in_session_and_counts_down", () => {
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

  it("c8_ratings_say_when_the_card_comes_back", () => {
    expect(RATINGS.map((r) => [r.label, r.short])).toEqual([["Again", "10m"], ["Good", "3d"], ["Easy", "8d"]]);
    expect(TERMS.at(-1)!.v).toBeLessThan(TERMS[0].v);
  });

  it("c9_offers_only_the_six_dark_looks", () => {
    expect(LOOKS.map((l) => l.room)).toEqual(["night", "maroon", "astraMoon", "tokyoNight", "dracula", "nord"]);
    for (const l of LOOKS) expect(luminance(l.swatch[0])).toBeLessThan(0.1);
    expect(isDarkLook("nord")).toBe(true);
    expect(isDarkLook("day")).toBe(false);
  });

  it("c16_first_run_is_only_the_ai_choice", () => {
    expect(showFirstRun(false, { id: "chat" })).toBe(true);
    expect(showFirstRun(false, undefined)).toBe(false);
    expect(showFirstRun(true, { id: "chat" })).toBe(false);
  });
});

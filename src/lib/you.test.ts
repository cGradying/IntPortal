import { describe, expect, it } from "vitest";
import { GROUPS, SETTINGS, moveCard, oneOf, parseCards, rowProblem, searchSettings, toggleCard } from "./you";

const ok = { sisRejected: false, mabiniRejected: false, mabiniError: null, notifications: true, remindersOn: true, queuedError: "", lockError: "" };
const names = (q: string) => searchSettings(q).map((s) => s.name);

describe("you", () => {
  it("c2_search_finds_every_setting by its own name, on a page that has a row", () => {
    const pages = GROUPS.flatMap(([, rows]) => rows.map(([id]) => id));
    for (const s of SETTINGS) {
      expect(names(s.name), s.name).toContain(s.name);
      expect(pages).toContain(s.page);
    }
  });

  it("c2 search understands Taglish and ignores case and accents", () => {
    expect(names("tunog")).toEqual(["Sounds"]);
    expect(names("Kandado")).toEqual(["Lock"]);
    expect(names("burahin")).toEqual(["Erase everything"]);
    expect(names("paalala aral")).toEqual(["Study reminders"]);
    expect(names("kulây")).toEqual(["Rooms", "Make a theme"]);
    expect(names("")).toEqual([]);
    expect(names("zzz")).toEqual([]);
  });

  it("c3 a problem shows on its own row", () => {
    expect(rowProblem("accounts", { ...ok, sisRejected: true })).toBe("Login turned down");
    expect(rowProblem("accounts", { ...ok, mabiniError: "offline" })).toBe("eMabini didn't sync");
    expect(rowProblem("reminders", { ...ok, notifications: false })).toBe("Notifications off");
    expect(rowProblem("reminders", { ...ok, notifications: false, remindersOn: false })).toBe(null);
    expect(rowProblem("reminders", { ...ok, queuedError: "x" })).toBe("Couldn't schedule");
    expect(rowProblem("privacy", { ...ok, lockError: "no face id" })).toBe("Lock not set");
    expect(rowProblem("theme", { ...ok, sisRejected: true })).toBe(null);
  });

  it("c6_every_card_can_hide_and_move", () => {
    const c = parseCards(null);
    expect(c).toEqual({ order: ["next", "due", "coach", "term"], hidden: [] });
    expect(moveCard(c.order, 0, 1)).toEqual(["due", "next", "coach", "term"]);
    expect(moveCard(c.order, 3, -1)).toEqual(["next", "due", "term", "coach"]);
    expect(moveCard(c.order, 0, -1)).toEqual(["next", "due", "coach", "term"]);
    expect(moveCard(c.order, 3, 1)).toEqual(["next", "due", "coach", "term"]);
    for (const id of ["next", "due", "coach", "term", "events"] as const) {
      const hid = toggleCard(c, id);
      expect(hid.hidden).toEqual([id]);
      expect(toggleCard(hid, id).hidden).toEqual([]);
    }
  });

  it("c6 a stored choice round-trips, and a damaged one falls back", () => {
    const saved = { order: moveCard(["next", "due", "coach", "term"], 1, 1), hidden: ["due", "events"] };
    expect(parseCards(JSON.stringify(saved))).toEqual({ order: ["next", "coach", "due", "term"], hidden: ["due", "events"] });
    expect(parseCards('{"order":["term","bogus","term"]}')).toEqual({ order: ["term", "next", "due", "coach"], hidden: [] });
    expect(parseCards("not json")).toEqual({ order: ["next", "due", "coach", "term"], hidden: [] });
  });

  it("c5 c7 c8 stored choices fall back to the first option", () => {
    expect(oneOf("study", ["today", "schedule", "study"])).toBe("study");
    expect(oneOf("grades", ["today", "schedule", "study"])).toBe("today");
    expect(oneOf(null, ["full", "short", "off"])).toBe("full");
  });
});

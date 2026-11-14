import { describe, expect, it } from "vitest";
import type { Deadline, DeadlineEntry } from "./api";
import { dueLabel, entryLabel, knowsNothingDue, mabiniState, splitCourseName, splitDeadlines, subjectOf, titleOf } from "./deadlines";

const secs = (y: number, m: number, d: number, h = 12) => new Date(y, m - 1, d, h).getTime() / 1000;
const mk = (id: number, due: number, over: Partial<Deadline> = {}): Deadline => ({
  id,
  name: "X is due",
  course_id: 1,
  course: "Subject_First Sem 2627_BSIT 1-A",
  kind: "assign",
  due,
  overdue: false,
  url: "",
  ...over,
});

describe("dueLabel", () => {
  const now = new Date(2026, 9, 11, 9);
  it("names today, tomorrow and the weekday by local date", () => {
    expect(dueLabel(mk(1, secs(2026, 10, 11, 23)), now)).toBe("Today");
    expect(dueLabel(mk(1, secs(2026, 10, 12, 0)), now)).toBe("Tomorrow");
    expect(dueLabel(mk(1, secs(2026, 10, 14)), now)).toBe(new Date(2026, 9, 14).toLocaleDateString(undefined, { weekday: "short" }));
  });
  it("gives a date a week or more out", () => {
    expect(dueLabel(mk(1, secs(2026, 10, 25)), now)).toBe(new Date(2026, 9, 25).toLocaleDateString(undefined, { month: "short", day: "numeric" }));
  });
  it("says Overdue for a missed one, whatever its day", () => {
    expect(dueLabel(mk(1, secs(2026, 10, 10), { overdue: true }), now)).toBe("Overdue");
    expect(dueLabel(mk(1, secs(2026, 10, 11, 8)), now)).toBe("Overdue");
  });
});

describe("splitDeadlines", () => {
  const now = new Date(2026, 9, 11, 9);
  it("puts overdue first, each soonest first", () => {
    const list = [mk(1, secs(2026, 10, 15)), mk(2, secs(2026, 10, 9)), mk(3, secs(2026, 10, 12)), mk(4, secs(2026, 10, 10), { overdue: true })];
    const { overdue, upcoming } = splitDeadlines(list, now);
    expect(overdue.map((d) => d.id)).toEqual([2, 4]);
    expect(upcoming.map((d) => d.id)).toEqual([3, 1]);
  });
  it("caps what it returns", () => {
    const list = [1, 2, 3, 4, 5, 6].map((i) => mk(i, secs(2026, 10, 12 + i)));
    expect(splitDeadlines(list, now, 4).upcoming).toHaveLength(4);
  });
});

describe("names", () => {
  it("strips Moodle's verb off an event title", () => {
    expect(titleOf("PETA 1 is due")).toBe("PETA 1");
    expect(titleOf("Pagsusulit 1 closes")).toBe("Pagsusulit 1");
    expect(titleOf("Quiz 2 opens")).toBe("Quiz 2");
    expect(titleOf("Plain title")).toBe("Plain title");
  });
  it("takes the subject out of a course name", () => {
    expect(subjectOf("Filipino_First Sem 2627_BSIT 1-A")).toBe("Filipino");
    expect(subjectOf("Orientation")).toBe("Orientation");
    expect(splitCourseName("Filipino_First Sem 2627_BSIT 1-A")).toEqual({ subject: "Filipino", term: "First Sem 2627", section: "BSIT 1-A" });
    expect(splitCourseName("A_B")).toEqual({ subject: "A_B", term: "", section: "" });
  });
});

describe("spec 041 C7: entryLabel", () => {
  const now = new Date(2026, 10, 3, 12);
  const e = (due: DeadlineEntry["due"], overdue = false): DeadlineEntry => ({ id: "x", source: "own", subject: null, course: null, title: "T", kind: "project", due, overdue, url: null });
  it("a whole-day deadline is today until midnight", () => {
    expect(entryLabel(e({ day: "2026-11-03" }), now)).toBe("Today");
    expect(entryLabel(e({ day: "2026-11-04" }), now)).toBe("Tomorrow");
  });
  it("a timed one is overdue once its time passed, and the core's flag wins", () => {
    expect(entryLabel(e({ at: new Date(2026, 10, 3, 9).getTime() / 1000 }), now)).toBe("Overdue");
    expect(entryLabel(e({ day: "2026-11-05" }, true), now)).toBe("Overdue");
  });
});

describe("c9_three_states: spec 041 C9 / 040 C3, the card never says nothing is due without data", () => {
  const now = new Date(2026, 10, 3, 12);
  const sec = (h: number) => new Date(2026, 10, 3, h).getTime() / 1000;
  it("names eMabini's state", () => {
    expect(mabiniState(false, null, null)).toBe("off");
    expect(mabiniState(true, null, null)).toBe("never");
    expect(mabiniState(true, sec(9), "down")).toBe("failed");
    expect(mabiniState(true, sec(9), null)).toBe("ok");
  });
  it("c9_three_states: nothing due only with a connected, fresh source", () => {
    const old = String(sec(9) - 2 * 86_400);
    expect(knowsNothingDue(true, String(sec(9)), "ok", sec(9), now)).toBe(true);
    expect(knowsNothingDue(true, String(sec(9)), "off", null, now)).toBe(true);
    expect(knowsNothingDue(false, null, "ok", sec(9), now)).toBe(true);
    expect(knowsNothingDue(true, String(sec(9)), "never", null, now)).toBe(false);
    expect(knowsNothingDue(true, String(sec(9)), "failed", sec(9), now)).toBe(false);
    expect(knowsNothingDue(true, old, "off", null, now)).toBe(false);
    expect(knowsNothingDue(true, null, "off", null, now)).toBe(false);
    expect(knowsNothingDue(true, null, "ok", sec(9), now)).toBe(false);
    expect(knowsNothingDue(false, null, "off", null, now)).toBe(false);
  });
});

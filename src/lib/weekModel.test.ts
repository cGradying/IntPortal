import { describe, expect, it } from "vitest";
import type { ClassSession, DeadlineEntry, Meeting } from "./api";
import { columns, freshStamps, gapText, gaps, month, movedFrom, onColor, phaseOf, pin, stampOf } from "./weekModel";
import { contrast } from "./rooms";

const s = (subject_code: string, day: ClassSession["day"], start: number, end: number, occurrence = 0): ClassSession => ({ subject_code, description: "", faculty: "", day, start, end, occurrence });
const m = (session: ClassSession, moved = false): Meeting => ({ id: session.subject_code, session, date: "2026-11-02", mark: "in_person", moved });
const dl = (day: string, overdue = false): DeadlineEntry => ({ id: day, source: "own", subject: null, course: null, title: "x", kind: "other" as DeadlineEntry["kind"], due: { day }, overdue, url: null });

describe("the week's columns (044 C3)", () => {
  it("c3_days_shown: class days and today are full, others are ghosts that keep their place", () => {
    const cols = columns([m(s("A", "Monday", 480, 600))], [], 2);
    expect(cols.filter((c) => c.full).map((c) => c.index)).toEqual([0, 2]);
    expect(cols.map((c) => c.index)).toEqual([0, 1, 2, 3, 4, 5]);
  });
  it("shows Sunday only when something is on it", () => {
    expect(columns([m(s("A", "Sunday", 480, 600))], [], 2).some((c) => c.index === 6)).toBe(true);
  });
  it("a day with only the student's own events is full", () => {
    expect(columns([], [4], 2).find((c) => c.index === 4)?.full).toBe(true);
  });
});

describe("blocks (044 C2, C4, C7)", () => {
  it("c2_text_colour_contrast: reads on every course colour", () => {
    for (const c of ["#e0697e", "#e8866f", "#e0b04a", "#b58ad0", "#5fbf9c", "#7ea3e0", "#7a1128", "#b13e34", "#8f6410", "#5c315f", "#2e5a4f", "#3f517a"]) expect(contrast(onColor(c), c)).toBeGreaterThanOrEqual(4.5);
  });
  it("c4_stamp_per_mark", () => {
    expect(stampOf("online", false)?.text).toBe("ONLINE");
    expect(stampOf("vacant", true)?.text).toBe("VACANT");
    expect(stampOf("in_person", true)?.text).toBe("MOVED");
    expect(stampOf("in_person", false)).toBeNull();
  });
  it("c5_thunk_once_per_new_stamp", () => {
    expect(freshStamps(["a", "b"], new Set(["a"]))).toEqual(["b"]);
  });
  it("c6_moved_ghost_at_old_slot", () => {
    const term = [s("A", "Monday", 480, 600)];
    expect(movedFrom(m(s("A", "Friday", 480, 600), true), term)?.day).toBe("Monday");
    expect(movedFrom(m(s("A", "Monday", 480, 600), false), term)).toBeNull();
  });
  it("c7_finished_classes_fade at a fixed clock, on today only", () => {
    const c = { start: 480, end: 600 };
    expect(phaseOf(c, true, 700)).toBe("past");
    expect(phaseOf(c, true, 500)).toBe("now");
    expect(phaseOf(c, true, 400)).toBe("later");
    expect(phaseOf(c, false, 700)).toBe("later");
  });
});

describe("the day (044 C9)", () => {
  it("folds free time of 30 minutes or more, between classes only", () => {
    const list = [{ start: 450, end: 540 }, { start: 630, end: 720 }, { start: 730, end: 800 }];
    expect(gaps(list, 30)).toEqual([{ start: 540, end: 630 }]);
  });
  it("says when the student is in the gap now", () => {
    const g = { start: 540, end: 630 };
    expect(gapText(g, false, 600)).toBe("1h 30m free");
    expect(gapText(g, true, 600)).toBe("Now · free for 30m");
  });
});

describe("the four-week month (044 C11)", () => {
  const monday = new Date(2026, 10, 2);
  it("marks due, overdue, today and this week", () => {
    const cells = month([dl("2026-11-03", true), dl("2026-11-12")], monday, "2026-11-04");
    expect(cells).toHaveLength(28);
    expect(cells[1].over).toBe(true);
    expect(cells[10].due).toBe(true);
    expect(cells[2].today).toBe(true);
    expect(cells[6].thisWeek).toBe(true);
    expect(cells[7].thisWeek).toBe(false);
  });
  it("pins a day under its header", () => {
    expect(pin([dl("2026-11-03", true)], "2026-11-03")).toBe("over");
    expect(pin([dl("2026-11-12")], "2026-11-12")).toBe("due");
    expect(pin([], "2026-11-12")).toBeNull();
  });
});

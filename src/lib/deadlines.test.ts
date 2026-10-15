import { describe, expect, it } from "vitest";
import type { Deadline } from "./api";
import { dueLabel, splitCourseName, splitDeadlines, subjectOf, titleOf } from "./deadlines";

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

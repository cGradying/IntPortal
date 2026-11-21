import { describe, expect, it } from "vitest";
import type { ClassSession } from "./api";
import { classesOf, problem, timeLine } from "./ownClass";

const s = (day: ClassSession["day"], start: number, end: number, own = true): ClassSession => ({ subject_code: "C1", description: "Calculus 1", faculty: "", day, start, end, occurrence: 0, own, room: "R1" });

describe("own classes", () => {
  it("groups own sessions back into one class, synced ones left out", () => {
    const got = classesOf([s("Wednesday", 450, 540), s("Monday", 450, 540), s("Friday", 780, 900), s("Tuesday", 450, 540, false)]);
    expect(got).toEqual([
      { code: "C1", name: "Calculus 1", room: "R1", teacher: "", meetings: [{ days: ["Monday", "Wednesday"], start: 450, end: 540 }, { days: ["Friday"], start: 780, end: 900 }] },
    ]);
  });

  it("writes a meeting the way a schedule does", () => {
    expect(timeLine({ days: ["Thursday", "Tuesday"], start: 450, end: 540 })).toBe("TTh 7:30–9:00 AM");
    expect(timeLine({ days: ["Friday"], start: 660, end: 780 })).toBe("F 11:00 AM–1:00 PM");
  });

  it("says what is missing before saving", () => {
    const ok = { code: "", name: "Calc", room: "", teacher: "", meetings: [{ days: ["Monday" as const], start: 450, end: 540 }] };
    expect(problem(ok)).toBe("");
    expect(problem({ ...ok, name: " " })).toBe("Give the class a name.");
    expect(problem({ ...ok, meetings: [{ days: [], start: 450, end: 540 }] })).toBe("Pick at least one day.");
    expect(problem({ ...ok, meetings: [{ days: ["Monday"], start: 540, end: 450 }] })).toBe("It has to end after it starts.");
  });
});

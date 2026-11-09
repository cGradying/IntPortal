import { describe, expect, it } from "vitest";
import type { ClassSession, DeadlineDraft } from "./api";
import { dayLabel, dayName, guessSubject, kindName, meets, nextClassDays, stub, tickets, verdict, whenDays, type Ticket } from "./addDue";

const MON = "2026-11-09";
const at = (subject_code: string, day: ClassSession["day"]): ClassSession => ({ subject_code, description: "", faculty: "", day, start: 480, end: 570, occurrence: 0 });
const SESSIONS = [at("COMP 20073", "Tuesday"), at("COMP 20073", "Friday"), at("MATH 20133", "Monday")];
const draft = (over: Partial<DeadlineDraft> = {}): DeadlineDraft => ({ title: "Quiz", subject: "COMP 20073", kind: "quiz", date: "2026-11-13", ...over });
const ticket = (over: Partial<Ticket> = {}): Ticket => ({ ...draft(), keep: true, ...over });

describe("tickets", () => {
  it("lays the student's fixes and keep toggles over the core's drafts, by position", () => {
    const parsed = [draft({ title: "Lab 4", kind: "project", subject: null, date: "2026-11-12" }), draft({ title: "Midterm exam", kind: "exam", subject: null, date: "2026-11-16" })];
    expect(tickets(parsed, [{}, { subject: "MATH 20133" }], [true])).toEqual([
      { title: "Lab 4", subject: null, kind: "project", date: "2026-11-12", keep: false },
      { title: "Midterm exam", subject: "MATH 20133", kind: "exam", date: "2026-11-16", keep: true },
    ]);
  });
  it("keeps a fix when the text is read again", () => {
    expect(tickets([draft({ date: null })], [{ date: "2026-11-20", title: "Quiz 3" }], [])).toEqual([{ title: "Quiz 3", subject: "COMP 20073", kind: "quiz", date: "2026-11-20", keep: true }]);
  });
  it("keeps a lone ticket, even one unticked when there were two", () => {
    expect(tickets([draft()], [], [true])[0].keep).toBe(true);
  });
  it("is empty for no text", () => {
    expect(tickets([], [{ title: "x" }], [])).toEqual([]);
  });
});

describe("class days", () => {
  it("knows the days a subject meets", () => {
    expect(meets(SESSIONS, "COMP 20073", "2026-11-10")).toBe(true);
    expect(meets(SESSIONS, "COMP 20073", "2026-11-11")).toBe(false);
    expect(meets(SESSIONS, null, "2026-11-10")).toBe(false);
  });
  it("gives the next two after tomorrow", () => {
    expect(nextClassDays(SESSIONS, "COMP 20073", MON)).toEqual(["2026-11-13", "2026-11-17"]);
    expect(nextClassDays(SESSIONS, "MATH 20133", MON)).toEqual(["2026-11-16", "2026-11-23"]);
    expect(nextClassDays(SESSIONS, "GEED 10053", MON)).toEqual([]);
    expect(nextClassDays(SESSIONS, null, MON)).toEqual([]);
  });
  it("builds the When row: today, tomorrow, class days, then the ticket's own day, in order", () => {
    expect(whenDays(SESSIONS, "COMP 20073", "2026-12-04", MON)).toEqual(["2026-11-09", "2026-11-10", "2026-11-13", "2026-11-17", "2026-12-04"]);
    expect(whenDays(SESSIONS, "COMP 20073", "2026-11-13", MON)).toEqual(["2026-11-09", "2026-11-10", "2026-11-13", "2026-11-17"]);
    expect(whenDays([], null, null, "2026-12-31")).toEqual(["2026-12-31", "2027-01-01"]);
  });
});

describe("words", () => {
  it("names a day for a chip", () => {
    expect(dayLabel(MON, MON)).toBe("Today");
    expect(dayLabel("2026-11-10", MON)).toBe("Tomorrow");
    expect(dayLabel("2026-11-13", MON)).toBe("Fri 13");
    expect(dayLabel("2026-12-04", MON)).toBe("Fri, Dec 4");
    expect(dayName("2026-11-13")).toBe("Friday, November 13");
  });
  it("cuts the stub", () => {
    expect(stub("2026-11-13")).toEqual({ dow: "FRI", day: 13, mon: "NOV" });
  });
  it("names the kinds it offers", () => {
    expect([kindName("quiz"), kindName("exam"), kindName("project"), kindName("lecture")]).toEqual(["Quiz", "Exam", "Project", "Project"]);
  });
});

describe("verdict", () => {
  it("says Add, Add 2 or Save when it can", () => {
    expect(verdict([ticket()], false)).toEqual({ ok: true, label: "Add" });
    expect(verdict([ticket(), ticket(), ticket({ keep: false })], false)).toEqual({ ok: true, label: "Add 2" });
    expect(verdict([ticket()], true)).toEqual({ ok: true, label: "Save" });
  });
  it("says what is missing, and where", () => {
    expect(verdict([], false)).toEqual({ ok: false, label: "Add", why: "text" });
    expect(verdict([], true)).toEqual({ ok: false, label: "Save", why: "text" });
    expect(verdict([ticket({ keep: false })], false)).toEqual({ ok: false, label: "Keep one", why: "keep" });
    expect(verdict([ticket(), ticket({ date: null })], false)).toEqual({ ok: false, label: "Add a day", why: "day", i: 1 });
    expect(verdict([ticket({ title: "  " }), ticket({ date: null, keep: false })], false)).toEqual({ ok: false, label: "Name it", why: "name", i: 0 });
  });
  it("asks for the day before the name", () => {
    expect(verdict([ticket({ title: "", date: null })], false)).toEqual({ ok: false, label: "Add a day", why: "day", i: 0 });
  });
});

describe("guessSubject", () => {
  const two = [...SESSIONS, at("COMP 20083", "Monday")];
  it("picks the COMP that meets on the day when two share the letters", () => {
    expect(guessSubject(draft({ title: "Quiz COMP", subject: null }), two)).toEqual(draft({ title: "Quiz", subject: "COMP 20073" }));
  });
  it("takes the only subject with those letters", () => {
    expect(guessSubject(draft({ title: "math quiz", subject: null, date: "2026-11-13" }), SESSIONS)).toEqual(draft({ title: "quiz", subject: "MATH 20133" }));
  });
  it("leaves it alone when neither or both meet that day", () => {
    const d = draft({ title: "Quiz COMP", subject: null, date: "2026-11-11" });
    expect(guessSubject(d, two)).toEqual(d);
  });
  it("never replaces a subject the core found", () => {
    expect(guessSubject(draft({ title: "math quiz" }), SESSIONS).subject).toBe("COMP 20073");
  });
});

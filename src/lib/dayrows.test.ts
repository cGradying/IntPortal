import { describe, expect, it } from "vitest";
import { dayRows, weekSpans } from "./dayrows";

const cls = (start: number, end: number, phase = "upcoming") => ({ session: { start, end }, phase });
const busy = (from: [string, number], to: [string, number]) => ({ from: { date: from[0], minute: from[1] }, to: { date: to[0], minute: to[1] }, title: "Org" });
const day = "2026-10-03";
const shape = (rows: ReturnType<typeof dayRows>) => rows.map((r) => (r.kind === "gap" ? `gap ${r.minutes}` : `${r.kind} ${r.start}`));

describe("dayRows", () => {
  it("puts free stretches of 15 minutes or more between classes", () => {
    expect(shape(dayRows([cls(450, 540), cls(550, 600), cls(630, 720)], [], day, 0))).toEqual(["class 450", "class 550", "gap 30", "class 630"]);
  });

  it("slots the student's events in by time and takes them out of the gaps", () => {
    const rows = dayRows([cls(780, 870), cls(960, 1140)], [busy([day, 885], [day, 945])], day, 0);
    expect(shape(rows)).toEqual(["class 780", "gap 15", "busy 885", "gap 15", "class 960"]);
  });

  it("clips an event from last night to midnight and one into a class to the class", () => {
    const rows = dayRows([cls(480, 600)], [busy(["2026-10-02", 1320], [day, 420]), busy([day, 570], [day, 660])], day, 0);
    expect(shape(rows)).toEqual(["busy 0", "gap 60", "class 480", "busy 570"]);
  });

  it("greys out what has passed", () => {
    const rows = dayRows([cls(450, 540, "past"), cls(600, 660, "past"), cls(700, 760)], [], day, 690);
    expect(rows.filter((r) => r.kind === "gap").map((r) => r.past)).toEqual([true, false]);
  });
});

describe("weekSpans", () => {
  const monday = "2026-09-28";
  it("places each event on its weekday, split at midnight and clipped to the week", () => {
    const spans = weekSpans(
      [busy(["2026-09-29", 600], ["2026-09-29", 660]), busy(["2026-10-01", 1380], ["2026-10-02", 60]), busy(["2026-09-27", 1320], ["2026-09-28", 30]), busy(["2026-10-05", 600], ["2026-10-05", 660])],
      monday,
    );
    expect(spans.map((s) => [s.day, s.start, s.end])).toEqual([
      [1, 600, 660],
      [3, 1380, 1440],
      [4, 0, 60],
      [0, 0, 30],
    ]);
  });
});

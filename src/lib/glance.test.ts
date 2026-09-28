import { describe, expect, it } from "vitest";
import { ago, glanceView } from "./glance";

describe("glanceView", () => {
  it("counts down to the next class in the island's few characters", () => {
    expect(glanceView({ kind: "next_today", code: "GEED 10053", when: "in 12m" }, "GEED 10053 · in 12m", false, false, false)).toEqual({
      trip: null,
      tone: "calm",
      line: "GEED 10053 · in 12m",
      label: "GEED 10053",
      short: "12m",
    });
    expect(glanceView({ kind: "next_today", code: "GEED 10053", when: "at 1PM" }, "", false, false, false).short).toBe("1PM");
  });

  it("marks a class in session as live, with its end time", () => {
    const v = glanceView({ kind: "in_session", code: "COMP 20073", until: "9AM" }, "COMP 20073 · until 9AM", false, false, false);
    expect([v.tone, v.label, v.short]).toEqual(["live", "COMP 20073", "9AM"]);
  });

  it("puts the journey ahead of the class", () => {
    const next = { kind: "next_today", code: "X", when: "in 5m" } as const;
    expect(glanceView(next, "X · in 5m", true, false, false)).toEqual({ trip: "drive", tone: "calm", line: "On the way to SIS…", label: "Syncing", short: "" });
    expect(glanceView(next, "X · in 5m", false, true, false).trip).toBe("arrived");
    expect(glanceView(next, "X · in 5m", false, false, true).trip).toBe("stalled");
  });

  it("flags sync trouble", () => {
    expect(glanceView({ kind: "sync_trouble", message: "Couldn't reach SIS" }, "Couldn't reach SIS · Try again", false, false, true)).toEqual({
      trip: "stalled",
      tone: "trouble",
      line: "Couldn't reach SIS · Try again",
      label: "SIS",
      short: "Retry",
    });
  });
});

describe("ago", () => {
  it("reads the last sync in plain words", () => {
    const now = 1_000_000_000_000;
    expect(ago(null, now)).toBe("never");
    expect(ago(String(now / 1000 - 20), now)).toBe("just now");
    expect(ago(String(now / 1000 - 5 * 60), now)).toBe("5 min ago");
    expect(ago(String(now / 1000 - 3 * 3600), now)).toBe("3 h ago");
  });
});

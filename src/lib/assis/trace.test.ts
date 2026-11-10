import { describe, expect, it } from "vitest";
import type { Step } from "./assis.svelte";
import { doing, rows, summary } from "./trace";

const found: Step = { step: "found", found: [{ key: "note:a", title: "OOP Interfaces" }, { key: "card:7", title: "OOP" }], quote: "a promise" };

describe("spec 048: LAR's trace", () => {
  it("c12: an open question reads, finds and writes; the running step is the last until the reply lands", () => {
    const steps: Step[] = [{ step: "read" }, { step: "search" }, found, { step: "write" }];
    expect(rows(steps, "ask", true).map((r) => [r.text, r.done])).toEqual([
      ["Read your timetable", true],
      ["Found 1 note and 1 deck", true],
      ["Writing", false],
    ]);
    expect(rows(steps, "ask", true)[1]).toMatchObject({ found: found.found, quote: "a promise" });
    expect(rows(steps, "ask", false).every((r) => r.done)).toBe(true);
  });

  it("c12: while searching, the search row runs; a rule answer's read step is done once the reply lands", () => {
    expect(rows([{ step: "read" }, { step: "search" }], "due", true).map((r) => [r.text, r.done])).toEqual([
      ["Read your dues and timetable", true],
      ["Searching your notes and decks…", false],
    ]);
    expect(rows([{ step: "read" }], "remind", true)[0].done).toBe(false);
    expect(rows([{ step: "read" }], "remind", false)[0].done).toBe(true);
  });

  it("c12: a woken turn says so, and a search can find nothing or be off", () => {
    expect(rows([{ step: "wake" }, { step: "read" }], "ask", false).map((r) => r.text)).toEqual(["Woke up", "Read your timetable"]);
    expect(rows([{ step: "wake" }], "ask", true)[0].text).toBe("Waking up");
    expect(rows([{ step: "read" }, { step: "search" }, { step: "nothing" }], "ask", false)[1].text).toBe("Nothing close in your notes or decks");
    expect(rows([{ step: "read" }, { step: "search" }, { step: "search_off" }], "ask", false)[1].text).toBe("Note search is off");
  });

  it("c14: folds into one line by what happened", () => {
    expect(summary([{ step: "read" }, { step: "search" }, found, { step: "write" }])).toBe("Looked at 1 note and 1 deck");
    expect(summary([{ step: "read" }, { step: "search" }, { step: "nothing" }])).toBe("Searched, nothing close");
    expect(summary([{ step: "read" }], "due")).toBe("Read your dues");
    expect(summary([{ step: "read" }], "remind")).toBe("Read your timetable");
  });

  it("c10: the status says the running step", () => {
    expect(doing([{ step: "read" }, { step: "search" }])).toBe("Searching your notes and decks…");
    expect(doing([{ step: "read" }], "due")).toBe("Reading your dues…");
    expect(doing([{ step: "wake" }])).toBe("Waking up");
    expect(doing([])).toBe("Thinking");
  });
});

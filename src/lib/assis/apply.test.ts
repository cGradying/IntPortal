import { describe as suite, expect, it } from "vitest";
import { appended, describe, newDeck, noteFor, noteTarget, reminderAt, reminderId, replaced, starters } from "./apply";

suite("applying a proposal", () => {
  it("puts a class note on the class and anything else on one note a day", () => {
    expect(noteTarget({ subject: "COMP 20073" }, "2026-10-15")).toEqual({ key: "class:COMP 20073", title: null });
    expect(noteTarget({ subject: null }, "2026-10-15")).toEqual({ key: "note:lar-2026-10-15", title: "From LAR" });
  });

  it("adds to what the student already wrote, never over it", () => {
    expect(appended(undefined, "Bring calculator")).toBe("Bring calculator");
    expect(appended("Quiz Friday\n", "Bring calculator")).toBe("Quiz Friday\n\nBring calculator");
  });

  it("reminds at 8 AM local on the day, with an id that is stable and positive", () => {
    const d = reminderAt("2026-10-16");
    expect([d.getFullYear(), d.getMonth(), d.getDate(), d.getHours(), d.getMinutes()]).toEqual([2026, 9, 16, 8, 0]);
    const id = reminderId("Pay tuition", "2026-10-19");
    expect(id).toBe(reminderId("Pay tuition", "2026-10-19"));
    expect(id).not.toBe(reminderId("Pay tuition", "2026-10-20"));
    expect(id).toBeGreaterThan(0);
    expect(id).toBeLessThanOrEqual(0x7fffffff);
  });

  it("builds a deck whose cards are new and due now", () => {
    const deck = newDeck("d1", "Binary trees", null, [{ front: "Root?", back: "Top node" }]);
    expect(deck.cards).toEqual([{ id: "", front: "Root?", back: "Top node", accepted: [], memory: { due: 0, stability: 0, difficulty: 0, reps: 0, lapses: 0, last_review: null } }]);
  });

  it("finds the student's note on a deck's subject", () => {
    const notes = [{ key: "class:COMP 20073", text: "heaps: root is min", title: null, updated: 1, preview: "" }];
    expect(noteFor(notes, "COMP 20073")).toBe("heaps: root is min");
    expect(noteFor(notes, "MATH 101")).toBeUndefined();
    expect(noteFor(notes, null)).toBeUndefined();
  });

  it("says what it will do before it does it", () => {
    expect(describe({ kind: "add_note", subject: "MATH 101", text: "x" })).toEqual({ label: "Note for MATH 101", text: "x", yes: "Save note" });
    expect(describe({ kind: "make_cards", topic: "trees", count: 8 }).yes).toBe("Make cards");
    expect(describe({ kind: "set_reminder", date: "2026-10-16", text: "Pay" }).label).toMatch(/^Reminder · .*8 AM$/);
  });
});

suite("Ask AI in a note", () => {
  it("swaps a selection or the whole note, and keeps the rest", () => {
    expect(replaced("one two three", 4, 7, "2")).toBe("one 2 three");
    expect(replaced("all of it", 0, 9, "clean")).toBe("clean");
  });

  it("suggests the open note first when one is open", () => {
    expect(starters(true)[0].label).toBe("Summarize this note");
    expect(starters(false)[0].label).toBe("Ano ang due ko?");
    expect(starters(true).every((s) => s.label.length > 0)).toBe(true);
  });
});

suite("Ask AI results landing in the note", () => {
  const note = "Heaps keep the min on top.\nQuiz on Friday.";

  it("Replace on a selection changes only those words", () => {
    const start = note.indexOf("min");
    expect(replaced(note, start, start + 3, "smallest")).toBe("Heaps keep the smallest on top.\nQuiz on Friday.");
  });

  it("Replace with nothing selected swaps the whole note (the editor's [0, length] range)", () => {
    expect(replaced(note, 0, note.length, "Tidy note.")).toBe("Tidy note.");
  });

  it("an empty range inserts at the caret and removes nothing", () => {
    expect(replaced("ab", 1, 1, "X")).toBe("aXb");
    expect(replaced("", 0, 0, "new")).toBe("new");
  });

  it("Replace leaves the original string untouched, so Undo can put it back exactly", () => {
    const original = "  keep\tthis \n\n  exactly  \n";
    const copy = `${original}`;
    const after = replaced(original, 2, 6, "changed");
    expect(after).toBe("  changed\tthis \n\n  exactly  \n");
    expect(original).toBe(copy);
  });

  it("Insert below trims the old trailing space and leaves a blank line", () => {
    expect(appended("Quiz Friday\n\n\n", "Summary")).toBe("Quiz Friday\n\nSummary");
    expect(appended("", "Summary")).toBe("Summary");
    expect(appended("   \n", "Summary")).toBe("Summary");
  });

  it("starts the chat from the open note with four suggestions, none empty", () => {
    expect(starters(true)).toHaveLength(4);
    expect(starters(false)).toHaveLength(4);
    expect(starters(true).map((s) => s.label)).toContain("What should I review from this note?");
  });
});

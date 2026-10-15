import { describe, expect, it } from "vitest";
import type { NoteItem } from "../api";
import { friendlyError, MAX_CARDS, MAX_SOURCE, noteLabel, sourceText, tidy, usable } from "./cards";

const note = (key: string, text: string, updated = 0, title: string | null = null): NoteItem => ({ key, text, title, updated, preview: "" });

describe("cards from a note", () => {
  it("cuts a long note at a line break and leaves a short one whole", () => {
    expect(sourceText("  A  b\r\n\n\n\nC ")).toBe("A b\n\nC");
    const long = `${"x".repeat(MAX_SOURCE - 100)}\n${"y".repeat(500)}`;
    expect(sourceText(long)).toBe("x".repeat(MAX_SOURCE - 100));
    expect(sourceText("z".repeat(MAX_SOURCE + 50))).toHaveLength(MAX_SOURCE);
  });

  it("trims, drops blanks and cards the deck already has, and repeats in the list", () => {
    const out = tidy(
      [
        { front: " Stack ", back: " LIFO " },
        { front: "stack?", back: "again" },
        { front: "Queue", back: "FIFO" },
        { front: "Heap", back: "  " },
        { front: " ", back: "x" },
        { front: "Tree", back: "Nodes" },
      ],
      ["QUEUE"],
    );
    expect(out).toEqual([{ front: "Stack", back: "LIFO" }, { front: "Tree", back: "Nodes" }]);
  });

  it("keeps at most MAX_CARDS", () => {
    const many = Array.from({ length: 50 }, (_, i) => ({ front: `Term ${i}`, back: "b" }));
    expect(tidy(many, [])).toHaveLength(MAX_CARDS);
    expect(tidy(many, [], 3)).toHaveLength(3);
  });

  it("offers notes with words, the deck's class first, then the newest", () => {
    const notes = [note("note:a", "old", 1), note("class:COMP 1", "mine", 0), note("note:b", "  "), note("note:c", "new", 9)];
    expect(usable(notes, "COMP 1").map((n) => n.key)).toEqual(["class:COMP 1", "note:c", "note:a"]);
    expect(usable(notes, null).map((n) => n.key)).toEqual(["note:c", "note:a", "class:COMP 1"]);
  });

  it("names a note the way the You tab does", () => {
    expect(noteLabel({ key: "note:a", title: " Trees " })).toBe("Trees");
    expect(noteLabel({ key: "note:a", title: null })).toBe("Untitled note");
    expect(noteLabel({ key: "class:COMP 1", title: null })).toBe("COMP 1");
  });

  it("turns a raw error into a sentence for the student", () => {
    expect(friendlyError("Select the words first.")).toBe("Select the words first.");
    expect(friendlyError("prompt of 5000 tokens does not fit 4096 context")).toMatch(/too long/);
    expect(friendlyError(new Error("not enough memory"))).toMatch(/memory/);
    expect(friendlyError("reqwest: reset")).not.toMatch(/reqwest/);
  });
});

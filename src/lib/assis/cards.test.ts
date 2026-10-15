import { describe, expect, it } from "vitest";
import type { NoteItem } from "../api";
import { friendlyError, hasText, MAX_CARDS, MAX_PDF, MAX_SOURCE, noteLabel, pdfError, pdfProblem, sourceText, tidy, usable } from "./cards";

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

describe("cards from a PDF", () => {
  const f = (size: number, type = "application/pdf", name = "notes.pdf") => ({ size, type, name });

  it("accepts a PDF up to the cap and says the cap when it is over", () => {
    expect(pdfProblem(f(MAX_PDF))).toBeNull();
    expect(pdfProblem(f(MAX_PDF + 1))).toBe("That PDF is over 20 MB. Pick a smaller one, o hatiin muna.");
  });

  it("refuses an empty file or a file that is not a PDF", () => {
    expect(pdfProblem(f(0))).toBe("That file is empty. Pick another PDF.");
    expect(pdfProblem(f(10, "image/png", "a.png"))).toBe("That isn't a PDF. Pick a .pdf file.");
    expect(pdfProblem(f(10, "", "Lecture.PDF"))).toBeNull();
  });

  it("treats a scan, with no real words, as having no text", () => {
    expect(hasText("")).toBe(false);
    expect(hasText(" \n\n 12 34 \u0000 ")).toBe(false);
    expect(hasText("A stack is a last-in, first-out structure.")).toBe(true);
  });

  it("turns the reader's errors into plain sentences", () => {
    expect(pdfError("This PDF has no text to read")).toBe("This PDF looks scanned, so there is no text to read. Walang mabasa si LAR dito. Try a PDF you can select words in.");
    expect(pdfError("This PDF is over 20 MB")).toContain("over 20 MB");
    expect(pdfError("This PDF has 400 pages; the limit is 300")).toBe("That PDF has too many pages (limit 300). Pick a shorter one.");
    expect(pdfError("This file could not be read as a PDF")).toBe("I couldn't open that file as a PDF. Try another one.");
    expect(pdfError("Send the PDF as raw bytes")).toBe("I couldn't read that PDF. Try again, or try a note instead.");
    expect(pdfError(new Error("LAR is busy."))).toBe("LAR is busy.");
    expect(pdfError("busy")).toBe("LAR is still working on something. Give it a second.");
  });
});

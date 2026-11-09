import { describe, expect, it } from "vitest";
import type { NoteItem } from "./api";
import { heightOf, MAX_PX, pixels, search, shelves, subjectOf } from "./shelf";

const note = (key: string, updated: number, extra: Partial<NoteItem> = {}): NoteItem => ({ key, text: "", title: null, updated, subject: null, pinned: false, preview: "", ...extra });
const deck = (id: string, subject: string | null, due = 0) => ({ id, name: id, subject, cards: 10, due });
const subjects: [string, string][] = [["COMP 20083", "OOP"], ["MATH 20133", "Discrete"]];

describe("the notebook shelf (046 C1 to C7)", () => {
  it("c2_class_notes_by_key_freeform_by_subject", () => {
    expect(subjectOf(note("class:COMP 20083", 1))).toBe("COMP 20083");
    expect(subjectOf(note("note:a", 1, { subject: "MATH 20133" }))).toBe("MATH 20133");
    expect(subjectOf(note("note:b", 1))).toBe("");
    expect(subjectOf(note("note:c", 1, { subject: "  " }))).toBe("");
  });

  it("c3_day_notes_go_under_general_newest_first", () => {
    const [general] = shelves(subjects, [note("day:2026-11-01", 1), note("day:2026-11-02", 2)], []);
    expect(general.code).toBe("");
    expect(general.notes.map((n) => n.key)).toEqual(["day:2026-11-02", "day:2026-11-01"]);
  });

  it("c4_subject_shelves_sort_pinned_then_newest", () => {
    const books = shelves(subjects, [note("note:old-pinned", 1, { subject: "COMP 20083", pinned: true }), note("class:COMP 20083", 5), note("note:new", 9, { subject: "COMP 20083" })], [deck("d1", "COMP 20083", 3)]);
    const comp = books.find((b) => b.code === "COMP 20083")!;
    expect(comp.notes.map((n) => n.key)).toEqual(["note:old-pinned", "note:new", "class:COMP 20083"]);
    expect(comp.decks.map((d) => d.id)).toEqual(["d1"]);
    expect(comp.due).toBe(3);
  });

  it("c1_one_notebook_per_subject_plus_general_in_schedule_order", () => {
    expect(shelves(subjects, [], []).map((b) => b.code)).toEqual(["", "COMP 20083", "MATH 20133"]);
  });

  it("c7_a_code_off_the_schedule_keeps_its_notes_and_decks_as_past", () => {
    const books = shelves(subjects, [note("class:CHEM 10013", 1)], [deck("old", "CHEM 10013", 2), deck("free", null)]);
    const past = books.find((b) => b.code === "CHEM 10013")!;
    expect(past.past).toBe(true);
    expect(past.name).toBe("CHEM 10013");
    expect(past.notes).toHaveLength(1);
    expect(past.decks).toHaveLength(1);
    expect(books.at(-1)!.code).toBe("CHEM 10013");
    expect(books[0].decks.map((d) => d.id)).toEqual(["free"]);
  });

  it("c1a_one_pixel_per_note_then_per_card_due_up_to_15", () => {
    const [b] = shelves([], [note("day:1", 1), note("day:2", 2)], [deck("d", null, 20)]);
    const px = pixels(b);
    expect(px).toHaveLength(MAX_PX);
    expect(px.slice(0, 2)).toEqual(["note", "note"]);
    expect(px[2]).toBe("due");
    expect(heightOf(b)).toBeGreaterThan(heightOf(shelves([], [], [])[0]));
  });

  it("c6_search_across_subjects", () => {
    const books = shelves(subjects, [note("note:a", 1, { subject: "MATH 20133", title: "Graphs", text: "trees and cycles" }), note("class:COMP 20083", 2, { text: "inheritance" })], [deck("Trees deck", "COMP 20083")]);
    const found = search(books, "tree");
    expect(found.notes.map((n) => n.key)).toEqual(["note:a"]);
    expect(found.decks.map((d) => d.id)).toEqual(["Trees deck"]);
    expect(search(books, "  ").notes).toHaveLength(0);
  });
});

import { describe, expect, it } from "vitest";
import type { NoteItem } from "./api";
import { hasNotes, hasText, photoProblem, previewOf } from "./photos";

const note = (extra: Partial<NoteItem>): NoteItem => ({ key: "note:a", text: "", title: null, updated: 0, subject: null, pinned: false, preview: "", ...extra });

describe("photo-only notes", () => {
  it("c17d_photo_only_preview", () => {
    expect(previewOf(note({ photos: 3 }))).toBe("3 photos");
    expect(previewOf(note({ photos: 1 }))).toBe("1 photo");
    expect(previewOf(note({ preview: "Trees", photos: 3 }))).toBe("Trees");
    expect(previewOf(note({}))).toBe("");
    expect(hasNotes(note({ key: "class:A", photos: 2 }))).toBe(true);
    expect(hasNotes(note({}))).toBe(false);
  });
  it("c17d_after_class_needs_text", () => {
    const only = note({ key: "class:A", photos: 2 });
    expect(hasText(only)).toBe(false);
    expect(hasText(note({ text: "Quiz Friday" }))).toBe(true);
  });
  it("c17b_each_problem_has_its_own_line", () => {
    expect(new Set(["camera_denied", "no_camera", "no_space", "other"].map((k) => photoProblem(k as "other"))).size).toBe(4);
  });
});

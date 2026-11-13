import { describe, expect, it } from "vitest";
import { anyReminderOn, dueDecks } from "./planning";

const off = { lead: 0, deadlineAt: -1, studyAt: -1, warmUp: false, afterClass: false, brief: false };
const decks = [
  { subject: "A", due: 3 },
  { subject: "B", due: 0 },
  { subject: "B", due: 2 },
];

describe("spec 042 plan helpers", () => {
  it("c4_start_without_subject_reviews_every_due_deck", () => {
    expect(dueDecks(decks, null)).toHaveLength(2);
  });
  it("c7_five_card_session_takes_that_subjects_due_deck", () => {
    expect(dueDecks(decks, "B")).toEqual([{ subject: "B", due: 2 }]);
  });
  it("c16_extras_schedule_with_everything_else_off", () => {
    expect(anyReminderOn(off)).toBe(false);
    expect(anyReminderOn({ ...off, brief: true })).toBe(true);
    expect(anyReminderOn({ ...off, afterClass: true })).toBe(true);
    expect(anyReminderOn({ ...off, warmUp: true })).toBe(true);
    expect(anyReminderOn({ ...off, lead: 10 })).toBe(true);
  });
});

import { describe, expect, it } from "vitest";
import type { DeadlineEntry } from "./api";
import { addDone, pruneWeek, removeDone, undoable, UNDO_MS, WEEK_MS } from "./doneWeek";

const e = (id: string) => ({ id, title: id }) as DeadlineEntry;

describe("spec 041 C6: Undo window and Done this week", () => {
  it("c6_undo_lasts_five_seconds", () => {
    const [x] = addDone([], e("a"), 1000);
    expect(undoable(x, 1000 + UNDO_MS - 1)).toBe(true);
    expect(undoable(x, 1000 + UNDO_MS)).toBe(false);
  });
  it("c6_done_this_week_keeps_newest_first_and_unmarks", () => {
    let l = addDone([], e("a"), 1);
    l = addDone(l, e("b"), 2);
    l = addDone(l, e("a"), 3);
    expect(l.map((x) => x.entry.id)).toEqual(["a", "b"]);
    expect(removeDone(l, "a").map((x) => x.entry.id)).toEqual(["b"]);
  });
  it("c6_week_drops_old", () => {
    const l = [...addDone([], e("old"), 0), ...addDone([], e("new"), WEEK_MS)];
    expect(pruneWeek(l, WEEK_MS + 1).map((x) => x.entry.id)).toEqual(["new"]);
  });
});

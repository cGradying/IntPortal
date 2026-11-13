// Spec 041 C6: Done shows Undo for 5 seconds, then the item rests in a quiet
// "Done this week" row where it can still be un-marked. Pure helpers; the card
// keeps the list in localStorage so it survives leaving Today.
import type { DeadlineEntry } from "./api";

export const UNDO_MS = 5000;
export const WEEK_MS = 7 * 86_400_000;
const KEY = "ip.doneWeek";

export interface DoneItem {
  entry: DeadlineEntry;
  at: number;
}

/** Newest first, no duplicates. */
export const addDone = (list: DoneItem[], entry: DeadlineEntry, at: number): DoneItem[] => [{ entry, at }, ...list.filter((x) => x.entry.id !== entry.id)];

export const removeDone = (list: DoneItem[], id: string): DoneItem[] => list.filter((x) => x.entry.id !== id);

/** Drops what was finished more than a week ago. */
export const pruneWeek = (list: DoneItem[], now: number): DoneItem[] => list.filter((x) => now - x.at < WEEK_MS);

/** Still inside the 5-second Undo window. */
export const undoable = (x: DoneItem, now: number) => now - x.at < UNDO_MS;

export function loadDone(now: number): DoneItem[] {
  try {
    return pruneWeek(JSON.parse(localStorage.getItem(KEY) ?? "[]"), now);
  } catch {
    return [];
  }
}

export function saveDone(list: DoneItem[]) {
  try {
    localStorage.setItem(KEY, JSON.stringify(list));
  } catch {
    // Private mode or full: the row just won't survive a relaunch.
  }
}

import { describe as suite, expect, it } from "vitest";
import type { DeadlineEntry, Today } from "../api";
import { entryLabel } from "../deadlines";
import { appended, changedDay, dayLabel, describe, doneWord, weekOf, whenLabel, folded, marked, noteLines, pickCaption, withNotes, wordDiff, followUps, lineDiff, foundLine, newDeck, noteFor, noteTarget, reminderAt, reminderId, replaced, starters, topicOf } from "./apply";

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
    const notes = [{ key: "class:COMP 20073", text: "heaps: root is min", title: null, updated: 1, subject: null, pinned: false, preview: "" }];
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

suite("spec 048: the chat's suggestions and the found line", () => {
  const now = new Date("2026-11-09T09:40:00");
  const lab: DeadlineEntry = { id: "1", source: "syllabus", subject: "COMP 20083", course: null, title: "Lab 4: Interfaces", kind: "project", due: { day: "2026-11-11" }, overdue: false, url: null };
  const next = { session: { subject_code: "COMP 20083", description: "OOP", faculty: "x", day: "Monday", start: 630, end: 810, occurrence: 0 }, date: "2026-11-09", is_now: false, minutes_away: 50 } as Today["next"];

  it("c17: starts from the day, each with its reason, and the reminder that fills the field", () => {
    const s = starters(false, { now, due: lab, note: { key: "note:a", title: "OOP Interfaces" }, next });
    expect(s.map((x) => [x.label, x.why, x.fill])).toEqual([
      ["What's due this week?", `Lab 4: Interf… ${entryLabel(lab, now)}`, false],
      ["Explain OOP Interfaces simply", "last note", false],
      ["Anong klase ko ngayon?", "10:30", false],
      ["Remind me bukas ng umaga", undefined, true],
    ]);
  });

  it("c17: skips what it does not know, and tops up from the plain ones", () => {
    const s = starters(false, { now });
    expect(s).toHaveLength(4);
    expect(s.map((x) => x.label)).toEqual(["Remind me bukas ng umaga", "Ano ang due ko?", "Anong klase ko ngayon?", "Add a note: bring calculator"]);
    expect(s.every((x) => !x.why)).toBe(true);
  });

  it("c18: a due answer offers the reminder the night before and the subject; an open answer, cards and the note", () => {
    expect(followUps({ intent: "due" }, { now, due: lab })).toEqual([{ label: "Remind me Tuesday night", fill: true }, { label: "Open COMP 20083", fill: false, open: "plan:COMP 20083" }]);
    expect(followUps({ intent: "ask", sources: [{ key: "note:a", title: "OOP Interfaces" }] })).toEqual([{ label: "Make 5 cards from OOP Interfaces", fill: false }, { label: "Open OOP Interfaces", fill: false, open: "note:a" }]);
    expect(followUps({ intent: "classes" }, { now, next }).map((x) => x.label)).toEqual(["What's due this week?", "Open COMP 20083"]);
    expect(followUps({ intent: "grades" }, { now }).map((x) => x.label)).toEqual(starters(false, { now }).map((x) => x.label));
    expect(followUps({}, undefined)).toEqual(starters(false));
  });

  it("c12: names what a search found by kind", () => {
    expect(foundLine([{ key: "note:a" }, { key: "class:MATH 101" }])).toBe("2 notes");
    expect(foundLine([{ key: "note:a" }, { key: "card:7" }])).toBe("1 note and 1 deck");
    expect(foundLine([{ key: "note:a" }, { key: "note:b" }, { key: "card:7" }, { key: "plan:COMP 20083" }])).toBe("2 notes, 1 deck and 1 subject");
    expect(foundLine([{ key: "card:1" }, { key: "card:2" }])).toBe("2 decks");
    expect(foundLine([])).toBe("");
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

suite("follow-ups after an answer from what LAR knows (spec 021 C21)", () => {
  it("offers simpler and cards on the question's topic", () => {
    const f = followUps({ intent: "ask", known: true }, undefined, "What is osmosis?");
    expect(f.map((s) => s.label)).toEqual(["Explain it simpler", "Quiz me on it"]);
    expect(f[1].say).toBe("Make 5 flashcards on osmosis");
  });

  it("reads the topic out of the question", () => {
    expect(topicOf("explain the chain rule")).toBe("chain rule");
    expect(topicOf("Who is Jose Rizal?")).toBe("Jose Rizal");
    expect(topicOf("how does a hash table work?")).toBe("hash table work");
    expect(topicOf("photosynthesis")).toBe("photosynthesis");
  });

  it("an answer from notes keeps its own follow-ups", () => {
    const f = followUps({ intent: "ask", known: false, sources: [{ key: "note:a", title: "Bio" }] }, undefined, "What is osmosis?");
    expect(f[0].label).toMatch(/^Make 5 cards from Bio/);
  });
});

suite("spec 062 C13: the before-and-after of a note change", () => {
  it("keeps shared lines and marks the rest removed or added", () => {
    expect(lineDiff("Quiz Friday\nBring ID\nRoom 302", "Quiz Monday\nBring ID\nRoom 302")).toEqual([
      { kind: "del", text: "Quiz Friday" },
      { kind: "add", text: "Quiz Monday" },
      { kind: "same", text: "Bring ID" },
      { kind: "same", text: "Room 302" },
    ]);
    expect(lineDiff("a", "a\nb")).toEqual([{ kind: "same", text: "a" }, { kind: "add", text: "b" }]);
  });

  it("folds more than three unchanged lines in a row", () => {
    const before = "1\n2\n3\n4\n5\nold";
    const rows = folded(lineDiff(before, "1\n2\n3\n4\n5\nnew"));
    expect(rows).toEqual([{ kind: "same", text: "1" }, { kind: "fold", n: 3 }, { kind: "same", text: "5" }, { kind: "del", text: "old" }, { kind: "add", text: "new" }]);
  });

  it("names the change on the card", () => {
    expect(describe({ kind: "edit_note", key: "note:1", name: "Heaps", edit: "append", before: "", after: "x" }).label).toBe("Add to Heaps");
    expect(describe({ kind: "delete_note", key: "note:1", name: "Heaps", preview: "x" })).toMatchObject({ label: "Delete this note?", yes: "Delete" });
  });
});

suite("spec 062 C5: the note-from-chat card", () => {
  it("shows the whole body with Save, and leaves the subject to its chip (063 C1)", () => {
    expect(describe({ kind: "save_note", title: "Heaps", subject: "COMP 20073", text: "- a\n- b", partial: false })).toEqual({ label: "Note from our chat", text: "- a\n- b", yes: "Save" });
  });

  it("has no subject on the label when none was picked", () => {
    expect(describe({ kind: "save_note", title: "Heaps", subject: null, text: "- a", partial: false }).label).toBe("Note from our chat");
  });

  it("looks the same when older turns did not fit", () => {
    const p = { kind: "save_note" as const, title: "Heaps", subject: null, text: "- a", partial: false };
    expect(describe({ ...p, partial: true })).toEqual(describe(p));
  });
});

suite("spec 062 B: the diff and its folds, more cases", () => {
  const kinds = (rows: { kind: string }[]) => rows.map((r) => r.kind);

  it("shows removed lines before the added ones in each changed block", () => {
    expect(lineDiff("1\n2\n3", "x\ny\n3")).toEqual([
      { kind: "del", text: "1" },
      { kind: "del", text: "2" },
      { kind: "add", text: "x" },
      { kind: "add", text: "y" },
      { kind: "same", text: "3" },
    ]);
    expect(kinds(lineDiff("keep\nold\nkeep too", "keep\nnew\nkeep too"))).toEqual(["same", "del", "add", "same"]);
  });

  it("marks a note that did not change as all unchanged, and a removed last line as removed", () => {
    expect(kinds(lineDiff("a\nb", "a\nb"))).toEqual(["same", "same"]);
    expect(lineDiff("a\nb", "a")).toEqual([{ kind: "same", text: "a" }, { kind: "del", text: "b" }]);
    expect(lineDiff("a\nc", "a\nb\nc")).toEqual([{ kind: "same", text: "a" }, { kind: "add", text: "b" }, { kind: "same", text: "c" }]);
  });

  it("an appended line is shown as added only", () => {
    expect(lineDiff("- a\n- b", "- a\n- b\n- c")).toEqual([{ kind: "same", text: "- a" }, { kind: "same", text: "- b" }, { kind: "add", text: "- c" }]);
  });

  it("adding to an empty note shows only the added line", () => {
    expect(lineDiff("", "x")).toEqual([{ kind: "add", text: "x" }]);
  });

  it("rebuilds both notes from the diff", () => {
    const [a, b] = ["Quiz Friday\nBring ID\nRoom 302\nHeaps", "Quiz Monday\nRoom 302\nCalculator\nHeaps"];
    const rows = lineDiff(a, b);
    expect(rows.filter((r) => r.kind !== "add").map((r) => r.text).join("\n")).toBe(a);
    expect(rows.filter((r) => r.kind !== "del").map((r) => r.text).join("\n")).toBe(b);
  });

  it("keeps three unchanged lines and folds from four", () => {
    const same = (n: number) => Array.from({ length: n }, (_, i) => ({ kind: "same" as const, text: String(i) }));
    expect(folded(same(3))).toHaveLength(3);
    expect(folded(same(4))).toEqual([same(4)[0], { kind: "fold", n: 2 }, same(4)[3]]);
    expect(folded(same(10))).toEqual([same(10)[0], { kind: "fold", n: 8 }, same(10)[9]]);
    expect(folded([])).toEqual([]);
  });

  it("folds each long run on its own and leaves the changes alone", () => {
    const run = (tag: string, n: number) => Array.from({ length: n }, (_, i) => ({ kind: "same" as const, text: `${tag}${i}` }));
    const rows = folded([...run("a", 5), { kind: "del", text: "x" }, { kind: "add", text: "y" }, ...run("b", 2), { kind: "add", text: "z" }, ...run("c", 6)]);
    expect(kinds(rows)).toEqual(["same", "fold", "same", "del", "add", "same", "same", "add", "same", "fold", "same"]);
    expect(rows.filter((r) => r.kind === "fold")).toEqual([{ kind: "fold", n: 3 }, { kind: "fold", n: 4 }]);
  });

  it("shows every line it does not fold: shown plus folded add up to the whole note", () => {
    const all = lineDiff(Array.from({ length: 12 }, (_, i) => `l${i}`).join("\n"), Array.from({ length: 12 }, (_, i) => (i === 6 ? "NEW" : `l${i}`)).join("\n"));
    const rows = folded(all);
    const hidden = rows.reduce((n, r) => n + (r.kind === "fold" ? (r as { n: number }).n : 0), 0);
    expect(rows.length - rows.filter((r) => r.kind === "fold").length + hidden).toBe(all.length);
  });
});

suite("spec 063 A: the cards in their picked look", () => {
  it("C1: draws a note's points as bullets and keeps other lines as they are", () => {
    expect(noteLines("Heaps\n- A tree\n* kept in an array\n\n+ O(log n)")).toEqual([
      { bullet: false, text: "Heaps" },
      { bullet: true, text: "A tree" },
      { bullet: true, text: "kept in an array" },
      { bullet: false, text: "" },
      { bullet: true, text: "O(log n)" },
    ]);
    expect(noteLines("-dash with no space")).toEqual([{ bullet: false, text: "-dash with no space" }]);
  });

  it("C3: marks only the words that changed inside a line, in runs", () => {
    expect(wordDiff("- Exam on Thursday, Room S512", "- Exam on Friday, Room S512")).toEqual([
      { kind: "same", text: "- Exam on" },
      { kind: "del", text: "Thursday," },
      { kind: "add", text: "Friday," },
      { kind: "same", text: "Room S512" },
    ]);
    expect(wordDiff("a b", "a b c d")).toEqual([{ kind: "same", text: "a b" }, { kind: "add", text: "c d" }]);
  });

  it("C3: a removed line followed by an added one that shares words shows once, with word marks", () => {
    const rows = marked(lineDiff("Title\nExam on Thursday\nEnd", "Title\nExam on Friday\nEnd"));
    expect(rows).toEqual([
      { kind: "same", text: "Title" },
      { kind: "change", words: [{ kind: "same", text: "Exam on" }, { kind: "del", text: "Thursday" }, { kind: "add", text: "Friday" }] },
      { kind: "same", text: "End" },
    ]);
  });

  it("C3: a line wholly added stays added, and one wholly removed stays removed", () => {
    expect(marked(lineDiff("a\nb", "a\nb\nHeapsort is O(n log n)"))).toEqual([{ kind: "same", text: "a" }, { kind: "same", text: "b" }, { kind: "add", text: "Heapsort is O(n log n)" }]);
    expect(marked(lineDiff("a\nold line", "a"))).toEqual([{ kind: "same", text: "a" }, { kind: "del", text: "old line" }]);
    // Nothing in common: struck over gold, not a line of marks.
    expect(marked(lineDiff("x\ncats sleep", "x\ndogs run")).map((r) => r.kind)).toEqual(["same", "del", "add"]);
  });

  it("C3: pairs removed and added lines in order, and leaves the extra ones whole", () => {
    const rows = marked(lineDiff("Quiz Friday\nBring ID", "Quiz Monday\nBring ID card\nRoom 302"));
    expect(rows.map((r) => r.kind)).toEqual(["change", "change", "add"]);
  });

  it("C3: unchanged runs still fold around the word marks", () => {
    const before = ["t", "1", "2", "3", "4", "Exam on Thursday", "5"].join("\n");
    const rows = folded(marked(lineDiff(before, before.replace("Thursday", "Friday"))));
    expect(rows.map((r) => r.kind)).toEqual(["same", "fold", "same", "change", "same"]);
    expect(rows[1]).toEqual({ kind: "fold", n: 3 });
  });

  it("C5: says what was done on an applied card", () => {
    expect(["edit_note", "rename_note", "move_note", "delete_note"].map((k) => doneWord(k as never))).toEqual(["Changed", "Renamed", "Moved", "Deleted"]);
  });

  const notes = [
    { key: "note:1", text: "", title: "Limits", updated: 100, subject: "MATH 101", pinned: false, preview: "" },
    { key: "class:COMP 20073", text: "", title: null, updated: 200, subject: null, pinned: false, preview: "" },
    { key: "note:2", text: "", title: "Loose", updated: 300, subject: null, pinned: false, preview: "" },
  ];

  it("C6: fills each candidate's subject and last change from the notes, and Move's old subject", () => {
    const pick = withNotes({ kind: "pick_note", ask: "fix it", candidates: ["note:1", "class:COMP 20073", "note:2", "note:gone"].map((key) => ({ key, name: key })) }, notes);
    expect(pick.kind === "pick_note" && pick.candidates.map((c) => [c.subject, c.updated])).toEqual([
      ["MATH 101", 100],
      ["COMP 20073", 200],
      ["", 300],
      [undefined, undefined],
    ]);
    expect(withNotes({ kind: "move_note", key: "note:1", name: "Limits", subject: "MATH 102" }, notes)).toMatchObject({ from: "MATH 101" });
    expect(withNotes({ kind: "rename_note", key: "note:1", name: "Limits", title: "X" }, notes)).toEqual({ kind: "rename_note", key: "note:1", name: "Limits", title: "X" });
  });

  it("C6: the row caption is '{subject} · changed {day}'", () => {
    const now = new Date(2026, 10, 27, 15, 0);
    const at = (d: Date) => d.getTime() / 1000;
    expect(changedDay(at(new Date(2026, 10, 27, 8, 0)), now)).toBe("today");
    expect(changedDay(at(new Date(2026, 10, 26, 23, 0)), now)).toBe("yesterday");
    expect(changedDay(at(new Date(2026, 10, 23, 9, 0)), now)).toBe(new Date(2026, 10, 23).toLocaleDateString(undefined, { weekday: "short" }));
    expect(changedDay(at(new Date(2026, 10, 2, 9, 0)), now)).toBe(new Date(2026, 10, 2).toLocaleDateString(undefined, { month: "short", day: "numeric" }));
    const today = at(new Date(2026, 10, 27, 8, 0));
    expect(pickCaption({ subject: "MATH 101", updated: today }, now)).toBe("MATH 101 · changed today");
    expect(pickCaption({ subject: "", updated: today }, now)).toBe("Changed today");
    expect(pickCaption({}, now)).toBe("");
  });
});

suite("spec 064: the week's cards", () => {
  it("C14: says which week, short on the card and spelled out for VoiceOver", () => {
    expect(dayLabel("2026-12-05")).toBe("Sat, Dec 5");
    expect(whenLabel("2026-12-04")).toBe("Fri, Dec 4 only");
    expect(whenLabel("2026-12-04", true)).toBe("Friday, December 4 only");
    expect(whenLabel(null)).toBe("Every week");
  });

  it("keys a one-week change by its week's Monday", () => {
    expect(weekOf("2026-12-04")).toBe("2026-11-30");
    expect(weekOf("2026-11-30")).toBe("2026-11-30");
    expect(weekOf("2026-12-06")).toBe("2026-11-30");
  });

  it("labels each card as the copy table says", () => {
    const label = (p: Parameters<typeof describe>[0]) => describe(p).label;
    expect(label({ kind: "add_deadline", title: "Essay", subject: null, deadline: "project", date: "2026-12-04" })).toBe("New deadline");
    expect(label({ kind: "change_deadline", id: "own:a", name: "Essay", was: "2026-12-04", title: "Essay", date: "2026-12-07" })).toBe("Move deadline");
    expect(label({ kind: "change_deadline", id: "own:a", name: "Essay", was: "2026-12-04", title: "Paper", date: "2026-12-04" })).toBe("Rename deadline");
    expect(label({ kind: "done_deadline", id: "x", name: "Quiz" })).toBe("Mark done");
    expect(describe({ kind: "delete_deadline", id: "own:a", name: "Essay", date: "2026-12-04" })).toMatchObject({ label: "Delete deadline", yes: "Delete" });
    expect(label({ kind: "mark_class", session: "s", name: "MATH", week: null, mark: "vacant" })).toBe("No class");
    expect(label({ kind: "mark_class", session: "s", name: "MATH", week: null, mark: "online" })).toBe("Online");
    const slot = { day: "Friday" as const, start: 540, end: 630 };
    expect(label({ kind: "move_class", session: "s", name: "MATH", week: null, was: slot, slot })).toBe("Move class");
    const c = { code: "ORG", name: "Org", room: "", teacher: "", meetings: [] };
    expect(label({ kind: "change_own_class", was: c, class: c })).toBe("Change class");
    expect(label({ kind: "delete_own_class", code: "ORG", name: "Org" })).toBe("Delete class");
    expect(label({ kind: "move_reminder", id: 1, text: "Pay", was: "2026-12-04", date: "2026-12-05" })).toBe("Move reminder");
    expect(label({ kind: "delete_reminder", id: 1, text: "Pay" })).toBe("Delete reminder");
  });

  it("C15: says Changed, Deleted or Done after Apply", () => {
    expect(["add_deadline", "change_deadline", "mark_class", "move_class", "change_own_class", "move_reminder"].map((k) => doneWord(k as never))).toEqual(Array(6).fill("Changed"));
    expect(["delete_deadline", "delete_own_class", "delete_reminder"].map((k) => doneWord(k as never))).toEqual(Array(3).fill("Deleted"));
    expect(doneWord("done_deadline")).toBe("Done");
  });
});

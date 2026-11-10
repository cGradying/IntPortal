import { describe, expect, it } from "vitest";
import { addEntry, applyTemplate, block, cardLines, entryHeading, setLines, toggleCheck, words, wrap } from "./md";
import { tidy } from "../assis/cards";

describe("inline marks", () => {
  it("c11_wraps_and_unwraps_a_selection", () => {
    const a = wrap("say hi now", 4, 6, "bold");
    expect(a).toEqual({ text: "say **hi** now", from: 6, to: 8 });
    expect(wrap(a.text, a.from, a.to, "bold")).toEqual({ text: "say hi now", from: 4, to: 6 });
    expect(wrap("x", 1, 1, "mark")).toEqual({ text: "x====", from: 3, to: 3 });
  });
});

describe("line kinds", () => {
  it("c11_turns_lines_into_a_list_and_back", () => {
    const a = setLines("one\ntwo", 0, 7, "number");
    expect(a.text).toBe("1. one\n2. two");
    expect(setLines(a.text, 0, a.text.length, "number").text).toBe("one\ntwo");
    expect(setLines("- one", 3, 3, "check").text).toBe("- [ ] one");
    expect(setLines("- [ ] one", 3, 3, "bullet").text).toBe("- one");
    expect(setLines("a\n### b", 3, 3, "h").text).toBe("a\nb");
  });
  it("c11_a_code_block_puts_the_cursor_inside", () => {
    const b = block("hi", 2, "code");
    expect(b.text).toBe("hi\n\n```\n\n```\n");
    expect(b.text.slice(b.from - 4, b.from)).toBe("```\n");
  });
});

describe("templates", () => {
  it("c13_template_never_replaces", () => {
    const t = applyTemplate("my notes", "cornell");
    expect(t.text.startsWith("my notes\n\n### Cues")).toBe(true);
    expect(applyTemplate("", "lecture").text.startsWith("### Key points\n- ")).toBe(true);
    expect(applyTemplate("kept", "blank").text).toBe("kept");
  });
  it("c13_the_cursor_lands_under_the_first_heading", () => {
    const t = applyTemplate("", "lecture");
    expect(t.text.slice(0, t.from)).toBe("### Key points\n- ");
  });
});

describe("dated entries", () => {
  it("c14_heading_in_the_phones_locale", () => {
    expect(entryHeading("2026-10-19", "en-US")).toBe("### Mon, Oct 19");
    expect(entryHeading("2026-10-20", "fil-PH")).toMatch(/^### /);
  });
  it("c14_entry_not_repeated", () => {
    const a = addEntry("old stuff", "### Mon, Oct 20");
    expect(a.text).toBe("old stuff\n\n### Mon, Oct 20\n");
    expect(a.from).toBe(a.text.length);
    const b = addEntry(a.text + "\n\n", "### Mon, Oct 20");
    expect(b.text).toBe(a.text);
    expect(addEntry("", "### Tue, Oct 21").text).toBe("### Tue, Oct 21\n");
  });
});

describe("checklists", () => {
  it("c12_a_tick_flips_only_that_box", () => {
    const t = "- [ ] a\n- [x] b";
    expect(toggleCheck(t, 0)).toBe("- [x] a\n- [x] b");
    expect(toggleCheck(t, 8)).toBe("- [ ] a\n- [ ] b");
    expect(toggleCheck("plain", 0)).toBe("plain");
  });
});

describe("words", () => {
  it("counts words in any language, not marks", () => {
    expect(words("## Hello, **mundo** – it's 2026")).toBe(4);
  });
});

describe("make cards", () => {
  it("c18_term_lines_start_chosen", () => {
    const l = cardLines("### Terms\n- Stack - last in, first out\nA plain sentence.\n\nQueue – first in, first out");
    expect(l.map((x) => x.chosen)).toEqual([false, true, false, true]);
    expect(l[1]).toMatchObject({ front: "Stack", back: "last in, first out" });
  });
  it("c20_duplicates_dropped", () => {
    expect(tidy([{ front: "Stack", back: "LIFO" }, { front: "queue", back: "FIFO" }], ["stack"])).toEqual([{ front: "queue", back: "FIFO" }]);
  });
});

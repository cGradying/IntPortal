import { describe, expect, it } from "vitest";
import { checkable, claimFor, faceFor, optionsFor } from "./quiz";

// A seeded random, so the long runs are the same every time.
function seeded(seed = 7) {
  let s = seed;
  return () => ((s = (s * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
}

const card = (back: string, wrong?: string[]) => ({ front: "Osmosis", back, wrong });

describe("spec 063 C16: true or false needs a checkable claim", () => {
  it("c16_a_changed_number_or_content_word_is_checkable", () => {
    expect(checkable("water moves toward more dissolved substance", "water moves toward less dissolved substance")).toBe(true);
    expect(checkable("it has 46 chromosomes", "it has 23 chromosomes")).toBe(true);
    expect(checkable("last in, first out", "first in, first out")).toBe(true);
  });

  it("c16_same_words_reordered_or_with_only_small_words_changed_is_not", () => {
    expect(checkable("the cell makes energy", "a cell makes energy")).toBe(false);
    expect(checkable("cells make energy", "the cell makes energy")).toBe(false);
    expect(checkable("A causes B", "B causes A")).toBe(false);
  });

  it("c16_a_card_with_no_checkable_wrong_is_never_dealt_true_or_false", () => {
    const rnd = seeded();
    const c = card("A causes B", ["B causes A", "the B causes an A", "B, causes, A"]);
    let last: string[] = [];
    for (let i = 0; i < 300; i++) {
      const f = faceFor(last, c, rnd);
      expect(f).not.toBe("tf");
      last = [...last, f];
    }
  });

  it("c16_a_false_claim_is_only_ever_a_checkable_wrong_answer", () => {
    const rnd = seeded(3);
    const c = card("water moves toward more dissolved substance", ["water moves toward more substance dissolved", "water moves toward less dissolved substance", "salt moves toward more dissolved substance"]);
    const t = { t: 0, f: 0 };
    for (let i = 0; i < 200; i++) {
      const { claim, truth } = claimFor(c, t, rnd);
      if (!truth) expect(["water moves toward less dissolved substance", "salt moves toward more dissolved substance"]).toContain(claim);
      else expect(claim).toBe(c.back);
    }
  });
});

describe("spec 063 C10: Quiz deals each card as one of three", () => {
  const c = card("water moves toward more dissolved substance", ["water moves toward less dissolved substance", "salt moves toward more dissolved substance", "water moves toward more dissolved sugar"]);

  it("c10_mixes_all_three_faces", () => {
    const rnd = seeded();
    let last: string[] = [];
    for (let i = 0; i < 300; i++) last = [...last, faceFor(last, c, rnd)];
    for (const f of ["choice", "type", "tf"]) expect(last.filter((x) => x === f).length).toBeGreaterThan(60);
  });

  it("c10_never_the_same_face_three_times_in_a_row", () => {
    for (const seed of [1, 2, 3, 4, 5]) {
      const rnd = seeded(seed);
      let last: string[] = [];
      for (let i = 0; i < 500; i++) {
        last = [...last, faceFor(last, i % 3 ? c : card("A causes B"), rnd)];
        const [a, b, d] = last.slice(-3);
        if (last.length >= 3) expect(a === b && b === d).toBe(false);
      }
    }
  });

  it("c10_true_or_false_is_half_the_back_and_half_a_wrong_answer", () => {
    const rnd = seeded(11);
    const t = { t: 0, f: 0 };
    for (let i = 0; i < 1000; i++) claimFor(c, t, rnd);
    expect(t.t + t.f).toBe(1000);
    expect(Math.abs(t.t - t.f)).toBeLessThan(60);
    // A short session leans back toward even.
    const short = { t: 3, f: 0 };
    let falses = 0;
    for (let i = 0; i < 200; i++) if (!claimFor(c, { ...short }, rnd).truth) falses++;
    expect(falses).toBeGreaterThan(120);
  });
});

describe("spec 063 C7: multiple choice options", () => {
  it("c7_options_are_the_back_and_its_three_wrong_answers", () => {
    const opts = optionsFor(card("b", ["w1", "w2", "w3"]), seeded());
    expect([...opts!].sort()).toEqual(["b", "w1", "w2", "w3"]);
  });

  it("c7_a_card_without_three_wrong_answers_falls_back_to_other_backs", () => {
    expect(optionsFor(card("b"), seeded())).toBeNull();
    expect(optionsFor(card("b", ["w1"]), seeded())).toBeNull();
  });
});

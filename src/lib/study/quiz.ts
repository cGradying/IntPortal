// Quiz mode's dealing (specs 062 C21, 063 C7–C10, C16): each card is shown as multiple choice,
// identification (Type) or true or false, picked at random per card and never the same three
// times in a row. Pure, so the rules are tested apart from the session.
import type { Face } from "./game";

type QuizCard = { back: string; wrong?: string[] };

const SMALL = new Set("a an the of to in on at by for from with and or but as is are was were be been it its this that these those which who whom".split(" "));
// Plural and singular count as the same word, so "cells" against "cell" isn't a change.
const words = (s: string) => (s.toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? []).filter((w) => /\d/.test(w) || (w.length > 1 && !SMALL.has(w))).map((w) => (w.length > 3 ? w.replace(/s$/, "") : w));

/** C16: a wrong answer is a fair true-or-false claim only when it drops or changes a number or a content word the back has. */
export function checkable(back: string, wrong: string): boolean {
  const has = new Set(words(wrong));
  return words(back).some((w) => !has.has(w));
}

const claims = (c: QuizCard) => (c.wrong ?? []).filter((w) => checkable(c.back, w));

/** The face for the next card: never a third in a row, and true or false only with a checkable claim. */
export function faceFor(last: readonly string[], c: QuizCard, rnd = Math.random): Face {
  const [a, b] = last.slice(-2);
  const ok = (["choice", "type", "tf"] as const).filter((f) => !(a === f && b === f) && (f !== "tf" || claims(c).length));
  return ok[Math.floor(rnd() * ok.length)];
}

/**
 * The claim on a true-or-false card: its back or one of its checkable wrong answers, half and half.
 * `tally` counts the claims dealt so far and leans the coin back toward even, so a short quiz
 * isn't all True, while the next one still can't be called.
 */
export function claimFor(c: QuizCard, tally: { t: number; f: number }, rnd = Math.random): { claim: string; truth: boolean } {
  const wrong = claims(c);
  const truth = !wrong.length || rnd() < (tally.t < tally.f ? 0.7 : tally.t > tally.f ? 0.3 : 0.5);
  if (truth) tally.t++;
  else tally.f++;
  return { claim: truth ? c.back : wrong[Math.floor(rnd() * wrong.length)], truth };
}

/** C7: the back and the card's three wrong answers in random order, or null to take other cards' backs as Choice does. */
export function optionsFor(c: QuizCard, rnd = Math.random): string[] | null {
  const a = [c.back, ...(c.wrong ?? [])];
  // The tiles are keyed by their text, so a repeat would break the face.
  if (a.length !== 4 || new Set(a).size !== 4) return null;
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rnd() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

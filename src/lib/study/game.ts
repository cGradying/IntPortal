// The study session's game rules (spec 055): a combo that multiplies, a soft clock that
// heats the table, a personal best per deck. Pure, so the rules are tested apart from the UI.

export type Mode = "flash" | "type" | "choice" | "quiz";
/** How one card is shown. Quiz deals each card as choice, type or true or false (spec 063 C10). */
export type Face = "flash" | "type" | "choice" | "tf";
export type Answer = "right" | "hard" | "miss";
export type Run = { streak: number; top: number; score: number; heat: number; rights: number; tries: number };

export const fresh = (): Run => ({ streak: 0, top: 0, score: 0, heat: 0, rights: 0, tries: 0 });

/** x2 at three in a row, x3 at six, x4 at ten. */
export const TIERS = [3, 6, 10] as const;
export const mult = (streak: number) => 1 + TIERS.filter((t) => streak >= t).length;

/** How far the combo meter is toward the next tier, or null at x4. */
export function toNext(streak: number): { need: number; frac: number } | null {
  const next = TIERS.find((t) => streak < t);
  if (next === undefined) return null;
  const prev = [0, ...TIERS][TIERS.indexOf(next)];
  return { need: next - streak, frac: (streak - prev) / (next - prev) };
}

/** The soft clock per card: typing gets longer; true or false is timed like Choice. Running out is never a miss. */
export const clockSecs = (face: Face) => (face === "type" ? 14 : 8);
export const QUICK_BONUS = 5;

/**
 * One answer. Right adds 10 × the multiplier, plus a bonus when it came in the first half of
 * the clock. Hard keeps the combo and scores nothing. A miss drops the combo and the heat.
 * Heat (0–3) rises one step on a quick answer and cools one step on a slow one.
 */
export function play(run: Run, answer: Answer, secs: number, face: Face) {
  const clock = clockSecs(face);
  const quick = answer === "right" && secs <= clock / 2;
  const slow = secs > clock;
  const was = mult(run.streak);
  const r = { ...run, tries: run.tries + 1 };
  let points = 0;
  if (answer === "miss") {
    r.streak = 0;
    r.heat = 0;
  } else {
    r.rights++;
    if (answer === "right") {
      r.streak++;
      points = 10 * mult(r.streak) + (quick ? QUICK_BONUS : 0);
    }
    r.heat = quick ? Math.min(3, r.heat + 1) : slow ? Math.max(0, r.heat - 1) : r.heat;
  }
  r.top = Math.max(r.top, r.streak);
  r.score += points;
  return { run: r, points, quick, tierUp: mult(r.streak) > was, heatUp: r.heat > run.heat };
}

/** A missed card comes back three cards later, or last when fewer are left. */
export function requeue<T>(queue: T[], pos: number, item: T): T[] {
  const at = Math.min(pos + 4, queue.length);
  return [...queue.slice(0, at), item, ...queue.slice(at)];
}

const bestKey = (deck: string) => `studyBest:${deck}`;
export function readBest(deck: string): number {
  try {
    return Number(localStorage.getItem(bestKey(deck))) || 0;
  } catch {
    return 0;
  }
}
export function saveBest(deck: string, score: number) {
  try {
    localStorage.setItem(bestKey(deck), String(score));
  } catch {
    // Kept for this session only.
  }
}

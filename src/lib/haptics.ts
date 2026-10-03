// Small taps of feedback on the phone. Silent where there's no haptics
// engine (desktop, the simulator), the plugin isn't there, or the student
// turned haptics off in You.
import { impactFeedback, notificationFeedback, selectionFeedback } from "@tauri-apps/plugin-haptics";

function stored(): boolean {
  try {
    return localStorage.getItem("haptics") !== "0";
  } catch {
    return true;
  }
}

export const haptics = { on: stored() };

export function setHaptics(on: boolean) {
  haptics.on = on;
  try {
    localStorage.setItem("haptics", on ? "1" : "0");
  } catch {
    // Remembered for this session only.
  }
}

// Two buzzes closer than this blur into one mushy one; keep the first.
const GAP_MS = 35;
let last = -Infinity;

const send = (fire: () => Promise<unknown>) => () => {
  const now = Date.now();
  if (!haptics.on || Math.abs(now - last) < GAP_MS) return;
  last = now;
  fire().catch(() => {});
};

export const buzz = {
  /** Moving between tabs, days, views or options. */
  select: send(() => selectionFeedback()),
  /** A crisp change: a mark, a colour, a card flipped. */
  tick: send(() => impactFeedback("rigid")),
  /** A long press opening its actions. */
  press: send(() => impactFeedback("medium")),
  /** Pull-to-sync crossing its line, either way. */
  pull: send(() => impactFeedback("soft")),
  /** Letting go of a pull to sync. */
  release: send(() => impactFeedback("light")),
  /** Something landed: a sync, a save, an unlock, a finished session. */
  done: send(() => notificationFeedback("success")),
  /** Not broken, but worth a look: a stalled sync, offline. */
  warn: send(() => notificationFeedback("warning")),
  /** Something went wrong: a failed sync, a wrong answer. */
  fail: send(() => notificationFeedback("error")),
};

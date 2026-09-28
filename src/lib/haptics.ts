// Small taps of feedback on the phone. Silent where there's no haptics
// engine (desktop, the simulator) or the plugin isn't there.
import { impactFeedback, notificationFeedback, selectionFeedback } from "@tauri-apps/plugin-haptics";

const quiet = (p: Promise<unknown>) => p.catch(() => {});

export const buzz = {
  /** Moving between tabs, days or options. */
  select: () => quiet(selectionFeedback()),
  /** A choice that changes something: a mark, a rating, a save. */
  tap: () => quiet(impactFeedback("light")),
  /** Something landed: a sync, a new grade, a finished session. */
  done: () => quiet(notificationFeedback("success")),
  /** Something went wrong: a failed sync, a wrong answer. */
  fail: () => quiet(notificationFeedback("error")),
};

// One switch for everything that draws on its own (#189). While the app is hidden, or LAR's window
// covers the screen, nothing behind it should spend a frame: on a 4 GB phone those frames starved
// the model while it loaded. The CSS half is in app.css, keyed on the same two attributes.

/** Whether something should hold still: the app is hidden, or it sits in the shell behind LAR's window. */
export const holdsStill = (s: { hidden: boolean; covered: boolean; inShell: boolean }) => s.hidden || (s.covered && s.inShell);

const CHANGE = "quietchange";

/** LAR's window opened over the shell, or closed. */
export function setCovered(on: boolean) {
  document.documentElement.toggleAttribute("data-behind", on);
  dispatchEvent(new Event(CHANGE));
}

/**
 * Calls `frame` every animation frame while it can be seen, and stops asking for frames while it
 * can't. `where` is the element that draws, so one inside LAR's own window keeps going.
 * Returns the stop function.
 */
export function animate(frame: (now: number) => void, where?: () => Element | null | undefined): () => void {
  let raf = 0;
  const still = () => holdsStill({ hidden: document.hidden, covered: document.documentElement.hasAttribute("data-behind"), inShell: !!where?.()?.closest(".shell") });
  const tick = (now: number) => {
    raf = 0;
    if (still()) return;
    frame(now);
    raf = requestAnimationFrame(tick);
  };
  const wake = () => {
    if (!raf && !still()) raf = requestAnimationFrame(tick);
  };
  document.addEventListener("visibilitychange", wake);
  addEventListener(CHANGE, wake);
  wake();
  return () => {
    cancelAnimationFrame(raf);
    document.removeEventListener("visibilitychange", wake);
    removeEventListener(CHANGE, wake);
  };
}

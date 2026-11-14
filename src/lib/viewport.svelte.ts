// The visual viewport while a sheet is open. With the keyboard up, iOS
// shrinks it and scrolls the page, so a bottom-pinned sheet would slide its
// top off screen; a frame that follows it keeps the sheet whole.
export function visualViewport() {
  const vv = $state({ h: innerHeight, top: 0 });
  $effect(() => {
    const v = window.visualViewport;
    if (!v) return;
    const sync = () => ((vv.h = v.height), (vv.top = v.offsetTop));
    sync();
    v.addEventListener("resize", sync);
    v.addEventListener("scroll", sync);
    return () => {
      v.removeEventListener("resize", sync);
      v.removeEventListener("scroll", sync);
    };
  });
  return {
    get h() {
      return vv.h;
    },
    get top() {
      return vv.top;
    },
    /** The keyboard is up. */
    get keyboard() {
      return vv.h < innerHeight - 120;
    },
  };
}

/** The keyboard is up when the viewport has lost more than 120 px of the tallest it has been.
 *  The yardstick is the tallest height seen, not `innerHeight`: Android shrinks the whole window. */
export const keyboardUp = (height: number, tallest: number) => height < tallest - 120;

/** A focus hides the bars at once only when a finger just put it there. A focus from code waits
 *  for the viewport to shrink, because iOS raises no keyboard for it (#253). */
export const focusOpens = (sinceTouchMs: number) => sinceTouchMs < 700;

/** Sets `data-keyboard="open"` on the root while the keyboard is up, so the tab bar and the
 *  dock step aside instead of riding up on top of it. */
export function watchKeyboard() {
  const root = document.documentElement;
  const v = window.visualViewport;
  const height = () => v?.height ?? innerHeight;
  const field = (el: EventTarget | null) => !!(el as HTMLElement | null)?.matches?.("input:not([type=checkbox]):not([type=radio]), textarea, select");
  let tallest = height();
  let width = innerWidth;
  let touched = -Infinity;
  const set = (open: boolean) => (open ? (root.dataset.keyboard = "open") : delete root.dataset.keyboard);
  const sync = () => {
    // A turned phone starts over: its old height is no yardstick.
    if (innerWidth !== width) ((width = innerWidth), (tallest = 0));
    tallest = Math.max(tallest, height());
    set(keyboardUp(height(), tallest));
  };
  addEventListener("pointerdown", () => (touched = performance.now()), true);
  addEventListener("focusin", (e) => field(e.target) && focusOpens(performance.now() - touched) && set(true));
  addEventListener("focusout", () => setTimeout(() => !field(document.activeElement) && sync(), 50));
  v?.addEventListener("resize", sync);
}

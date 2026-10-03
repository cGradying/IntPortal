// Long press: hold still for HOLD_MS and it fires; move more than a few
// points first and it's a scroll or a swipe instead. The click that follows
// a long press is swallowed, so the row doesn't also open.
export const HOLD_MS = 450;
const SLOP = 8;

export function pressTimer(onLong: () => void) {
  let timer: ReturnType<typeof setTimeout> | undefined;
  let x = 0;
  let y = 0;
  let fired = false;
  const cancel = () => clearTimeout(timer);
  return {
    down(px: number, py: number) {
      cancel();
      [x, y, fired] = [px, py, false];
      timer = setTimeout(() => {
        fired = true;
        onLong();
      }, HOLD_MS);
    },
    move(px: number, py: number) {
      if (Math.hypot(px - x, py - y) > SLOP) cancel();
    },
    /** Lets go; true when the hold already fired, so the click should be ignored. */
    up(): boolean {
      cancel();
      return fired;
    },
  };
}

/** `use:longpress={fn}` on a row or block. */
export function longpress(node: HTMLElement, onLong: () => void) {
  let handler = onLong;
  const p = pressTimer(() => handler());
  const down = (e: PointerEvent) => p.down(e.clientX, e.clientY);
  const move = (e: PointerEvent) => p.move(e.clientX, e.clientY);
  const up = () => {
    if (p.up()) node.addEventListener("click", (e) => (e.stopImmediatePropagation(), e.preventDefault()), { capture: true, once: true });
  };
  const menu = (e: Event) => e.preventDefault();
  node.addEventListener("pointerdown", down);
  node.addEventListener("pointermove", move);
  node.addEventListener("pointerup", up);
  node.addEventListener("pointercancel", up);
  node.addEventListener("contextmenu", menu);
  return {
    update(next: () => void) {
      handler = next;
    },
    destroy() {
      p.up();
      node.removeEventListener("pointerdown", down);
      node.removeEventListener("pointermove", move);
      node.removeEventListener("pointerup", up);
      node.removeEventListener("pointercancel", up);
      node.removeEventListener("contextmenu", menu);
    },
  };
}

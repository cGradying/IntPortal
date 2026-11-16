// Small motion helpers the screens share (spec 045 C26 to C33). Pure where they can be,
// so the direction rules and the "once per value" rule are testable.
import { cubicOut } from "svelte/easing";

const EASE = "cubic-bezier(0.22, 1, 0.36, 1)";

/** Reduce Motion: every helper here does nothing, or just changes state in place. */
export const still = () => typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;

/** Which side new content arrives from: +1 from the right (going on), -1 from the left. */
export const direction = (from: number, to: number): -1 | 0 | 1 => Math.sign(to - from) as -1 | 0 | 1;

/** True when `sig` is not what was last played, so a one-time moment should play. */
export const isNew = (stored: string | null, sig: string) => stored !== sig;

/** Svelte transition and flip params for a list that gains, loses or reorders rows. */
export const flow = () => ({ duration: still() ? 0 : 220, easing: cubicOut });

/** `use:slideOnChange={index}`: when the index changes the element slides in from that side. Never on first paint. */
export function slideOnChange(el: HTMLElement, index: number) {
  let last = index;
  return {
    update(next: number) {
      const dir = direction(last, next);
      last = next;
      if (!dir || still()) return;
      el.animate([{ translate: `${dir * 28}px 0`, opacity: 0 }, { translate: "0 0", opacity: 1 }], { duration: 260, easing: EASE });
    },
  };
}

/** `use:playOnce={{ key, sig, play }}`: runs `play(el)` when `sig` differs from what this device last saw under `key`. */
export function playOnce(el: HTMLElement | SVGElement, p: { key: string; sig: string; play: (el: Element) => void }) {
  const run = (q: typeof p) => {
    let seen: string | null = null;
    try {
      seen = localStorage.getItem(q.key);
      localStorage.setItem(q.key, q.sig);
    } catch {
      // Storage off: it plays each time. Harmless.
    }
    if (isNew(seen, q.sig) && !still()) q.play(el);
  };
  run(p);
  return { update: run };
}

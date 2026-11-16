// The motion vocabulary (spec 045 C30-C36): a few named moves built on the tokens in app.css.
// Pages, sheets, scrims and rises are Svelte transitions; `dismiss` is a drag-down action;
// `rubber` is the pull curve. Every one reads Reduce Motion live and falls back to a fade.
import type { TransitionConfig } from "svelte/transition";

/** Which way the page slides: toward a later tab (1) or an earlier one (-1). */
export type Dir = 1 | -1;
export const TAB_ORDER = ["today", "schedule", "grades", "study", "you"] as const;

export const tabDir = (from: string, to: string, order: readonly string[] = TAB_ORDER): Dir => (order.indexOf(to) >= order.indexOf(from) ? 1 : -1);

/** "0.32s" or "120ms" to milliseconds; the fallback when a token is missing. */
export function ms(token: string, fallback: number): number {
  const m = /^\s*([0-9.]+)(ms|s)\s*$/.exec(token);
  return m ? parseFloat(m[1]) * (m[2] === "s" ? 1000 : 1) : fallback;
}

/** A CSS `cubic-bezier(a, b, c, d)` as a function of progress, so Svelte can sample it. */
export function bezier(css: string, fallback: (t: number) => number = (t) => t): (t: number) => number {
  const m = /cubic-bezier\(\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*,\s*([-0-9.]+)\s*\)/.exec(css);
  if (!m) return fallback;
  const [x1, y1, x2, y2] = m.slice(1).map(Number);
  const at = (a: number, b: number, s: number) => 3 * a * (1 - s) ** 2 * s + 3 * b * (1 - s) * s * s + s ** 3;
  return (t) => {
    if (t <= 0 || t >= 1) return t;
    let lo = 0;
    let hi = 1;
    for (let i = 0; i < 24; i++) {
      const mid = (lo + hi) / 2;
      if (at(x1, x2, mid) < t) lo = mid;
      else hi = mid;
    }
    return at(y1, y2, (lo + hi) / 2);
  };
}

type Tokens = { quick: number; move: number; flow: number; exit: number; shift: number; easeCss: string; ease: (t: number) => number; easeIn: (t: number) => number; easeSheet: (t: number) => number };
let read: Tokens | undefined;
/** The tokens from :root, read once. Outside a browser (tests) the defaults in app.css apply. */
export function tokens(): Tokens {
  if (read) return read;
  const v = (name: string) => (typeof document === "undefined" ? "" : getComputedStyle(document.documentElement).getPropertyValue(name));
  read = {
    quick: ms(v("--t-quick"), 160),
    move: ms(v("--t-move"), 320),
    flow: ms(v("--t-flow"), 360),
    exit: ms(v("--t-exit"), 200),
    shift: parseFloat(v("--shift")) || 12,
    easeCss: v("--ease").trim() || "cubic-bezier(0.22, 1, 0.36, 1)",
    ease: bezier(v("--ease")),
    easeIn: bezier(v("--ease-in")),
    easeSheet: bezier(v("--ease-sheet")),
  };
  return read;
}

export const reduced = () => typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches;

/** What a move is: how far it travels, how long it takes. Reduce Motion keeps the fade and drops the travel. */
export type Move = { x: number; y: number; ms: number };
export const calm = (m: Move, quick: number, off: boolean): Move => (off ? { x: 0, y: 0, ms: Math.min(m.ms, quick) } : m);

/** A page changing tab: it leaves toward -dir and the next one arrives from +dir. */
export function pageMove(dir: Dir, enter: boolean, off: boolean, t = tokens()): Move {
  return calm({ x: (enter ? dir : -dir) * t.shift, y: 0, ms: enter ? t.move : t.exit }, t.quick, off);
}

/** Takes a leaving element out of the flow where it stands, so what replaces it never waits for it. */
export function pin(node: HTMLElement) {
  const r = node.getBoundingClientRect();
  const h = Math.max(0, Math.min(r.height, innerHeight - r.top));
  Object.assign(node.style, { position: "fixed", top: `${r.top}px`, left: `${r.left}px`, width: `${r.width}px`, height: `${h}px`, margin: "0", overflow: "hidden", pointerEvents: "none" });
}

/** The third argument Svelte gives a `transition:` function: which way it is playing. */
type Ctx = { direction: "in" | "out" | "both" };
const isIn = (c?: Ctx) => c?.direction !== "out"; // `transition:` reports "both", so the sheets use `in:` and `out:`

const cfg = (m: Move, easing: (t: number) => number, fade = true): TransitionConfig => ({
  duration: m.ms,
  easing,
  css: (t, u) => `translate: ${m.x * u}px ${m.y * u}px;${fade ? ` opacity: ${t};` : ""}`,
});

/** Shared axis, for a tab change (use with `in:` and `out:`). The leaving page is pinned in place. */
export function shared(node: HTMLElement, o: { dir: Dir; enter: boolean; off?: boolean }): TransitionConfig {
  const t = tokens();
  if (!o.enter) pin(node);
  // Both legs decelerate: the old page is mostly gone by the time the new one is clearly there.
  return { ...cfg(pageMove(o.dir, o.enter, o.off ?? reduced(), t), t.ease), delay: o.enter ? 40 : 0 };
}

/** A bottom sheet: slides up from below its own height with a hair of overshoot, back down faster. */
export function sheet(node: HTMLElement, o: { off?: boolean; skip?: boolean } = {}, c?: Ctx): TransitionConfig {
  const t = tokens();
  const enter = isIn(c);
  // `gone`: dragged off already; `skip`: it grows from somewhere else instead.
  if (o.skip || node.dataset.gone) return { duration: 0 };
  const off = o.off ?? reduced();
  const y = innerHeight - node.getBoundingClientRect().top;
  const m = calm({ x: 0, y, ms: enter ? t.flow : t.exit }, t.quick, off);
  return { ...cfg(m, enter ? t.easeSheet : t.easeIn, off), duration: m.ms };
}

/** The dimmer behind a sheet. */
export function scrim(_: HTMLElement, o: { skip?: boolean } = {}, c?: Ctx): TransitionConfig {
  const t = tokens();
  return { duration: o.skip ? 0 : isIn(c) ? t.move : t.exit, easing: t.ease, css: (a) => `opacity: ${a}` };
}

/** A full-screen page over the shell (the editor, the theme maker): lifts in, drops out. */
export function overlay(_: HTMLElement, o: { off?: boolean } = {}, c?: Ctx): TransitionConfig {
  const t = tokens();
  const enter = isIn(c);
  const m = calm({ x: 0, y: enter ? 24 : 16, ms: enter ? t.flow : t.exit }, t.quick, o.off ?? reduced());
  return cfg(m, enter ? t.ease : t.easeIn);
}

/** Content that arrives once: fades up a little. */
export function rise(_: HTMLElement, o: { delay?: number; y?: number } = {}): TransitionConfig {
  const t = tokens();
  const m = calm({ x: 0, y: o.y ?? 8, ms: t.move }, t.quick, reduced());
  return { ...cfg(m, t.ease), delay: o.delay ?? 0 };
}

/** Leaves in place and fades, so a skeleton and the content that replaces it cross over without a jump. */
export function leave(node: HTMLElement): TransitionConfig {
  const t = tokens();
  pin(node);
  return { duration: t.quick, easing: t.easeIn, css: (a) => `opacity: ${a}` };
}

/** Pull resistance: follows the finger at first, then gives less and less, never past `max`. */
export const rubber = (dy: number, max: number, c = 1): number => (dy <= 0 ? 0 : (1 - 1 / ((dy * c) / max + 1)) * max);

/** Past `at` px or `fast` px/ms: let go and the sheet goes. */
export const dismissed = (dy: number, v: number, at = 80, fast = 0.5) => dy > at || (dy > 12 && v > fast);

/**
 * `use:dismiss={() => close()}` on a fixed or absolute bottom sheet: adds a grab bar and lets the
 * sheet be dragged down. It follows the finger, goes with the velocity, or springs back. The
 * callback runs once it is off the screen, and the sheet's own exit is skipped.
 */
export function dismiss(node: HTMLElement, done: () => void) {
  let finish = done;
  const grip = document.createElement("i");
  grip.className = "grip";
  grip.setAttribute("aria-hidden", "true");
  node.prepend(grip);
  let y0 = 0;
  let dy = 0;
  let last = { y: 0, t: 0 };
  let v = 0;
  let live = false;
  const down = (e: PointerEvent) => {
    live = true;
    y0 = e.clientY;
    last = { y: e.clientY, t: e.timeStamp };
    v = dy = 0;
    grip.setPointerCapture(e.pointerId);
  };
  const move = (e: PointerEvent) => {
    if (!live) return;
    const raw = e.clientY - y0;
    // Down moves the sheet 1:1; up only gives a little.
    dy = raw >= 0 ? raw : -rubber(-raw, 24);
    const dt = e.timeStamp - last.t;
    if (dt > 0) v = (e.clientY - last.y) / dt;
    last = { y: e.clientY, t: e.timeStamp };
    node.style.translate = `0 ${dy}px`;
  };
  const up = () => {
    if (!live) return;
    live = false;
    const t = tokens();
    if (dismissed(dy, v) && reduced()) return void ((node.dataset.gone = "1"), finish());
    const go = dismissed(dy, v);
    const rest = go ? innerHeight - node.getBoundingClientRect().top + 24 : 0;
    const a = node.animate({ translate: [`0 ${dy}px`, `0 ${rest}px`] }, { duration: go ? t.exit : t.move, easing: go ? "cubic-bezier(0.5, 0, 0.75, 0)" : "cubic-bezier(0.32, 1.2, 0.5, 1)", fill: "forwards" });
    const end = () => {
      if (dismissed(dy, v)) {
        node.dataset.gone = "1";
        finish();
      } else {
        node.style.translate = "";
        a.cancel();
      }
    };
    a.finished.then(end, end);
  };
  grip.addEventListener("pointerdown", down);
  grip.addEventListener("pointermove", move);
  grip.addEventListener("pointerup", up);
  grip.addEventListener("pointercancel", up);
  return {
    update(next: () => void) {
      finish = next;
    },
    destroy() {
      grip.remove();
    },
  };
}

/** Which side new content arrives from: +1 from the right (going on), -1 from the left. */
export const direction = (from: number, to: number): -1 | 0 | 1 => Math.sign(to - from) as -1 | 0 | 1;

/** True when `sig` is not what was last played, so a one-time moment should play. */
export const isNew = (stored: string | null, sig: string) => stored !== sig;

/** Svelte transition and flip params for a list that gains, loses or reorders rows. */
export const flow = () => ({ duration: reduced() ? 0 : tokens().exit, easing: tokens().ease });

/** `use:slideOnChange={index}`: when the index changes the element slides in from that side. Never on first paint. */
export function slideOnChange(el: HTMLElement, index: number) {
  let last = index;
  return {
    update(next: number) {
      const dir = direction(last, next);
      last = next;
      if (!dir || reduced()) return;
      const t = tokens();
      el.animate([{ translate: `${dir * t.shift * 2}px 0`, opacity: 0 }, { translate: "0 0", opacity: 1 }], { duration: t.move, easing: t.easeCss });
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
    if (isNew(seen, q.sig) && !reduced()) q.play(el);
  };
  run(p);
  return { update: run };
}

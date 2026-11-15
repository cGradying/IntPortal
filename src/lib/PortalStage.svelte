<script lang="ts">
  // The landing's stage: the tile portal carousel (spec 010, drawn by the
  // Rust scene through tiles.ts) in whatever room the form leaves, so it fits
  // every phone's shape. Swipe, or use the arrows and dots, to choose a
  // portal, or tap the school's name for the hub (PortalHub) with every
  // school; each has its own frame, motif and colours, and they ride an
  // orbit that turns between them. LAR flies round it (LarFlight), never
  // through a portal's blocks.
  import { onMount, untrack } from "svelte";
  import LarFlight, { type Context } from "./lar/LarFlight.svelte";
  import PortalHub from "./PortalHub.svelte";
  import PortalPeek from "./PortalPeek.svelte";
  import MiniPortal from "./MiniPortal.svelte";
  import { api, type PortalStatus } from "./api";
  import { statusChip } from "./portals";
  import { PAGE_MS, isTap, nextPage } from "./peek";
  import type { Portal } from "./api";
  import { buzz } from "./haptics";
  import { release, settle, step, type Motion } from "./carousel";
  import type { Standing } from "./dive";
  import { TICK, fpsFor, loadTiles, type Stage } from "./tiles";

  let {
    portals,
    index,
    onselect,
    locked = false,
    stage,
    returning,
    still = false,
    showLar,
    leaving = false,
    ctx,
  }: {
    portals: Portal[];
    /** The selected portal. */
    index: number;
    onselect: (i: number) => void;
    /** Signed in or busy: the carousel stays on the selected portal. */
    locked?: boolean;
    stage: Stage;
    returning: boolean;
    /** A field has focus: hold the layout still (C17). */
    still?: boolean;
    showLar: boolean;
    leaving?: boolean;
    /** What the student is doing, for LAR. */
    ctx: Context;
  } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  /** The selected portal and LAR, in device px of the screen, for the dive to start from. */
  export function leaveInfo(): Standing | null {
    if (!tiles || !canvas) return null;
    const dpr = Math.min(devicePixelRatio, 3);
    const box = canvas.getBoundingClientRect();
    const [x, y] = tiles.rect(motion.pos);
    const lar = flight?.where();
    return { ox: x + Math.round(box.left * dpr), oy: y + Math.round(box.top * dpr), ...tiles.metrics(), lar: lar ? { x: lar.x * dpr, y: lar.y * dpr } : null };
  }

  let canvas: HTMLCanvasElement;
  let flight = $state<LarFlight>();
  let tiles: Awaited<ReturnType<typeof loadTiles>> | null = null;
  let start = performance.now();
  let prev = 0;
  let last = -1;
  let openedAt: number | null = untrack(() => returning) ? 0 : null;
  let raf = 0;
  // The carousel: where it is, where it is heading, and an active drag.
  let motion: Motion = { pos: untrack(() => index), vel: 0 };
  let target = untrack(() => index);
  let drag: { x: number; pos: number; t: number; lastX: number; lastT: number } | null = null;
  let moving = $state(false);
  let hub = $state(false);
  /** Where the plaque was when it opened the wall, so the wall dithers out of it. */
  let hubFrom = $state<DOMRect>();

  // The peek through the portal (C36–C37): which page is open, and where the portal was when it opened.
  let peek = $state<number | null>(null);
  let peekAt = $state({ box: { x: 0, y: 0, w: 0, h: 0 }, room: { w: 0, h: 0 }, inset: 0 });
  let press: { x: number; y: number; t: number } | null = null;
  let peeked = $state(false);
  try {
    peeked = localStorage.getItem("peeked") === "1";
  } catch {
    // Then the hint shows until the first peek this launch.
  }

  // Whether each portal is answering (C40): asked when it comes to the front, and again on a tap.
  let statuses = $state<Record<string, PortalStatus | null>>({});
  let asked: Record<string, number> = {};
  function check(id: string, wait = 0) {
    if (performance.now() - (asked[id] ?? -Infinity) < wait) return;
    asked[id] = performance.now();
    statuses[id] = null;
    api
      .portalStatus(id)
      .catch(() => ({ up: false, host: null }))
      .then((st) => {
        statuses[id] = st;
      });
  }
  $effect(() => {
    const p = portals[index];
    // A minute is fresh enough when a portal comes round again.
    if (p?.status === "ready") untrack(() => check(p.id, 60_000));
  });

  const now = () => (performance.now() - start) / 1000;
  const current = $derived(portals[index] ?? portals[0]);
  const chip = $derived(statusChip(current, statuses[current.id] ?? null));
  const larPortal = $derived({ id: current.id, name: current.name, school: current.school, ready: current.status === "ready", ramp: current.theme.ramp, accent: current.theme.accent });

  // The selected portal's frame in CSS px, and the neighbours peeking in, for
  // LAR to steer round.
  function portalRects() {
    if (!tiles || !canvas) return null;
    const t = tiles;
    const dpr = Math.min(devicePixelRatio, 3);
    const css = (p: number) => {
      const [x, y, w, h] = t.rect(motion.pos, p);
      return { x: x / dpr, y: y / dpr, w: w / dpr, h: h / dpr };
    };
    const sel = Math.round(motion.pos);
    // A neighbour round the back of the orbit has no box.
    return { portal: css(sel), others: [sel - 1, sel + 1].filter((p) => p >= 0 && p < portals.length).map(css).filter((r) => r.w > 0) };
  }

  function draw(t: number) {
    const ctx = canvas.getContext("2d");
    if (!tiles || !ctx) return;
    // A held finger that has stopped moving is not still turning the orbit.
    const vel = drag && performance.now() / 1000 - drag.lastT > 0.08 ? 0 : motion.vel;
    const ev = tiles.draw(ctx, { t, prev, stage, openedAt: openedAt ?? 0, returning, reduce, pos: motion.pos, vel });
    if (ev & TICK) buzz.tick();
    prev = t;
  }

  let lastStep = 0;
  function loop() {
    raf = requestAnimationFrame(loop);
    const t = now();
    if (!drag && !settle(motion, target)) {
      motion = reduce ? { pos: target, vel: 0 } : step(motion, target, Math.min(0.05, t - lastStep));
      if (settle(motion, target)) motion = { pos: target, vel: 0 };
    }
    lastStep = t;
    moving = !!drag || !settle(motion, target);
    if (t - last < 1 / fpsFor(t, stage, openedAt, moving) - 0.004) return;
    last = t;
    draw(t);
  }

  function fit() {
    if (still) return;
    // Layout size, not the on-screen box: the intro's lift scales the stage up, and a buffer
    // sized to that would put LAR's frame box and the page's dots off by the same factor.
    const [width, height] = [canvas.clientWidth, canvas.clientHeight];
    const dpr = Math.min(devicePixelRatio, 3);
    canvas.width = Math.max(1, Math.round(width * dpr));
    canvas.height = Math.max(1, Math.round(height * dpr));
    tiles?.resize(canvas.width, canvas.height);
    ground();
    draw(now());
  }

  /** The page's grid of dots takes its pitch and place from the scene, so dots and tiles share centres (C3). */
  function ground() {
    const page = canvas?.closest<HTMLElement>(".landing");
    if (!tiles || !page) return;
    const dpr = Math.min(devicePixelRatio, 3);
    const g = tiles.grid(Math.round(motion.pos));
    // Where the canvas lies on the page, without the lift's transform.
    let [x, y] = [0, 0];
    for (let el: HTMLElement | null = canvas; el && el !== page; el = el.offsetParent as HTMLElement | null) {
      x += el.offsetLeft;
      y += el.offsetTop;
    }
    page.style.setProperty("--grid-x", `${x + g.x / dpr}px`);
    page.style.setProperty("--grid-y", `${y + g.y / dpr}px`);
    page.style.setProperty("--grid-pitch", `${g.pitch / dpr}px`);
    page.style.setProperty("--grid-dot", `${g.dot / dpr}px`);
  }

  // Rendering stops while the app is in the background (C23).
  function visibility() {
    cancelAnimationFrame(raf);
    if (!document.hidden && !reduce) loop();
  }

  onMount(() => {
    // Resizing the canvas inside the observer's callback can trip the
    // browser's "ResizeObserver loop" error, so it waits for the next frame.
    let pending = 0;
    const ro = new ResizeObserver(() => {
      cancelAnimationFrame(pending);
      pending = requestAnimationFrame(fit);
    });
    loadTiles()
      .then((t) => {
        tiles = t;
        tiles.portals(portals);
        start = performance.now();
        ro.observe(canvas);
        fit();
        visibility();
      })
      // No portal, but the form still works (spec 010 Errors).
      .catch(() => {});
    document.addEventListener("visibilitychange", visibility);
    return () => {
      ro.disconnect();
      clearTimeout(opening);
      cancelAnimationFrame(pending);
      cancelAnimationFrame(raf);
      document.removeEventListener("visibilitychange", visibility);
    };
  });

  // The core's list replaces the fallback once it arrives.
  $effect(() => {
    const list = portals;
    tiles?.portals(list);
    if (reduce) draw(now());
  });

  // Typing done: catch up on any resize held while the field had focus.
  $effect(() => {
    if (!still) fit();
  });

  $effect(() => {
    if (stage === "open" && openedAt === null) openedAt = now();
    if (stage !== "open") openedAt = null;
  });

  // Chosen from outside (or by the arrows and dots): glide there.
  $effect(() => {
    const i = index;
    untrack(() => {
      target = i;
      if (reduce) {
        motion = { pos: i, vel: 0 };
        draw(now());
      }
    });
  });

  function go(i: number) {
    if (locked) return;
    const j = Math.max(0, Math.min(portals.length - 1, i));
    if (j !== index) buzz.select();
    // A pick from the hub may be far along the orbit: warp to three portals
    // short of it and let the spring turn the rest, streaking the stars.
    if (Math.abs(j - motion.pos) > 3 && !reduce) {
      const d = Math.sign(j - motion.pos);
      motion = { pos: j - 3 * d, vel: 4 * d };
    }
    target = j;
    onselect(j);
  }

  // Drag to swipe: the scene's spacing between portals, in CSS px, so the
  // portal under the finger moves with it.
  const width = () => (tiles?.gap() ?? 0) / Math.min(devicePixelRatio, 3) || canvas.getBoundingClientRect().width * 0.6;
  function down(e: PointerEvent) {
    press = { x: e.clientX, y: e.clientY, t: performance.now() };
    if (locked || portals.length < 2) return;
    const t = performance.now() / 1000;
    drag = { x: e.clientX, pos: motion.pos, t, lastX: e.clientX, lastT: t };
    motion = { pos: motion.pos, vel: 0 };
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
  }
  function move(e: PointerEvent) {
    if (!drag) return;
    const t = performance.now() / 1000;
    const raw = drag.pos - (e.clientX - drag.x) / width();
    // Past the ends it resists, like a rubber band.
    const max = portals.length - 1;
    const pos = raw < 0 ? raw * 0.3 : raw > max ? max + (raw - max) * 0.3 : raw;
    const vel = (-(e.clientX - drag.lastX) / width()) / Math.max(1 / 240, t - drag.lastT);
    motion = { pos, vel: motion.vel * 0.6 + vel * 0.4 };
    drag.lastX = e.clientX;
    drag.lastT = t;
    if (reduce) draw(now());
  }
  function up(e: PointerEvent) {
    const p = press;
    press = null;
    const tap = !!p && isTap(e.clientX - p.x, e.clientY - p.y, performance.now() - p.t);
    if (drag) {
      drag = null;
      go(release(motion.pos, tap ? 0 : motion.vel, portals.length));
    }
    if (tap) touch(e);
  }
  function cancel() {
    press = null;
    if (!drag) return;
    drag = null;
    go(release(motion.pos, motion.vel, portals.length));
  }

  // A tap on the portal rings its tiles from the finger and opens, or turns, the peek;
  // a tap on the void round it closes the peek (C36).
  function touch(e: PointerEvent) {
    if (!tiles || !canvas || leaving) return;
    const dpr = Math.min(devicePixelRatio, 3);
    const cb = canvas.getBoundingClientRect();
    const px = (e.clientX - cb.left) * dpr;
    const py = (e.clientY - cb.top) * dpr;
    const [x, y, w, h] = tiles.rect(motion.pos);
    if (px < x || px > x + w || py < y || py > y + h) {
      peek = null;
      return;
    }
    const { pitch } = tiles.metrics();
    tiles.poke((px - x) / pitch, (py - y) / pitch, now());
    buzz.select();
    if (peek !== null) return turn();
    // The ring runs through the frame first, then the view opens out of the mouth.
    clearTimeout(opening);
    opening = setTimeout(() => {
      if (leaving || still) return;
      peekAt = { box: { x: x / dpr, y: y / dpr, w: w / dpr, h: h / dpr }, room: { w: cb.width, h: cb.height }, inset: (2 * pitch) / dpr };
      peek = 0;
    }, reduce ? 0 : RING_MS);
  }
  /** The Peek button: the same ring and view as a tap in the middle of the mouth. */
  function peekFromButton() {
    if (!tiles || !canvas || leaving) return;
    const dpr = Math.min(devicePixelRatio, 3);
    const cb = canvas.getBoundingClientRect();
    const [x, y, w, h] = tiles.rect(motion.pos);
    const { pitch } = tiles.metrics();
    tiles.poke(w / pitch / 2, h / pitch / 2, now());
    buzz.select();
    clearTimeout(opening);
    opening = setTimeout(() => {
      if (leaving || still) return;
      peekAt = { box: { x: x / dpr, y: y / dpr, w: w / dpr, h: h / dpr }, room: { w: cb.width, h: cb.height }, inset: (2 * pitch) / dpr };
      peek = 0;
    }, reduce ? 0 : RING_MS);
  }
  /** How long the ring runs before the view opens. */
  const RING_MS = 380;
  let opening: ReturnType<typeof setTimeout> | undefined;
  function turn() {
    peek = peek === null ? null : nextPage(peek);
  }

  // Each page: LAR names it, and it turns on its own after a while; the last one closes.
  $effect(() => {
    const p = peek;
    if (p === null) return;
    untrack(() => {
      if (!peeked) {
        peeked = true;
        try {
          localStorage.setItem("peeked", "1");
        } catch {
          // Only this launch remembers it.
        }
      }
    });
    const id = setTimeout(turn, PAGE_MS);
    return () => clearTimeout(id);
  });

  // A field, a swipe to another portal or Step through closes the peek.
  $effect(() => {
    if (still || leaving) peek = null;
  });
  $effect(() => {
    void index;
    untrack(() => (peek = null));
  });

</script>

<div class="stage" class:leaving>
  <canvas
    bind:this={canvas}
    aria-hidden="true"
    onpointerdown={down}
    onpointermove={move}
    onpointerup={up}
    onpointercancel={cancel}
  ></canvas>
  <p class="sr">{current.name} portal, {current.status === "ready" ? "open" : "opens soon"}.</p>
  {#if peek !== null}
    <PortalPeek box={peekAt.box} room={peekAt.room} inset={peekAt.inset} page={peek} accent={current.theme.accent} onnext={turn} />
  {/if}
  <div class="sky"><LarFlight bind:this={flight} getRects={portalRects} show={showLar} {ctx} portal={larPortal} /></div>
  <!-- One quiet row of things to do before signing in: peek inside (C37) and whether the portal answers (C40).
       Once the student has peeked, the peek steps back and stays for a screen reader. -->
  <div class="quick" class:off={locked}>
    {#if showLar && !locked && current.status === "ready" && peek === null}
      <button class="peek" class:known={peeked} onclick={peekFromButton}>
        <svg viewBox="0 0 7 5" aria-hidden="true" shape-rendering="crispEdges"><path d="M2 0h3v1H2zM1 1h1v1H1zM5 1h1v1H5zM0 2h1v1H0zM3 2h1v1H3zM6 2h1v1H6zM1 3h1v1H1zM5 3h1v1H5zM2 4h3v1H2z" fill="currentColor" /></svg>
        Peek inside
      </button>
    {/if}
    <button class="chip {chip.tone}" aria-live="polite" aria-label="{chip.text}. Check again" disabled={current.status !== "ready" || chip.tone === "wait"} onclick={() => check(current.id, 3000)}>
      <i aria-hidden="true"></i>{chip.text}
    </button>
  </div>
  <!-- The plaque names the school and opens the wall (C13a). -->
  {#key current.id}
    <button class="plate" class:off={locked} aria-label="{current.name}, {current.school}. Choose your school" disabled={locked || portals.length < 2} onclick={(e) => ((hubFrom = e.currentTarget.getBoundingClientRect()), (hub = true))}>
      <span class="mini"><MiniPortal portal={current} /></span>
      <span class="names">
        <b style:color={current.theme.accent}>{current.name}</b>
        <span>{current.school}</span>
      </span>
      {#if portals.length > 1 && !locked}
        <svg class="opens" viewBox="0 0 7 4" aria-hidden="true" shape-rendering="crispEdges"><path d="M0 0h1v1H0zM1 1h1v1H1zM2 2h1v1H2zM3 3h1v1H3zM4 2h1v1H4zM5 1h1v1H5zM6 0h1v1H6z" fill="currentColor" /></svg>
      {/if}
    </button>
  {/key}
</div>
{#if hub}
  <PortalHub {portals} {index} from={hubFrom} onpick={go} onclose={() => (hub = false)} />
{/if}

<style>
  .stage {
    position: relative;
    display: grid;
    grid-template-rows: minmax(0, 1fr) auto auto;
    justify-items: center;
    min-height: 0;
  }
  /* Spoken, not shown: the canvas itself is hidden from VoiceOver. */
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    margin: 0;
    overflow: hidden;
    clip-path: inset(50%);
  }
  /* LAR's sky shares the portal's cell, over it. */
  canvas,
  .sky {
    grid-area: 1 / 1;
  }
  .sky {
    position: relative;
    width: 100%;
    height: 100%;
    min-height: 0;
    pointer-events: none;
    transition: opacity var(--t-flow) var(--ease);
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
    min-height: 0;
    touch-action: pan-y;
  }
  /* Step through: the dive (Dive.svelte) draws LAR from here on. */
  .leaving .sky {
    opacity: 0;
    transition: none;
  }
  .leaving .quick,
  .leaving .plate {
    opacity: 0;
  }
  .quick {
    position: relative;
    display: flex;
    justify-content: space-between;
    gap: 8px;
    width: 100%;
    margin-top: 6px;
    transition: opacity var(--t-move) var(--ease);
  }
  .off {
    opacity: 0.5;
  }
  .plate,
  .peek,
  .chip {
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(20 12 22 / 0.86);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
    font-family: var(--font-ui);
  }
  .peek {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    padding: 0 14px 0 12px;
    color: var(--parch);
    font: 600 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    animation: fade var(--t-hero) var(--ease) 1.2s both;
  }
  .peek svg {
    width: 14px;
    height: 10px;
    color: var(--gold);
  }
  /* Peeked before: out of sight, still there for a screen reader and a keyboard. */
  .peek.known:not(:focus-visible) {
    position: absolute;
    width: 1px;
    height: 1px;
    min-height: 0;
    padding: 0;
    overflow: hidden;
    clip-path: inset(50%);
  }
  .plate {
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: 10px;
    width: 100%;
    min-height: 52px;
    margin-top: 8px;
    padding: 6px 14px 6px 10px;
    color: rgb(244 236 216 / 0.74);
    text-align: left;
    transition: opacity var(--t-move) var(--ease);
    animation: fade var(--t-flow) var(--ease);
  }
  .plate:active,
  .peek:active,
  .chip:active {
    background: rgb(28 18 32 / 0.94);
  }
  .plate:disabled {
    opacity: 1;
  }
  .plate.off {
    opacity: 0.5;
  }
  .mini {
    width: 20px;
    height: 28px;
  }
  .names {
    display: grid;
    min-width: 0;
  }
  .names b {
    font: 600 var(--text-sub) / 1.2 var(--font-ui);
  }
  .names span {
    font-size: var(--text-label);
    line-height: 1.3;
    text-wrap: balance;
  }
  .opens {
    width: 14px;
    height: 8px;
    color: rgb(244 236 216 / 0.6);
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 7px;
    margin-left: auto;
    padding: 0 14px;
    color: rgb(244 236 216 / 0.82);
    font-size: var(--text-caption);
    font-weight: 600;
    white-space: nowrap;
  }
  .chip:disabled {
    opacity: 1;
  }
  .chip i {
    width: 6px;
    height: 6px;
    background: rgb(244 236 216 / 0.5);
  }
  .chip.up i {
    background: var(--good);
    animation: live 2.4s steps(2) infinite;
  }
  .chip.down {
    color: var(--rose);
  }
  .chip.down i {
    background: var(--rose);
  }
  @keyframes live {
    50% {
      opacity: 0.35;
    }
  }
  @keyframes fade {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  /* A short phone: the plaque keeps to one line, and the portal gets the room. */
  @media (max-height: 700px) {
    .quick {
      margin-top: 2px;
    }
    .plate {
      min-height: 44px;
      margin-top: 6px;
    }
    .names {
      display: flex;
      align-items: baseline;
      gap: 8px;
    }
    .names span {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .sky,
    .quick,
    .plate {
      transition: none;
    }
    .plate,
    .peek,
    .chip i {
      animation: none;
    }
  }
</style>

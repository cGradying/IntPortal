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
  import type { Portal } from "./api";
  import { buzz } from "./haptics";
  import { release, settle, step, type Motion } from "./carousel";
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

  let canvas: HTMLCanvasElement;
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

  const now = () => (performance.now() - start) / 1000;
  const current = $derived(portals[index] ?? portals[0]);
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
    const { width, height } = canvas.getBoundingClientRect();
    const dpr = Math.min(devicePixelRatio, 3);
    canvas.width = Math.max(1, Math.round(width * dpr));
    canvas.height = Math.max(1, Math.round(height * dpr));
    tiles?.resize(canvas.width, canvas.height);
    draw(now());
  }

  // Rendering stops while the app is in the background (C23).
  function visibility() {
    cancelAnimationFrame(raf);
    if (!document.hidden && !reduce) loop();
  }

  onMount(() => {
    const ro = new ResizeObserver(fit);
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
  function up() {
    if (!drag) return;
    drag = null;
    go(release(motion.pos, motion.vel, portals.length));
  }

</script>

<div class="stage" class:leaving>
  <canvas
    bind:this={canvas}
    aria-hidden="true"
    onpointerdown={down}
    onpointermove={move}
    onpointerup={up}
    onpointercancel={up}
  ></canvas>
  <div class="sky"><LarFlight getRects={portalRects} show={showLar} {ctx} portal={larPortal} /></div>
  {#if portals.length > 1}
    <div class="picker" class:off={locked} role="group" aria-label="Choose a portal">
      <button class="arrow" aria-label="Previous portal" disabled={locked || index === 0} onclick={() => go(index - 1)}>‹</button>
      {#key current.id}
        <button class="caption" aria-live="polite" aria-label="{current.name}, {current.school}. Choose your school" disabled={locked} onclick={() => (hub = true)}>
          <b style:color={current.theme.accent}>{current.name}</b>
          <span>{current.school}</span>
          <small>{current.status === "ready" ? `${index + 1} of ${portals.length}` : "Opens soon"}</small>
        </button>
      {/key}
      <button class="arrow" aria-label="Next portal" disabled={locked || index === portals.length - 1} onclick={() => go(index + 1)}>›</button>
    </div>
  {/if}
</div>
{#if hub}
  <PortalHub {portals} {index} onpick={go} onclose={() => (hub = false)} />
{/if}

<style>
  .stage {
    position: relative;
    display: grid;
    grid-template-rows: minmax(0, 1fr) auto;
    justify-items: center;
    min-height: 0;
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
    transition: opacity 0.4s var(--ease);
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
    min-height: 0;
    touch-action: pan-y;
    transition:
      transform 1.1s cubic-bezier(0.55, 0, 1, 0.45),
      opacity 1.1s ease-in;
  }
  /* Step through: dive into the portal. The morph into Today is spec 010 C20. */
  .leaving canvas {
    transform: scale(2.6);
    opacity: 0;
  }
  .leaving .sky,
  .leaving .picker {
    opacity: 0;
  }
  .picker {
    display: flex;
    align-items: center;
    gap: 6px;
    margin-top: 4px;
    transition: opacity 0.3s var(--ease);
  }
  .picker.off {
    opacity: 0.35;
  }
  .arrow {
    width: 36px;
    height: 36px;
    border: 0;
    background: transparent;
    -webkit-appearance: none;
    appearance: none;
    color: rgb(244 236 216 / 0.7);
    font: 600 22px/1 var(--font-display);
  }
  .arrow:disabled {
    opacity: 0.25;
  }
  /* The school's name opens the hub: a quiet pill, the short name in the portal's accent. */
  .caption {
    flex: 0 1 auto;
    min-width: 0;
    max-width: min(76vw, 340px);
    min-height: 44px;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: 8px;
    padding: 0 12px 0 14px;
    border: 0;
    border-radius: 22px;
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
    color: rgb(244 236 216 / 0.6);
    font: 400 min(0.765rem, 23px) var(--font-ui);
    text-align: left;
    animation: fade 0.35s var(--ease);
  }
  .caption:active {
    background: rgb(244 236 216 / 0.1);
  }
  .caption:disabled {
    opacity: 1;
  }
  .caption b {
    font: 700 min(0.824rem, 25px) var(--font-display);
  }
  .caption span {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .caption small {
    font: 500 min(0.647rem, 20px) var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(244 236 216 / 0.75);
    white-space: nowrap;
  }
  /* A chevron says it opens. */
  .caption small::after {
    content: "";
    display: inline-block;
    width: 5px;
    height: 5px;
    margin-left: 6px;
    border-right: 1.5px solid currentColor;
    border-bottom: 1.5px solid currentColor;
    transform: translateY(-2px) rotate(45deg);
  }
  @keyframes fade {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    canvas,
    .sky,
    .picker {
      transition: none;
    }
    .caption {
      animation: none;
    }
  }
</style>

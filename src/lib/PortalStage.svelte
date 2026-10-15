<script lang="ts">
  // The landing's stage: the tile portal carousel (spec 010, drawn by the
  // Rust scene through tiles.ts) in whatever room the form leaves, so it fits
  // every phone's shape. Swipe, or use the arrows and dots, to choose a
  // portal; each school has its own frame, motif and colours, and they ride
  // an orbit that turns between them. LAR flies round it (LarFlight), never
  // through a portal's blocks.
  import { onMount, untrack } from "svelte";
  import LarFlight, { type Context } from "./lar/LarFlight.svelte";
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
    const ev = tiles.draw(ctx, { t, prev, stage, openedAt: openedAt ?? 0, returning, reduce, pos: motion.pos });
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
      <div class="pager">
        {#each portals as p, i (p.id)}
          <button
            class="dot"
            class:on={i === index}
            style:--c={p.theme.accent}
            aria-label="{p.name}, {p.status === 'ready' ? 'ready' : 'opens soon, unavailable'}"
            aria-current={i === index}
            disabled={locked}
            onclick={() => go(i)}
          ></button>
        {/each}
      </div>
      <button class="arrow" aria-label="Next portal" disabled={locked || index === portals.length - 1} onclick={() => go(index + 1)}>›</button>
    </div>
    {#key current.id}
      <p class="caption" aria-live="polite">
        <b style:color={current.theme.accent}>{current.name}</b>
        <span>{current.school}</span>
        {#if current.status !== "ready"}<small>Opens soon</small>{/if}
      </p>
    {/key}
  {/if}
</div>

<style>
  .stage {
    position: relative;
    display: grid;
    grid-template-rows: minmax(0, 1fr) auto auto;
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
  .leaving .picker,
  .leaving .caption {
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
  .pager {
    display: flex;
    gap: 2px;
  }
  /* 28 px hit area, a tile-shaped mark inside. */
  .dot {
    width: 22px;
    height: 28px;
    border: 0;
    padding: 0;
    background: transparent;
    -webkit-appearance: none;
    appearance: none;
    display: grid;
    place-items: center;
  }
  .dot::after {
    content: "";
    width: 7px;
    height: 7px;
    background: rgb(244 236 216 / 0.22);
    transition:
      background 0.3s var(--ease),
      transform 0.3s var(--ease);
  }
  .dot.on::after {
    background: var(--c);
    transform: scale(1.35);
  }
  .caption {
    margin: 0;
    display: flex;
    flex-wrap: wrap;
    justify-content: center;
    align-items: baseline;
    gap: 2px 8px;
    min-height: 1.4em;
    text-align: center;
    font-size: min(0.765rem, 23px);
    color: rgb(244 236 216 / 0.6);
    animation: fade 0.35s var(--ease);
  }
  .caption b {
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .caption small {
    font-family: var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(244 236 216 / 0.75);
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
    .picker,
    .dot::after {
      transition: none;
    }
    .caption {
      animation: none;
    }
  }
</style>

<script lang="ts">
  // The landing's stage: the tile portal (spec 010, drawn by the Rust scene
  // through tiles.ts) in whatever room the form leaves, so it fits every
  // phone's aspect ratio, and LAR standing at its foot.
  import { onMount } from "svelte";
  import Lar, { type Gesture } from "./lar/Lar.svelte";
  import type { Mood } from "./lar/sprite";
  import { buzz } from "./haptics";
  import { TICK, fpsFor, loadTiles, type Stage } from "./tiles";

  let {
    stage,
    theme,
    returning,
    still = false,
    showLar,
    leaving = false,
    mood,
    gesture,
  }: {
    stage: Stage;
    theme: { ramp: string[]; accent: string };
    returning: boolean;
    /** A field has focus: hold the layout still (C17). */
    still?: boolean;
    showLar: boolean;
    leaving?: boolean;
    mood: Mood;
    gesture: Gesture;
  } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // LAR's art pixel, in CSS px.
  const CELL = 3;

  let canvas: HTMLCanvasElement;
  let tiles: Awaited<ReturnType<typeof loadTiles>> | null = null;
  let start = performance.now();
  let prev = 0;
  let last = -1;
  let openedAt: number | null = returning ? 0 : null;
  let raf = 0;

  const now = () => (performance.now() - start) / 1000;

  function draw(t: number) {
    const ctx = canvas.getContext("2d");
    if (!tiles || !ctx) return;
    const ev = tiles.draw(ctx, { t, prev, stage, openedAt: openedAt ?? 0, returning, reduce });
    if (ev & TICK) buzz.tick();
    prev = t;
  }

  // Stepped motion: draw only when the stage's frame rate says so (C22).
  function loop() {
    raf = requestAnimationFrame(loop);
    const t = now();
    if (t - last < 1 / fpsFor(t, stage, openedAt) - 0.004) return;
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
        tiles.theme(theme.ramp, theme.accent);
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

  $effect(() => {
    tiles?.theme(theme.ramp, theme.accent);
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
</script>

<div class="stage" class:leaving>
  <canvas bind:this={canvas} aria-hidden="true"></canvas>
  <span class="lar" class:on={showLar}><Lar size={CELL} {mood} {gesture} /></span>
</div>

<style>
  .stage {
    position: relative;
    display: grid;
    grid-template-rows: minmax(0, 1fr) auto;
    justify-items: center;
    min-height: 0;
  }
  canvas {
    display: block;
    width: 100%;
    height: 100%;
    min-height: 0;
    transition:
      transform 1.1s cubic-bezier(0.55, 0, 1, 0.45),
      opacity 1.1s ease-in;
  }
  /* Step through: dive into the portal. The morph into Today is spec 010 C20. */
  .leaving canvas {
    transform: scale(2.6);
    opacity: 0;
  }
  .lar {
    margin-top: -12px;
    opacity: 0;
    transform: translateY(8px);
    transition:
      opacity 0.4s var(--ease),
      transform 0.4s var(--ease);
  }
  .lar.on {
    opacity: 1;
    transform: none;
  }
  .leaving .lar {
    opacity: 0;
  }
  @media (prefers-reduced-motion: reduce) {
    canvas,
    .lar {
      transition: none;
    }
  }
</style>

<script lang="ts">
  // The dive over Today (spec 010 C26–C30), drawn by the Rust scene through
  // dive.ts. It lasts until `ready`, then lands on Today's dot grid and frees
  // its canvas. Sign-in never depends on it: if it can't load, `onfail` goes on
  // to Today without it.
  import { onMount } from "svelte";
  import { loadDive, themeOf, type DiveStart } from "./dive";
  import { fieldPulse } from "./fieldPulse";
  import { buzz } from "./haptics";
  import { W, drawLar, rig } from "./lar/sprite";

  let {
    start,
    ready,
    oncovered,
    ondone,
    onfail,
  }: {
    start: DiveStart;
    /** Today has painted under the field. */
    ready: boolean;
    /** The field fully hides what was under it: the landing can go. */
    oncovered: () => void;
    ondone: () => void;
    onfail: () => void;
  } = $props();

  /** Seconds for a first sign-in's field to fade in over the landing, and to fully hide it. */
  const FADE = 0.18;
  const COVER = 0.2;
  /** LAR's bubble stays this long, and his body's centre in the sprite. */
  const SAYS_UNTIL = 0.62;
  /** The most one frame may advance the dive, in seconds. */
  const MAX_STEP = 0.05;
  const MID = { x: W / 2, y: 12 };

  let canvas: HTMLCanvasElement;
  let bubble = $state<HTMLDivElement>();

  onMount(() => {
    const { first, portal } = start;
    let raf = 0;
    let dead = false;
    loadDive()
      .then((d) => {
        if (dead) return;
        const dpr = Math.min(devicePixelRatio, 3);
        const box = canvas.getBoundingClientRect();
        canvas.width = Math.round(box.width * dpr);
        canvas.height = Math.round(box.height * dpr);
        const ctx = canvas.getContext("2d");
        if (!ctx) return onfail();
        ctx.imageSmoothingEnabled = false;
        d.start(start, canvas.width, canvas.height, dpr);
        const theme = themeOf(portal);
        const look = rig("fly");
        // A hitch (Today mounting underneath) pauses the dive; it never skips ahead.
        let last = performance.now();
        let t = 0;
        let readyAt = -1;
        let covered = false;
        let revealed = false;
        if (!first) buzz.release();
        const frame = (now: number) => {
          raf = requestAnimationFrame(frame);
          t += Math.min(MAX_STEP, Math.max(0, now - last) / 1000);
          last = now;
          if (ready && readyAt < 0) readyAt = t;
          if (!covered && (!first || t >= COVER)) {
            covered = true;
            oncovered();
          }
          // A first sign-in's field fades in over the landing; LAR is in front of it from the start.
          ctx.globalAlpha = first ? Math.min(1, t / FADE) : 1;
          const info = d.draw(ctx, t, readyAt);
          ctx.globalAlpha = 1;
          if (!revealed && readyAt >= 0 && t >= d.arrive(readyAt)) {
            revealed = true;
            buzz.pull();
          }
          if (info.lar.alpha > 0) {
            const { x, y, scale, alpha } = info.lar;
            ctx.save();
            ctx.globalAlpha = alpha;
            ctx.setTransform(scale, 0, 0, scale, x - MID.x * scale, y - MID.y * scale);
            drawLar(ctx, look.at(t, { vx: 0, vy: 0 }, false), theme, t, { shadow: false });
            ctx.restore();
            if (bubble) {
              bubble.style.opacity = t < SAYS_UNTIL ? "1" : "0";
              bubble.style.transform = `translate(${x / dpr}px, ${y / dpr}px)`;
            }
          }
          if (info.done) {
            cancelAnimationFrame(raf);
            dead = true;
            fieldPulse(innerWidth / 2, innerHeight / 2, 1.3);
            ondone();
          }
        };
        raf = requestAnimationFrame(frame);
      })
      // No dive, but the app still opens (spec 010 Errors).
      .catch(() => onfail());
    return () => {
      dead = true;
      cancelAnimationFrame(raf);
    };
  });
</script>

<canvas bind:this={canvas} aria-hidden="true"></canvas>
{#if start.first}
  <div bind:this={bubble} class="says" aria-hidden="true"><b>LAR</b>Ayos! Tara, pasok!</div>
{/if}

<style>
  canvas {
    position: fixed;
    left: 0;
    top: 0;
    width: 100vw;
    /* The large viewport: at launch the small one can leave the tab bar showing below it. */
    height: 100lvh;
    z-index: 80;
    pointer-events: none;
  }
  .says {
    position: fixed;
    left: 0;
    top: 0;
    z-index: 81;
    margin: -74px 0 0 -40px;
    padding: 5px 8px;
    white-space: nowrap;
    pointer-events: none;
    color: #f4ecd8;
    background: #170b1a;
    box-shadow: inset 0 2px 0 #3a2446;
    font: 500 min(0.765rem, 22px) var(--font-ui);
    transition: opacity 0.12s linear;
  }
  .says b {
    margin-right: 5px;
    color: #f5b227;
    font: 700 min(0.706rem, 20px) var(--font-pixel);
    letter-spacing: 0.06em;
  }
</style>

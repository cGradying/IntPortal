<script lang="ts" module>
  export type { Context } from "./wander";
</script>

<script lang="ts">
  // LAR on the landing: he comes out of the portal, resolving from a few
  // big pixels into his full sprite, then flies round it with a swarm of
  // pixel birds (wander.ts, flock.ts). The portal's frame is solid to all of
  // them. Now and then he says something about the app (lines.ts); tap him
  // and he answers. He is pixelated on purpose, drawn small and scaled up
  // with no smoothing, but he moves smoothly between pixels.
  import { onMount, untrack } from "svelte";
  import { buzz } from "../haptics";
  import { spawn as spawnBirds, step as stepBirds, wingsUp, type Bird } from "./flock";
  import { hold, pause, pick, remember, type Topic } from "./lines";
  import { VIEW, blinkAt, lar as larShapes, paint, type Gesture, type Mood } from "./vector";
  import { create, landing, rng, tick, turnOf, type Context, type Lar, type Rect, type World } from "./wander";

  let {
    getRect,
    show,
    ctx,
    mood,
    portal,
  }: {
    /** The selected portal's frame box, in this layer's CSS px. */
    getRect: () => Rect | null;
    /** The landing is resting: time for him to come out. */
    show: boolean;
    ctx: Context;
    mood: Mood;
    portal: { id: string; name: string; school: string; ready: boolean; ramp: string[]; accent: string };
  } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  /** His drawn width in CSS px, and the art resolution he resolves up to. */
  const WIDE = 74;
  const RES = 34;
  const R = 28;
  const BIRDS = 11;
  const SPAWN = 1.1;
  // Wings up, wings down: 5 by 3 art pixels.
  const UP = ["#...#", ".#.#.", "..#.."];
  const DOWN = ["..#..", ".#.#.", "#...#"];

  let canvas: HTMLCanvasElement;
  let bubble: HTMLDivElement;
  let tap: HTMLButtonElement;
  const off = typeof document !== "undefined" ? document.createElement("canvas") : null;
  const rand = rng(Math.floor(Math.random() * 1e9));
  let me: Lar | null = null;
  let birds: Bird[] = [];
  let bornAt: number | null = null;
  let start = performance.now();
  let lastT = 0;
  let raf = 0;
  let line = $state("");
  let live = $state(false);
  let lineUntil = 0;
  let nextTalk = 4;
  let recent: string[] = [];
  let tappedAt = -9;

  const now = () => (performance.now() - start) / 1000;
  const easeOut = (x: number) => 1 - Math.pow(1 - Math.min(1, Math.max(0, x)), 3);

  function world(): World | null {
    const p = getRect();
    if (!p || !canvas) return null;
    const { width, height } = canvas.getBoundingClientRect();
    return { w: width, h: height, portal: p, keepOut: [], r: R };
  }

  function say(topic?: Topic, announce = false) {
    const text = pick({ hour: new Date().getHours(), portal, typing: ctx === "typing" }, recent, rand, topic);
    if (!text) return;
    recent = remember(recent, text);
    line = text;
    live = announce;
    const t = now();
    lineUntil = t + hold(text);
    nextTalk = lineUntil + pause(rand);
  }

  function frame() {
    const g = canvas?.getContext("2d");
    const w = world();
    if (!g || !w) return;
    const t = now();
    const dt = Math.min(0.05, Math.max(0, t - lastT));
    lastT = t;
    const dpr = Math.min(devicePixelRatio, 3);
    const cw = Math.round(w.w * dpr);
    const ch = Math.round(w.h * dpr);
    if (canvas.width !== cw || canvas.height !== ch) {
      canvas.width = cw;
      canvas.height = ch;
    }
    g.clearRect(0, 0, cw, ch);
    if (bornAt === null) return;

    // Coming out: from the opening's centre to just below the frame, growing
    // and resolving in steps from coarse pixels to his full sprite.
    const k = reduce ? 1 : (t - bornAt) / SPAWN;
    const centre = { x: w.portal.x + w.portal.w / 2, y: w.portal.y + w.portal.h / 2 };
    const land = landing(w);
    let x: number;
    let y: number;
    let grow = 1;
    let res = RES;
    let alpha = 1;
    if (k < 1) {
      const e = easeOut(k);
      x = centre.x + (land.x - centre.x) * e;
      y = centre.y + (land.y - centre.y) * e;
      grow = 0.3 + 0.7 * e;
      res = [8, 12, 17, 24, RES][Math.min(4, Math.floor(k * 5))];
      alpha = Math.min(1, k * 5);
    } else {
      if (!me) {
        me = create(w, rand);
        birds = reduce ? [] : spawnBirds(BIRDS, land.x, land.y - 10, rand);
      }
      if (!reduce) {
        tick(me, w, ctx, dt, rand);
        stepBirds(birds, me, w, dt, t, rand);
      }
      x = me.x;
      y = me.y;
      grow = 0.9 + 0.16 * me.depth;
    }

    // The swarm, in the portal's accent and gold, a few art pixels each.
    const px = Math.max(1, Math.round(2 * dpr));
    for (let i = 0; i < birds.length; i++) {
      const b = birds[i];
      g.fillStyle = i % 3 === 0 ? "#f5b227" : portal.accent;
      const sprite = wingsUp(b, t) ? UP : DOWN;
      const bx = Math.round(b.x * dpr) - 2 * px;
      const by = Math.round(b.y * dpr) - px;
      sprite.forEach((row, j) => {
        for (let c = 0; c < 5; c++) if (row[c] === "#") g.fillRect(bx + c * px, by + j * px, px, px);
      });
    }

    // LAR: painted small, then scaled up with no smoothing.
    const face: Mood = t - tappedAt < 1.2 ? "wink" : mood === "open" && !reduce ? blinkAt(t) : mood;
    const gesture: Gesture = ctx === "signed" || t - tappedAt < 1.2 ? "wave" : "idle";
    const shapes = larShapes({ mood: face, gesture, t: reduce ? 0 : t, turn: me ? turnOf(me) * 0.8 : 0, ramp: portal.ramp, cube: res >= 17 });
    if (off) {
      const rw = res;
      const rh = Math.round((res * VIEW.h) / VIEW.w);
      off.width = rw;
      off.height = rh;
      const o = off.getContext("2d");
      if (o) {
        o.clearRect(0, 0, rw, rh);
        paint(o, shapes, rw / VIEW.w);
        const dw = WIDE * grow * dpr;
        const dh = (dw * VIEW.h) / VIEW.w;
        g.save();
        g.globalAlpha = alpha;
        g.imageSmoothingEnabled = false;
        g.drawImage(off, Math.round(x * dpr - dw / 2), Math.round(y * dpr - dh / 2), Math.round(dw), Math.round(dh));
        g.restore();
      }
    }

    // His tap target and speech bubble follow him (written straight to the
    // DOM each frame, so Svelte isn't re-rendering at 60 fps).
    const half = (WIDE * grow) / 2;
    if (tap) tap.style.transform = `translate(${x - half}px, ${y - half * 0.75}px)`;
    if (t > lineUntil && line) line = "";
    if (!line && t >= nextTalk && k >= 1 && ctx !== "typing") say();
    if (bubble && line) {
      const right = x < w.w / 2;
      const bw = bubble.offsetWidth;
      const bx = right ? Math.min(w.w - bw - 4, x + half * 0.8) : Math.max(4, x - half * 0.8 - bw);
      const by = Math.max(4, y - half - bubble.offsetHeight + 4);
      bubble.style.transform = `translate(${bx}px, ${by}px)`;
      bubble.dataset.side = right ? "right" : "left";
    }
  }

  function loop() {
    raf = requestAnimationFrame(loop);
    frame();
  }

  function visibility() {
    cancelAnimationFrame(raf);
    if (!document.hidden && !reduce) loop();
  }

  onMount(() => {
    start = performance.now();
    visibility();
    document.addEventListener("visibilitychange", visibility);
    const ro = new ResizeObserver(() => reduce && frame());
    ro.observe(canvas);
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      document.removeEventListener("visibilitychange", visibility);
    };
  });

  // Out he comes once the landing rests.
  $effect(() => {
    if (show && bornAt === null) {
      untrack(() => {
        bornAt = now();
        nextTalk = bornAt + SPAWN + 1.2;
        if (reduce) requestAnimationFrame(frame);
      });
    }
  });

  // What the student does gets an answer straight away.
  $effect(() => {
    const c = ctx;
    untrack(() => {
      if (c === "error") say("error", true);
      else if (c === "busy") say("busy");
      else if (c === "signed") say("signed", true);
      else if (c === "typing") line = "";
      if (reduce) frame();
    });
  });

  function poke() {
    tappedAt = now();
    buzz.select();
    say("tap", true);
    if (reduce) frame();
  }
</script>

<div class="flight">
  <canvas bind:this={canvas} aria-hidden="true"></canvas>
  <button bind:this={tap} class="tap" class:on={show} aria-label="LAR, tap to talk" onclick={poke}></button>
  <div bind:this={bubble} class="bubble" class:on={!!line} aria-live={live ? "polite" : "off"}>
    {#if line}<b>LAR</b> {line}{/if}
  </div>
</div>

<style>
  .flight {
    position: absolute;
    inset: 0;
    pointer-events: none;
  }
  canvas {
    width: 100%;
    height: 100%;
    display: block;
  }
  .tap {
    position: absolute;
    top: 0;
    left: 0;
    width: 74px;
    height: 56px;
    border: 0;
    padding: 0;
    background: transparent;
    -webkit-appearance: none;
    appearance: none;
    pointer-events: none;
  }
  .tap.on {
    pointer-events: auto;
  }
  .tap:focus-visible {
    outline: 2px solid #f5b227;
    outline-offset: 2px;
  }
  .bubble {
    position: absolute;
    top: 0;
    left: 0;
    max-width: min(240px, 62%);
    padding: 7px 10px;
    background: #170b1a;
    box-shadow:
      inset 0 2px 0 #3a2446,
      inset 0 -2px 0 #060307;
    font-size: min(0.765rem, 23px);
    line-height: 1.35;
    color: #f4e8d6;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    opacity: 0;
    transition: opacity 0.25s var(--ease);
  }
  .bubble.on {
    opacity: 1;
  }
  .bubble b {
    margin-right: 5px;
    font-family: var(--font-pixel);
    font-weight: 400;
    letter-spacing: 0.06em;
    color: #f5b227;
  }
  @media (prefers-reduced-motion: reduce) {
    .bubble {
      transition: none;
    }
  }
</style>

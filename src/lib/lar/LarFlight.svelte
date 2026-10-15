<script lang="ts" module>
  export type { Context } from "./wander";
</script>

<script lang="ts">
  // LAR on the landing: he comes out of a fire below the portal, in the
  // portal's own colours, resolving from coarse blocks to his sprite, then
  // flies round it on his own (wander.ts). The portals' frames are solid to
  // him. His state follows what he and the
  // student are doing (fly, think, error, happy, sleep), eased by a rig. Now
  // and then he says something about the app (lines.ts); tap him and he
  // answers. His first line is a greeting, the moment he lands. A line grows
  // out of his side in four pixel steps, types itself out with a blinking
  // caret and leaves with a short reverse (Reduce Motion: it just appears).
  import { flushSync, onMount, tick as settle, untrack } from "svelte";
  import { buzz } from "../haptics";
  import { hold, pause, pick, remember, type Topic } from "./lines";
  import { SPAWN_SECS, W, drawLar, rig, type State } from "./sprite";
  import { create, landing, rng, tick, type Context, type Lar, type Rect, type World } from "./wander";

  let {
    getRects,
    show,
    ctx,
    portal,
  }: {
    /** The selected portal's frame box, and its neighbours', in this layer's CSS px: all solid. */
    getRects: () => { portal: Rect; others: Rect[] } | null;
    /** The landing is resting: time for him to come out. */
    show: boolean;
    ctx: Context;
    portal: { id: string; name: string; school: string; ready: boolean; ramp: string[]; accent: string };
  } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  /** CSS px per sprite px: whole, so he stays crisp. */
  const SIZE = 2;
  /** His body's centre in the sprite, and his reach round it (mitts included), in CSS px. */
  const MID = { x: W / 2, y: 12 };
  const R = 36;
  /** A line's bubble: seconds to grow and to leave, in steps; then characters typed per second. */
  const GROW = 0.24;
  const LEAVE = 0.16;
  const CPS = 35;

  let canvas: HTMLCanvasElement;
  let bubble: HTMLDivElement;
  let tap: HTMLButtonElement;
  const rand = rng(Math.floor(Math.random() * 1e9));
  const look = rig("idle");
  let me: Lar | null = null;
  let bornAt: number | null = null;
  let start = performance.now();
  let lastT = 0;
  let raf = 0;
  /** What he is saying now (for the timing) ... */
  let line = "";
  /** ... and what the bubble shows: it outlives `line` by the leave animation. */
  let shown = $state("");
  let typed = $state(0);
  let leaving = $state(false);
  /** Bumped per line, so each one restarts the grow. */
  let serial = $state(0);
  let live = $state(false);
  let lineAt = 0;
  let lineUntil = 0;
  let nextTalk = 4;
  let greeted = false;
  let leaveTimer: ReturnType<typeof setTimeout> | undefined;
  let recent: string[] = [];
  let tappedAt = -9;
  let restFrom = 0;

  const now = () => (performance.now() - start) / 1000;
  const theme = $derived({ ramp: portal.ramp, accent: portal.accent });

  function world(): World | null {
    const rects = getRects();
    if (!rects || !canvas) return null;
    const { width, height } = canvas.getBoundingClientRect();
    return { w: width, h: height, portal: rects.portal, keepOut: rects.others, r: R };
  }

  function say(topic?: Topic, announce = false) {
    const text = pick({ hour: new Date().getHours(), portal, typing: ctx === "typing" }, recent, rand, topic);
    if (!text) return;
    recent = remember(recent, text);
    clearTimeout(leaveTimer);
    line = shown = text;
    live = announce;
    leaving = false;
    typed = reduce ? text.length : 0;
    serial++;
    // Hidden until the next frame has measured and placed it.
    delete bubble?.dataset.placed;
    lineAt = now();
    lineUntil = lineAt + (reduce ? 0 : GROW + text.length / CPS) + hold(text);
    nextTalk = lineUntil + pause(rand);
  }

  /** He stops talking: the bubble shrinks back to his side, then goes. */
  function hide() {
    line = "";
    if (!shown) return;
    if (reduce) return void (shown = "");
    leaving = true;
    leaveTimer = setTimeout(() => ((shown = ""), (leaving = false)), LEAVE * 1000);
  }

  /** What he is doing, from what the student is doing and how he moves. */
  function stateFor(t: number, speed: number): State {
    if (t - tappedAt < 1.4 || ctx === "signed") return "happy";
    if (ctx === "error") return "error";
    if (ctx === "busy") return "think";
    if (ctx === "typing" || (me?.mode === "rest" && t - restFrom > 6)) return "sleep";
    // A little hysteresis, so he doesn't flicker between gliding and hovering.
    if (speed > 55 || (look.state === "fly" && speed > 35)) return "fly";
    return "idle";
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
    g.setTransform(1, 0, 0, 1, 0, 0);
    g.clearRect(0, 0, cw, ch);
    if (bornAt === null) return;

    // Coming out: a fire flares just below the frame and he resolves inside it.
    const k = reduce ? 1 : (t - bornAt) / SPAWN_SECS;
    const land = landing(w);
    let x = land.x;
    let y = land.y;
    let vx = 0;
    let vy = 0;
    if (k >= 1) {
      if (!me) me = create(w, rand);
      const was = me.mode;
      if (!reduce) tick(me, w, ctx, dt, rand);
      if (me.mode === "rest" && was !== "rest") restFrom = t;
      ({ x, y, vx, vy } = me);
      look.set(stateFor(t, Math.hypot(vx, vy)), t);
    }

    // LAR, from the same renderer as everywhere else, his body centred on x, y.
    const s = SIZE * dpr;
    g.setTransform(s, 0, 0, s, (x - MID.x * SIZE) * dpr, (y - MID.y * SIZE) * dpr);
    const p = look.at(t, { vx: vx / SIZE, vy: vy / SIZE }, reduce);
    if (t - tappedAt < 1.2 && p.mood === "happy") p.mood = "wink";
    drawLar(g, p, theme, reduce ? 0 : t, { shadow: false });

    // His tap target and speech bubble follow him (written straight to the
    // DOM each frame, so Svelte isn't re-rendering at 60 fps).
    if (tap) tap.style.transform = `translate(${x - R}px, ${y - R * 0.85}px)`;
    if (t > lineUntil && line) hide();
    // He greets the moment he lands, then chats now and then.
    if (!line && k >= 1 && !greeted) {
      greeted = true;
      say("greet");
    } else if (!line && t >= nextTalk && k >= 1 && ctx !== "typing") say();
    if (line && typed < line.length) typed = Math.min(line.length, Math.max(0, Math.floor((t - lineAt - GROW) * CPS)));
    // Svelte has to render a fresh line before it can be measured.
    flushSync();
    if (bubble && shown) {
      const right = x < w.w / 2;
      const bw = bubble.offsetWidth;
      const bx = right ? Math.min(w.w - bw - 4, x + R * 0.8) : Math.max(4, x - R * 0.8 - bw);
      const by = Math.max(4, y - R - bubble.offsetHeight + 4);
      bubble.style.transform = `translate(${bx}px, ${by}px)`;
      bubble.dataset.side = right ? "right" : "left";
      bubble.dataset.placed = "";
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
      clearTimeout(leaveTimer);
      ro.disconnect();
      document.removeEventListener("visibilitychange", visibility);
    };
  });

  // Out he comes once the landing rests.
  $effect(() => {
    if (show && bornAt === null) {
      untrack(() => {
        bornAt = now();
        look.start("spawn", bornAt);
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
      else if (c === "typing") hide();
      if (reduce) settle().then(frame);
    });
  });

  function poke() {
    tappedAt = now();
    buzz.select();
    say("tap", true);
    if (reduce) settle().then(frame);
  }
</script>

<div class="flight">
  <canvas bind:this={canvas} aria-hidden="true"></canvas>
  <button bind:this={tap} class="tap" class:on={show} aria-label="LAR, tap to talk" onclick={poke}></button>
  <div bind:this={bubble} class="bubble" class:on={!!shown} class:leaving aria-live={live ? "polite" : "off"}>
    <!-- Screen readers get the whole line at once; the typed copy is only for the eyes. -->
    <span class="sr">{shown ? `LAR: ${shown}` : ""}</span>
    {#key serial}
      {#if shown}
        <div class="pop" aria-hidden="true">
          <b>LAR</b> {shown.slice(0, typed)}<i class="caret" class:done={typed >= shown.length}></i><span class="rest">{shown.slice(typed)}</span>
        </div>
      {/if}
    {/key}
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
    width: 72px;
    height: 62px;
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
    visibility: hidden;
  }
  .bubble.on:global([data-placed]) {
    visibility: visible;
  }
  /* Grows out of the corner nearest LAR, in whole steps like the rest of him. */
  .pop {
    padding: 7px 10px;
    background: #170b1a;
    box-shadow:
      inset 0 2px 0 #3a2446,
      inset 0 -2px 0 #060307;
    font-size: min(0.765rem, 23px);
    line-height: 1.35;
    color: #f4e8d6;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    transform-origin: 0 100%;
    animation: grow 0.24s steps(4, end) both;
  }
  .bubble:global([data-side="left"]) .pop {
    transform-origin: 100% 100%;
  }
  .bubble.leaving .pop {
    animation: leave 0.16s steps(3, end) both;
  }
  /* The not-yet-typed rest keeps its room, so the bubble never changes size. */
  .rest {
    visibility: hidden;
  }
  .caret {
    position: relative;
    display: inline-block;
    width: 0;
    height: 1em;
    vertical-align: -0.14em;
  }
  .caret::after {
    content: "";
    position: absolute;
    left: 1px;
    top: 0;
    width: 3px;
    height: 100%;
    background: #f5b227;
    animation: blink 0.5s steps(1) infinite;
  }
  .caret.done {
    display: none;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  .pop b {
    margin-right: 5px;
    font-family: var(--font-pixel);
    font-weight: 400;
    letter-spacing: 0.06em;
    color: #f5b227;
  }
  @keyframes grow {
    from {
      transform: scale(0.25);
    }
    to {
      transform: scale(1);
    }
  }
  @keyframes leave {
    from {
      transform: scale(1);
    }
    to {
      transform: scale(0.25);
    }
  }
  @keyframes blink {
    50% {
      opacity: 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .pop,
    .bubble.leaving .pop {
      animation: none;
    }
    .caret {
      display: none;
    }
  }
</style>

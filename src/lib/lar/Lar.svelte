<script lang="ts" module>
  export type Gesture = "idle" | "wave" | "point" | "reach" | "thumbs";
</script>

<script lang="ts">
  // LAR on screen. The parts are separate canvases so he moves smoothly
  // between whole pixels: pose() (sprite.ts) says where every part goes for
  // his state, and this lays them out. Pass `t` to drive him from a
  // timeline; without it he keeps his own clock. `theme` tints him for a
  // portal. Reduce Motion holds him in a still pose.
  import { onMount, untrack } from "svelte";
  import {
    ANTENNA, CUBE, H, MITT, SIS, SPARKLE, SPAWN_SECS, STREAK, THUMB, W, ZZZ, bodyGrid, dotsGrid, drawSwirl, faceGrid, mosaic, pose, redGrid, rows, tint,
    type Grid, type Mood, type Palette, type State, type Theme,
  } from "./sprite";

  let {
    size = 4,
    mood,
    gesture = "idle",
    state: mode = "idle",
    theme = SIS,
    vx,
    vy,
    t: driven,
    cube = true,
    label = "LAR, the Lakbay-Aral Robot",
  }: {
    size?: number;
    /** Overrides the face his state would wear. */
    mood?: Mood;
    gesture?: Gesture;
    state?: State;
    /** A portal's ramp and accent: his rim light, studs, cube and swirl follow it. */
    theme?: Theme;
    /** Fly velocity in sprite px per second. */
    vx?: number;
    vy?: number;
    t?: number;
    cube?: boolean;
    label?: string;
  } = $props();

  const reduce = typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  let own = $state(0);
  const t = $derived(driven ?? (reduce ? 0 : own));

  onMount(() => {
    if (driven !== undefined || reduce) return;
    let raf = 0;
    const start = performance.now();
    const frame = (now: number) => {
      own = (now - start) / 1000;
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  });

  // A switch of state: remember where we came from, when, and the cube angle
  // already owed, so everything eases across the change and nothing pops.
  let from = $state<State | undefined>();
  let switched = $state(-Infinity);
  let phase = $state(0);
  let cur: State = untrack(() => mode);
  let lastAngle = 0;
  $effect.pre(() => {
    const next = mode;
    untrack(() => {
      if (next === cur) return;
      phase = lastAngle - pose(cur, t, { phase: 0, vx, vy }).cube.angle;
      from = cur;
      cur = next;
      switched = t;
    });
  });

  const since = $derived(reduce ? Infinity : t - switched);
  const P = $derived(pose(mode, t, { from: reduce ? undefined : from, since, k: reduce ? 1 : Math.min(1, since / SPAWN_SECS), vx, vy, phase }));
  $effect(() => {
    lastAngle = P.cube.angle;
  });

  const pal: Palette = $derived(tint(theme));
  const face: Mood = $derived(mood && mood !== "open" ? mood : P.mood);
  const res = $derived(P.resolve);

  const BODY = bodyGrid();
  const RED = redGrid();
  const sharp = (g: Grid) => (res > 1 ? mosaic(g, res, pal) : g);
  const paint = (g: Grid) => (cv: HTMLCanvasElement) => {
    cv.width = g[0].length;
    cv.height = g.length;
    const x = cv.getContext("2d")!;
    g.forEach((row, j) =>
      row.forEach((k, i) => {
        if (!k) return;
        x.fillStyle = pal[k];
        x.fillRect(i, j, 1, 1);
      }),
    );
  };
  // While he resolves, body and face are blocked together so the blocks agree.
  const flat = (...layers: Grid[]): Grid => BODY.map((row, j) => row.map((k, i) => layers.reduce((acc, l) => l[j][i] ?? acc, k)));

  let belly = $state<HTMLCanvasElement>();
  $effect(() => {
    const x = belly?.getContext("2d");
    if (x) drawSwirl(x, t, 6, 5, theme.ramp);
  });

  // [dx, dy, rot] per mitt, in sprite pixels from where it floats.
  const GEST: Record<Gesture, [number, number, number][]> = {
    idle: [[0, 0, 0], [0, 0, 0]],
    wave: [[0, 0, 0], [3, -12, -30]],
    point: [[0, 0, 0], [9, -6, -20]],
    reach: [[-3, -10, -30], [3, -10, 30]],
    thumbs: [[0, 0, 0], [3, -7, 0]],
  };
  const hands = $derived(
    P.mitts.map((m, i) => {
      const [dx, dy, rot] = GEST[gesture][i];
      const wave = gesture === "wave" && i === 1 ? Math.sin(t * 9) * 28 : 0;
      return { ...m, x: m.x + dx, y: m.y + dy, rot: m.rot + rot + wave, thumb: gesture === "thumbs" && i === 1 };
    }),
  );
  const px = (v: number) => `${v * size}px`;
</script>

{#snippet orbit()}
  <canvas
    class="part"
    {@attach paint(sharp(rows(CUBE)))}
    style:transform="translate({px(P.cube.x - 3.5)}, {px(P.cube.y - 3.5)}) scale({P.cube.scale})"
    style:transform-origin="{px(3.5)} {px(3.5)}"
    style:width={px(7)}
  ></canvas>
{/snippet}

<span class="lar" role="img" aria-label={label} style:width={px(W)} style:height={px(H)} style:--s="{size}px" style:opacity={P.alpha}>
  {#if cube && !P.cube.front && P.cube.scale > 0.01}{@render orbit()}{/if}
  {#each hands as h, i (i)}
    {#if h.streak > 0.02}
      <canvas
        class="part"
        {@attach paint(rows(STREAK))}
        style:width={px(6)}
        style:opacity={h.streak * 0.9}
        style:transform="translate({px(h.x - 6)}, {px(h.y + 2)}) rotate({h.streakRot}deg)"
        style:transform-origin="{px(9.5)} {px(1.5)}"
      ></canvas>
    {/if}
  {/each}
  <span class="body" style:transform="translate({px(P.body.x)}, {px(P.body.y)}) rotate({P.body.rot}deg) scale({P.body.sx}, {P.body.sy})" style:transform-origin="{px(W / 2)} {px(15)}">
    <canvas
      class="part"
      {@attach paint(sharp(rows(ANTENNA)))}
      style:width={px(7)}
      style:transform="translate({px(P.antenna.x)}, {px(P.antenna.y)}) rotate({P.antenna.rot}deg)"
      style:transform-origin="{px(3.5)} {px(9)}"
    ></canvas>
    {#if res > 1}
      <canvas class="part" {@attach paint(mosaic(P.red ? flat(RED, faceGrid(face)) : flat(faceGrid(face)), res, pal))} style:width={px(W)}></canvas>
    {:else}
      <canvas class="part" {@attach paint(BODY)} style:width={px(W)}></canvas>
      {#if P.red}<canvas class="part" {@attach paint(RED)} style:width={px(W)}></canvas>{/if}
      <canvas class="part" {@attach paint(faceGrid(face))} style:width={px(W)}></canvas>
      {#if P.dots >= 0}<canvas class="part" {@attach paint(dotsGrid(P.dots))} style:width={px(W)}></canvas>{/if}
      <canvas class="part" bind:this={belly} width="6" height="5" style:width={px(6)} style:transform="translate({px(W / 2 - 3)}, {px(15)})"></canvas>
    {/if}
  </span>
  {#if cube && P.cube.front && P.cube.scale > 0.01}{@render orbit()}{/if}
  {#each hands as h, i (i)}
    <canvas
      class="part"
      {@attach paint(sharp(rows(h.thumb ? THUMB : MITT)))}
      style:width={px(7)}
      style:transform="translate({px(h.x)}, {px(h.y)}) rotate({h.rot}deg) scaleX({h.side})"
      style:transform-origin="{px(3.5)} {px(3.5)}"
    ></canvas>
  {/each}
  {#each P.zzz as g, i (i)}
    <canvas class="part" {@attach paint(rows(ZZZ[g.s]))} style:width={px(ZZZ[g.s][0].length)} style:opacity={g.a} style:transform="translate({px(g.x)}, {px(g.y)})"></canvas>
  {/each}
  {#each P.sparkle as g, i (i)}
    <canvas class="part" {@attach paint(rows(SPARKLE[g.s]))} style:width={px(SPARKLE[g.s][0].length)} style:opacity={g.a} style:transform="translate({px(g.x)}, {px(g.y)})"></canvas>
  {/each}
  <i class="shadow" style:transform="translateX({px(P.body.x)}) scaleX({Math.max(0.5, 1 + P.body.y / 16)})"></i>
</span>

<style>
  /* The mitts float 5 sprite pixels past the body on each side. */
  .lar {
    position: relative;
    display: inline-block;
    flex: none;
    margin-inline: calc(var(--s) * 5);
  }
  .body {
    position: absolute;
    inset: 0;
  }
  .part {
    position: absolute;
    top: 0;
    left: 0;
    height: auto;
    image-rendering: pixelated;
  }
  .shadow {
    position: absolute;
    left: calc(var(--s) * 5);
    top: calc(var(--s) * 24.5);
    width: calc(var(--s) * 16);
    height: calc(var(--s) * 2);
    border-radius: 50%;
    background: rgb(0 0 0 / 0.3);
  }
</style>

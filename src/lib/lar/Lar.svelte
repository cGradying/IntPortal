<script lang="ts" module>
  export type Gesture = "idle" | "wave" | "point" | "reach" | "thumbs";
</script>

<script lang="ts">
  // LAR on screen. The parts are separate canvases so he moves smoothly
  // between whole pixels: the body bobs, the antenna sways, the mitts float
  // and lag, the cube orbits behind and in front, the belly swirl turns.
  // Pass `t` to drive him from a timeline; without it he keeps his own idle
  // clock. Reduce Motion holds him still.
  import { onMount } from "svelte";
  import { ANTENNA, CUBE, H, LAR_PAL, MITT, THUMB, W, blinkAt, bodyGrid, drawSwirl, faceGrid, rows, type Grid, type Mood } from "./sprite";

  let {
    size = 4,
    mood = "open",
    gesture = "idle",
    t: driven,
    cube = true,
    label = "LAR, the Lakbay-Aral Robot",
  }: { size?: number; mood?: Mood; gesture?: Gesture; t?: number; cube?: boolean; label?: string } = $props();

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

  function paint(cv: HTMLCanvasElement, g: Grid) {
    cv.width = g[0].length;
    cv.height = g.length;
    const x = cv.getContext("2d")!;
    g.forEach((row, j) =>
      row.forEach((k, i) => {
        if (!k) return;
        x.fillStyle = LAR_PAL[k];
        x.fillRect(i, j, 1, 1);
      }),
    );
  }

  let belly: HTMLCanvasElement;
  $effect(() => {
    const x = belly?.getContext("2d");
    if (x) drawSwirl(x, t, 6, 5);
  });

  // [dx, dy, rot] per mitt, in sprite pixels from where it floats.
  const GEST: Record<Gesture, [number, number, number][]> = {
    idle: [[0, 0, 0], [0, 0, 0]],
    wave: [[0, 0, 0], [3, -12, -30]],
    point: [[0, 0, 0], [9, -6, -20]],
    reach: [[-3, -10, -30], [3, -10, 30]],
    thumbs: [[0, 0, 0], [3, -7, 0]],
  };

  const face = $derived(mood === "open" && !reduce ? blinkAt(t) : mood);
  const bob = $derived(Math.sin(t * 3.1) * 1.4);
  const sway = $derived(Math.sin(t * 3.1 - 0.9) * 6);
  const angle = $derived(t * 2.2);
  const cubeFront = $derived(Math.sin(angle) > 0);
  const hands = $derived(
    [0, 1].map((i) => {
      const side = i === 0 ? -1 : 1;
      const lag = Math.sin(t * 3.1 - 0.7 - i * 0.3) * 1.2;
      let [dx, dy, rot] = GEST[gesture][i];
      if (gesture === "wave" && i === 1) rot += Math.sin(t * 9) * 28;
      return { x: W / 2 + side * 14.5 - 3.5 + dx, y: 13 + dy + lag, rot, side, thumb: gesture === "thumbs" && i === 1 };
    }),
  );
</script>

{#snippet orbit()}
  <canvas
    class="part"
    use:paint={rows(CUBE)}
    style:transform="translate({(W / 2 - 3.5 + Math.cos(angle) * 16) * size}px, {(6 + Math.sin(angle) * 3 + bob * 0.5) * size}px) scale({0.75 + 0.25 * Math.sin(angle)})"
    style:width="{7 * size}px"
  ></canvas>
{/snippet}

<span class="lar" role="img" aria-label={label} style:width="{W * size}px" style:height="{H * size}px" style:--s="{size}px">
  {#if cube && !cubeFront}{@render orbit()}{/if}
  <span class="body" style:transform="translateY({bob * size}px)">
    <canvas class="part" use:paint={rows(ANTENNA)} style:width="{7 * size}px" style:transform="translate({(W / 2 - 3.5) * size}px, {-7 * size}px) rotate({sway}deg)" style:transform-origin="{3.5 * size}px {9 * size}px"></canvas>
    <canvas class="part" use:paint={bodyGrid()} style:width="{W * size}px"></canvas>
    {#key face}<canvas class="part" use:paint={faceGrid(face)} style:width="{W * size}px"></canvas>{/key}
    <canvas class="part" bind:this={belly} width="6" height="5" style:width="{6 * size}px" style:transform="translate({(W / 2 - 3) * size}px, {15 * size}px)"></canvas>
  </span>
  {#if cube && cubeFront}{@render orbit()}{/if}
  {#each hands as h, i (i)}
    <canvas
      class="part"
      use:paint={rows(h.thumb ? THUMB : MITT)}
      style:width="{7 * size}px"
      style:transform="translate({h.x * size}px, {h.y * size}px) rotate({h.rot}deg) scaleX({h.side})"
      style:transform-origin="{3.5 * size}px {3.5 * size}px"
    ></canvas>
  {/each}
  <i class="shadow" style:transform="scaleX({1 - bob / 16})"></i>
</span>

<style>
  .lar {
    position: relative;
    display: inline-block;
    flex: none;
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

<script lang="ts">
  // The cube LAR holds, floating on its own (drawCube). Decorative: the
  // control it sits in carries the name.
  import { onMount } from "svelte";
  import { CUBE_BOX, drawCube, type Theme } from "./sprite";
  import { larTheme } from "./Lar.svelte";

  let { size = 5, theme, speed = 1 }: { size?: number; theme?: Theme; speed?: number } = $props();

  const reduce = typeof matchMedia !== "undefined" && matchMedia("(prefers-reduced-motion: reduce)").matches;
  const look = $derived(theme ?? larTheme());
  const box = CUBE_BOX * 2;
  let canvas: HTMLCanvasElement;
  let t = $state(0);

  onMount(() => {
    if (reduce) return;
    let raf = 0;
    const start = performance.now();
    const frame = (now: number) => {
      t = (now - start) / 1000;
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  });

  $effect(() => {
    const dpr = Math.min(3, devicePixelRatio || 1);
    const s = size * dpr;
    const w = Math.round(box * s);
    if (canvas.width !== w) canvas.width = canvas.height = w;
    const ctx = canvas.getContext("2d")!;
    ctx.setTransform(1, 0, 0, 1, 0, 0);
    ctx.clearRect(0, 0, w, w);
    ctx.setTransform(s, 0, 0, s, w / 2, w / 2);
    drawCube(ctx, look, t, { speed, still: reduce });
  });
</script>

<canvas bind:this={canvas} aria-hidden="true" style:width="{box * size}px" style:height="{box * size}px"></canvas>

<style>
  canvas {
    display: block;
    image-rendering: pixelated;
    pointer-events: none;
  }
</style>

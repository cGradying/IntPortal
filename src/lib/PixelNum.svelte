<script lang="ts">
  // A hero number in pixel numerals (spec 045 C10). `size` is CSS px per art
  // pixel at the default text size; it grows in whole pixels with the phone's
  // text size, so it stays crisp. Anything without a glyph stays plain text.
  import { drawable, pixels } from "./pixelNum";

  let { text, size = 4 }: { text: string; size?: number } = $props();

  const scale = typeof document === "undefined" ? 1 : parseFloat(getComputedStyle(document.documentElement).fontSize) / 17 || 1;
  const u = $derived(Math.max(1, Math.round(size * Math.min(scale, 1.5))));
  const art = $derived(drawable(text) ? pixels(text) : null);
</script>

{#if art}
  <svg role="img" aria-label={text} viewBox="0 0 {art.w} {art.h}" width={art.w * u} height={art.h * u} fill="currentColor" shape-rendering="crispEdges">
    {#each art.on as [x, y] (`${x},${y}`)}<rect {x} {y} width="1" height="1" />{/each}
  </svg>
{:else}
  {text}
{/if}

<style>
  svg {
    display: inline-block;
    vertical-align: baseline;
  }
</style>

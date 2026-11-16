<script lang="ts">
  // A hero number in pixel numerals (spec 045 C10). `size` is CSS px per art
  // pixel at the default text size; it grows in whole pixels with the phone's
  // text size, so it stays crisp. Anything without a glyph stays plain text.
  import { drawable, pixels } from "./pixelNum";

  import { still } from "./swap";

  // `roll`: when the text changes, the new numeral steps down into place, three art pixels
  // at a time. Only for a number that changes now and then (a countdown), never on first
  // paint and never for one that counts every frame.
  let { text, size = 4, roll = false }: { text: string; size?: number; roll?: boolean } = $props();

  const scale = typeof document === "undefined" ? 1 : parseFloat(getComputedStyle(document.documentElement).fontSize) / 17 || 1;
  const u = $derived(Math.max(1, Math.round(size * Math.min(scale, 1.5))));
  const art = $derived(drawable(text) ? pixels(text) : null);

  function rolled(el: Element, value: string) {
    let last = value;
    return {
      update(next: string) {
        if (next === last) return;
        last = next;
        if (!roll || still()) return;
        el.animate([{ translate: `0 ${-3 * u}px`, opacity: 0.3 }, { translate: "0 0", opacity: 1 }], { duration: 270, easing: "steps(3, end)" });
      },
    };
  }
</script>

{#if art}
  <svg use:rolled={text} role="img" aria-label={text} viewBox="0 0 {art.w} {art.h}" width={art.w * u} height={art.h * u} fill="currentColor" shape-rendering="crispEdges">
    {#each art.on as [x, y] (`${x},${y}`)}<rect {x} {y} width="1" height="1" />{/each}
  </svg>
{:else}
  <span class="plain" use:rolled={text}>{text}</span>
{/if}

<style>
  svg,
  .plain {
    display: inline-block;
    vertical-align: baseline;
  }
</style>

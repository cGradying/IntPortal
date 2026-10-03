<script lang="ts">
  // The study streak's pixel flame: two frames that flicker. Still under
  // Reduce Motion.
  import { FLAME, FLAME_COLORS } from "./sprites";

  let { size = 18 }: { size?: number } = $props();
  const frames = FLAME.map((rows) => rows.flatMap((row, y) => [...row].map((c, x) => ({ x, y, c })).filter((p) => p.c !== ".")));
</script>

<span class="flame" style:width="{(size * 7) / 9}px" style:height="{size}px" aria-hidden="true">
  {#each frames as cells, i (i)}
    <svg class="f{i}" viewBox="0 0 7 9" shape-rendering="crispEdges">
      {#each cells as p (p.x * 9 + p.y)}<rect x={p.x} y={p.y} width="1" height="1" fill={FLAME_COLORS[p.c]} />{/each}
    </svg>
  {/each}
</span>

<style>
  .flame {
    position: relative;
    display: inline-block;
    vertical-align: -2px;
  }
  svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }
  .f1 {
    animation: flicker 0.5s steps(1) infinite;
  }
  @keyframes flicker {
    0% { opacity: 0; }
    50% { opacity: 1; }
  }
  @media (prefers-reduced-motion: reduce) {
    .f1 { display: none; }
  }
</style>

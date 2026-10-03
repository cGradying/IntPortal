<script lang="ts">
  // Isko, the student: you. Waves or cheers on a slow loop; Reduce Motion
  // keeps him standing.
  import { ISKO, ISKO_CHEER, ISKO_COLORS, ISKO_WAVE } from "./sprites";

  type Pose = "stand" | "wave" | "cheer";
  let { size = 84, pose = "wave" }: { size?: number; pose?: Pose } = $props();
  const cells = (rows: readonly string[]) => rows.flatMap((row, y) => [...row].map((c, x) => ({ x, y, c })).filter((p) => p.c !== "."));
  const stand = cells(ISKO);
  const moving = $derived(pose === "cheer" ? cells(ISKO_CHEER) : cells(ISKO_WAVE));
  const wave = $derived(pose !== "stand");
</script>

<span class="isko" class:wave style:width="{size * 0.7}px" style:height="{size}px" role="img" aria-label="Isko, a pixel student">
  <svg class="a" viewBox="0 0 14 20" shape-rendering="crispEdges">
    {#each stand as p (p.x * 20 + p.y)}<rect x={p.x} y={p.y} width="1" height="1" fill={ISKO_COLORS[p.c]} />{/each}
  </svg>
  {#if wave}
    <svg class="b" viewBox="0 0 14 20" shape-rendering="crispEdges">
      {#each moving as p (p.x * 20 + p.y)}<rect x={p.x} y={p.y} width="1" height="1" fill={ISKO_COLORS[p.c]} />{/each}
    </svg>
  {/if}
</span>

<style>
  .isko {
    position: relative;
    display: inline-block;
  }
  svg {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
  }
  .wave .b {
    animation: wave 2.4s steps(1) infinite;
  }
  .wave .a {
    animation: stand 2.4s steps(1) infinite;
  }
  @keyframes stand {
    0%, 60% { opacity: 1; }
    65%, 75% { opacity: 0; }
    80%, 85% { opacity: 1; }
    90%, 100% { opacity: 0; }
  }
  @keyframes wave {
    0%, 60% { opacity: 0; }
    65%, 75% { opacity: 1; }
    80%, 85% { opacity: 0; }
    90%, 100% { opacity: 1; }
  }
  @media (prefers-reduced-motion: reduce) {
    .wave .a { animation: none; opacity: 1; }
    .wave .b { display: none; }
  }
</style>

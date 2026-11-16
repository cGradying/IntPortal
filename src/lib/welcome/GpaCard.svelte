<script lang="ts">
  // The Grades demo (spec 049 C8): the GPA line draws itself across four sample terms.
  import PixelNum from "../PixelNum.svelte";
  import { plot, spoken } from "../gpaTrend";
  import { TERMS } from "./intro";

  const trend = plot(TERMS);
</script>

<div class="gpa" role="img" aria-label="Sample: {spoken(TERMS)}">
  <span class="num"><PixelNum text={TERMS.at(-1)!.v.toFixed(2)} size={3} /><small>GPA, up from {TERMS.at(-2)!.v.toFixed(2)}</small></span>
  <svg class="trend" viewBox="0 0 100 40" aria-hidden="true">
    {#each trend.guides as g (g.v)}<line class="guide" x1="0" x2="100" y1={g.y} y2={g.y} />{/each}
    <polyline pathLength="1" points={trend.points.map((q) => `${q.x},${q.y}`).join(" ")} />
    {#each trend.points as q, k (k)}<rect x={q.x - 2} y={q.y - 2} width="4" height="4" style:animation-delay="{0.5 + k * 0.12}s" />{/each}
  </svg>
</div>

<style>
  .gpa {
    display: flex;
    align-items: center;
    gap: 14px;
    padding: 12px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.05);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
    color: var(--cream);
  }
  .num {
    display: grid;
    gap: 4px;
  }
  .num small {
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
    white-space: nowrap;
  }
  .trend {
    flex: 1;
    min-width: 0;
    height: 40px;
  }
  .trend polyline {
    fill: none;
    stroke: var(--portal-accent);
    stroke-width: 1.4;
    stroke-linejoin: round;
    stroke-dasharray: 1;
    stroke-dashoffset: 1;
    animation: draw calc(var(--t-hero) * 2) var(--ease) forwards;
    animation-delay: 200ms;
  }
  @keyframes draw {
    to {
      stroke-dashoffset: 0;
    }
  }
  .guide {
    stroke: rgb(244 236 216 / 0.12);
    stroke-width: 0.5;
    stroke-dasharray: 1 2;
  }
  .trend rect {
    fill: var(--cream);
    opacity: 0;
    animation: dot var(--t-move) var(--ease) forwards;
  }
  @keyframes dot {
    to {
      opacity: 1;
    }
  }
</style>

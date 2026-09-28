<script lang="ts">
  // The sync moment's jeepney. Driving: it bobs while the road scrolls under
  // it. Arrived: parked, with a gold check. Stalled: smoke puffs.
  import { JEEP, JEEP_COLORS } from "./sprites";

  let { mode = "drive" }: { mode?: "drive" | "arrived" | "stalled" } = $props();
  const cells = JEEP.flatMap((row, y) => [...row].map((c, x) => ({ x, y, c })).filter((p) => p.c !== "."));
</script>

<span class="lane" data-mode={mode} aria-hidden="true">
  <svg class="jeep" viewBox="0 0 18 7" shape-rendering="crispEdges">
    {#each cells as p (p.x * 7 + p.y)}
      <rect class:wheel={p.y === 6} x={p.x} y={p.y} width="1" height="1" fill={JEEP_COLORS[p.c]} />
    {/each}
  </svg>
  {#if mode === "arrived"}
    <svg class="check" viewBox="0 0 7 5" shape-rendering="crispEdges"><path d="M0 2h1v1h1v1h1V3h1V2h1V1h1V0h1v1H6v1H5v1H4v1H3v1H2V4H1V3H0z" fill="#f5b227" /></svg>
  {/if}
  {#if mode === "stalled"}
    <span class="puff a"></span><span class="puff b"></span><span class="puff c"></span>
  {/if}
</span>

<style>
  .lane {
    position: relative;
    display: block;
    width: 46px;
    height: 20px;
    flex: none;
    overflow: hidden;
  }
  .lane::after {
    content: "";
    position: absolute;
    left: 0;
    right: 0;
    bottom: 1px;
    height: 1px;
    background: repeating-linear-gradient(90deg, rgba(242, 193, 78, 0.55) 0 4px, transparent 4px 8px);
  }
  [data-mode="drive"]::after {
    animation: road 0.4s steps(4) infinite;
  }
  @keyframes road {
    to { background-position: -8px 0; }
  }
  .jeep {
    position: absolute;
    left: 5px;
    bottom: 2px;
    width: 36px;
    height: 14px;
  }
  [data-mode="drive"] .jeep {
    animation: bob 0.3s steps(2) infinite;
  }
  @keyframes bob {
    50% { transform: translateY(-1px); }
  }
  [data-mode="arrived"] .jeep {
    animation: park 0.5s steps(5) both;
  }
  @keyframes park {
    from { transform: translateX(-20px); }
  }
  [data-mode="stalled"] .jeep {
    filter: saturate(0.4) brightness(0.8);
    animation: shudder 0.18s steps(2) 4;
  }
  @keyframes shudder {
    50% { transform: translateX(1px); }
  }
  .check {
    position: absolute;
    right: 0;
    top: 0;
    width: 10px;
    height: 7px;
    animation: pop 0.4s steps(3) both 0.4s;
  }
  @keyframes pop {
    from { transform: translateY(4px); opacity: 0; }
  }
  .puff {
    position: absolute;
    width: 4px;
    height: 4px;
    background: #8d8d95;
    animation: smoke 1.2s steps(6) infinite;
  }
  .puff.a { left: 2px; bottom: 6px; }
  .puff.b { left: 0; bottom: 9px; animation-delay: 0.4s; }
  .puff.c { left: 4px; bottom: 12px; animation-delay: 0.8s; }
  @keyframes smoke {
    from { opacity: 0.9; transform: translate(0, 0) scale(1); }
    to { opacity: 0; transform: translate(-6px, -8px) scale(1.6); }
  }
</style>

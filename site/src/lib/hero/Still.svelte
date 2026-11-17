<script lang="ts">
  // Spec 057 C2: the open portal as a still, drawn from the same layout and
  // swirl as the 3D scene. It is the first paint, and stays where 3D can't run.
  import { COLS, RAMP, ROWS, TONES, frameTiles, swirlAt } from "./portal";

  const tiles = frameTiles();
  const MW = 16;
  const MH = 24;
  const mouth: { x: number; y: number; c: string }[] = [];
  for (let y = 0; y < MH; y++)
    for (let x = 0; x < MW; x++) mouth.push({ x, y, c: RAMP[swirlAt(x / (MW - 1), y / (MH - 1), x, y)] });
  const cw = (COLS - 4) / MW;
  const ch = (ROWS - 4) / MH;
</script>

<svg viewBox="0 0 {COLS} {ROWS}" shape-rendering="crispEdges" aria-hidden="true" preserveAspectRatio="xMidYMid meet">
  {#each mouth as p (p.x + "," + p.y)}
    <rect x={2 + p.x * cw} y={ROWS - 2 - (p.y + 1) * ch} width={cw} height={ch} fill={p.c} />
  {/each}
  {#each tiles as t (t.x + "," + t.y)}
    <rect x={t.x + 0.1} y={ROWS - 1 - t.y + 0.1} width="0.8" height="0.8" fill={TONES[t.tone]} />
  {/each}
</svg>

<style>
  svg {
    display: block;
    width: 100%;
    height: 100%;
  }
</style>

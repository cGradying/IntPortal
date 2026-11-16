<script lang="ts">
  // A small tile portal for the wordmark: 7 by 9 tiles of obsidian round the
  // SIS ramp, drawn as crisp rects (DESIGN.md, the tile portal).
  let { size = 3 }: { size?: number } = $props();
  const W = 7;
  const H = 9;
  const TONES = ["#1a1622", "#241f2e", "#2f2939", "#3c3548"];
  const RAMP = ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"];
  const cells: { x: number; y: number; c: string }[] = [];
  for (let y = 0; y < H; y++)
    for (let x = 0; x < W; x++) {
      const edge = x === 0 || y === 0 || x === W - 1 || y === H - 1;
      if (edge) cells.push({ x, y, c: TONES[(x * 3 + y * 5) % 4] });
      else cells.push({ x, y, c: RAMP[Math.min(4, Math.max(0, 4 - Math.round(Math.hypot(x - 3, y - 5.5) * 1.2)))] });
    }
</script>

<svg width={W * size} height={H * size} viewBox="0 0 {W} {H}" shape-rendering="crispEdges" aria-hidden="true">
  {#each cells as c (c.x + "," + c.y)}<rect x={c.x} y={c.y} width="1" height="1" fill={c.c} />{/each}
</svg>

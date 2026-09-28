<script lang="ts" module>
  // Small pixel scenes for empty states, drawn as rects on a 40x22 grid.
  // [x, y, w, h, colour, part?]; a part names a group that animates.
  type R = [number, number, number, number, string, string?];

  const ground: R[] = [
    [0, 18, 40, 4, "#6b8f4e"],
    [0, 18, 40, 1, "#7fa55c"],
    [3, 17, 1, 1, "#577a3f"],
    [12, 17, 1, 1, "#577a3f"],
    [25, 17, 1, 1, "#577a3f"],
    [36, 17, 1, 1, "#577a3f"],
    [7, 20, 2, 1, "#577a3f"],
    [30, 19, 2, 1, "#577a3f"],
  ];

  function palm(x: number, flip: boolean): R[] {
    const f = (dx: number, w = 1) => (flip ? x + 1 - dx - (w - 1) : x + dx);
    return [
      [x, 6, 2, 12, "#8a5a3b"],
      [flip ? x : x + 1, 6, 1, 12, "#6d452c"],
      [x, 9, 2, 1, "#6d452c"],
      [x, 13, 2, 1, "#6d452c"],
      [f(-4, 10), 3, 10, 2, "#3f8a4a"],
      [f(-5, 3), 5, 3, 1, "#2f6b3a"],
      [f(4, 3), 5, 3, 1, "#2f6b3a"],
      [f(-6, 1), 6, 1, 1, "#2f6b3a"],
      [f(6, 1), 6, 1, 1, "#2f6b3a"],
      [f(-2, 5), 2, 5, 1, "#6fbf6a"],
      [f(0, 2), 5, 2, 1, "#3f8a4a"],
    ];
  }

  export const SCENES: Record<string, R[]> = {
    // A free day: a hammock between two palms, a book left on it, a lazy sun.
    hammock: [
      [18, 1, 4, 4, "#ffd166", "sun"],
      [17, 2, 6, 2, "#ffd166", "sun"],
      [19, 2, 2, 2, "#fff1b8", "sun"],
      ...ground,
      ...palm(5, false),
      ...palm(33, true),
      [12, 17, 16, 1, "rgba(0,0,0,.18)"],
      [7, 8, 3, 1, "var(--gold)", "sway"],
      [10, 9, 3, 1, "var(--gold)", "sway"],
      [13, 10, 14, 1, "var(--gold)", "sway"],
      [13, 11, 14, 1, "#b8860b", "sway"],
      [27, 9, 3, 1, "var(--gold)", "sway"],
      [30, 8, 3, 1, "var(--gold)", "sway"],
      [18, 9, 4, 1, "#b3202a", "sway"],
      [19, 8, 2, 1, "#e9e4d6", "sway"],
    ],
    // No grades yet: a sleeping mailbox, flag down.
    mailbox: [
      ...ground,
      [18, 11, 3, 7, "#8a5a3b"],
      [20, 11, 1, 7, "#6d452c"],
      [14, 3, 11, 1, "#7a1128"],
      [13, 4, 13, 7, "#7a1128"],
      [14, 4, 11, 1, "#9b1d36"],
      [24, 4, 2, 7, "#560a19"],
      [15, 7, 6, 1, "#3a0710"],
      [13, 10, 13, 1, "#560a19"],
      [26, 6, 1, 5, "#c7ccd3"],
      [27, 9, 3, 2, "#f2c14e"],
      [29, 1, 2, 1, "var(--ink-3)", "zz"],
      [30, 2, 1, 1, "var(--ink-3)", "zz"],
      [29, 3, 2, 1, "var(--ink-3)", "zz"],
      [33, 0, 1, 1, "var(--ink-3)", "zz2"],
      [32, 1, 1, 1, "var(--ink-3)", "zz2"],
    ],
  };
</script>

<script lang="ts">
  let { name, label }: { name: keyof typeof SCENES; label: string } = $props();
</script>

<svg viewBox="0 0 40 22" shape-rendering="crispEdges" role="img" aria-label={label}>
  {#each SCENES[name] as [x, y, w, h, fill, part], i (i)}
    <rect {x} {y} width={w} height={h} {fill} class={part} />
  {/each}
</svg>

<style>
  svg {
    width: 160px;
    height: 88px;
  }
  .sun {
    animation: bob 3s steps(2) infinite;
  }
  .sway {
    animation: sway 2.4s steps(2) infinite;
  }
  .zz {
    animation: float 2s steps(4) infinite;
  }
  .zz2 {
    animation: float 2s steps(4) infinite 1s;
  }
  @keyframes bob {
    50% { transform: translateY(1px); }
  }
  @keyframes sway {
    50% { transform: translateY(0.5px); }
  }
  @keyframes float {
    from { opacity: 0; transform: translateY(2px); }
    50% { opacity: 1; }
    to { opacity: 0; transform: translateY(-2px); }
  }
</style>

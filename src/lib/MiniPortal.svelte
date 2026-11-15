<script lang="ts">
  // A portal at icon size: an obsidian ring round the school's ramp, darkest at the top, its accent
  // as the keystone. The plaque, the portal wall and its rows all draw a school this way.
  import type { Portal } from "./api";

  let { portal }: { portal: Pick<Portal, "theme"> } = $props();
</script>

<svg viewBox="0 0 5 7" aria-hidden="true" shape-rendering="crispEdges">
  <rect width="5" height="7" style="fill: var(--obsidian)" />
  {#each portal.theme.ramp.slice(1) as c, i (i)}<rect x="1" y={1 + i * 1.25} width="3" height="1.25" fill={c} />{/each}
  <rect x="2" y="0" width="1" height="1" fill={portal.theme.accent} />
</svg>

<style>
  svg {
    display: block;
    width: 100%;
    height: 100%;
  }
</style>

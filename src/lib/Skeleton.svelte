<script lang="ts">
  // Grey rows standing in for content that's on its way, with a stepped
  // pixel shimmer; still under Reduce Motion.
  let { rows = 3, height = 56 }: { rows?: number; height?: number } = $props();
</script>

<div class="skeleton" role="status" aria-label="Loading">
  {#each { length: rows } as _, i (i)}<i style:height="{height}px"></i>{/each}
</div>

<style>
  .skeleton {
    display: grid;
    gap: 8px;
  }
  i {
    display: block;
    border-radius: 10px;
    background: linear-gradient(90deg, var(--sunk) 0 40%, var(--edge) 50%, var(--sunk) 60% 100%) 0 0 / 300% 100%;
    animation: shimmer 1.4s steps(8) infinite;
  }
  i:nth-child(2n) {
    width: 86%;
  }
  @keyframes shimmer {
    from { background-position: 100% 0; }
    to { background-position: 0 0; }
  }
  @media (prefers-reduced-motion: reduce) {
    i {
      animation: none;
    }
  }
</style>

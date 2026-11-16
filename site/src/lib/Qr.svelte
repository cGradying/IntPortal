<script lang="ts">
  import qrcode from "qrcode-generator";
  let { text, label }: { text: string; label: string } = $props();
  const cells = $derived.by(() => {
    const q = qrcode(0, "M");
    q.addData(text);
    q.make();
    const n = q.getModuleCount();
    const out: [number, number][] = [];
    for (let r = 0; r < n; r++) for (let c = 0; c < n; c++) if (q.isDark(r, c)) out.push([c, r]);
    return { n, out };
  });
</script>

<figure>
  <svg viewBox="-2 -2 {cells.n + 4} {cells.n + 4}" shape-rendering="crispEdges" role="img" aria-label={label}>
    <rect x="-2" y="-2" width={cells.n + 4} height={cells.n + 4} fill="#f4ecd8" />
    {#each cells.out as [x, y] (x * 1000 + y)}<rect {x} {y} width="1" height="1" fill="#0b0710" />{/each}
  </svg>
  <figcaption>{label}</figcaption>
</figure>

<style>
  figure {
    margin: 0;
    display: grid;
    gap: 8px;
    justify-items: center;
  }
  svg {
    width: 132px;
    height: 132px;
    border-radius: 6px;
  }
  figcaption {
    font-size: 0.82rem;
    color: var(--site-ink-3);
    text-align: center;
    max-width: 16ch;
  }
</style>

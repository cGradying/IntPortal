<script lang="ts">
  // Stand-in until the UI engineer's changelog lands (spec 057 C12); theirs replaces this file.
  import { releaseId } from "$lib/content/changelog";
  let { data } = $props();
</script>

<svelte:head><title>Changelog · IntPortal</title></svelte:head>
<h1>Changelog</h1>
{#each data.releases as r (r.version)}
  <h2 id={releaseId(r.version)}>{r.version} · {r.date}</h2>
  {#if r.intro}<p>{r.intro}</p>{/if}
  <ul>{#each r.items as item, i (i)}<li>{item}</li>{/each}</ul>
{/each}

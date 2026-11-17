<script lang="ts">
  // Stand-in until the UI engineer's feature page lands (spec 057 C10); theirs replaces this file.
  let { data } = $props();
</script>

<svelte:head><title>{data.feature.name} · IntPortal</title><meta name="description" content={data.feature.line} /></svelte:head>
<h1>{data.feature.name}</h1>
<p>{data.group.name}</p>
{#each data.feature.body as p, i (i)}<p>{p}</p>{/each}
<ol>{#each data.feature.steps as s, i (i)}<li>{s}</li>{/each}</ol>
{#if data.prev}<a href="/features/{data.prev.slug}">{data.prev.name}</a>{/if}
{#if data.next}<a href="/features/{data.next.slug}">{data.next.name}</a>{/if}

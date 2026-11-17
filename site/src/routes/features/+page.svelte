<script lang="ts">
  // Stand-in until the UI engineer's directory lands (spec 057 C9); theirs replaces this file.
  let { data } = $props();
</script>

<svelte:head><title>Features · IntPortal</title></svelte:head>
<h1>Everything in IntPortal</h1>
{#each data.groups as g (g.id)}
  <h2>{g.name}</h2>
  <ul>
    {#each data.features.filter((f) => f.group === g.id) as f (f.slug)}<li><a href="/features/{f.slug}">{f.name}</a>: {f.line}</li>{/each}
  </ul>
{/each}

<script lang="ts">
  // Stand-in until the UI engineer's roadmap lands (spec 057 C13); theirs replaces this file.
  let { data } = $props();
</script>

<svelte:head><title>Roadmap · IntPortal</title></svelte:head>
<h1>Roadmap</h1>
{#each ["shipped", "building", "next", "later"] as lane (lane)}
  <h2>{lane}</h2>
  <ul>{#each data.items.filter((i) => i.lane === lane) as i (i.href)}<li><a href={i.href}>{i.title}</a>: {i.line}{i.date ? ` (${i.date})` : ""}</li>{/each}</ul>
{/each}

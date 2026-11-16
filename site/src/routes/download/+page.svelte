<script lang="ts">
  import Downloads from "$lib/Downloads.svelte";
  import { PLATFORMS } from "$lib/platforms";
  let { data } = $props();
</script>

<svelte:head>
  <title>Download IntPortal</title>
  <meta name="description" content="IntPortal for Android, iPhone, Mac, Windows, Linux and the browser, with install help for each." />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<section class="wrap">
  <h1>Download</h1>
  <p class="lede">The newest IntPortal for each device. Updates install over the old version and keep your data.</p>
  <Downloads release={data.release} />
  <h2>Installing it</h2>
  {#each PLATFORMS as p (p.id)}
    <h3>{p.name}</h3>
    <ol>{#each p.steps as s (s)}<li>{s}</li>{/each}</ol>
  {/each}
</section>

<style>
  section {
    padding-top: clamp(32px, 7vh, 80px);
  }
  h1 {
    font-size: clamp(2.6rem, 7vw, 4.4rem);
    letter-spacing: -0.035em;
  }
  .lede {
    margin: 16px 0 40px;
    max-width: 52ch;
    font-size: 1.2rem;
    color: var(--site-ink-2);
  }
  h2 {
    font-size: clamp(1.8rem, 4vw, 2.6rem);
    margin: 96px 0 8px;
  }
  h3 {
    font-size: 1.2rem;
    margin: 36px 0 10px;
  }
  ol {
    max-width: 65ch;
    margin: 0;
    padding-left: 1.3em;
    color: var(--site-ink-2);
    line-height: 1.6;
  }
  li + li {
    margin-top: 6px;
  }
</style>

<script lang="ts">
  import { page } from "$app/state";
  import { browser } from "$app/environment";
  import Lar from "$app_lib/lar/Lar.svelte";
  // 058 C8: offline, a page that wasn't saved says so instead of "not found".
  const offline = browser && !navigator.onLine;
</script>

<svelte:head><title>{offline ? "Offline" : page.status === 404 ? "Not found" : "Something went wrong"} · IntPortal</title></svelte:head>

<section class="wrap">
  <Lar size={5} state="idle" mood="wow" label="LAR, surprised" />
  {#if offline}
    <h1>You're offline.</h1>
    <p>This page wasn't saved yet. Pages you've opened before still work.</p>
    <a class="gold" href="/help">Open Help</a>
  {:else}
    <h1>{page.status === 404 ? "Walang ganitong page." : "Something went wrong."}</h1>
    <p>{page.status === 404 ? "LAR looked on both sides of the portal. It isn't here." : "Try again in a bit."}</p>
    <a class="gold" href="/">Back to IntPortal</a>
  {/if}
</section>

<style>
  section {
    padding-top: clamp(48px, 12vh, 140px);
    display: grid;
    justify-items: start;
    gap: 18px;
  }
  h1 {
    font-size: clamp(2.2rem, 6vw, 3.6rem);
  }
  p {
    color: var(--site-ink-2);
    font-size: 1.15rem;
  }
</style>

<script lang="ts">
  import { page } from "$app/state";
  import { browser } from "$app/environment";
  import Lar from "$app_lib/lar/Lar.svelte";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  // 058 C8: offline, a page that wasn't saved says so instead of "not found".
  const offline = browser && !navigator.onLine;
  // 060 C19: search with the words of the address that wasn't found.
  const find = () => {
    const q = decodeURIComponent(page.url.pathname.split("/").filter(Boolean).pop() ?? "").replace(/[-_]+/g, " ");
    dispatchEvent(new CustomEvent("site-search", { detail: { q } }));
  };
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
    <div class="acts">
      <a class="gold" href="/">Back to IntPortal</a>
      <button class="ghost" onclick={find}><PixelIcon name="search" size={16} />Search the site</button>
    </div>
    <nav class="chips" aria-label="Or go to">
      <a href="/features">Features</a>
      <a href="/help">Help</a>
      <a href="/changelog">What's new</a>
    </nav>
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
  .acts,
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }
  .ghost {
    gap: 10px;
  }
  .chips {
    gap: 6px;
  }
  .chips a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 14px;
    border-radius: var(--radius);
    background: rgba(244, 236, 216, 0.05);
    color: var(--site-ink-2);
    font-weight: 600;
    text-decoration: none;
  }
  .chips a:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.09);
  }
</style>

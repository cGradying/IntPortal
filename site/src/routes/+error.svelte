<script lang="ts">
  import { page } from "$app/state";
  import Lar from "$app_lib/lar/Lar.svelte";
</script>

<svelte:head><title>Not found · IntPortal</title></svelte:head>

<section class="wrap">
  <Lar size={5} state="idle" mood="wow" label="LAR, surprised" />
  <h1>{page.status === 404 ? "Walang ganitong page." : "Something went wrong."}</h1>
  <p>{page.status === 404 ? "LAR looked on both sides of the portal. It isn't here." : "Try again in a bit."}</p>
  <a class="gold" href="/">Back to IntPortal</a>
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

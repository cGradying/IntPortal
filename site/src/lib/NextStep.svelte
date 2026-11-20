<script lang="ts">
  // 060 C5: inner pages end on one next step: this device's download, or the browser.
  // iPhones and unknown devices get /download, where the steps are.
  import { onMount } from "svelte";
  import { page } from "$app/state";
  import { device } from "./device";
  import { firstFor, PLATFORMS } from "./platforms";
  import type { Release } from "./releases";

  let get = $state<{ href: string; name?: string }>({ href: "/download" });
  onMount(() => {
    const id = firstFor(device(navigator.userAgent, navigator.maxTouchPoints));
    const file = (page.data.release as Release | null)?.assets.find((a) => a.platform === id);
    if (file) get = { href: file.url, name: PLATFORMS.find((p) => p.id === id)?.name };
  });
</script>

<section class="next" aria-labelledby="next-h">
  <div>
    <h2 id="next-h">Have it on your phone</h2>
    <p>Free, with no IntPortal account. Your login only goes to your school.</p>
  </div>
  <div class="go">
    <div class="links">
      <a class="gold" href={get.href}>Get IntPortal</a>
      <a class="ghost" href="/try">Try it in your browser</a>
    </div>
    {#if get.name}<p class="fine">For {get.name}. Other devices are on <a href="/download">Download</a>.</p>{/if}
  </div>
</section>

<style>
  .next {
    display: flex;
    flex-wrap: wrap;
    align-items: end;
    justify-content: space-between;
    gap: 24px 48px;
    margin-top: clamp(72px, 10vh, 120px);
    padding: clamp(28px, 5vw, 56px);
    background: var(--void-2, #0e0a12);
    box-shadow: inset 0 0 0 1px var(--site-line);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  h2 {
    font-size: clamp(1.8rem, 4vw, 2.6rem);
  }
  .next > div > p {
    margin-top: 14px;
    max-width: 48ch;
    color: var(--site-ink-2);
    line-height: 1.6;
  }
  .links {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
  }
  .go .fine {
    margin-top: 12px;
  }
</style>

<script lang="ts">
  // The reel (spec 054). Its files land in static/reel/ when it is rendered;
  // until then the page says so instead of showing a broken player.
  import { onMount } from "svelte";
  const files = import.meta.glob("/static/reel/*", { query: "?url", import: "default" });
  const has = (name: string) => Object.keys(files).includes(`/static/reel/${name}`);
  const ready = has("intportal-16x9.mp4") && has("intportal-9x16.mp4");
  let tall = $state(false);
  onMount(() => (tall = matchMedia("(max-aspect-ratio: 4/5)").matches));
</script>

<svelte:head>
  <title>The reel · IntPortal</title>
  <meta name="description" content="IntPortal in under a minute: the portal, LAR, your day, and where to get it." />
</svelte:head>

<section class="wrap">
  <h1>The reel</h1>
  <p class="lede">IntPortal in under a minute: the portal opens, LAR comes through, and your day is on your phone.</p>
  {#if ready}
    <!-- svelte-ignore a11y_media_has_caption: the captions track is below -->
    <video class:tall controls playsinline preload="metadata" poster={tall ? "/reel/poster-9x16.webp" : "/reel/poster-16x9.webp"} src={tall ? "/reel/intportal-9x16.mp4" : "/reel/intportal-16x9.mp4"}>
      <track kind="captions" src="/reel/captions.vtt" srclang="en" label="English" default />
    </video>
    <p class="fine files">
      Download: <a href="/reel/intportal-16x9.mp4" download>16:9</a> · <a href="/reel/intportal-9x16.mp4" download>9:16, for stories</a>
    </p>
  {:else}
    <div class="soon">
      <p>The reel isn't out yet. It comes with a later release.</p>
      <a class="gold" href="/download">Get the app meanwhile</a>
    </div>
  {/if}
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
  video {
    display: block;
    width: 100%;
    aspect-ratio: 16 / 9;
    border-radius: 14px;
    background: #000;
  }
  video.tall {
    width: min(100%, 420px);
    aspect-ratio: 9 / 16;
    margin-inline: auto;
  }
  .files {
    margin-top: 14px;
  }
  .soon {
    display: grid;
    justify-items: start;
    gap: 20px;
    padding: 48px 0;
    font-size: 1.2rem;
    color: var(--site-ink-2);
  }
</style>

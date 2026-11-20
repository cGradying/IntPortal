<script lang="ts">
  // 057 C14: the owner alone, from their public GitHub profile and nothing else.
  import Lar from "$app_lib/lar/Lar.svelte";
  import NextStep from "$lib/NextStep.svelte";
  import PixelPortal from "$lib/PixelPortal.svelte";
  import { REPO_URL } from "$lib/releases";

  const PROFILE = "https://github.com/cGradying";
  const roles = ["AI Researcher and Enthusiast", "Aspiring AI Data Engineer", "Data Analyst", "Software and Game Engineer", "Fullstack Developer"];
  const stack = [
    ["Rust", "The core: signing in, reading the portal, the encrypted store, the study scheduler, and the portal and dive art, compiled to WebAssembly."],
    ["Svelte 5", "Every screen, the same on every platform."],
    ["Tauri 2", "One app for iPhone, Android, Mac, Windows and Linux."],
    ["SQLCipher", "Your data, encrypted on the device."],
    ["llama.cpp", "LAR's assistant, running on the phone itself."],
    ["WebAssembly", "The Rust core in your browser, for Try it."],
  ];
</script>

<svelte:head>
  <title>About · IntPortal</title>
  <meta name="description" content="IntPortal is made by one student at the Polytechnic University of the Philippines: cGradying." />
  <meta property="og:title" content="About · IntPortal" />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<div class="wrap">
  <div class="intro page-head">
    <div class="copy">
      <h1>Made by one student</h1>
      <p class="lede">
        IntPortal is built by <a href={PROFILE} rel="noopener">cGradying</a>, a student at the Polytechnic University of the Philippines, as an
        independent project. It isn't made by or for any school.
      </p>
      <ul class="roles" aria-label="cGradying, in their own words">
        {#each roles as r (r)}<li class="pixel">{r}</li>{/each}
      </ul>
      <div class="actions">
        <a class="ghost" href={PROFILE} rel="noopener">cGradying on GitHub</a>
        <a class="ghost" href={REPO_URL} rel="noopener">IntPortal's source</a>
      </div>
    </div>
    <figure class="card" aria-label="LAR beside a small tile portal">
      <div class="scene">
        <PixelPortal size={9} />
        <div class="lar"><Lar size={5} gesture="wave" label="LAR waving" /></div>
      </div>
      <figcaption class="pixel">cGradying · PUP</figcaption>
    </figure>
  </div>

  <section aria-labelledby="what-h">
    <h2 id="what-h">What it's for</h2>
    <p>
      Students check their schedule and grades many times a day, often on weak data, while the portal itself is slow or down. IntPortal signs in once,
      keeps everything on the phone, and adds what the portal never had: a week you can mark up, one list of what's due, notes, decks that
      remember for you, and LAR, who gives one nudge at a time.
    </p>
  </section>

  <section aria-labelledby="how-h">
    <h2 id="how-h">How it's built</h2>
    <dl>
      {#each stack as [name, what] (name)}
        <div><dt>{name}</dt><dd>{what}</dd></div>
      {/each}
    </dl>
    <p class="fine after">Every change starts as a written spec and lands as a reviewed pull request. All of it is public on <a href={REPO_URL} rel="noopener">GitHub</a>, and what's next is on the <a href="/roadmap">roadmap</a>.</p>
  </section>

  <section aria-labelledby="talk-h">
    <h2 id="talk-h">Say something</h2>
    <p>Found a bug, or want your school next? <a href="{REPO_URL}/issues" rel="noopener">Open an issue</a> on GitHub.</p>
  </section>

  <NextStep />
</div>

<style>
  .intro {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: clamp(32px, 6vw, 96px);
    align-items: center;
  }
  .lede a {
    color: var(--site-ink);
    font-weight: 600;
  }
  .roles {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin: 24px 0 0;
    padding: 0;
    list-style: none;
  }
  .roles li {
    padding: 6px 10px;
    font-size: 0.78rem;
    color: var(--site-ink-2);
    background: rgba(244, 236, 216, 0.06);
    border-radius: 3px;
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    margin-top: 28px;
  }
  .card {
    margin: 0;
    /* LAR's canvas is wider than he is (room for his mitts); keep it in the card. */
    overflow: hidden;
    padding: 28px 28px 18px;
    background:
      radial-gradient(rgba(245, 178, 39, 0.08) 1px, transparent 1.5px) 0 0 / 14px 14px,
      radial-gradient(circle at 50% 45%, rgba(148, 28, 48, 0.3), transparent 70%),
      var(--void-3);
    box-shadow: inset 0 0 0 3px var(--slab-edge);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  .scene {
    display: flex;
    align-items: flex-end;
    justify-content: center;
  }
  .lar {
    margin-left: -10px;
  }
  figcaption {
    margin-top: 14px;
    text-align: center;
    font-size: 0.8rem;
    color: var(--site-ink-3);
  }
  section {
    margin-top: clamp(72px, 10vh, 112px);
    max-width: 70ch;
  }
  h2 {
    font-size: clamp(1.8rem, 4vw, 2.6rem);
    margin-bottom: 18px;
  }
  section > p {
    font-size: 1.15rem;
    line-height: 1.65;
    color: var(--site-ink-2);
  }
  dl {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 280px), 1fr));
    gap: 28px 40px;
    margin: 8px 0 0;
  }
  dt {
    font-family: var(--site-display);
    font-weight: 700;
    font-size: 1.15rem;
  }
  dd {
    margin: 6px 0 0;
    color: var(--site-ink-2);
    line-height: 1.55;
  }
  .after {
    margin-top: 32px;
  }
  @media (max-width: 760px) {
    .intro {
      grid-template-columns: 1fr;
    }
    .card {
      justify-self: start;
    }
  }
</style>

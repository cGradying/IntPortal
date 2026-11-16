<svelte:head>
  <title>Try IntPortal in your browser</title>
  <meta name="description" content="The whole IntPortal app on sample data, in any browser. Nothing is installed or kept." />
</svelte:head>

<section class="wrap">
  <h1>Try it in your browser</h1>
  <p class="lede">This is IntPortal on demo data. Nothing you change is kept.</p>
  <p class="soon">The browser version opens here with IntPortal 0.4. Until then, Look around on the app's sign-in page shows the same sample week.</p>
  <a class="gold" href="/download">Get the app</a>
</section>

<style>
  section {
    padding-top: clamp(32px, 7vh, 80px);
    display: grid;
    justify-items: start;
    gap: 20px;
  }
  h1 {
    font-size: clamp(2.6rem, 7vw, 4.4rem);
    letter-spacing: -0.035em;
  }
  .lede,
  .soon {
    max-width: 52ch;
    font-size: 1.2rem;
    color: var(--site-ink-2);
  }
</style>

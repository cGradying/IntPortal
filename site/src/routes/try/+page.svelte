<script lang="ts">
  // Look around in any browser (spec 052): the app itself, built for the
  // browser by scripts/web.sh into /app, on demo data. A phone-sized frame on a
  // wide screen (C6); on a phone it fills the screen.
</script>

<svelte:head>
  <title>Try IntPortal in your browser</title>
  <meta name="description" content="The whole IntPortal app on sample data, in any browser. Nothing is installed, sent or kept." />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<section class="wrap try">
  <div class="copy">
    <h1>Try it in your browser</h1>
    <p class="lede">This is IntPortal on demo data. Nothing you change is kept.</p>
    <p class="fine">It's the real app: the same screens and the same Rust core, running in this page. Signing in to your school, reminders, the camera and the assistant need the app on your phone.</p>
    <div class="actions">
      <a class="gold" href="/download">Get the app</a>
      <a class="ghost" href="/app/" target="_blank" rel="noopener">Open it full screen</a>
    </div>
  </div>
  <div class="frame">
    <iframe src="/app/" title="IntPortal, running on demo data" allow="fullscreen"></iframe>
  </div>
</section>

<style>
  .try {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: clamp(32px, 6vw, 96px);
    padding-top: clamp(24px, 5vh, 64px);
  }
  .copy {
    max-width: 40ch;
    display: grid;
    gap: 18px;
    justify-items: start;
  }
  h1 {
    font-size: clamp(2.4rem, 5vw, 3.8rem);
    letter-spacing: -0.035em;
  }
  .lede {
    font-size: 1.2rem;
    color: var(--site-ink-2);
  }
  .actions {
    display: flex;
    flex-wrap: wrap;
    gap: 12px;
  }
  .frame {
    flex: none;
    width: 390px;
    height: min(844px, calc(100svh - 120px));
    padding: 10px;
    border-radius: 48px;
    background: #050307;
    box-shadow: inset 0 0 0 1px rgba(244, 236, 216, 0.12), 0 40px 80px -40px rgba(0, 0, 0, 0.9), 0 0 0 1px #000;
  }
  iframe {
    display: block;
    width: 100%;
    height: 100%;
    border: 0;
    border-radius: 38px;
    background: var(--void);
  }
  @media (max-width: 860px) {
    .try {
      flex-direction: column;
      align-items: stretch;
    }
    .frame {
      width: auto;
      height: calc(100svh - 80px);
      margin-inline: calc(-1 * var(--site-gutter));
      padding: 0;
      border-radius: 0;
      box-shadow: none;
    }
    iframe {
      border-radius: 0;
    }
  }
</style>

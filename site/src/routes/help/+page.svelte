<script lang="ts">
  // 057 C11: install help, questions, fixes, and where to go next.
  import { afterNavigate } from "$app/navigation";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import Share from "$lib/Share.svelte";
  import { FAQ, FIXES } from "$lib/content/help";
  import { PLATFORMS } from "$lib/platforms";
  import { REPO_URL } from "$lib/releases";

  // 058 C5: /help#q-… opens that answer, on load and when search or a link
  // changes the hash on this page.
  function reveal() {
    const id = decodeURIComponent(location.hash.slice(1));
    const d = id.startsWith("q-") ? document.getElementById(id) : null;
    if (!(d instanceof HTMLDetailsElement)) return;
    d.open = true;
    d.scrollIntoView({ block: "start" });
  }
  afterNavigate(reveal);

  // 058 C14: print every answer, not only the open ones.
  const printAll = () => document.querySelectorAll("details").forEach((d) => (d.open = true));
</script>

<svelte:window onbeforeprint={printAll} onhashchange={reveal} />

<svelte:head>
  <title>Help · IntPortal</title>
  <meta name="description" content="Installing IntPortal on Android, iPhone, Mac, Windows and Linux, answers to common questions, and fixes for when something's wrong." />
  <meta property="og:title" content="Help · IntPortal" />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<div class="wrap page">
  <h1>Help</h1>
  <p class="lede">Installing it, the usual questions, and what to do when something's wrong. Still stuck? <a href="{REPO_URL}/issues" rel="noopener">Report a problem</a>.</p>

  <nav class="jump" aria-label="On this page">
    <a href="#install"><PixelIcon name="down" size={12} />Installing it</a>
    <a href="#questions"><PixelIcon name="down" size={12} />Questions</a>
    <a href="#fixes"><PixelIcon name="down" size={12} />Something's wrong</a>
  </nav>

  <section id="install" aria-labelledby="install-h">
    <h2 id="install-h">Installing it</h2>
    <div class="cols">
      {#each PLATFORMS as p (p.id)}
        <div class="plat">
          <h3>{p.name}</h3>
          <p class="needs pixel">{p.needs}</p>
          <ol>{#each p.steps as s (s)}<li>{s}</li>{/each}</ol>
        </div>
      {/each}
    </div>
    <p class="fine after">Every file, with its size and version, is on <a href="/download">Download</a>. No install at all: <a href="/try">try it in your browser</a>.</p>
  </section>

  <section id="questions" aria-labelledby="q-h">
    <h2 id="q-h">Questions</h2>
    {#each FAQ as h (h.id)}
      <details id={h.id}>
        <summary>{h.q}</summary>
        <p>{h.a}</p>
        <Share href="/help#{h.id}" title={h.q} />
      </details>
    {/each}
    <p class="fine after">The whole story of your data is in the <a href="/privacy">privacy policy</a>.</p>
  </section>

  <section id="fixes" aria-labelledby="fix-h">
    <h2 id="fix-h">Something's wrong</h2>
    {#each FIXES as h (h.id)}
      <details id={h.id}>
        <summary>{h.q}</summary>
        <p>{h.a}</p>
        <Share href="/help#{h.id}" title={h.q} />
      </details>
    {/each}
  </section>
</div>

<style>
  .page {
    padding-top: clamp(40px, 8vh, 88px);
  }
  h1 {
    font-size: clamp(2.4rem, 6vw, 4.2rem);
    font-weight: 800;
    letter-spacing: -0.035em;
  }
  .lede {
    margin-top: 16px;
    max-width: 58ch;
    font-size: 1.15rem;
    color: var(--site-ink-2);
    line-height: 1.55;
  }
  .jump {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 28px;
  }
  .jump a {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
    padding: 0 14px;
    border-radius: var(--radius);
    background: rgba(244, 236, 216, 0.05);
    color: var(--site-ink-2);
    font-weight: 600;
    text-decoration: none;
  }
  .jump a:hover {
    color: var(--site-ink);
  }
  section {
    margin-top: clamp(72px, 10vh, 112px);
    scroll-margin-top: 88px;
  }
  h2 {
    font-size: clamp(1.9rem, 4.4vw, 2.8rem);
    margin-bottom: 28px;
  }
  .cols {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 320px), 1fr));
    gap: 20px;
  }
  .plat {
    padding: 22px 22px 18px;
    background: var(--void-2);
    border-radius: var(--radius);
    box-shadow: inset 0 0 0 1px var(--site-line);
  }
  h3 {
    font-size: 1.3rem;
  }
  .needs {
    margin-top: 6px;
    font-size: 0.78rem;
    color: var(--site-ink-3);
  }
  .plat ol {
    margin: 16px 0 6px;
    padding-left: 1.25em;
    color: var(--site-ink-2);
    line-height: 1.55;
  }
  .plat li + li {
    margin-top: 8px;
  }
  .plat li::marker {
    color: var(--gold);
    font-weight: 700;
  }
  .after {
    margin-top: 24px;
  }
  details {
    max-width: 820px;
    box-shadow: inset 0 -1px 0 var(--site-line);
  }
  summary {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 16px;
    min-height: 60px;
    font-family: var(--site-display);
    font-weight: 600;
    font-size: 1.15rem;
    cursor: pointer;
    list-style: none;
  }
  summary::-webkit-details-marker {
    display: none;
  }
  summary::after {
    content: "";
    width: 12px;
    height: 12px;
    flex: none;
    background: linear-gradient(var(--gold), var(--gold)) center / 12px 2px no-repeat, linear-gradient(var(--gold), var(--gold)) center / 2px 12px no-repeat;
    transition: transform var(--t-move) var(--ease);
  }
  details[open] summary::after {
    transform: rotate(45deg);
  }
  details {
    scroll-margin-top: 88px;
  }
  details p {
    max-width: 65ch;
    margin: 0 0 4px;
    color: var(--site-ink-2);
    line-height: 1.6;
  }
  details :global(.share) {
    margin-bottom: 12px;
  }
  @media print {
    .jump,
    details :global(.share),
    summary::after {
      display: none;
    }
    h2 {
      margin-bottom: 12px;
    }
    .plat {
      background: none;
      box-shadow: inset 0 0 0 1px #999;
      break-inside: avoid;
    }
    details {
      break-inside: avoid;
    }
  }
</style>

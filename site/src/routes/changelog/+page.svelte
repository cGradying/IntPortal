<script lang="ts">
  // 057 C12: CHANGELOG.md, newest first, an anchor per version.
  import { releaseId } from "$lib/content/changelog";
  import { notes } from "$lib/notes";
  import Share from "$lib/Share.svelte";

  let { data } = $props();
  const md = notes;
  const day = (d: string) => new Date(d + "T12:00:00+08:00").toLocaleDateString("en-PH", { month: "long", day: "numeric", year: "numeric", timeZone: "Asia/Manila" });
</script>

<svelte:head>
  <title>What's new · IntPortal</title>
  <meta name="description" content="Every IntPortal release, newest first: what changed for students, and what's still missing." />
  <meta property="og:title" content="What's new · IntPortal" />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<div class="wrap page">
  <h1>What's new</h1>
  <p class="lede">Every release, newest first: what changed, in the words of the release notes, and what's still missing. What comes next is on the <a href="/roadmap">roadmap</a>.</p>

  {#each data.releases as r, i (r.version)}
    <section id={releaseId(r.version)} class="release" aria-labelledby="{releaseId(r.version)}-h">
      <div class="when">
        <h2 id="{releaseId(r.version)}-h"><a href="#{releaseId(r.version)}">{r.version}</a></h2>
        <p class="date pixel"><time datetime={r.date}>{day(r.date)}</time></p>
        {#if i === 0}<p class="latest pixel">Latest</p>{/if}
        <Share href="/changelog#{releaseId(r.version)}" title="IntPortal {r.version}" />
      </div>
      <div class="what">
        {#if r.intro}<p class="intro">{@html md(r.intro)}</p>{/if}
        {#if r.items.length}
          <ul>{#each r.items as item, j (j)}<li>{@html md(item)}</li>{/each}</ul>
        {/if}
        {#if r.gaps.length}
          <div class="gaps">
            <p class="label pixel">Known gaps</p>
            <ul>{#each r.gaps as g, j (j)}<li>{@html md(g)}</li>{/each}</ul>
          </div>
        {/if}
      </div>
    </section>
  {/each}
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
  .release {
    display: grid;
    grid-template-columns: 220px minmax(0, 1fr);
    gap: 24px 56px;
    padding-top: 48px;
    margin-top: 48px;
    box-shadow: inset 0 1px 0 var(--site-line);
    scroll-margin-top: 80px;
  }
  .when {
    position: sticky;
    top: 88px;
    align-self: start;
  }
  h2 {
    font-size: clamp(2rem, 4vw, 2.8rem);
    font-weight: 800;
    letter-spacing: -0.03em;
    font-variant-numeric: tabular-nums;
  }
  h2 a {
    text-decoration: none;
  }
  h2 a:hover {
    color: var(--gold);
  }
  .date {
    margin-top: 8px;
    font-size: 0.82rem;
    color: var(--site-ink-3);
  }
  .latest {
    display: inline-block;
    margin-top: 12px;
    padding: 4px 10px;
    background: var(--gold);
    color: #1b1406;
    font-size: 0.75rem;
    box-shadow: inset 0 -2px 0 #b87a10;
  }
  .what {
    max-width: 70ch;
  }
  .intro {
    font-size: 1.18rem;
    line-height: 1.55;
    margin-bottom: 20px;
  }
  ul {
    margin: 0;
    padding: 0;
    list-style: none;
  }
  li {
    position: relative;
    padding: 10px 0 10px 22px;
    line-height: 1.6;
    color: var(--site-ink-2);
  }
  li::before {
    content: "";
    position: absolute;
    left: 2px;
    top: 0.95em;
    width: 6px;
    height: 6px;
    background: var(--gold);
  }
  li :global(strong) {
    color: var(--site-ink);
  }
  li :global(a),
  .intro :global(a) {
    color: var(--site-ink);
  }
  li :global(code) {
    font-size: 0.92em;
    padding: 1px 5px;
    border-radius: 3px;
    background: rgba(244, 236, 216, 0.08);
  }
  .gaps {
    margin-top: 24px;
    padding: 18px 22px 8px;
    background: var(--void-2);
    border-radius: var(--radius);
    box-shadow: inset 0 0 0 1px var(--site-line);
  }
  .label {
    font-size: 0.8rem;
    color: var(--site-ink-3);
  }
  .gaps li::before {
    background: var(--site-ink-3);
  }
  @media (max-width: 760px) {
    .release {
      grid-template-columns: 1fr;
    }
    .when {
      position: static;
    }
  }
</style>

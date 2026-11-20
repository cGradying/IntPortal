<script lang="ts">
  // 057 C12: CHANGELOG.md, newest first, an anchor per version.
  import { onMount } from "svelte";
  import { afterNavigate } from "$app/navigation";
  import { releaseId } from "$lib/content/changelog";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import { notes } from "$lib/notes";
  import NextStep from "$lib/NextStep.svelte";
  import Share from "$lib/Share.svelte";

  let { data } = $props();
  const md = notes;
  const changes = (n: number) => `${n} ${n === 1 ? "change" : "changes"}`;

  // 060 C16: /changelog#v0.2.0 opens that release when it's folded.
  function reveal() {
    const d = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    if (!(d instanceof HTMLDetailsElement)) return;
    d.open = true;
    d.scrollIntoView({ block: "start" });
  }
  onMount(reveal);
  afterNavigate(reveal);
  const day = (d: string) => new Date(d + "T12:00:00+08:00").toLocaleDateString("en-PH", { month: "long", day: "numeric", year: "numeric", timeZone: "Asia/Manila" });
</script>

<svelte:window onhashchange={reveal} />

<svelte:head>
  <title>What's new · IntPortal</title>
  <meta name="description" content="Every IntPortal release, newest first: what changed for students, and what's still missing." />
  <meta property="og:title" content="What's new · IntPortal" />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<div class="wrap">
  <header class="page-head">
    <h1>What's new</h1>
    <p class="lede">Every release, newest first: what changed, in the words of the release notes, and what's still missing. What comes next is on the <a href="/roadmap">roadmap</a>.</p>
    <nav class="chips" aria-label="Releases">
      {#each data.releases as r, i (r.version)}
        <a href="#{releaseId(r.version)}" class:new={i === 0}>{r.version}</a>
      {/each}
    </nav>
  </header>

  {#snippet what(r: (typeof data.releases)[number])}
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
  {/snippet}

  {#each data.releases as r, i (r.version)}
    {@const id = releaseId(r.version)}
    {#if i < 3}
      <section {id} class="release" aria-labelledby="{id}-h">
        <div class="when">
          <h2 id="{id}-h"><a href="#{id}">{r.version}</a></h2>
          <p class="date pixel"><time datetime={r.date}>{day(r.date)}</time></p>
          {#if i === 0}<p class="latest pixel">Latest</p>{/if}
          <Share href="/changelog#{id}" title="IntPortal {r.version}" />
        </div>
        {@render what(r)}
      </section>
    {:else}
      <details {id} class="release old">
        <summary>
          <h2 id="{id}-h">{r.version}</h2>
          <span class="date pixel"><time datetime={r.date}>{day(r.date)}</time></span>
          <span class="count">{changes(r.items.length)}</span>
          <span class="chev" aria-hidden="true"><PixelIcon name="chev" size={12} /></span>
        </summary>
        <div class="body">
          <div class="when"><Share href="/changelog#{id}" title="IntPortal {r.version}" /></div>
          {@render what(r)}
        </div>
      </details>
    {/if}
  {/each}

  <NextStep />
</div>

<style>
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
    margin-top: 28px;
  }
  .chips a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    padding: 0 12px;
    border-radius: var(--radius);
    background: rgba(244, 236, 216, 0.05);
    color: var(--site-ink-2);
    font-weight: 600;
    font-variant-numeric: tabular-nums;
    text-decoration: none;
    transition: background var(--t-quick) var(--ease), color var(--t-quick) var(--ease);
  }
  .chips a:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.09);
  }
  .chips a.new {
    color: var(--gold);
    box-shadow: inset 0 0 0 1px rgba(245, 178, 39, 0.4);
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
    display: inline-flex;
    align-items: center;
    min-height: 44px;
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
  /* Older releases fold to one line: version, date, how many changes. */
  .old {
    display: block;
    padding-top: 0;
    margin-top: 0;
  }
  .old:first-of-type {
    margin-top: 48px;
  }
  summary {
    display: grid;
    grid-template-columns: 220px auto 1fr auto;
    align-items: center;
    gap: 8px 56px;
    min-height: 72px;
    padding: 12px 0;
    cursor: pointer;
    list-style: none;
  }
  summary::-webkit-details-marker {
    display: none;
  }
  .old h2 {
    font-size: 1.6rem;
  }
  .old .date {
    margin: 0;
  }
  .count {
    color: var(--site-ink-3);
  }
  .chev {
    display: flex;
    color: var(--site-ink-3);
    rotate: 90deg;
    transition: rotate var(--t-quick) var(--ease);
  }
  .old[open] .chev {
    rotate: -90deg;
  }
  summary:hover h2,
  summary:hover .chev {
    color: var(--gold);
  }
  .old .body {
    display: grid;
    grid-template-columns: 220px minmax(0, 1fr);
    gap: 24px 56px;
    padding: 8px 0 40px;
  }
  .old .when {
    position: static;
  }
  @media (max-width: 760px) {
    .release,
    .old .body {
      grid-template-columns: 1fr;
    }
    summary {
      grid-template-columns: auto 1fr auto;
      gap: 4px 16px;
    }
    .count {
      grid-column: 1 / 3;
      grid-row: 2;
      font-size: 0.9rem;
    }
    .chev {
      grid-row: 1 / 3;
      grid-column: 3;
    }
    .when {
      position: static;
    }
  }
</style>

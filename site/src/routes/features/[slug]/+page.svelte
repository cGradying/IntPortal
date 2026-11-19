<script lang="ts">
  // 057 C10: one feature: what it does, how to use it, where it lives.
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import Phone from "$lib/Phone.svelte";
  import Share from "$lib/Share.svelte";
  import { releaseId } from "$lib/content/changelog";
  import { GROUP_ICON } from "$lib/groupIcon";
  import { REPO_URL } from "$lib/releases";

  let { data } = $props();
  const f = $derived(data.feature);
</script>

<svelte:head>
  <title>{f.name} · IntPortal</title>
  <meta name="description" content="{f.line} {f.body[0] ?? ''}" />
  <meta property="og:title" content="{f.name} · IntPortal" />
  <meta property="og:description" content={f.line} />
  <meta property="og:image" content={f.media && !f.media.video ? f.media.src : "/og.png"} />
</svelte:head>

<article class="wrap page">
  <nav class="crumbs" aria-label="Breadcrumb">
    <a href="/features">Features</a>
    <PixelIcon name="chev" size={10} />
    <a href="/features#{data.group.id}">{data.group.name}</a>
  </nav>

  <div class="layout" class:bare={!f.media}>
    <div class="text">
      <header>
        <h1 style:view-transition-name="f-{f.slug}">{f.name}</h1>
        <p class="line">{f.line}</p>
        <p class="meta pixel">
          <span><PixelIcon name={GROUP_ICON[data.group.id]} size={12} />{data.group.name}</span>
          {#if f.since}<a href="/changelog#{releaseId(f.since)}">since {f.since}</a>{/if}
        </p>
        <Share href="/features/{f.slug}" title="{f.name} · IntPortal" />
      </header>

      <div class="body">
        {#each f.body as para, i (i)}<p>{para}</p>{/each}
      </div>

      {#if f.steps.length}
        <section aria-labelledby="how">
          <h2 id="how">How to use it</h2>
          <ol>
            {#each f.steps as s, i (i)}<li><span class="n pixel" aria-hidden="true">{i + 1}</span><span>{s}</span></li>{/each}
          </ol>
        </section>
      {/if}

      {#if f.spec}
        <p class="fine spec">How it's meant to work, criterion by criterion: <a href="{REPO_URL}/blob/main/docs/specs/{f.spec}.md" rel="noopener">spec {f.spec.split("-")[0]}</a>.</p>
      {/if}
    </div>

    {#if f.media}
      <div class="show">
        <Phone src={f.media.src} alt={f.media.alt} video={f.media.video} poster={f.media.poster} />
      </div>
    {/if}
  </div>

  <nav class="pager" aria-label="More in {data.group.name}">
    {#if data.prev}
      <a class="prev" href="/features/{data.prev.slug}"><span class="pixel">Previous</span><strong>{data.prev.name}</strong></a>
    {:else}<span></span>{/if}
    {#if data.next}
      <a class="next" href="/features/{data.next.slug}"><span class="pixel">Next</span><strong>{data.next.name}</strong></a>
    {:else}
      <a class="next" href="/features"><span class="pixel">Back to</span><strong>Every feature</strong></a>
    {/if}
  </nav>
</article>

<style>
  .page {
    padding-top: clamp(28px, 6vh, 64px);
  }
  .crumbs {
    display: flex;
    align-items: center;
    gap: 8px;
    color: var(--site-ink-3);
  }
  .crumbs a {
    display: inline-flex;
    align-items: center;
    min-height: 44px;
    color: var(--site-ink-2);
    text-decoration: none;
  }
  .crumbs a:hover {
    color: var(--site-ink);
    text-decoration: underline;
  }
  .layout.bare {
    grid-template-columns: minmax(0, 1fr);
  }
  .layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: clamp(32px, 7vw, 112px);
    align-items: start;
    margin-top: 24px;
  }
  .text {
    max-width: 62ch;
  }
  h1 {
    font-size: clamp(2.4rem, 6vw, 4rem);
    font-weight: 800;
    letter-spacing: -0.035em;
  }
  .line {
    margin-top: 14px;
    font-size: clamp(1.15rem, 2vw, 1.35rem);
    color: var(--site-ink-2);
    line-height: 1.45;
  }
  .meta {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
    margin-top: 20px;
    font-size: 0.8rem;
  }
  .meta > * {
    display: inline-flex;
    align-items: center;
    gap: 6px;
    min-height: 44px;
    padding: 0 12px;
    border-radius: var(--radius-sm, 3px);
    background: rgba(244, 236, 216, 0.06);
    color: var(--site-ink-2);
    text-decoration: none;
  }
  .meta a:hover {
    color: var(--gold);
  }
  .body {
    margin-top: 36px;
    display: grid;
    gap: 16px;
    font-size: 1.12rem;
    line-height: 1.65;
    color: var(--site-ink);
  }
  section {
    margin-top: 48px;
  }
  h2 {
    font-size: 1.5rem;
    margin-bottom: 18px;
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 2px;
  }
  li {
    display: grid;
    grid-template-columns: 36px 1fr;
    gap: 12px;
    align-items: baseline;
    padding: 12px 0;
    box-shadow: inset 0 -1px 0 var(--site-line);
    line-height: 1.55;
  }
  .n {
    display: inline-grid;
    place-items: center;
    width: 28px;
    height: 28px;
    background: var(--gold-soft);
    color: var(--gold);
    font-size: 0.85rem;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .spec {
    margin-top: 32px;
  }
  .show {
    position: sticky;
    top: 96px;
  }
  .pager {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 16px;
    margin-top: 88px;
  }
  .pager a {
    display: grid;
    gap: 4px;
    padding: 20px 22px;
    background: var(--void-2);
    box-shadow: inset 0 0 0 1px var(--site-line);
    border-radius: var(--radius);
    text-decoration: none;
    transition: box-shadow var(--t-quick) var(--ease);
  }
  .pager a:hover {
    box-shadow: inset 0 0 0 1px rgba(245, 178, 39, 0.5);
  }
  .pager .next {
    text-align: right;
    grid-column: 2;
  }
  .pager span {
    font-size: 0.78rem;
    color: var(--site-ink-3);
  }
  .pager strong {
    font-family: var(--site-display);
    font-size: 1.12rem;
  }
  @media (max-width: 820px) {
    .layout {
      grid-template-columns: 1fr;
    }
    .show {
      position: static;
      order: -1;
    }
  }
</style>

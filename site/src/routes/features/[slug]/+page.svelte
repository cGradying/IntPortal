<script lang="ts">
  // 057 C10: one feature: what it does, how to use it, where it lives.
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import NextStep from "$lib/NextStep.svelte";
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

<article class="wrap page-head">
  <nav class="crumbs" aria-label="Breadcrumb">
    <a href="/features">Features</a>
    <PixelIcon name="chev" size={10} />
    <a href="/features#{data.group.id}">{data.group.name}</a>
  </nav>

  <div class="layout">
    <header>
      <h1 style:view-transition-name="f-{f.slug}">{f.name}</h1>
      <p class="lede">{f.line}</p>
      <p class="meta pixel">
        <span><PixelIcon name={GROUP_ICON[data.group.id]} size={12} />{data.group.name}</span>
        {#if f.since}<a href="/changelog#{releaseId(f.since)}">since {f.since}</a>{/if}
      </p>
      <Share href="/features/{f.slug}" title="{f.name} · IntPortal" />
    </header>

    <div class="show">
      {#if f.media}
        <Phone src={f.media.src} alt={f.media.alt} video={f.media.video} poster={f.media.poster} />
      {:else}
        <!-- 060 C15: no screen yet, so the phone shows where the feature lives. -->
        <figure class="tile">
          <PixelIcon name={GROUP_ICON[data.group.id]} size={96} />
          <figcaption class="pixel">Lives in {data.group.name}</figcaption>
        </figure>
      {/if}
    </div>

    <div class="text">
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
    </div>
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

  <NextStep />

  {#if f.spec}
    <p class="fine spec">How it's meant to work, criterion by criterion: <a href="{REPO_URL}/blob/main/docs/specs/{f.spec}.md" rel="noopener">spec {f.spec.split("-")[0]}</a>.</p>
  {/if}
</article>

<style>
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
  /* Wide: the text runs down the left, the phone stays in view on the right.
     Phones: the title, then the phone, then the rest. */
  .layout {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    grid-template-rows: auto 1fr;
    grid-template-areas: "head show" "text show";
    column-gap: clamp(32px, 7vw, 112px);
    align-items: start;
    margin-top: 24px;
  }
  header {
    grid-area: head;
    max-width: 62ch;
  }
  .text {
    grid-area: text;
    max-width: 62ch;
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
    margin-top: 20px;
  }
  .show {
    grid-area: show;
    position: sticky;
    top: 96px;
  }
  .tile {
    display: grid;
    place-content: center;
    justify-items: center;
    gap: 22px;
    width: min(260px, 70vw);
    aspect-ratio: 9 / 20;
    margin: 0;
    background:
      url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='15' height='15'%3E%3Crect width='3' height='3' fill='%23f5b227' fill-opacity='.16'/%3E%3C/svg%3E") 6px 6px / 15px 15px,
      radial-gradient(circle at 50% 45%, rgba(245, 178, 39, 0.08), transparent 65%),
      var(--void-3);
    box-shadow: inset 0 0 0 3px var(--slab-edge);
    color: var(--parch);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  .tile figcaption {
    font-size: 0.875rem;
    color: var(--site-ink-2);
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
      grid-template-columns: minmax(0, 1fr);
      grid-template-rows: none;
      grid-template-areas: "head" "show" "text";
    }
    .show {
      position: static;
      margin-top: 36px;
    }
    .tile {
      width: min(180px, 50vw);
    }
  }
</style>

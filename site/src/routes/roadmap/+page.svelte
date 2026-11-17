<script lang="ts">
  // 057 C13: what's shipped, being built, next and later. No invented dates.
  import type { Lane, RoadItem } from "$lib/content/types";

  let { data } = $props();
  const lane = (l: Lane) => data.items.filter((i: RoadItem) => i.lane === l);
  const ahead = [
    { id: "building", name: "Building", line: "Approved specs, being built now." },
    { id: "next", name: "Next", line: "Open work at the top of the list." },
    { id: "later", name: "Later", line: "Drafts and ideas for after that." },
  ] as const;
  const shipped = $derived(lane("shipped"));
  const day = (d: string) => new Date(d + "T12:00:00+08:00").toLocaleDateString("en-PH", { month: "short", day: "numeric", year: "numeric", timeZone: "Asia/Manila" });
  const tag = (i: RoadItem) => (i.kind === "issue" ? `Issue #${i.href.split("/").pop()}` : i.kind === "spec" ? `Spec ${i.href.split("/").pop()?.slice(0, 3)}` : "Release");
  const ext = (href: string) => (href.startsWith("http") ? "noopener" : undefined);
</script>

<svelte:head>
  <title>Roadmap · IntPortal</title>
  <meta name="description" content="What's shipped in IntPortal, what's being built, what's next and what comes later, straight from the specs and issues it's built from." />
  <meta property="og:title" content="Roadmap · IntPortal" />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<div class="wrap page">
  <h1>Roadmap</h1>
  <p class="lede">What's done, what's being built, and what comes after. No dates until they're real.</p>

  <div class="lanes">
    {#each ahead as l (l.id)}
      {@const items = lane(l.id)}
      <section class="lane {l.id}" aria-labelledby="{l.id}-h">
        <header>
          <h2 id="{l.id}-h"><span class="dot" aria-hidden="true"></span>{l.name}<span class="n pixel">{items.length}</span></h2>
          <p>{l.line}</p>
        </header>
        <ul>
          {#each items as i (i.href)}
            <li>
              <a href={i.href} rel={ext(i.href)}>
                <strong>{i.title}</strong>
                <span class="line">{i.line}</span>
                <span class="tag pixel">{tag(i)}</span>
              </a>
            </li>
          {:else}
            <li class="none">Nothing here right now.</li>
          {/each}
        </ul>
      </section>
    {/each}
  </div>

  <section class="shipped" aria-labelledby="shipped-h">
    <h2 id="shipped-h">Shipped</h2>
    <p class="sub">{shipped.length} releases so far. Each one's full notes are in <a href="/changelog">What's new</a>.</p>
    <ol>
      {#each shipped as i (i.href)}
        <li>
          <a href={i.href}>
            {#if i.date}<time class="pixel" datetime={i.date}>{day(i.date)}</time>{/if}
            <strong>{i.title}</strong>
            <span class="line">{i.line}</span>
          </a>
        </li>
      {/each}
    </ol>
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
    max-width: 56ch;
    font-size: 1.15rem;
    color: var(--site-ink-2);
  }
  .lanes {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 20px;
    margin-top: 48px;
    align-items: start;
  }
  .lane {
    padding: 22px 20px 12px;
    background: var(--void-2);
    box-shadow: inset 0 0 0 1px var(--site-line);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  .lane h2 {
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 1.35rem;
  }
  .dot {
    width: 10px;
    height: 10px;
    background: var(--site-ink-3);
  }
  .building .dot {
    background: var(--gold);
    box-shadow: 0 0 0 3px var(--gold-soft);
  }
  .next .dot {
    background: #e08a35;
  }
  .n {
    margin-left: auto;
    font-size: 0.8rem;
    color: var(--site-ink-3);
  }
  .lane header p {
    margin-top: 6px;
    color: var(--site-ink-3);
    font-size: 0.95rem;
  }
  ul,
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .lane ul {
    margin-top: 14px;
  }
  .lane li a {
    display: grid;
    gap: 6px;
    padding: 14px 0;
    box-shadow: inset 0 1px 0 var(--site-line);
    text-decoration: none;
  }
  .lane strong {
    font-family: var(--site-display);
    font-size: 1.05rem;
    line-height: 1.3;
    transition: color var(--t-quick) var(--ease);
  }
  .lane a:hover strong {
    color: var(--gold);
  }
  .line {
    color: var(--site-ink-2);
    line-height: 1.5;
  }
  .tag {
    font-size: 0.72rem;
    color: var(--site-ink-3);
  }
  .none {
    padding: 14px 0;
    color: var(--site-ink-3);
    box-shadow: inset 0 1px 0 var(--site-line);
  }
  .shipped {
    margin-top: clamp(80px, 12vh, 140px);
  }
  .shipped h2 {
    font-size: clamp(2rem, 5vw, 3rem);
  }
  .sub {
    margin-top: 12px;
    color: var(--site-ink-2);
  }
  .shipped ol {
    margin-top: 32px;
    position: relative;
  }
  .shipped ol::before {
    content: "";
    position: absolute;
    left: 5px;
    top: 8px;
    bottom: 8px;
    width: 2px;
    background: var(--site-line);
  }
  .shipped li a {
    position: relative;
    display: grid;
    grid-template-columns: 150px minmax(0, 1fr);
    gap: 4px 24px;
    padding: 16px 0 16px 32px;
    text-decoration: none;
  }
  .shipped li a::before {
    content: "";
    position: absolute;
    left: 1px;
    top: 22px;
    width: 10px;
    height: 10px;
    background: var(--void);
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .shipped li:first-child a::before {
    background: var(--gold);
  }
  time {
    grid-row: 1 / 3;
    padding-top: 3px;
    font-size: 0.8rem;
    color: var(--site-ink-3);
  }
  .shipped strong {
    font-family: var(--site-display);
    font-size: 1.2rem;
    font-variant-numeric: tabular-nums;
  }
  .shipped a:hover strong {
    color: var(--gold);
  }
  @media (max-width: 900px) {
    .lanes {
      grid-template-columns: 1fr;
    }
  }
  @media (max-width: 560px) {
    .shipped li a {
      grid-template-columns: 1fr;
    }
    time {
      grid-row: auto;
    }
  }
</style>

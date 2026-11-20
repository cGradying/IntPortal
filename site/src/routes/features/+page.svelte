<script lang="ts">
  // 057 C9: every feature, in its group, with a filter.
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import Lar from "$app_lib/lar/Lar.svelte";
  import { GROUP_ICON } from "$lib/groupIcon";

  let { data } = $props();
  let q = $state("");

  const norm = (s: string) => s.toLowerCase().normalize("NFKD");
  const shown = $derived.by(() => {
    const words = norm(q).split(/\s+/).filter(Boolean);
    const hit = (f: (typeof data.features)[number]) => {
      const hay = norm([f.name, f.line, ...f.body].join(" "));
      return words.every((w) => hay.includes(w));
    };
    return data.groups
      .map((g) => ({ ...g, items: data.features.filter((f) => f.group === g.id && hit(f)) }))
      .filter((g) => g.items.length);
  });
  const total = $derived(shown.reduce((n, g) => n + g.items.length, 0));

  // 060 C18: nothing here, so look across the whole site with the same words.
  const everything = () => dispatchEvent(new CustomEvent("site-search", { detail: { q } }));

  // 060 C18: the rail marks the group in the upper part of the screen.
  let current = $state("");
  let rail = $state<HTMLElement>();
  $effect(() => {
    const groups = shown;
    current = "";
    const seen = new Set<string>();
    const io = new IntersectionObserver(
      (es) => {
        for (const e of es) (e.isIntersecting ? seen.add(e.target.id) : seen.delete(e.target.id));
        current = groups.find((g) => seen.has(g.id))?.id ?? "";
      },
      { rootMargin: "-140px 0px -55% 0px" },
    );
    document.querySelectorAll("section.group").forEach((s) => io.observe(s));
    return () => io.disconnect();
  });
  // On a phone the rail scrolls sideways; keep the marked group in it.
  $effect(() => {
    const a = current && rail?.querySelector<HTMLElement>(`a[href="#${current}"]`);
    if (a && rail) rail.scrollTo({ left: a.offsetLeft - (rail.clientWidth - a.offsetWidth) / 2 });
  });
</script>

<svelte:head>
  <title>Every feature · IntPortal</title>
  <meta name="description" content="Everything IntPortal does, from signing in to your school's portal to the study game, reminders and the desktop app. Each feature with its own page." />
  <meta property="og:title" content="Every feature · IntPortal" />
  <meta property="og:image" content="/og.png" />
</svelte:head>

<div class="wrap">
  <header class="page-head">
    <h1>Everything in IntPortal</h1>
    <p class="lede">{data.features.length} features in {data.groups.length} groups. Each has its own page with what it does and how to use it.</p>
    <div class="find">
      <label for="q" class="sr">Find a feature</label>
      <span class="glass" aria-hidden="true"><PixelIcon name="search" size={18} /></span>
      <input id="q" type="search" placeholder="Find a feature" autocomplete="off" bind:value={q} />
      <p class="sr" aria-live="polite">{q ? `${total} ${total === 1 ? "feature" : "features"} match` : ""}</p>
    </div>
  </header>

  <nav class="rail" aria-label="Groups" bind:this={rail}>
    {#each data.groups as g (g.id)}
      <a href="#{g.id}" class:dim={q && !shown.some((s) => s.id === g.id)} aria-current={current === g.id ? "location" : undefined}><PixelIcon name={GROUP_ICON[g.id]} size={16} />{g.name}</a>
    {/each}
  </nav>

  {#each shown as g (g.id)}
    <section id={g.id} class="group" aria-labelledby="{g.id}-h">
      <div class="gh">
        <span class="gi"><PixelIcon name={GROUP_ICON[g.id]} size={24} /></span>
        <div>
          <h2 id="{g.id}-h">{g.name}</h2>
          <p>{g.line}</p>
        </div>
      </div>
      <ul>
        {#each g.items as f (f.slug)}
          <li>
            <a href="/features/{f.slug}">
              <span class="fn" style:view-transition-name="f-{f.slug}">{f.name}</span>
              <span class="fl">{f.line}</span>
              {#if f.since}<span class="since pixel">since {f.since}</span>{/if}
            </a>
          </li>
        {/each}
      </ul>
    </section>
  {:else}
    <div class="empty">
      <Lar size={3} mood="wow" label="LAR, surprised" />
      <div>
        <p>No feature called “{q.trim()}” yet. Try a shorter word, or look across help and releases too.</p>
        <div class="acts">
          <button class="gold" onclick={everything}>Search everything</button>
          <button class="ghost" onclick={() => (q = "")}>Clear</button>
        </div>
        <p class="fine">Or <a href="/roadmap">see what's coming</a>.</p>
      </div>
    </div>
  {/each}
</div>

<style>
  .find {
    position: relative;
    max-width: 520px;
    margin-top: 32px;
  }
  .glass {
    position: absolute;
    left: 16px;
    top: 50%;
    translate: 0 -50%;
    color: var(--site-ink-3);
    display: flex;
  }
  input {
    width: 100%;
    height: 54px;
    padding: 0 16px 0 46px;
    border: 0;
    border-radius: var(--radius);
    background: var(--void-2);
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.14);
    color: #fff;
    caret-color: var(--gold);
    font: inherit;
    font-size: max(16px, 1rem);
  }
  input::placeholder {
    color: var(--site-ink-3);
  }
  input:focus {
    outline: none;
    box-shadow: inset 0 0 0 1.5px var(--gold);
  }
  .rail {
    position: sticky;
    top: 64px;
    z-index: 5;
    display: flex;
    gap: 6px;
    margin: 40px calc(-1 * var(--site-gutter)) 0;
    padding: 10px var(--site-gutter);
    overflow-x: auto;
    scrollbar-width: none;
    background: color-mix(in srgb, var(--void) 92%, transparent);
    backdrop-filter: blur(12px);
    -webkit-backdrop-filter: blur(12px);
  }
  .rail a {
    flex: none;
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
    transition: background var(--t-quick) var(--ease), color var(--t-quick) var(--ease), opacity var(--t-quick) var(--ease);
  }
  .rail a:hover {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.09);
  }
  .rail a.dim {
    opacity: 0.4;
  }
  .rail a[aria-current] {
    color: var(--site-ink);
    background: rgba(244, 236, 216, 0.09);
    box-shadow: inset 0 -2px 0 var(--gold);
  }
  .group {
    margin-top: 72px;
    scroll-margin-top: 140px;
  }
  .gh {
    display: flex;
    gap: 16px;
    align-items: flex-start;
    padding-bottom: 20px;
    box-shadow: inset 0 -1px 0 var(--site-line);
  }
  .gi {
    display: grid;
    place-items: center;
    width: 48px;
    height: 48px;
    flex: none;
    background: var(--void-3);
    box-shadow: inset 0 0 0 2px var(--slab-edge);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    color: var(--parch);
  }
  .gh h2 {
    font-size: clamp(1.6rem, 3.4vw, 2.2rem);
  }
  .gh p {
    margin-top: 6px;
    color: var(--site-ink-2);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(min(100%, 340px), 1fr));
    column-gap: 40px;
  }
  li a {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 4px 16px;
    padding: 18px 0;
    box-shadow: inset 0 -1px 0 var(--site-line);
    text-decoration: none;
  }
  .fn {
    font-family: var(--site-display);
    font-weight: 700;
    font-size: 1.1rem;
    transition: color var(--t-quick) var(--ease);
  }
  li a:hover .fn {
    color: var(--gold);
  }
  .fl {
    grid-column: 1;
    color: var(--site-ink-2);
    line-height: 1.45;
  }
  .since {
    grid-column: 2;
    grid-row: 1;
    align-self: center;
    font-size: 0.875rem;
    color: var(--site-ink);
    opacity: 0.7;
  }
  .empty {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 16px 28px;
    margin-top: 56px;
  }
  .empty > div > p:first-child {
    max-width: 44ch;
    font-size: 1.15rem;
    color: var(--site-ink-2);
  }
  .acts {
    display: flex;
    flex-wrap: wrap;
    gap: 10px;
    margin-top: 20px;
  }
  .empty .fine {
    margin-top: 14px;
  }
</style>

<script lang="ts">
  // The portal hub (spec 010 C13a): every school the core lists, in one
  // sheet over the landing. Search by short name, school or region; the
  // student's recent picks and their region come first, then A–Z with a rail
  // to jump. Picking one turns the orbit to it.
  import { tick } from "svelte";
  import type { Portal } from "./api";
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { loadRecent, remember, saveRecent, sections } from "./hub";
  import { visualViewport } from "./viewport.svelte";

  let { portals, index, onpick, onclose }: { portals: Portal[]; index: number; onpick: (i: number) => void; onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));

  const vv = visualViewport();
  let q = $state("");
  let recent = $state(loadRecent());
  const current = $derived(portals[index]);
  const region = $derived(portals.find((p) => p.id === recent[0])?.region ?? current?.region);
  const list = $derived(sections(portals, q, recent, region));
  const letters = $derived(list.filter((s) => s.letter).map((s) => s.letter!));
  let scroller: HTMLElement | undefined = $state();

  function pick(p: Portal) {
    buzz.select();
    recent = remember(recent, p.id);
    saveRecent(recent);
    onpick(portals.indexOf(p));
    onclose();
  }

  // The rail follows the finger, like the phone's own contact list.
  let railing = false;
  function jump(e: PointerEvent) {
    const el = document.elementFromPoint(e.clientX, e.clientY) as HTMLElement | null;
    const l = el?.dataset.letter;
    const target = l && scroller?.querySelector<HTMLElement>(`[data-section="${l}"]`);
    if (!target || !scroller) return;
    scroller.scrollTop = target.offsetTop - scroller.offsetTop;
    buzz.tick();
  }
  function railDown(e: PointerEvent) {
    railing = true;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    jump(e);
  }

  async function clear(input: HTMLInputElement) {
    q = "";
    await tick();
    input.focus();
  }
  let field: HTMLInputElement;
</script>

{#snippet mini(p: Portal)}
  <!-- A tiny portal: an obsidian ring round the school's ramp, darkest at the top. -->
  <svg class="mini" viewBox="0 0 5 7" aria-hidden="true" shape-rendering="crispEdges">
    <rect width="5" height="7" fill="#2f2939" />
    {#each p.theme.ramp.slice(1) as c, i (i)}<rect x="1" y={1 + i * 1.25} width="3" height="1.25" fill={c} />{/each}
    <rect x="2" y="0" width="1" height="1" fill={p.theme.accent} />
  </svg>
{/snippet}

<div class="scrim" role="presentation" onclick={onclose}></div>
<div class="frame" style:top="{vv.top}px" style:height="{vv.h}px">
  <div class="sheet" role="dialog" aria-label="Choose your school" style:--accent={current?.theme.accent ?? "#f5b227"}>
    <header>
      <h2>Choose your school</h2>
      <button class="close" onclick={onclose}>Done</button>
    </header>

    <label class="search">
      <svg viewBox="0 0 12 12" aria-hidden="true" shape-rendering="crispEdges">
        <path d="M3 1h4v1H3zM2 2h1v1H2zM7 2h1v1H7zM1 3h1v4H1zM8 3h1v4H8zM2 7h1v1H2zM7 7h1v1H7zM3 8h4v1H3zM8 8h1v1H8zM9 9h1v1H9zM10 10h1v1h-1z" fill="currentColor" />
      </svg>
      <input
        bind:this={field}
        bind:value={q}
        type="search"
        placeholder="School, short name or region"
        aria-label="Search schools"
        enterkeyhint="search"
        autocomplete="off"
        autocapitalize="off"
        spellcheck="false"
      />
      {#if q}<button type="button" class="clear" onclick={() => clear(field)}>Clear</button>{/if}
    </label>

    <div class="body">
      <div class="list" bind:this={scroller}>
        {#each list as s (s.title)}
          <section data-section={s.letter ?? s.title}>
            <h3>{s.title}</h3>
            <ul>
              {#each s.items as p (p.id)}
                <li>
                  <button class="row" class:on={p === current} aria-current={p === current} onclick={() => pick(p)} style:--c={p.theme.accent}>
                    {@render mini(p)}
                    <span class="names">
                      <b>{p.name}</b>
                      <span>{p.school}</span>
                    </span>
                    {#if p.status === "ready"}<span class="chip ready">Ready</span>{:else}<span class="chip">Soon</span>{/if}
                  </button>
                </li>
              {/each}
            </ul>
          </section>
        {:else}
          <p class="none">No school matches “{q}”. Try its short name, like PUP or BulSU, or its region.</p>
        {/each}
        {#if list.length && list[0].title === "Results"}
          <p class="count">{list[0].items.length} of {portals.length} schools</p>
        {/if}
      </div>
      {#if letters.length > 1}
        <div
          class="rail"
          role="navigation"
          aria-label="Jump to letter"
          onpointerdown={railDown}
          onpointermove={(e) => railing && jump(e)}
          onpointerup={() => (railing = false)}
          onpointercancel={() => (railing = false)}
        >
          {#each letters as l (l)}<span data-letter={l}>{l}</span>{/each}
        </div>
      {/if}
    </div>
  </div>
</div>

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgb(0 0 0 / 0.55);
    animation: fade 0.2s both;
  }
  .frame {
    position: fixed;
    left: 0;
    right: 0;
    z-index: 61;
    display: flex;
    align-items: flex-end;
    padding-top: calc(var(--safe-top) + 12px);
    pointer-events: none;
  }
  .sheet {
    --step: 4px;
    pointer-events: auto;
    width: 100%;
    height: 100%;
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    gap: 12px;
    padding: 16px var(--gutter) 0;
    background: #140c16;
    color: #f4ecd8;
    font-family: var(--font-ui);
    box-shadow: inset 0 1px 0 rgb(245 178 39 / 0.16);
    clip-path: polygon(0 8px, 4px 8px, 4px 4px, 8px 4px, 8px 0, calc(100% - 8px) 0, calc(100% - 8px) 4px, calc(100% - 4px) 4px, calc(100% - 4px) 8px, 100% 8px, 100% 100%, 0 100%);
    animation: rise 0.42s var(--ease) both;
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  h2 {
    margin: 0;
    font: 700 min(1.059rem, 32px) / 1.2 var(--font-display);
    letter-spacing: -0.01em;
  }
  .close {
    min-width: 44px;
    height: 44px;
    margin-right: -8px;
    padding: 0 8px;
    border: 0;
    background: none;
    color: #f5b227;
    font: 600 min(0.941rem, 29px) var(--font-ui);
  }
  .search {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 46px;
    padding: 0 6px 0 14px;
    border-radius: 10px;
    background: #0b0710;
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    color: rgb(244 236 216 / 0.55);
    transition: box-shadow 0.16s var(--ease);
  }
  .search:focus-within {
    box-shadow: inset 0 0 0 1.5px var(--accent);
    color: var(--accent);
  }
  .search svg {
    width: 18px;
    height: 18px;
    flex: none;
  }
  .search input {
    flex: 1;
    min-width: 0;
    height: 100%;
    border: 0;
    background: none;
    color: #fff;
    font: 400 max(16px, min(0.941rem, 29px)) var(--font-ui);
    caret-color: #f5b227;
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }
  .search input::placeholder {
    color: rgb(244 236 216 / 0.5);
  }
  .search input::-webkit-search-cancel-button {
    display: none;
  }
  .clear {
    height: 44px;
    padding: 0 10px;
    border: 0;
    background: none;
    color: rgb(244 236 216 / 0.7);
    font: 600 min(0.765rem, 23px) var(--font-ui);
  }
  .body {
    position: relative;
    min-height: 0;
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
  }
  .list {
    overflow-y: auto;
    overscroll-behavior: contain;
    padding-bottom: calc(var(--safe-bottom) + 24px);
    scrollbar-width: none;
  }
  .list::-webkit-scrollbar {
    display: none;
  }
  section + section {
    margin-top: 14px;
  }
  /* Section names stick while their rows scroll under them. */
  h3 {
    position: sticky;
    top: 0;
    z-index: 1;
    margin: 0;
    padding: 6px 0;
    background: #140c16;
    font: 500 min(0.706rem, 22px) var(--font-pixel);
    letter-spacing: 0.08em;
    color: rgb(244 236 216 / 0.6);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .row {
    width: 100%;
    min-height: 56px;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: center;
    gap: 12px;
    padding: 8px 10px 8px 6px;
    border: 0;
    border-radius: 12px;
    background: none;
    color: inherit;
    text-align: left;
    transition: background 0.16s var(--ease);
  }
  .row:active {
    background: rgb(255 255 255 / 0.05);
  }
  .row.on {
    background: color-mix(in srgb, var(--c) 10%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--c) 45%, transparent);
  }
  .row:focus-visible {
    outline: 2px solid var(--c);
    outline-offset: -2px;
  }
  .mini {
    width: 20px;
    height: 28px;
    image-rendering: pixelated;
  }
  .names {
    display: grid;
    gap: 1px;
    min-width: 0;
  }
  .names b {
    font-weight: 600;
    font-size: min(0.941rem, 29px);
    color: #fff;
  }
  .row.on b {
    color: var(--c);
  }
  .names span {
    font-size: min(0.765rem, 23px);
    line-height: 1.3;
    color: rgb(244 236 216 / 0.6);
  }
  .chip {
    padding: 3px 6px 2px;
    font: 500 min(0.647rem, 20px) var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(244 236 216 / 0.55);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.18);
  }
  .chip.ready {
    color: #1b1406;
    background: #f5b227;
    box-shadow: inset 0 -2px 0 #b87a10;
  }
  .none,
  .count {
    margin: 16px 4px;
    font-size: min(0.824rem, 25px);
    line-height: 1.4;
    color: rgb(244 236 216 / 0.6);
  }
  .count {
    margin-top: 8px;
    font-size: min(0.765rem, 23px);
    text-align: center;
  }
  .rail {
    display: flex;
    flex-direction: column;
    justify-content: center;
    width: 22px;
    margin-right: calc(var(--gutter) * -1 + 2px);
    padding-bottom: calc(var(--safe-bottom) + 24px);
    touch-action: none;
    user-select: none;
  }
  .rail span {
    display: grid;
    place-items: center;
    flex: 0 1 20px;
    font: 700 min(0.588rem, 16px) var(--font-pixel);
    color: #f5b227;
  }
  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  @keyframes rise {
    from {
      transform: translateY(40px);
      opacity: 0;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .scrim,
    .sheet {
      animation: fade 0.2s both;
    }
  }
</style>

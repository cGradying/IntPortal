<script lang="ts">
  // The portal hub (spec 010 C13a): every school the core lists, in one
  // sheet over the landing. Search by short name, school or region; the
  // student's recent picks and their region come first, then A–Z with a rail
  // to jump. Picking one turns the orbit to it.
  import { onMount, tick } from "svelte";
  import type { Portal } from "./api";
  import { flatFace, runDither } from "./assis/dither-draw";
  import MiniPortal from "./MiniPortal.svelte";
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { loadRecent, remember, saveRecent, sections } from "./hub";
  import { visualViewport } from "./viewport.svelte";

  let {
    portals,
    index,
    from,
    onpick,
    onclose,
  }: {
    portals: Portal[];
    index: number;
    /** The plaque it opens from: the wall dithers out of it and back into it, like LAR's chat (spec 048). */
    from?: DOMRect;
    onpick: (i: number) => void;
    onclose: () => void;
  } = $props();
  $effect(() => closable(() => close()));

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let sheet: HTMLElement;
  let pc: HTMLCanvasElement;
  /** The cells are drawing the wall: the real sheet waits, hidden, for the swap frame. */
  let dithering = $state(!reduce);
  let closing = false;
  const face = () => flatFace(getComputedStyle(sheet).backgroundColor, "rgb(245 178 39 / 0.3)");
  const box = () => {
    const r = sheet.getBoundingClientRect();
    return { x: r.left, y: r.top, w: r.width, h: r.height };
  };
  const chip = () => (from ? { x: from.left, y: from.top, w: from.width, h: from.height } : { x: innerWidth / 2 - 22, y: innerHeight - 66, w: 44, h: 44 });

  onMount(() => {
    if (reduce) return;
    tick()
      .then(() => runDither({ canvas: pc, chip: chip(), win: box(), face: face(), mode: "open" }))
      .finally(() => (dithering = false));
  });

  function close() {
    if (closing) return;
    closing = true;
    if (reduce) return onclose();
    const win = box();
    dithering = true;
    runDither({ canvas: pc, chip: chip(), win, face: face(), mode: "close" }).finally(onclose);
  }

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
    close();
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

<div class="scrim" role="presentation" onclick={close}></div>
<canvas class="dither" bind:this={pc} aria-hidden="true"></canvas>
<div class="frame" style:top="{vv.top}px" style:height="{vv.h}px">
  <div class="sheet" class:dithering bind:this={sheet} role="dialog" aria-label="Choose your school" style:--accent={current?.theme.accent ?? "var(--portal-gold)"}>
    <header>
      <h2>Choose your school</h2>
      <button class="close" onclick={close}>Done</button>
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
            {#if s.title === "Open now"}
              <!-- The portals that work today, as large cards: the reason to be here (C13a). -->
              <ul class="open">
                {#each s.items as p (p.id)}
                  <li>
                    <button class="card" class:on={p === current} aria-current={p === current} onclick={() => pick(p)} style:--c={p.theme.accent}>
                      <span class="big"><MiniPortal portal={p} /></span>
                      <b>{p.name}</b>
                      <span>{p.school}</span>
                    </button>
                  </li>
                {/each}
              </ul>
            {:else}
              <ul>
                {#each s.items as p (p.id)}
                  <li>
                    <button class="row" class:on={p === current} aria-current={p === current} onclick={() => pick(p)} style:--c={p.theme.accent}>
                      <span class="mini"><MiniPortal portal={p} /></span>
                      <span class="names">
                        <b>{p.name}</b>
                        <span>{p.school}</span>
                      </span>
                      {#if p.status === "ready"}<span class="chip ready">Ready</span>{:else}<span class="chip">Soon</span>{/if}
                    </button>
                  </li>
                {/each}
              </ul>
            {/if}
          </section>
        {/each}
        {#if q.trim() && !list[0]?.items.length}
          <p class="none">No school matches “{q.trim()}”. Try its short name, like PUP or BulSU, or its region.</p>
        {:else if q.trim()}
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
    animation: fade var(--t-quick) both;
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
    background: var(--void-2);
    color: var(--parch);
    font-family: var(--font-ui);
    box-shadow: inset 0 1px 0 rgb(245 178 39 / 0.16);
    clip-path: polygon(0 8px, 4px 8px, 4px 4px, 8px 4px, 8px 0, calc(100% - 8px) 0, calc(100% - 8px) 4px, calc(100% - 4px) 4px, calc(100% - 4px) 8px, 100% 8px, 100% 100%, 0 100%);
    animation: rise var(--t-flow) var(--ease) both;
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  h2 {
    margin: 0;
    font: 700 var(--text-headline) / 1.2 var(--font-display);
    letter-spacing: -0.01em;
  }
  .close {
    min-width: 44px;
    height: 44px;
    margin-right: -8px;
    padding: 0 8px;
    border: 0;
    background: none;
    color: var(--portal-gold);
    font: 600 var(--text-body) var(--font-ui);
  }
  .search {
    display: flex;
    align-items: center;
    gap: 10px;
    height: 46px;
    padding: 0 6px 0 14px;
    border-radius: var(--radius);
    background: var(--void);
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    color: rgb(244 236 216 / 0.55);
    transition: box-shadow var(--t-quick) var(--ease);
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
    color: var(--white);
    font: 400 var(--text-input) var(--font-ui);
    caret-color: var(--portal-gold);
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
    font: 600 var(--text-caption) var(--font-ui);
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
    background: var(--void-2);
    font: 500 var(--text-label) var(--font-pixel);
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
    border-radius: var(--radius);
    background: none;
    color: inherit;
    text-align: left;
    transition: background var(--t-quick) var(--ease);
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
  }
  .open {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
    gap: 10px;
    padding-top: 2px;
  }
  .card {
    width: 100%;
    height: 100%;
    display: grid;
    justify-items: start;
    align-content: start;
    gap: 2px;
    padding: 14px 14px 12px;
    border: 0;
    border-radius: var(--radius);
    background: color-mix(in srgb, var(--c) 7%, var(--void));
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--c) 28%, transparent);
    color: inherit;
    text-align: left;
    transition: background var(--t-quick) var(--ease);
  }
  .card:active {
    background: color-mix(in srgb, var(--c) 14%, var(--void));
  }
  .card.on {
    box-shadow: inset 0 0 0 1.5px var(--c);
  }
  .card:focus-visible {
    outline: 2px solid var(--c);
    outline-offset: 2px;
  }
  .big {
    width: 30px;
    height: 42px;
    margin-bottom: 10px;
  }
  .card b {
    font: 700 var(--text-body) / 1.2 var(--font-ui);
    color: var(--c);
  }
  .card > span:last-child {
    font-size: var(--text-caption);
    line-height: 1.3;
    color: rgb(244 236 216 / 0.66);
  }
  /* The dither draws the wall in and out; the real sheet waits for the swap frame (spec 048). */
  .dither {
    position: fixed;
    inset: 0;
    z-index: 62;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
  .sheet.dithering {
    visibility: hidden;
    animation: none;
  }
  .names {
    display: grid;
    gap: 1px;
    min-width: 0;
  }
  .names b {
    font-weight: 600;
    font-size: var(--text-body);
    color: var(--white);
  }
  .row.on b {
    color: var(--c);
  }
  .names span {
    font-size: var(--text-caption);
    line-height: 1.3;
    color: rgb(244 236 216 / 0.6);
  }
  .chip {
    padding: 3px 6px 2px;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(244 236 216 / 0.55);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.18);
  }
  .chip.ready {
    color: var(--on-portal-gold);
    background: var(--portal-gold);
    box-shadow: inset 0 -2px 0 var(--portal-gold-shade);
  }
  .none,
  .count {
    margin: 16px 4px;
    font-size: var(--text-sub);
    line-height: 1.4;
    color: rgb(244 236 216 / 0.6);
  }
  .count {
    margin-top: 8px;
    font-size: var(--text-caption);
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
    font: 700 var(--text-micro) var(--font-pixel);
    color: var(--portal-gold);
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
      animation: fade var(--t-quick) both;
    }
  }
</style>

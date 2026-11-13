<script lang="ts" module>
  import { subjectColor } from "./api";
  import { app } from "./state.svelte";
  import { GENERAL } from "./shelf";

  /** A notebook's colour: the subject's, or a quiet plum for General. */
  export const colorOf = (code: string) => (code === GENERAL ? "#5a4a63" : subjectColor(code, app.snapshot?.colors ?? {}));
</script>

<script lang="ts">
  import { friendly } from "./errors";
  // The notebook shelf (spec 046 C1 to C7): a notebook per subject, its window lit with one pixel
  // per note and one gold pixel per card due. Pull one out to see its notes below; decks live on Cards.
  import { api, type NoteItem } from "./api";
  import { photosInShare, previewOf } from "./photos";
  import { assis } from "./assis/assis.svelte";
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { contrast } from "./rooms";
  import { shareFile } from "./share";
  import { heightOf, pixels, search, shelves, subjectOf, type Notebook, type ShelfDeck } from "./shelf";
  import { openNote, refreshNotes } from "./state.svelte";

  let { decks, current = $bindable(GENERAL) }: { decks: ShelfDeck[]; current?: string } = $props();

  const subjects = $derived<[string, string][]>(Array.from(new Map((app.snapshot?.sessions ?? []).map((s) => [s.subject_code, s.description] as [string, string]))));
  const books = $derived(shelves(subjects, app.notes, decks));
  const open = $derived(books.find((b) => b.code === current) ?? books[0]);
  let query = $state("");
  const found = $derived(search(books, query));
  // The due pixels hold still while the model runs or LAR's sheet is up (#189).
  const still = $derived(assis.open || !!assis.busy);

  const inkOn = (c: string) => (contrast("#ffffff", c) >= contrast("#120a06", c) ? "#ffffff" : "#120a06");
  const label = (b: Notebook) => `${b.code || "General"}${b.past ? ", past subject" : ""}: ${b.notes.length} ${b.notes.length === 1 ? "note" : "notes"}${b.due ? `, ${b.due} ${b.due === 1 ? "card" : "cards"} due` : ""}`;

  function heading(n: NoteItem): string {
    if (n.key.startsWith("note:")) return n.title?.trim() || "Untitled note";
    if (n.key.startsWith("class:")) return `${n.key.slice(6)} class notes`;
    const [y, m, d] = n.key.slice(4).split("-").map(Number);
    return new Date(y, m - 1, d).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
  }
  const edited = (t: number) => new Date(t * 1000).toLocaleDateString(undefined, { month: "short", day: "numeric" });

  function pull(b: Notebook) {
    if (b.code === current) return;
    buzz.select();
    current = b.code;
  }

  export function newNote(code = current) {
    openNote(`note:${crypto.randomUUID()}`, "New note", "", code || undefined);
  }

  // A note's actions (C5): from its menu, or a long press.
  let acting = $state<NoteItem | null>(null);
  let moving = $state(false);
  let confirming = $state(false);
  let problem = $state("");
  $effect(() => {
    if (acting) return closable(() => (acting = null));
  });
  function act(n: NoteItem) {
    buzz.tick();
    [acting, moving, confirming, problem] = [n, false, false, ""];
  }
  let press: ReturnType<typeof setTimeout> | undefined;
  let held = false;
  const hold = (n: NoteItem) => {
    held = false;
    press = setTimeout(() => ((held = true), act(n)), 500);
  };
  const release = () => clearTimeout(press);

  async function run(job: () => Promise<unknown>) {
    try {
      await job();
      await refreshNotes();
      acting = null;
    } catch (e) {
      problem = friendly(e);
    }
  }
  const pin = (n: NoteItem) => run(() => api.setNotePin(n.key, !n.pinned));
  const move = (n: NoteItem, code: string) => run(() => api.setNoteSubject(n.key, code || null));
  const remove = (n: NoteItem) => run(() => api.deleteNote(n.key));

  let exportNote = $state("");
  async function exportAll() {
    exportNote = "";
    try {
      if (app.notes.some((n) => n.photos)) {
        await shareFile("IntPortal notes.zip", "application/zip", await api.notesZip(null));
        exportNote = photosInShare;
      } else await shareFile("IntPortal notes.md", "text/markdown", await api.notesMarkdown(null));
    } catch (e) {
      exportNote = friendly(e);
    }
  }

  // Now and then one pixel twinkles, so the shelf reads as alive without anything else moving.
  let twinkle = $state(-1);
  $effect(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const id = setInterval(() => {
      if (still || document.hidden) return;
      twinkle = Math.floor(Math.random() * 40);
      setTimeout(() => (twinkle = -1), 600);
    }, 3200);
    return () => clearInterval(id);
  });
</script>

{#snippet noteRow(n: NoteItem)}
  <li>
    <button class="rowb" data-source={n.key} onclick={() => !held && openNote(n.key, heading(n), n.title)} onpointerdown={() => hold(n)} onpointerup={release} onpointerleave={release} oncontextmenu={(e) => e.preventDefault()}>
      <span class="tx">
        <strong>{#if n.pinned}<span class="pinned">Pinned</span>{/if}{heading(n)}</strong>
        <small>{edited(n.updated)} · {previewOf(n) || "Empty"}</small>
      </span>
    </button>
    <button class="more" aria-label="More for {heading(n)}" onclick={() => act(n)}><i></i><i></i><i></i></button>
  </li>
{/snippet}

{#snippet deckRow(d: ShelfDeck)}
  <li>
    <button class="rowb" onclick={() => (app.deck = d.id)}>
      <span class="tx"><strong>{d.name}</strong><small>{d.cards} cards</small></span>
      {#if d.due}<span class="val due">{d.due} due</span>{:else}<span class="val">Caught up</span>{/if}
    </button>
  </li>
{/snippet}

<input class="search" type="search" bind:value={query} placeholder="Search notes and decks" aria-label="Search notes and decks" />

{#if query.trim()}
  <section class="card notch list" aria-label="Search results">
    {#if found.notes.length || found.decks.length}
      <ul>
        {#each found.notes as n (n.key)}{@render noteRow(n)}{/each}
        {#each found.decks as d (d.id)}{@render deckRow(d)}{/each}
      </ul>
    {:else}
      <p class="fine pad">Nothing mentions "{query.trim()}".</p>
    {/if}
  </section>
{:else}
  <div class="spines" role="group" aria-label="Notebooks" class:still>
    {#each books as b, i (b.code)}
      {#if b.past && !books[i - 1]?.past}<span class="gap" aria-hidden="true">Past</span>{/if}
      {@const c = colorOf(b.code)}
      <button class="spine" style:--c={c} style:--on-c={inkOn(c)} style:--h="{heightOf(b)}px" aria-pressed={b.code === open.code} aria-label={label(b)} onclick={() => pull(b)}>
        <b>{b.code ? b.code.split(" ")[0] : "General"}</b>
        {#if b.code}<small>{b.code.split(" ").slice(1).join(" ")}</small>{/if}
        <span class="well" aria-hidden="true">
          {#each pixels(b) as p, k (k)}<u class={p} class:tw={twinkle === (i * 7 + k) % 40} style:--i={k}></u>{/each}
        </span>
      </button>
    {/each}
  </div>

  <section class="card notch list" aria-label={open.code || "General"}>
    <div class="head">
      <div>
        <p class="name">{open.code ? `${open.code}${open.past ? "" : ` · ${open.name}`}` : "General"}</p>
        <p class="fine">{open.notes.length} {open.notes.length === 1 ? "note" : "notes"}{open.due ? ` · ${open.due} ${open.due === 1 ? "card" : "cards"} due` : ""}{open.past ? " · past subject" : ""}</p>
      </div>
      <button class="ghost" onclick={() => newNote(open.code)}>New note</button>
    </div>
    {#if open.notes.length}
      <ul>
        {#each open.notes as n (n.key)}{@render noteRow(n)}{/each}
      </ul>
    {:else}
      <p class="fine pad">{open.code ? "Nothing here yet. Notes you keep from this class on Schedule land here too." : "Day notes and notes without a subject land here."}</p>
    {/if}
  </section>
  {#if app.notes.length}
    <button class="link" onclick={exportAll}>Export all notes</button>
    {#if exportNote}<p class="fine" role="alert">{exportNote}</p>{/if}
  {/if}
{/if}

{#if acting}
  {@const n = acting}
  <button class="scrim" aria-label="Close" onclick={() => (acting = null)}></button>
  <div class="sheet card notch" role="dialog" aria-label={heading(n)}>
    <p class="label">{heading(n)}</p>
    {#if moving}
      {#each [[GENERAL, "General"] as [string, string], ...subjects] as [code, name] (code)}
        <button class="opt" aria-pressed={subjectOf(n) === code} onclick={() => move(n, code)}>{code ? `${code} · ${name}` : name}</button>
      {/each}
      <button class="opt quiet" onclick={() => (moving = false)}>Back</button>
    {:else if confirming}
      <p class="fine">Delete this note? This can't be undone.</p>
      <button class="opt danger" onclick={() => remove(n)}>Delete</button>
      <button class="opt quiet" onclick={() => (confirming = false)}>Keep it</button>
    {:else}
      {#if !n.key.startsWith("day:")}<button class="opt" onclick={() => pin(n)}>{n.pinned ? "Unpin" : "Pin to the top"}</button>{/if}
      {#if n.key.startsWith("note:")}<button class="opt" onclick={() => (moving = true)}>Move to another subject</button>{/if}
      <button class="opt danger" onclick={() => (confirming = true)}>Delete</button>
    {/if}
    {#if problem}<p class="fine bad" role="alert">{problem}</p>{/if}
  </div>
{/if}

<style>
  .search {
    height: 44px;
    min-width: 0;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, var(--text-body));
  }
  .spines {
    display: flex;
    align-items: flex-end;
    gap: 6px;
    margin-inline: calc(var(--gutter) * -1);
    padding: 20px var(--gutter) 0;
    overflow-x: auto;
    overflow-y: hidden;
    scrollbar-width: none;
  }
  .spines::-webkit-scrollbar {
    display: none;
  }
  .gap {
    flex: none;
    align-self: center;
    writing-mode: vertical-rl;
    rotate: 180deg;
    font: 500 var(--text-label) var(--font-label);
    letter-spacing: var(--label-track);
    text-transform: uppercase;
    color: var(--ink-3);
  }
  .spine {
    --s: var(--step);
    position: relative;
    flex: none;
    width: 70px;
    height: var(--h);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 2px;
    padding: 8px 6px 6px;
    border: 0;
    color: var(--on-c);
    text-align: left;
    background: var(--c);
    box-shadow:
      inset 3px 0 0 rgb(255 255 255 / 0.16),
      inset -3px 0 0 rgb(0 0 0 / 0.22),
      inset 0 -3px 0 rgb(0 0 0 / 0.22);
    clip-path: polygon(0 var(--s), var(--s) var(--s), var(--s) 0, calc(100% - var(--s)) 0, calc(100% - var(--s)) var(--s), 100% var(--s), 100% 100%, 0 100%);
    transition:
      translate var(--t-flow) var(--ease),
      height var(--t-flow) var(--ease);
  }
  .spine[aria-pressed="true"] {
    translate: 0 -14px;
  }
  .spine b {
    font: 800 min(0.824rem, 25px) / 1.05 var(--font-ui);
  }
  .spine small {
    font: 600 min(0.706rem, 22px) / 1.05 var(--font-ui);
    font-variant-numeric: tabular-nums;
  }
  .well {
    display: flex;
    flex-wrap: wrap-reverse;
    align-content: flex-start;
    gap: 2px;
    width: 100%;
    min-height: 22px;
    margin-top: auto;
    padding: 3px;
    background: rgb(0 0 0 / 0.42);
  }
  .well u {
    display: block;
    width: 8px;
    height: 8px;
    text-decoration: none;
  }
  .well u.note {
    background: var(--parch);
  }
  .well u.due {
    background: var(--gold);
    box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.25);
    animation: beat 2.2s ease-in-out infinite;
    animation-delay: calc(var(--i) * -0.23s);
  }
  .still .well u.due {
    animation: none;
  }
  .well u.tw {
    animation: twinkle 0.6s ease-in-out;
  }
  @keyframes beat {
    50% {
      opacity: 0.55;
    }
  }
  @keyframes twinkle {
    50% {
      scale: 1.25;
      filter: brightness(1.4);
    }
  }
  .list {
    --step: 4px;
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    padding: 4px 0;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 10px;
    padding: 10px 14px 6px;
  }
  .name {
    margin: 0;
    font-weight: 700;
    color: var(--ink);
  }
  .fine {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--ink-2);
  }
  .pad {
    padding: 10px 14px 12px;
  }
  .bad {
    color: var(--bad);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  li {
    display: flex;
    align-items: center;
  }
  li + li {
    border-top: 1px solid var(--edge);
  }
  .rowb {
    flex: 1;
    min-width: 0;
    min-height: 52px;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 14px;
    border: 0;
    background: none;
    color: var(--ink);
    text-align: left;
    -webkit-touch-callout: none;
    user-select: none;
    transition: scale var(--t-quick) var(--ease);
  }
  .rowb:active {
    scale: 0.98;
  }
  .tx {
    flex: 1;
    min-width: 0;
  }
  .tx strong {
    display: block;
    font-weight: 600;
  }
  .tx small {
    display: block;
    overflow: hidden;
    font-size: var(--text-caption);
    color: var(--ink-2);
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .pinned {
    margin-right: 6px;
    font: 500 min(0.588rem, 18px) var(--font-label);
    letter-spacing: var(--label-track);
    text-transform: uppercase;
    color: var(--gold);
  }
  .val {
    font-size: var(--text-caption);
    color: var(--ink-2);
    white-space: nowrap;
  }
  .val.due {
    font-weight: 700;
    color: var(--gold);
  }
  .more {
    flex: none;
    width: 44px;
    height: 44px;
    display: grid;
    grid-auto-flow: column;
    place-content: center;
    gap: 3px;
    border: 0;
    background: none;
  }
  .more i {
    width: 3px;
    height: 3px;
    background: var(--ink-3);
  }
  .ghost {
    flex: none;
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink);
    font-weight: 700;
  }
  .link {
    justify-self: start;
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink-2);
    font-weight: 600;
  }
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 40;
    border: 0;
    border-radius: 0;
    background: rgb(0 0 0 / 0.45);
  }
  .sheet {
    --step: 4px;
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 12px);
    z-index: 41;
    display: grid;
    gap: 6px;
    max-height: 70vh;
    overflow-y: auto;
    padding: 16px;
    background: var(--card-2);
    animation: rise 0.3s var(--ease) both;
  }
  .opt {
    min-height: 48px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-weight: 600;
    text-align: left;
  }
  .opt[aria-pressed="true"] {
    box-shadow: inset 0 0 0 1px var(--gold);
  }
  .opt.danger {
    color: var(--bad);
  }
  .opt.quiet {
    background: none;
    box-shadow: none;
    color: var(--ink-2);
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(12px);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .well u.due,
    .well u.tw,
    .sheet {
      animation: none;
    }
    .spine {
      transition: none;
    }
  }
</style>

<script lang="ts">
  import PixelNum from "../PixelNum.svelte";
  import { counted } from "../count.svelte";
  // Study opens on a home of part tiles (spec 046 C1): Review, Notes, Cards and Done,
  // each opening its own page with "‹ Study" as the way back.
  import DeckPage from "../DeckPage.svelte";
  import Shelf, { colorOf } from "../Shelf.svelte";
  import { CARDS_PER_PX, deckBar, deckGroups, GENERAL, pixels, shelves, weekBars } from "../shelf";
  import StudySession from "../StudySession.svelte";
  import ErrorCard from "../ErrorCard.svelte";
  import Flame from "../Flame.svelte";
  import LarNote from "../LarNote.svelte";
  import Skeleton from "../Skeleton.svelte";
  import { api, isoDate, type Deck } from "../api";
  import { closable } from "../back";
  import { buzz } from "../haptics";
  import { resource } from "../load.svelte";
  import { app, openNote } from "../state.svelte";
  import { dueDecks } from "../planning";
  import { friendly } from "../errors";
  import { assis } from "../assis/assis.svelte";

  const study = resource(() => api.study(isoDate(new Date())));
  const overview = $derived(study.current.state === "ready" ? study.current.value : null);
  const decks = $derived(overview?.decks ?? []);
  const dueCount = counted("due", () => overview?.due ?? null);
  const todayCount = counted("reviews", () => overview?.reviews_today ?? null);
  const bars = $derived(weekBars(overview?.week ?? [0, 0, 0, 0, 0, 0, 0], new Date()));
  const weekTotal = $derived(bars.reduce((a, b) => a + b.n, 0));
  const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;

  // Which part is open. Home every time Study opens, as the mockup did.
  type Part = "home" | "review" | "notes" | "cards" | "done";
  let part = $state<Part>("home");
  // Opening slides in from the right, going back from the left (C1).
  let from = $state(28);
  function go(to: Part) {
    from = to === "home" ? -28 : 28;
    part = to;
    scrollTo({ top: 0 });
  }
  // The phone's back gesture returns to the tiles.
  $effect(() => {
    if (part !== "home") return closable(() => go("home"));
  });

  // Leaving the tab closes the deck, as it always did.
  $effect(() => () => {
    app.deck = null;
  });
  // The crystal's + (spec 046 C1b): Ask LAR first, then what this screen can add.
  $effect(() => {
    const fresh = { label: "New note", run: () => openNote(`note:${crypto.randomUUID()}`, "New note", "", shelfAt || undefined) };
    const note = { label: "Today's note", run: () => openNote(`day:${isoDate(new Date())}`, new Date().toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })) };
    // The form lives on Cards, so a deck page or a review offers just the notes.
    const deck = { label: "New deck", run: () => { if (part !== "cards") go("cards"); naming = true; } };
    assis.menu = reviewing || app.deck ? [fresh, note] : [fresh, note, deck];
    return () => (assis.menu = []);
  });
  // Spec 040 C9: every due card across decks in one session.
  let reviewing = $state<Deck[] | null>(null);
  let reviewLimit = $state(0);
  let notice = $state("");
  // A review asked for from elsewhere (LAR's plan, a notification): start it here.
  $effect(() => {
    const ask = app.review;
    if (!ask) return;
    app.review = null;
    notice = "";
    api.study(isoDate(new Date()))
      .then((o) => Promise.all(dueDecks(o.decks, ask.subject).map((d) => api.deck(d.id))))
      .then((ds) => {
        if (ds.length) [reviewing, reviewLimit] = [ds, ask.limit];
        else notice = "Nothing due right now.";
      })
      .catch((e) => (notice = friendly(e)));
  });
  // The notebook pulled out on the shelf; a new note from the + is filed there (046 C2).
  let shelfAt = $state(GENERAL);
  async function reviewAll() {
    const due = decks.filter((d) => d.due > 0);
    reviewing = await Promise.all(due.map((d) => api.deck(d.id)));
  }

  let naming = $state(false);
  let name = $state("");
  let subject = $state("");
  let problem = $state("");

  const subjects = $derived<[string, string][]>([...new Map((app.snapshot?.sessions ?? []).map((s) => [s.subject_code, s.description] as [string, string])).entries()]);
  const books = $derived(shelves(subjects, app.notes, decks));
  const groups = $derived(deckGroups(subjects, decks));
  const totalCards = $derived(decks.reduce((a, d) => a + d.cards, 0));

  async function create() {
    try {
      const deck = await api.saveDeck({ id: crypto.randomUUID(), name: name.trim(), subject: subject || null, cards: [] });
      naming = false;
      name = "";
      subject = "";
      problem = "";
      buzz.tick();
      study.reload();
      app.deck = deck.id;
    } catch (e) {
      problem = friendly(e);
    }
  }
</script>

{#snippet chev()}
  <svg class="chev" viewBox="0 0 4 7" width="6" height="10" shape-rendering="crispEdges" aria-hidden="true"><path d="M0 0h1v1h1v1h1v1h1v1h-1v1h-1v1h-1v1h-1z" fill="currentColor" /></svg>
{/snippet}

{#snippet back()}
  <button class="back" onclick={() => go("home")}>‹ Study</button>
{/snippet}

{#snippet px(n: number, cls = "")}
  {#each { length: n } as _, i (i)}<u class={cls}></u>{/each}
{/snippet}

{#if reviewing}
  <StudySession decks={reviewing} mode="flash" title="All due" all limit={reviewLimit} onclose={() => { reviewing = null; study.reload(); }} />
{:else if app.deck}
  {#key app.deck}<DeckPage id={app.deck} onclose={() => { app.deck = null; study.reload(); }} />{/key}
{:else}
  {#key part}
    <div class="screen" style:--from="{from}px">
      {#if part === "home"}
        <h1>Study</h1>
        {#if notice}<p class="notice" role="status">{notice}</p>{/if}
        {#if study.current.state === "failed"}<ErrorCard error={study.current.error} onretry={study.reload} />{/if}

        <button class="card notch tile" onclick={() => go("review")}>
          <span class="tl">Review{@render chev()}</span>
          <span class="big num"><PixelNum text={String(Math.round(dueCount.value ?? 0))} size={6} /><span>{overview?.due === 1 ? "card" : "cards"} due now</span></span>
          {#if overview?.due}<span class="dp" aria-hidden="true">{@render px(Math.min(overview.due, 30))}</span>{/if}
          <span class="tm">Streak {plural(overview?.streak ?? 0, "day")} · {overview?.reviews_today ?? 0} reviewed today</span>
        </button>

        <div class="two">
          <button class="card notch tile" onclick={() => go("notes")}>
            <span class="tl">Notes{@render chev()}</span>
            <!-- ponytail: the first 6 notebooks fit a half-width tile; the rest are on the shelf. -->
            <span class="mini" aria-hidden="true">
              {#each books.slice(0, 6) as b (b.code)}
                {@const p = pixels(b)}
                <i style:--c={colorOf(b.code)} style:--h="{30 + p.length * 3}px"><span>{#each p as k, j (j)}<u class={k}></u>{/each}</span></i>
              {/each}
            </span>
            <span class="tm">{plural(app.notes.length, "note")} in {plural(books.length, "notebook")}</span>
          </button>
          <button class="card notch tile" onclick={() => go("cards")}>
            <span class="tl">Cards{@render chev()}</span>
            <span class="decks" aria-hidden="true">
              {#each decks.slice(0, 4) as d (d.id)}
                {@const bar = deckBar(d)}
                <span><span class="sq" style:--c={colorOf(d.subject?.trim() || GENERAL)}></span><span class="dp">{@render px(bar.gold)}{@render px(bar.rest, "o")}</span></span>
              {/each}
            </span>
            <span class="tm">{decks.length ? `${plural(decks.length, "deck")}, ${plural(totalCards, "card")}` : "No decks yet. Make your first."}</span>
          </button>
        </div>

        <button class="card notch tile wide" onclick={() => go("done")}>
          <span class="tl">Done{@render chev()}</span>
          <span class="mbars" aria-hidden="true">{#each bars as b, i (i)}<span class:t={b.today}>{#if b.px}{@render px(Math.min(9, b.px))}{:else}<u class="z"></u>{/if}</span>{/each}</span>
          <span class="tm">{plural(weekTotal, "card")} in 7 days</span>
        </button>
      {:else if part === "review"}
        {@render back()}
        <h1>Review</h1>
        <section class="card notch rv">
          <p class="big num"><PixelNum text={String(Math.round(dueCount.value ?? 0))} size={6} /><span>{overview?.due === 1 ? "card" : "cards"} due now</span></p>
          {#if decks.length}
            <div class="dk">
              {#each decks as d (d.id)}
                <span class="sq" style:--c={colorOf(d.subject?.trim() || GENERAL)}></span>
                <span class="dn">{d.name}</span>
                <span class="dp" aria-hidden="true">{@render px(Math.min(d.due, 8))}</span>
                <span class="dc" class:z={!d.due}>{d.due || "Caught up"}</span>
              {/each}
            </div>
          {/if}
        </section>
        <div class="sts">
          <section class="card notch st"><p class="label">Streak</p><p class="num">{#if overview?.streak}<Flame />{/if}<PixelNum text={String(overview?.streak ?? 0)} size={4} /><span>{overview?.streak === 1 ? "day" : "days"}</span></p></section>
          <section class="card notch st"><p class="label">Today</p><p class="num"><PixelNum text={String(Math.round(todayCount.value ?? 0))} size={4} /><span>{overview?.reviews_today === 1 ? "card" : "cards"}</span></p></section>
        </div>
        <button class="primary start" onclick={reviewAll} disabled={!overview?.due}>{overview?.due ? `Review ${overview.due} due` : "All caught up"}</button>
      {:else if part === "done"}
        {@render back()}
        <h1>Done</h1>
        <section class="card notch wk">
          <div class="bars" role="img" aria-label="Cards reviewed each day for the last 7 days: {bars.map((b) => `${b.day} ${b.n}`).join(', ')}">
            {#each bars as b, i (i)}
              <div class:t={b.today}><span>{#if b.px}{@render px(b.px)}{:else}<u class="z"></u>{/if}</span><small>{b.day}</small></div>
            {/each}
          </div>
          <p class="fine"><b>{weekTotal}</b> {weekTotal === 1 ? "card" : "cards"} in the last 7 days. One pixel is {CARDS_PER_PX} cards.</p>
        </section>
        <div class="sts">
          <section class="card notch st"><p class="label">Streak</p><p class="num">{#if overview?.streak}<Flame />{/if}<PixelNum text={String(overview?.streak ?? 0)} size={4} /><span>{overview?.streak === 1 ? "day" : "days"}</span></p></section>
          <section class="card notch st"><p class="label">Today</p><p class="num"><PixelNum text={String(overview?.reviews_today ?? 0)} size={4} /><span>{overview?.reviews_today === 1 ? "card" : "cards"}</span></p></section>
        </div>
      {:else if part === "notes"}
        {@render back()}
        <h1>Notes</h1>
        <Shelf {decks} bind:current={shelfAt} />
      {:else}
        {@render back()}
        <div class="head">
          <h1>Cards</h1>
          {#if !naming}<button class="ghost sm" onclick={() => (naming = true)}>+ New deck</button>{/if}
        </div>
        {#if naming}
          <section class="card notch new">
            <input bind:value={name} placeholder="Deck name, e.g. DSA midterm" aria-label="Deck name" />
            <select bind:value={subject} aria-label="Subject">
              <option value="">No subject</option>
              {#each subjects as [code, desc] (code)}<option value={code}>{code} · {desc}</option>{/each}
            </select>
            <div class="row">
              <button class="primary" onclick={create} disabled={!name.trim()}>Create</button>
              <button class="ghost" onclick={() => (naming = false)}>Cancel</button>
            </div>
            {#if problem}<p class="problem">{problem}</p>{/if}
          </section>
        {/if}
        {#if study.current.state === "loading"}
          <Skeleton rows={2} height={64} />
        {:else if study.current.state === "failed"}
          <ErrorCard error={study.current.error} onretry={study.reload} />
        {:else if !decks.length}
          <LarNote gesture="wave">No decks yet. Make one per subject or per exam, then paste your terms in as "term - meaning".</LarNote>
        {:else}
          <section class="card notch list" aria-label="Decks">
            {#each groups as g (g.code)}
              <p class="gl"><span class="sq" style:--c={colorOf(g.code)}></span>{g.code || "General"}</p>
              <ul>
                {#each g.decks as d (d.id)}
                  <li>
                    <button class="rowb" onclick={() => (app.deck = d.id)}>
                      <span class="tx"><strong>{d.name}</strong><small>{plural(d.cards, "card")}</small></span>
                      {#if d.due}<span class="val due">{d.due} due</span>{:else}<span class="val">Caught up</span>{/if}
                    </button>
                  </li>
                {/each}
              </ul>
            {/each}
          </section>
          <p class="fine">{plural(decks.length, "deck")}, {plural(totalCards, "card")}. Tap a deck to add cards or study it.</p>
        {/if}
      {/if}
    </div>
  {/key}
{/if}

<style>
  .screen {
    display: grid;
    gap: 12px;
    grid-template-columns: minmax(0, 1fr);
    /* Smooth Travel: a part slides in over --t-flow, from the side it lives on. */
    animation: part-in var(--t-flow) var(--ease) backwards;
  }
  @keyframes part-in {
    from {
      opacity: 0;
      translate: var(--from) 0;
    }
  }
  @keyframes part-fade {
    from {
      opacity: 0;
    }
  }
  /* Reduce Motion clamps every animation; parts still cross-fade, in place. */
  @media (prefers-reduced-motion: reduce) {
    .screen.screen {
      animation: part-fade 0.2s var(--ease) backwards !important;
    }
  }
  h1 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: var(--text-display);
    font-weight: var(--title-weight);
    letter-spacing: var(--title-track);
  }
  .back {
    justify-self: start;
    min-height: 44px;
    margin: -6px 0 -12px;
    padding: 0;
    background: none;
    color: var(--gold);
    font-family: inherit;
    font-weight: 600;
    font-size: min(0.882rem, 27px);
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
  }

  /* The tiles */
  .tile {
    --step: 4px;
    width: 100%;
    height: auto;
    display: grid;
    gap: 10px;
    align-content: start;
    padding: 14px;
    border-radius: 0;
    text-align: left;
    color: var(--ink);
    font: inherit;
    transition: scale var(--t-quick) var(--ease);
  }
  .tile:active {
    scale: 0.98;
  }
  .tile:focus-visible {
    outline: 0;
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .tl {
    display: flex;
    align-items: center;
    justify-content: space-between;
    font: 600 min(0.882rem, 27px) / 1.2 var(--font-ui);
  }
  .chev {
    color: var(--ink-3);
  }
  .tm {
    font-size: var(--text-caption);
    line-height: 1.3;
    color: var(--ink-2);
  }
  .two {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }
  .big {
    margin: 0;
    display: flex;
    align-items: flex-end;
    gap: 10px;
    color: var(--ink);
  }
  .big > span {
    font-size: min(0.882rem, 27px);
    line-height: 1;
    color: var(--ink-2);
  }
  .dp {
    display: flex;
    flex-wrap: wrap;
    gap: 2px;
    min-width: 0;
  }
  u {
    display: block;
    width: 6px;
    height: 6px;
    background: var(--gold);
    text-decoration: none;
  }
  u.o {
    background: color-mix(in srgb, var(--ink) 22%, transparent);
  }
  .tile > .dp u {
    width: 8px;
    height: 8px;
  }
  .sq {
    width: 12px;
    height: 12px;
    background: var(--c);
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% calc(100% - 2px), calc(100% - 2px) calc(100% - 2px), calc(100% - 2px) 100%, 2px 100%, 2px calc(100% - 2px), 0 calc(100% - 2px));
  }
  /* Notes tile: a little shelf, each notebook lit with its notes and due cards. */
  .mini {
    display: flex;
    align-items: flex-end;
    gap: 4px;
    height: 78px;
    overflow: hidden;
  }
  .mini i {
    flex: none;
    width: 18px;
    height: var(--h);
    padding: 2px;
    display: flex;
    align-items: flex-end;
    background: var(--c);
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% 100%, 0 100%);
    box-shadow:
      inset 2px 0 0 rgb(255 255 255 / 0.16),
      inset -2px 0 0 rgb(0 0 0 / 0.22);
  }
  .mini i > span {
    width: 100%;
    min-height: 6px;
    padding: 1px;
    display: flex;
    flex-wrap: wrap-reverse;
    gap: 1px;
    background: rgb(0 0 0 / 0.42);
  }
  .mini u {
    width: 3px;
    height: 3px;
  }
  .mini u.note {
    background: var(--parch);
  }
  /* Cards tile: a bar per deck, gold for what's due. */
  .decks {
    display: grid;
    gap: 8px;
    height: 78px;
    align-content: end;
  }
  .decks > span {
    display: grid;
    grid-template-columns: 12px minmax(0, 1fr);
    gap: 6px;
    align-items: center;
  }
  .decks .dp {
    gap: 1px;
    flex-wrap: nowrap;
    overflow: hidden;
  }
  .decks u {
    flex: none;
    width: 4px;
    height: 8px;
  }

  /* Done: a pixel per 3 cards, a bar per day, today in gold. */
  .mbars {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    align-items: end;
    height: 36px;
  }
  .mbars > span,
  .bars > div > span {
    display: flex;
    flex-direction: column-reverse;
    align-items: center;
    gap: 2px;
  }
  .mbars u,
  .bars u {
    display: block;
    width: 12px;
    height: 2px;
    background: var(--ink-3);
    text-decoration: none;
  }
  .bars u {
    width: 14px;
    height: 6px;
  }
  .mbars .t u,
  .bars .t u {
    background: var(--gold);
  }
  /* A day with no reviews keeps one faint pixel, so the week still reads as seven days. */
  .mbars u.z,
  .bars u.z {
    opacity: 0.35;
  }
  .wk {
    display: grid;
    gap: 10px;
  }
  .bars {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
  }
  .bars > div {
    display: grid;
    justify-items: center;
    gap: 6px;
  }
  .bars > div > span {
    height: 94px;
  }
  .bars small {
    font: 500 11px var(--font-pixel, monospace);
    color: var(--ink-3);
  }
  .bars .t small {
    color: var(--gold);
  }
  .wk b {
    color: var(--ink);
  }

  /* Review */
  .rv {
    --step: 4px;
    display: grid;
    gap: 14px;
    padding: 16px;
  }
  .dk {
    display: grid;
    grid-template-columns: 12px minmax(0, 1fr) auto auto;
    align-items: center;
    gap: 8px;
    font-size: var(--text-caption);
  }
  .dn {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .dk .dp {
    flex-wrap: nowrap;
  }
  .dc {
    min-width: 18px;
    text-align: right;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: var(--gold);
  }
  .dc.z {
    font-weight: 400;
    color: var(--ink-3);
  }
  .sts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }
  .st {
    --step: 4px;
    display: grid;
    gap: 6px;
    padding: 12px;
  }
  .st p {
    margin: 0;
  }
  .st .num {
    display: flex;
    align-items: flex-end;
    gap: 6px;
    color: var(--ink);
  }
  .st .num span {
    font-size: var(--text-caption);
    line-height: 1;
    color: var(--ink-2);
  }
  .start {
    min-height: 52px;
    font-size: var(--text-body);
  }

  /* Cards */
  .list {
    --step: 4px;
    padding: 2px 0;
  }
  .gl {
    margin: 0;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 12px 14px 0;
    font: 500 min(0.706rem, 22px) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--ink-2);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  li + li {
    border-top: 1px solid var(--edge);
  }
  .rowb {
    width: 100%;
    min-height: 52px;
    height: auto;
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 8px 14px;
    border-radius: 0;
    background: none;
    color: var(--ink);
    text-align: left;
    font: inherit;
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
  .tx small,
  .fine {
    display: block;
    margin: 0;
    font-size: var(--text-caption);
    color: var(--ink-2);
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
  .new {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px;
  }
  input,
  select {
    height: 44px;
    min-width: 0;
    padding: 0 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, var(--text-body));
  }
  .row {
    display: flex;
    gap: 8px;
  }
  button {
    height: 44px;
    padding: 0 16px;
    border: 0;
    border-radius: 10px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  button:disabled {
    opacity: 0.4;
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .ghost {
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
  }
  .ghost.sm {
    height: 44px;
    padding: 0 12px;
  }
  .notice {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-2);
  }
  .problem {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--bad);
  }
</style>

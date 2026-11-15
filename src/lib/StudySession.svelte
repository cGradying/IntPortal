<script lang="ts" module>
  export type Mode = "flash" | "type" | "choice";
</script>

<script lang="ts">
  import { friendly } from "./errors";
  // One pass through due cards: one deck's (every card when none is due, as
  // practice), or every deck's at once, oldest due first (spec 040 C9). Flashcards take the student's own rating; typed and
  // multiple-choice answers rate themselves: right is Good, wrong is Again.
  import { closable } from "./back";
  import WhyButton from "./assis/WhyButton.svelte";
  import Lar from "./lar/Lar.svelte";
  import { api, isoDate, type Card, type Deck, type Rating } from "./api";
  import { buzz } from "./haptics";
  import { dueQueue, type Entry } from "./dueQueue";
  import { dueIn, interval } from "./interval";

  let { decks, mode, onclose, title, all = false, limit = 0 }: { decks: Deck[]; mode: Mode; onclose: () => void; title?: string; all?: boolean; limit?: number } = $props();
  $effect(() => closable(() => onclose()));

  const now = Math.floor(Date.now() / 1000);
  // svelte-ignore state_referenced_locally
  const mixed = all || decks.length > 1;
  // svelte-ignore state_referenced_locally
  const dueCards: Entry[] = dueQueue(decks, now);
  const practice = dueCards.length === 0;
  // svelte-ignore state_referenced_locally
  const queue: Entry[] = (mixed ? dueCards : shuffle(practice ? decks[0].cards.map((card) => ({ deck: decks[0], card })) : dueCards)).slice(0, limit || undefined);
  // svelte-ignore state_referenced_locally
  const name = title ?? decks[0]?.name ?? "";

  let index = $state(0);
  let shown = $state(false);
  let typed = $state("");
  let verdict = $state<null | boolean>(null);
  let options = $state<string[]>([]);
  let picked = $state<string | null>(null);
  let right = $state(0);
  let problem = $state("");
  // What each rating would schedule, shown under its button (#268), and what each card got.
  let hints = $state<string[] | null>(null);
  let log = $state<{ id: string; front: string; rating: Rating; due: number | null }[]>([]);
  const RATES: [Rating, string][] = [["again", "Again"], ["hard", "Hard"], ["good", "Good"], ["easy", "Easy"]];
  const word = (r: Rating) => RATES.find(([k]) => k === r)![1];

  const card = $derived(queue[index]?.card as Card);
  const deck = $derived(queue[index]?.deck ?? decks[0]);
  const finished = $derived(index >= queue.length);
  // Finishing a pass does not celebrate (spec 045 C17): only a first sign-in, a done and a new grade do.

  function shuffle<T>(xs: T[]): T[] {
    const a = [...xs];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  $effect(() => {
    hints = null;
    if (mode !== "flash" || practice || finished) return;
    const c = card;
    api.reviewPreview(c.memory).then((ss) => { if (card === c) hints = ss.map(interval); }, () => {});
  });

  $effect(() => {
    if (mode !== "choice" || finished) return;
    const { deck: d, card: c } = queue[index];
    const at = d.cards.findIndex((x) => x.id === c.id);
    api.distractors(d.cards, at, index).then((ds) => (options = shuffle([c.back, ...ds])));
  });

  async function rate(r: Rating) {
    try {
      // Practice (nothing was due) leaves the schedule alone: reviewing a
      // card early would push it out before it's been forgotten.
      const due = practice ? null : ((await api.reviewCard(deck.id, card.id, r, isoDate(new Date()))).deck.cards.find((c) => c.id === card.id)?.memory.due ?? null);
      log.push({ id: `${deck.id}/${card.id}`, front: card.front, rating: r, due });
      if (r !== "again") right++;
      buzz.tick();
      if (index + 1 >= queue.length) buzz.done();
      index++;
      shown = false;
      typed = "";
      verdict = null;
      picked = null;
      problem = "";
    } catch (e) {
      problem = friendly(e);
    }
  }

  async function check() {
    verdict = await api.checkAnswer(card, typed);
    (verdict ? buzz.tick : buzz.fail)();
  }

  function choose(o: string) {
    if (picked) return;
    picked = o;
    verdict = o === card.back;
    (verdict ? buzz.tick : buzz.fail)();
  }
</script>

<div class="session" role="dialog" aria-label="Studying {name}">
  <header>
    <button class="back" onclick={onclose}>‹ {name}</button>
    <p class="label num">{Math.min(index + 1, queue.length)} / {queue.length}{practice ? " · practice" : ""}</p>
  </header>
  <div class="bar"><i style:width="{(index / queue.length) * 100}%"></i></div>

  {#if finished}
    <section class="card notch face">
      <div class="lar"><Lar size={4} state="idle" /></div>
      <p class="label">Done</p>
      <h2>{right} of {queue.length} remembered</h2>
      {#if queue.length}<p class="score num">{Math.round((right / queue.length) * 100)}% right</p>{/if}
      <p class="fine">{practice ? "Practice round: the schedule is unchanged." : "FSRS has scheduled each card for when you're about to forget it."}</p>
      {#if log.length}
        <ul class="recap">
          {#each log as l (l.id)}
            <li><span>{l.front}</span><small class:again={l.rating === "again"}>{word(l.rating)}{l.due !== null ? `, ${dueIn(l.due - now)}` : ""}</small></li>
          {/each}
        </ul>
      {/if}
      <button class="primary" onclick={onclose}>{mixed ? "Back to Study" : "Back to the deck"}</button>
    </section>
  {:else if mode === "flash"}
    <button class="card notch face tap" onclick={() => { if (!shown) buzz.tick(); shown = true; }}>
      <p class="label">{mixed ? deck.name : "Term"}</p>
      <h2>{card.front}</h2>
      {#if shown}<p class="answer">{card.back}</p>{:else}<p class="fine">Tap to show the meaning</p>{/if}
    </button>
    {#if shown}
      <div class="rates">
        {#each RATES as [r, label], i (r)}
          <button class:again={r === "again"} onclick={() => rate(r)} aria-label={hints ? `${label}, next in ${hints[i]}` : label}>{label}<small aria-hidden="true">{hints?.[i] ?? ""}</small></button>
        {/each}
      </div>
    {/if}
  {:else if mode === "type"}
    <section class="card notch face">
      <p class="label">{mixed ? deck.name : "Meaning"}</p>
      <h2>{card.back}</h2>
      <p class="fine">Type the term.</p>
    </section>
    <input bind:value={typed} autocapitalize="off" spellcheck="false" placeholder="Your answer" aria-label="Your answer" onkeydown={(e) => e.key === "Enter" && verdict === null && check()} />
    {#if verdict === null}
      <button class="primary" onclick={check} disabled={!typed.trim()}>Check</button>
    {:else}
      <p class="verdict" data-ok={verdict}>{verdict ? "Right." : `It's "${card.front}".`}</p>
      {#if !verdict}<WhyButton front={card.front} back={card.back} {typed} subject={deck.subject} />{/if}
      <button class="primary" onclick={() => rate(verdict ? "good" : "again")}>Next</button>
    {/if}
  {:else}
    <section class="card notch face">
      <p class="label">{mixed ? deck.name : "Term"}</p>
      <h2>{card.front}</h2>
    </section>
    <div class="options">
      {#each options as o (o)}
        <button class:right={picked && o === card.back} class:wrong={picked === o && o !== card.back} onclick={() => choose(o)}>{o}</button>
      {/each}
    </div>
    {#if verdict !== null}
      {#if !verdict}<WhyButton front={card.front} back={card.back} typed={picked ?? ""} subject={deck.subject} />{/if}
      <button class="primary" onclick={() => rate(verdict ? "good" : "again")}>Next</button>
    {/if}
  {/if}
  {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
</div>

<style>
  .session {
    display: grid;
    gap: 12px;
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .back {
    height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-body);
  }
  .bar {
    height: 6px;
    background: var(--sunk);
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--gold);
    transition: width var(--t-move) var(--ease);
  }
  .lar {
    justify-self: center;
  }
  .face {
    position: relative;
    --step: 4px;
    display: grid;
    gap: 8px;
    min-height: 180px;
    align-content: center;
    padding: 20px;
    text-align: left;
    color: var(--ink);
  }
  button.face {
    width: 100%;
    border: 0;
    font: inherit;
  }
  h2 {
    margin: 0;
    font-family: var(--font-display);
    font-size: var(--text-title);
  }
  .answer {
    margin: 8px 0 0;
    padding-top: 12px;
    border-top: 1px solid var(--edge);
    font-size: var(--text-headline);
  }
  .fine {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--ink-3);
  }
  button {
    min-height: 48px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-body);
  }
  button:disabled {
    opacity: 0.4;
  }
  .primary {
    background: var(--gold);
    box-shadow: none;
    color: var(--on-gold);
  }
  .rates {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 6px;
  }
  .rates .again {
    color: var(--bad);
  }
  .rates button {
    display: grid;
    place-content: center;
    gap: 2px;
  }
  /* The interval under each rating; the line is kept even while it loads, so nothing jumps. */
  .rates small {
    min-height: 1lh;
    font-size: var(--text-label);
    font-weight: 600;
    color: var(--ink-3);
  }
  .score {
    margin: 0;
    font-weight: 700;
    color: var(--gold);
  }
  .recap {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
    text-align: left;
  }
  .recap li {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    gap: 12px;
  }
  .recap span {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .recap small {
    flex: none;
    font-size: var(--text-caption);
    color: var(--ink-2);
  }
  .recap small.again {
    color: var(--bad);
  }
  input {
    height: 48px;
    padding: 0 12px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: var(--text-input);
  }
  .verdict {
    margin: 0;
    font-weight: 700;
    color: var(--bad);
  }
  .verdict[data-ok="true"] {
    color: var(--good);
  }
  .options {
    display: grid;
    gap: 8px;
  }
  .options button {
    height: auto;
    padding: 12px 14px;
    text-align: left;
    font-family: inherit;
    font-weight: 500;
  }
  .options .right {
    box-shadow: inset 0 0 0 2px var(--good);
  }
  .options .wrong {
    box-shadow: inset 0 0 0 2px var(--bad);
  }
  .problem {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--bad);
  }
</style>

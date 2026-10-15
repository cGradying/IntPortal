<script lang="ts" module>
  export type Mode = "flash" | "type" | "choice";
</script>

<script lang="ts">
  // One pass through a deck's due cards (every card when none is due, as
  // practice). Flashcards take the student's own rating; typed and
  // multiple-choice answers rate themselves: right is Good, wrong is Again.
  import { closable } from "./back";
  import WhyButton from "./assis/WhyButton.svelte";
  import Confetti from "./Confetti.svelte";
  import Isko from "./Isko.svelte";
  import { api, isoDate, type Card, type Deck, type Rating } from "./api";
  import { buzz } from "./haptics";

  let { deck, mode, onclose }: { deck: Deck; mode: Mode; onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));

  const now = Math.floor(Date.now() / 1000);
  // svelte-ignore state_referenced_locally
  const dueCards = deck.cards.filter((c) => c.memory.due <= now);
  // svelte-ignore state_referenced_locally
  const queue: Card[] = shuffle(dueCards.length ? dueCards : [...deck.cards]);
  const practice = dueCards.length === 0;

  let index = $state(0);
  let shown = $state(false);
  let typed = $state("");
  let verdict = $state<null | boolean>(null);
  let options = $state<string[]>([]);
  let picked = $state<string | null>(null);
  let right = $state(0);
  let problem = $state("");

  const card = $derived(queue[index]);
  const finished = $derived(index >= queue.length);
  // Four in five remembered is worth a cheer.
  const great = $derived(queue.length > 0 && right / queue.length >= 0.8);

  function shuffle<T>(xs: T[]): T[] {
    const a = [...xs];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  $effect(() => {
    if (mode !== "choice" || finished) return;
    const c = queue[index];
    const at = deck.cards.findIndex((x) => x.id === c.id);
    api.distractors(deck.cards, at, index).then((d) => (options = shuffle([c.back, ...d])));
  });

  async function rate(r: Rating) {
    try {
      // Practice (nothing was due) leaves the schedule alone: reviewing a
      // card early would push it out before it's been forgotten.
      if (!practice) await api.reviewCard(deck.id, card.id, r, isoDate(new Date()));
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
      problem = String(e);
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

<div class="session" role="dialog" aria-label="Studying {deck.name}">
  <header>
    <button class="back" onclick={onclose}>‹ {deck.name}</button>
    <p class="label num">{Math.min(index + 1, queue.length)} / {queue.length}{practice ? " · practice" : ""}</p>
  </header>
  <div class="bar"><i style:width="{(index / queue.length) * 100}%"></i></div>

  {#if finished}
    <section class="card notch face">
      {#if great}<Confetti />{/if}
      <div class="isko"><Isko size={72} pose={great ? "cheer" : "stand"} /></div>
      <p class="label">Done</p>
      <h2>{right} of {queue.length} remembered</h2>
      <p class="fine">{practice ? "Practice round: the schedule is unchanged." : "FSRS has scheduled each card for when you're about to forget it."}</p>
      <button class="primary" onclick={onclose}>Back to the deck</button>
    </section>
  {:else if mode === "flash"}
    <button class="card notch face tap" onclick={() => { if (!shown) buzz.tick(); shown = true; }}>
      <p class="label">Term</p>
      <h2>{card.front}</h2>
      {#if shown}<p class="answer">{card.back}</p>{:else}<p class="fine">Tap to show the meaning</p>{/if}
    </button>
    {#if shown}
      <div class="rates">
        <button class="again" onclick={() => rate("again")}>Again</button>
        <button onclick={() => rate("hard")}>Hard</button>
        <button onclick={() => rate("good")}>Good</button>
        <button onclick={() => rate("easy")}>Easy</button>
      </div>
    {/if}
  {:else if mode === "type"}
    <section class="card notch face">
      <p class="label">Meaning</p>
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
      <p class="label">Term</p>
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
    height: 32px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.882rem, 27px);
  }
  .bar {
    height: 6px;
    background: var(--sunk);
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--gold);
    transition: width 0.3s var(--ease);
  }
  .isko {
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
    font-size: min(1.412rem, 31px);
  }
  .answer {
    margin: 8px 0 0;
    padding-top: 12px;
    border-top: 1px solid var(--edge);
    font-size: min(1.059rem, 32px);
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  button {
    min-height: 48px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.882rem, 27px);
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
  input {
    height: 48px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(1rem, 31px));
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
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }
</style>

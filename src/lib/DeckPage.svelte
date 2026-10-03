<script lang="ts">
  // One deck: its cards, adding them one by one or pasted, and the way into
  // a study session in one of three modes.
  import ErrorCard from "./ErrorCard.svelte";
  import Skeleton from "./Skeleton.svelte";
  import StudySession, { type Mode } from "./StudySession.svelte";
  import { api, type Card, type Deck } from "./api";
  import { buzz } from "./haptics";
  import { resource } from "./load.svelte";

  let { id, onclose }: { id: string; onclose: () => void } = $props();

  // svelte-ignore state_referenced_locally
  const loaded = resource(() => api.deck(id));
  // Saves write the deck they return straight back here.
  let deck = $derived(loaded.current.state === "ready" ? loaded.current.value : null);
  let front = $state("");
  let back = $state("");
  let pasting = $state(false);
  let pasted = $state("");
  let pasteBox = $state<HTMLTextAreaElement>();
  let review = $state<Card[]>([]);
  let studying = $state<Mode | null>(null);
  let confirmDelete = $state(false);
  let problem = $state("");


  const now = () => Math.floor(Date.now() / 1000);
  const due = $derived(deck ? deck.cards.filter((c) => c.memory.due <= now()).length : 0);

  async function save(cards: Card[]) {
    if (!deck) return;
    try {
      deck = await api.saveDeck({ ...$state.snapshot(deck), cards } as Deck);
      problem = "";
      buzz.tick();
    } catch (e) {
      problem = String(e);
    }
  }

  const blank = (f: string, b: string): Card => ({ id: "", front: f, back: b, accepted: [], memory: { due: 0, stability: 0, difficulty: 0, reps: 0, lapses: 0, last_review: null } });

  async function addOne() {
    if (!deck || !front.trim() || !back.trim()) return;
    await save([...deck.cards, blank(front.trim(), back.trim())]);
    front = "";
    back = "";
  }

  async function readPaste() {
    pasted = pasteBox?.value ?? pasted;
    review = await api.parseCards(pasted);
  }

  async function acceptPaste() {
    if (!deck) return;
    await save([...deck.cards, ...review]);
    review = [];
    pasted = "";
    pasting = false;
  }

  async function remove(card: Card) {
    if (!deck) return;
    await save(deck.cards.filter((c) => c.id !== card.id));
  }

  async function deleteDeck() {
    await api.deleteDeck(id);
    onclose();
  }

  const whenDue = (c: Card) => {
    const d = Math.round((c.memory.due - now()) / 86_400);
    return c.memory.due <= now() ? "due" : d <= 0 ? "later today" : d === 1 ? "tomorrow" : `in ${d}d`;
  };
</script>

{#if studying && deck}
  <StudySession {deck} mode={studying} onclose={async () => { studying = null; deck = await api.deck(id); }} />
{:else}
  <div class="screen">
    <header>
      <button class="back" onclick={onclose}>‹ Decks</button>
      <h1>{deck?.name ?? ""}</h1>
      <p class="label">{deck?.subject ?? "No subject"} · {deck?.cards.length ?? 0} cards · {due} due</p>
    </header>

    {#if loaded.current.state === "loading"}
      <Skeleton rows={3} height={52} />
    {:else if loaded.current.state === "failed"}
      <ErrorCard error={loaded.current.error} onretry={loaded.reload} />
    {/if}
    {#if deck && deck.cards.length}
      <div class="modes">
        <button class="primary" onclick={() => (studying = "flash")}>Flashcards</button>
        <button class="ghost" onclick={() => (studying = "type")}>Type it</button>
        <button class="ghost" disabled={deck.cards.length < 4} onclick={() => (studying = "choice")}>Choices</button>
      </div>
      {#if deck.cards.length < 4}<p class="fine">Multiple choice needs at least 4 cards.</p>{/if}
    {/if}

    <section class="card notch add">
      <p class="label">Add a card</p>
      <input bind:value={front} placeholder="Term, e.g. Stack" aria-label="Front" />
      <input bind:value={back} placeholder="Meaning, e.g. last in, first out" aria-label="Back" />
      <div class="row">
        <button class="primary" onclick={addOne} disabled={!front.trim() || !back.trim()}>Add</button>
        <button class="ghost" onclick={() => (pasting = !pasting)}>{pasting ? "Close paste" : "Paste many"}</button>
      </div>
      {#if pasting}
        <textarea bind:this={pasteBox} bind:value={pasted} autocapitalize="off" spellcheck="false" placeholder={"Stack - last in, first out\nQueue - first in, first out"}></textarea>
        <button class="ghost" onclick={readPaste} disabled={!pasted.trim()}>Read them</button>
        {#if review.length}
          <ul class="cards">
            {#each review as c, i (i)}<li><span><strong>{c.front}</strong><small>{c.back}</small></span><button class="x" aria-label="Remove" onclick={() => review.splice(i, 1)}>×</button></li>{/each}
          </ul>
          <button class="primary" onclick={acceptPaste}>Add {review.length} cards</button>
        {/if}
      {/if}
    </section>

    <ul class="cards">
      {#each deck?.cards ?? [] as c (c.id)}
        <li>
          <span><strong>{c.front}</strong><small>{c.back}</small></span>
          <em>{whenDue(c)}</em>
          <button class="x" aria-label="Remove {c.front}" onclick={() => remove(c)}>×</button>
        </li>
      {/each}
    </ul>

    {#if confirmDelete}
      <div class="row">
        <button class="danger" onclick={deleteDeck}>Delete deck and cards</button>
        <button class="ghost" onclick={() => (confirmDelete = false)}>Keep it</button>
      </div>
    {:else}
      <button class="ghost" onclick={() => (confirmDelete = true)}>Delete deck</button>
    {/if}
    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
  </div>
{/if}

<style>
  .screen {
    display: grid;
    gap: 12px;
  }
  .back {
    height: 32px;
    padding: 0;
    background: none;
    color: var(--gold);
    font-size: 15px;
  }
  h1 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: 26px;
  }
  button {
    height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 14px;
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
  .danger {
    background: var(--bad);
    color: #fff;
  }
  .modes {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
  }
  .row {
    display: flex;
    gap: 8px;
  }
  .add {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px;
  }
  input,
  textarea {
    min-width: 0;
    height: 44px;
    padding: 0 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: 16px;
  }
  textarea {
    height: 120px;
    padding: 10px;
  }
  .cards {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
  }
  .cards li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 4px 8px 12px;
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .cards span {
    display: grid;
    flex: 1;
    min-width: 0;
  }
  .cards small {
    font-size: 13px;
    color: var(--ink-2);
  }
  .cards em {
    flex: none;
    font-style: normal;
    font-size: 12px;
    color: var(--ink-3);
  }
  .x {
    width: 36px;
    padding: 0;
    background: none;
    color: var(--ink-3);
    font-size: 20px;
  }
  .fine {
    margin: 0;
    font-size: 13px;
    color: var(--ink-3);
  }
  .problem {
    margin: 0;
    font-size: 13px;
    color: var(--bad);
  }
</style>

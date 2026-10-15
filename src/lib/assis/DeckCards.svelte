<script lang="ts">
  // "AI cards" in a deck: pick a note, LAR proposes cards, the student edits
  // and confirms. Nothing is saved until "Add N cards" (ADR 0003). Hidden
  // until IntAssis is on the phone.
  import { api, type NoteItem } from "../api";
  import { buzz } from "../haptics";
  import { cardsFrom, installed } from "./assis.svelte";
  import { friendlyError, noteLabel, sourceText, tidy, usable, type Draft } from "./cards";

  let { subject, fronts, onadd }: { subject: string | null; fronts: string[]; onadd: (cards: Draft[]) => Promise<void> } = $props();

  let step = $state<"closed" | "pick" | "working" | "review">("closed");
  let notes = $state<NoteItem[]>([]);
  let proposed = $state<Draft[]>([]);
  let problem = $state("");
  let run = 0;

  async function begin() {
    buzz.select();
    problem = "";
    step = "pick";
    try {
      notes = usable(await api.notes(), subject);
    } catch (e) {
      problem = friendlyError(e);
    }
  }

  async function make(n: NoteItem) {
    buzz.select();
    problem = "";
    step = "working";
    const mine = ++run;
    try {
      const cards = tidy(await cardsFrom(sourceText(n.text), 12), fronts);
      if (mine !== run) return;
      if (!cards.length) throw new Error("I couldn't find new cards in that note. Try another one.");
      proposed = cards;
      step = "review";
    } catch (e) {
      if (mine !== run) return;
      problem = friendlyError(e);
      step = "pick";
    }
  }

  function cancel() {
    run++;
    step = "closed";
    proposed = [];
    problem = "";
  }

  async function add() {
    const cards = tidy(proposed, fronts);
    if (!cards.length) return;
    await onadd(cards);
    cancel();
  }
</script>

{#if installed()}
  {#if step === "closed"}
    <button class="ghost wide" onclick={begin}>AI cards from a note</button>
  {:else}
    <section class="card notch box" aria-label="AI cards">
      <p class="label">AI cards</p>
      {#if step === "pick"}
        <p class="fine">Pick a note. LAR reads it on this phone and suggests cards. You choose which to keep.</p>
        {#if notes.length}
          <ul class="list">
            {#each notes as n (n.key)}
              <li><button class="pick" onclick={() => make(n)}><strong>{noteLabel(n)}</strong><small>{n.preview || n.text.slice(0, 80)}</small></button></li>
            {/each}
          </ul>
        {:else if !problem}
          <p class="fine">No notes with words in them yet. Write one in the You tab first.</p>
        {/if}
        <button class="ghost" onclick={cancel}>Close</button>
      {:else if step === "working"}
        <p class="working" role="status" aria-live="polite"><i aria-hidden="true"></i>LAR is reading your note…</p>
        <button class="ghost" onclick={cancel}>Cancel</button>
      {:else}
        <p class="fine">Edit or remove any card. Nothing is added until you tap the gold button.</p>
        <ul class="list">
          {#each proposed as c, i (i)}
            <li class="edit">
              <span>
                <input bind:value={c.front} aria-label="Front of card {i + 1}" />
                <input bind:value={c.back} aria-label="Back of card {i + 1}" />
              </span>
              <button class="x" aria-label="Remove card {i + 1}" onclick={() => proposed.splice(i, 1)}>×</button>
            </li>
          {/each}
        </ul>
        <div class="row">
          <button class="primary" disabled={!tidy(proposed, fronts).length} onclick={add}>Add {tidy(proposed, fronts).length} cards</button>
          <button class="ghost" onclick={cancel}>Discard</button>
        </div>
      {/if}
      {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
    </section>
  {/if}
{/if}

<style>
  .box {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px;
  }
  button {
    height: 44px;
    padding: 0 14px;
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
  .wide {
    width: 100%;
  }
  .row {
    display: flex;
    gap: 8px;
  }
  .row .primary {
    flex: 1;
  }
  .list {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
  }
  .pick {
    display: grid;
    width: 100%;
    height: auto;
    min-height: 44px;
    padding: 8px 12px;
    text-align: left;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
  }
  .pick small {
    font-family: var(--font-body, inherit);
    font-weight: 400;
    font-size: min(0.765rem, 23px);
    color: var(--ink-2);
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .edit {
    display: flex;
    align-items: center;
    gap: 4px;
    padding: 8px 4px 8px 8px;
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .edit span {
    display: grid;
    flex: 1;
    min-width: 0;
    gap: 6px;
  }
  input {
    min-width: 0;
    height: 44px;
    padding: 0 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
  }
  .x {
    width: 44px;
    padding: 0;
    background: none;
    color: var(--ink-3);
    font-size: min(1.176rem, 26px);
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  .working {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 0;
    font-size: min(0.824rem, 25px);
  }
  .working i {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    border: 2px solid var(--edge);
    border-top-color: var(--gold);
    animation: spin 0.9s linear infinite;
  }
  @keyframes spin {
    to {
      transform: rotate(360deg);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .working i {
      animation: none;
      border-top-color: var(--edge);
      border-right-color: var(--gold);
    }
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }
</style>

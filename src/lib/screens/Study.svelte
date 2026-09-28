<script lang="ts">
  // Decks of flashcards scheduled by FSRS in the core: what's due, the
  // streak, and a way in to each deck.
  import DeckPage from "../DeckPage.svelte";
  import { api, isoDate, type StudyOverview } from "../api";
  import { app } from "../state.svelte";

  let overview = $state<StudyOverview | null>(null);
  let open = $state<string | null>(null);
  let naming = $state(false);
  let name = $state("");
  let subject = $state("");
  let problem = $state("");

  const subjects = $derived([...new Map((app.snapshot?.sessions ?? []).map((s) => [s.subject_code, s.description])).entries()]);

  async function load() {
    overview = await api.study(isoDate(new Date()));
  }
  load();

  async function create() {
    try {
      const deck = await api.saveDeck({ id: crypto.randomUUID(), name: name.trim(), subject: subject || null, cards: [] });
      naming = false;
      name = "";
      subject = "";
      problem = "";
      await load();
      open = deck.id;
    } catch (e) {
      problem = String(e);
    }
  }
</script>

{#if open}
  <DeckPage id={open} onclose={() => { open = null; load(); }} />
{:else}
  <div class="screen">
    <header>
      <p class="label">Spaced repetition</p>
      <h1>Study</h1>
    </header>

    <section class="card notch sum">
      <div><p class="label">Due now</p><p class="big num">{overview?.due ?? 0}</p></div>
      <div><p class="label">Streak</p><p class="big num">{overview?.streak ?? 0}<small> {overview?.streak === 1 ? "day" : "days"}</small></p></div>
      <div><p class="label">Today</p><p class="big num">{overview?.reviews_today ?? 0}<small> cards</small></p></div>
    </section>

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
    {:else}
      <button class="primary" onclick={() => (naming = true)}>New deck</button>
    {/if}

    {#if overview && overview.decks.length === 0}
      <p class="fine">No decks yet. Make one per subject or per exam, then paste your terms in as "term - meaning".</p>
    {/if}
    <ul class="decks">
      {#each overview?.decks ?? [] as d (d.id)}
        <li>
          <button onclick={() => (open = d.id)}>
            <span class="what"><strong>{d.name}</strong><small>{d.subject ?? "No subject"} · {d.cards} cards</small></span>
            {#if d.due}<span class="due num">{d.due} due</span>{:else}<span class="done">Caught up</span>{/if}
          </button>
        </li>
      {/each}
    </ul>
  </div>
{/if}

<style>
  .screen {
    display: grid;
    gap: 14px;
  }
  h1 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }
  .sum {
    --step: 4px;
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
    padding: 16px;
  }
  .big {
    margin: 2px 0 0;
    font-size: 28px;
    font-weight: 800;
  }
  .big small {
    font-size: 13px;
    font-weight: 600;
    color: var(--ink-3);
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
    font-size: 16px;
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
  .decks {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 8px;
  }
  .decks button {
    width: 100%;
    height: auto;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 14px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    text-align: left;
  }
  .what {
    display: grid;
    flex: 1;
    min-width: 0;
  }
  .what small {
    font-family: var(--font-body, inherit);
    font-weight: 400;
    font-size: 13px;
    color: var(--ink-3);
  }
  .due {
    color: var(--gold);
  }
  .done {
    font-weight: 600;
    font-size: 12px;
    color: var(--ink-3);
  }
</style>

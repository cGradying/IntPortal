<script lang="ts">
  // "AI cards" in a deck: pick a note, LAR proposes cards, the student edits
  // and confirms. Nothing is saved until "Add N cards" (ADR 0003). Hidden
  // until IntAssis is on the phone. Write wrong answers runs here too, on the
  // deck's own cards, and saves each batch as it lands (spec 063 C12).
  import { api, type Card, type NoteItem } from "../api";
  import { buzz } from "../haptics";
  import { cardsFrom, installed, pdfText, writeWrongAnswers } from "./assis.svelte";
  import { friendlyError, hasText, lacksWrong, noteLabel, pdfError, pdfProblem, sourceText, tidy, usable, writeMissing, type Draft } from "./cards";

  let { subject, cards, onadd, onwrong }: { subject: string | null; cards: Card[]; onadd: (cards: Draft[]) => Promise<void>; onwrong: (part: Card[]) => Promise<void> } = $props();
  const fronts = $derived(cards.map((c) => c.front));

  let step = $state<"closed" | "pick" | "working" | "review" | "wrong">("closed");
  let notes = $state<NoteItem[]>([]);
  let proposed = $state<Draft[]>([]);
  let problem = $state("");
  let run = 0;
  let file = $state<HTMLInputElement>();
  let reading = $state<"note" | "PDF">("note");
  /** "Make a quiz": the cards also get three wrong answers each (spec 062 C17). */
  let quiz = $state(false);

  async function begin(asQuiz = false) {
    quiz = asQuiz;
    buzz.select();
    problem = "";
    step = "pick";
    try {
      notes = usable(await api.notes(), subject);
    } catch (e) {
      problem = friendlyError(e);
    }
  }

  // The picked PDF: type and size are checked before the file is read, the text
  // is pulled out on the phone, then it goes the way a note does.
  async function pdf() {
    const f = file?.files?.[0];
    if (file) file.value = "";
    if (!f) return;
    problem = pdfProblem(f) ?? "";
    if (problem) return;
    await read("PDF", async () => {
      const text = await pdfText(new Uint8Array(await f.arrayBuffer()));
      if (!hasText(text)) throw "This PDF has no text to read";
      return text;
    });
  }

  const make = (n: NoteItem) => read("note", async () => n.text);

  async function read(what: "note" | "PDF", text: () => Promise<string>) {
    buzz.select();
    problem = "";
    reading = what;
    step = "working";
    const mine = ++run;
    try {
      const t = await text();
      if (mine !== run) return;
      const cards = tidy(await cardsFrom(sourceText(t), quiz ? 6 : 12, quiz), fronts);
      if (mine !== run) return;
      if (!cards.length) throw new Error(`I couldn't find new cards in that ${what}. Try another one.`);
      proposed = cards;
      step = "review";
    } catch (e) {
      if (mine !== run) return;
      problem = what === "PDF" ? pdfError(e) : friendlyError(e);
      step = "pick";
    }
  }

  function cancel() {
    run++;
    step = "closed";
    proposed = [];
    problem = "";
  }

  // Write wrong answers: n of m while it runs, then how many were written.
  let wrong = $state({ done: 0, wrote: 0, of: 0, over: false });
  let stopping = $state(false);
  $effect(() => () => (stopping = true));
  const shown = () =>
    new Promise<void>((ok) => {
      const back = () => {
        if (document.hidden) return;
        document.removeEventListener("visibilitychange", back);
        ok();
      };
      document.addEventListener("visibilitychange", back);
    });

  async function writeWrong() {
    buzz.select();
    problem = "";
    stopping = false;
    wrong = { done: 0, wrote: 0, of: 0, over: false };
    step = "wrong";
    try {
      await writeMissing($state.snapshot(cards) as Card[], writeWrongAnswers, onwrong, {
        stopped: () => stopping,
        hidden: () => document.hidden,
        shown,
        progress: (done, wrote, of) => (wrong = { done, wrote, of, over: false }),
      });
      buzz.done();
    } catch {
      buzz.fail();
    }
    wrong.over = true;
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
    <button class="ghost wide" onclick={() => begin()}>AI cards from a note</button>
    <button class="ghost wide" onclick={() => begin(true)}>Make a quiz</button>
    {#if lacksWrong(cards)}<button class="ghost wide" onclick={writeWrong}>Write wrong answers</button>{/if}
  {:else}
    <section class="card notch box" aria-label="AI cards">
      <p class="label">{step === "wrong" ? "Wrong answers" : quiz ? "AI quiz" : "AI cards"}</p>
      {#if step === "wrong"}
        {#if !wrong.over}
          <p class="working" role="status" aria-live="polite"><i aria-hidden="true"></i>LAR is writing wrong answers…</p>
          <p class="fine num">{wrong.done} of {wrong.of} cards</p>
          <button class="ghost" disabled={stopping} onclick={() => (stopping = true)}>{stopping ? "Stopping…" : "Stop"}</button>
        {:else}
          <p class="fine" role="status">Wrote wrong answers for {wrong.wrote} of {wrong.of} cards.</p>
          <div class="row">
            {#if wrong.wrote < wrong.of}<button class="primary" onclick={writeWrong}>Try again</button>{/if}
            <button class="ghost" onclick={cancel}>Close</button>
          </div>
        {/if}
      {:else if step === "pick"}
        <p class="fine">Pick a note or a PDF. LAR reads it on this phone and suggests cards. You choose which to keep.</p>
        <input bind:this={file} type="file" accept="application/pdf" hidden aria-hidden="true" tabindex="-1" onchange={pdf} />
        <button class="ghost" onclick={() => file?.click()}>Pick a PDF (up to 20 MB)</button>
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
        <p class="working" role="status" aria-live="polite"><i aria-hidden="true"></i>LAR is reading your {reading}…</p>
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
    border-radius: var(--radius);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-sub);
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
    font-size: var(--text-caption);
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
    border-radius: var(--radius);
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
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: var(--text-input);
  }
  .x {
    width: 44px;
    padding: 0;
    background: none;
    color: var(--ink-3);
    font-size: var(--text-headline);
  }
  .fine {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--ink-3);
  }
  .working {
    display: flex;
    align-items: center;
    gap: 10px;
    margin: 0;
    font-size: var(--text-sub);
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
    font-size: var(--text-caption);
    color: var(--bad);
  }
</style>

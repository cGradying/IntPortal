<script lang="ts">
  // One subject's syllabus: its grading system with the running arithmetic,
  // and its outline of topics, quizzes, exams and projects.
  import { api, isoDate, type Component, type ItemKind, type Plan, type SyllabusItem, type Tally } from "./api";
  import { adopt, app, openNote } from "./state.svelte";

  let { code, description }: { code: string; description: string } = $props();

  const saved = $derived(app.snapshot?.syllabus[code]);
  // svelte-ignore state_referenced_locally
  let plan = $state<Plan>(structuredClone($state.snapshot(saved) ?? { items: [], grading: [], target: null }));
  let dirty = $state(false);
  let problem = $state("");
  let tab = $state<"grading" | "outline">(plan.grading.length || !plan.items.length ? "grading" : "outline");
  let tally = $state<Tally | null>(null);
  const target = $derived(plan.target ?? 90);

  $effect(() => {
    const comps = $state.snapshot(plan.grading) as Component[];
    api.tally(comps, target).then((t) => (tally = t));
  });

  function changed() {
    dirty = true;
  }

  async function save() {
    try {
      await adopt(await api.setPlan(code, $state.snapshot(plan) as Plan));
      dirty = false;
      problem = "";
    } catch (e) {
      problem = String(e);
    }
  }

  async function close() {
    if (dirty) await save();
    if (!problem) app.subject = null;
  }

  const num = (v: string) => (v.trim() === "" ? null : Number(v));

  // Outline: add one, or paste a whole outline and review it first.
  let newTopic = $state("");
  let newKind = $state<ItemKind>("quiz");
  let newDate = $state("");
  let pasting = $state(false);
  let pasted = $state("");
  let review = $state<SyllabusItem[]>([]);
  let pasteBox = $state<HTMLTextAreaElement>();

  function addItem() {
    if (!newTopic.trim()) return;
    plan.items.push({ id: "", topic: newTopic.trim(), kind: newKind, week: null, date: newDate || null, done: false });
    newTopic = "";
    newDate = "";
    changed();
  }

  async function readOutline() {
    // The box's live value: iOS can hold back the last autocorrected word.
    pasted = pasteBox?.value ?? pasted;
    review = await api.parseOutline(pasted, isoDate(new Date()));
  }

  function acceptReview() {
    plan.items.push(...review);
    review = [];
    pasted = "";
    pasting = false;
    changed();
  }

  const sorted = $derived(
    [...plan.items].sort((a, b) => (a.week ?? 99) - (b.week ?? 99) || (a.date ?? "9").localeCompare(b.date ?? "9")),
  );
  const shortDate = (d: string) => new Date(`${d}T00:00`).toLocaleDateString(undefined, { month: "short", day: "numeric" });
</script>

<div class="page" role="dialog" aria-label="{code} syllabus">
  <header>
    <div>
      <p class="label">{dirty ? "Not saved yet" : "Saved on this phone"}</p>
      <h2>{code}</h2>
      <p class="desc">{description}</p>
    </div>
    <button class="primary" onclick={close}>Done</button>
  </header>

  <div class="tabs" role="tablist">
    <button role="tab" class:on={tab === "grading"} aria-selected={tab === "grading"} onclick={() => (tab = "grading")}>Grading</button>
    <button role="tab" class:on={tab === "outline"} aria-selected={tab === "outline"} onclick={() => (tab = "outline")}>Outline</button>
    <button role="tab" onclick={() => { app.subject = null; openNote(`class:${code}`, code, description); }}>Notes</button>
  </div>

  <div class="body">
    {#if tab === "grading"}
      {#if tally && tally.scored_weight > 0}
        <section class="card notch sum">
          <p><strong class="num">{tally.standing?.toFixed(1)}%</strong> so far{#if tally.equivalent !== null}, about <strong class="num">{tally.equivalent.toFixed(2)}</strong>{/if}, on {tally.scored_weight}% of the grade.</p>
          {#if tally.needed !== null}
            <p class="need" data-over={tally.needed > 100}>
              {tally.needed > 100 ? `${target}% is out of reach now; even 100 on the rest won't make it.` : tally.needed <= 0 ? `${target}% is already secured.` : `${tally.needed.toFixed(1)}% on the rest for ${target}%.`}
            </p>
          {/if}
        </section>
      {/if}
      <p class="fine">Copy the grading system from your syllabus. Fill in a score when you get it back.</p>
      <ul class="comps">
        {#each plan.grading as c, i (i)}
          <li>
            <input bind:value={c.name} oninput={changed} placeholder="Midterm exam" aria-label="Component" />
            <div class="nums">
              <label>Weight % <input inputmode="decimal" value={c.weight || ""} placeholder="30" oninput={(e) => { c.weight = num(e.currentTarget.value) ?? 0; changed(); }} /></label>
              <label>Score % <input inputmode="decimal" value={c.score ?? ""} placeholder="—" oninput={(e) => { c.score = num(e.currentTarget.value); changed(); }} /></label>
              <button class="x" aria-label="Remove {c.name}" onclick={() => { plan.grading.splice(i, 1); changed(); }}>×</button>
            </div>
          </li>
        {/each}
      </ul>
      <button class="ghost" onclick={() => { plan.grading.push({ name: "", weight: 0, score: null }); changed(); }}>Add a component</button>
      {#if tally && plan.grading.length}
        <p class="fine" class:warn={tally.weight_total !== 100}>Weights add up to {tally.weight_total}%{tally.weight_total !== 100 ? "; a full grading system is 100%." : "."}</p>
      {/if}
      <label class="target">Aiming for <input inputmode="decimal" value={plan.target ?? ""} placeholder="90" oninput={(e) => { plan.target = num(e.currentTarget.value); changed(); }} /> %</label>
    {:else}
      {#if pasting}
        <textarea bind:this={pasteBox} bind:value={pasted} autocapitalize="off" spellcheck="false" placeholder={"Week 1: Introduction\nWeek 2: Linked lists\nQuiz 1 – Oct 9\nMidterm exam Oct 23"}></textarea>
        <div class="row">
          <button class="primary" onclick={readOutline} disabled={!pasted.trim()}>Read it</button>
          <button class="ghost" onclick={() => { pasting = false; review = []; }}>Cancel</button>
        </div>
        {#if review.length}
          <p class="label">Check these {review.length}, remove what's wrong</p>
          <ul class="items">
            {#each review as it, i (i)}
              <li><span class="kind" data-kind={it.kind}>{it.kind}</span><span class="topic">{it.topic}</span><span class="when">{it.week ? `Wk ${it.week}` : ""} {it.date ? shortDate(it.date) : ""}</span><button class="x" aria-label="Remove" onclick={() => review.splice(i, 1)}>×</button></li>
            {/each}
          </ul>
          <button class="primary" onclick={acceptReview}>Add {review.length} items</button>
        {/if}
      {:else}
        <div class="row">
          <button class="ghost" onclick={() => (pasting = true)}>Paste an outline</button>
        </div>
        <div class="add">
          <input bind:value={newTopic} placeholder="Quiz 2: trees" aria-label="Topic" />
          <select bind:value={newKind} aria-label="Kind">
            <option value="lecture">Lecture</option><option value="quiz">Quiz</option><option value="exam">Exam</option><option value="project">Project</option>
          </select>
          <input type="date" bind:value={newDate} aria-label="Date" />
          <button class="primary" onclick={addItem} disabled={!newTopic.trim()}>Add</button>
        </div>
        {#if sorted.length === 0}
          <p class="fine">No outline yet. Paste the one from your syllabus, or add quizzes and exams as they're announced.</p>
        {/if}
        <ul class="items">
          {#each sorted as it (it.id || it.topic)}
            <li class:done={it.done}>
              <input type="checkbox" checked={it.done} aria-label="Done" onchange={() => { it.done = !it.done; changed(); }} />
              <span class="kind" data-kind={it.kind}>{it.kind}</span>
              <span class="topic">{it.topic}</span>
              <span class="when">{it.week ? `Wk ${it.week}` : ""} {it.date ? shortDate(it.date) : ""}</span>
              <button class="x" aria-label="Remove {it.topic}" onclick={() => { plan.items.splice(plan.items.indexOf(it), 1); changed(); }}>×</button>
            </li>
          {/each}
        </ul>
      {/if}
    {/if}
    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
  </div>
</div>

<style>
  .page {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto auto 1fr;
    gap: 12px;
    padding: calc(var(--safe-top) + 12px) var(--gutter) 0;
    background: var(--ground);
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 12px;
  }
  h2 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: min(1.294rem, 29px);
  }
  .desc {
    margin: 2px 0 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  button {
    height: 40px;
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
  .tabs {
    display: flex;
    gap: 6px;
  }
  .tabs button {
    height: 34px;
    border-radius: 17px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
  }
  .tabs button.on {
    background: var(--gold);
    color: var(--on-gold);
  }
  .body {
    display: grid;
    align-content: start;
    gap: 10px;
    overflow-y: auto;
    padding-bottom: calc(var(--safe-bottom) + 24px);
  }
  .sum {
    --step: 4px;
    padding: 14px;
  }
  .sum p {
    margin: 0;
    font-size: min(0.882rem, 27px);
  }
  .need {
    margin-top: 6px !important;
    color: var(--ink-2);
  }
  .need[data-over="true"] {
    color: var(--bad);
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  .warn {
    color: var(--bad);
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
  }
  input,
  select,
  textarea {
    min-width: 0;
    height: 40px;
    padding: 0 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
  }
  textarea {
    height: 160px;
    padding: 10px;
    resize: vertical;
  }
  .comps li {
    display: grid;
    gap: 6px;
    padding: 10px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .nums {
    display: grid;
    grid-template-columns: 1fr 1fr auto;
    gap: 6px;
    align-items: end;
  }
  .comps label,
  .target {
    display: grid;
    gap: 2px;
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .target {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: min(0.824rem, 25px);
  }
  .target input {
    width: 80px;
  }
  .x {
    width: 40px;
    padding: 0;
    background: none;
    color: var(--ink-3);
    font-size: min(1.294rem, 29px);
  }
  .row {
    display: flex;
    gap: 8px;
  }
  .add {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 6px;
  }
  .add input:first-child {
    grid-column: 1 / 3;
  }
  .items li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 4px 8px 10px;
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-size: min(0.824rem, 25px);
  }
  .items li.done .topic {
    text-decoration: line-through;
    color: var(--ink-3);
  }
  .items input[type="checkbox"] {
    width: 20px;
    height: 20px;
    padding: 0;
    box-shadow: none;
  }
  .kind {
    flex: none;
    padding: 2px 6px;
    font-family: var(--font-pixel);
    font-size: min(0.647rem, 20px);
    text-transform: uppercase;
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink-2);
  }
  .kind[data-kind="exam"],
  .kind[data-kind="quiz"] {
    color: var(--gold);
  }
  .topic {
    flex: 1;
    min-width: 0;
  }
  .when {
    flex: none;
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }
</style>

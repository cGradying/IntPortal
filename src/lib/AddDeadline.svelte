<script lang="ts">
  // Spec 041 C10–C14: a deadline of the student's own, typed or pasted, read
  // by the core, confirmed before anything is saved. With `own` it edits one.
  import { api, isoDate, type DeadlineDraft, type DeadlineEntry, type ItemKind } from "./api";
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { adopt, app } from "./state.svelte";

  let { own, onclose }: { own?: DeadlineEntry; onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));

  type Row = DeadlineDraft & { keep: boolean };
  let text = $state("");
  let problem = $state("");
  // svelte-ignore state_referenced_locally
  let rows = $state<Row[]>(
    own ? [{ title: own.title, subject: own.subject, kind: own.kind, date: "day" in own.due ? own.due.day : null, keep: true }] : [],
  );
  const subjects = $derived([...new Map((app.snapshot?.sessions ?? []).map((s) => [s.subject_code, s.description])).keys()]);
  const kept = $derived(rows.filter((r) => r.keep));
  const ready = $derived(kept.length > 0 && kept.every((r) => r.title.trim() && r.date));

  async function paste() {
    try {
      text = (await navigator.clipboard.readText()) || text;
    } catch {
      // No clipboard access; the field stays as typed.
    }
  }

  async function read() {
    problem = "";
    const drafts = await api.parseOwn(text, isoDate(new Date())).catch((e) => ((problem = String(e)), []));
    rows = drafts.map((d) => ({ ...d, keep: true }));
  }

  async function save() {
    try {
      let snap = null;
      for (const r of kept) {
        snap = await api.saveOwn({ id: own ? own.id.replace(/^own:/, "") : "", title: r.title, subject: r.subject, kind: r.kind, date: r.date! });
      }
      if (snap) await adopt(snap);
      buzz.done();
      onclose();
    } catch (e) {
      problem = String(e);
    }
  }

  async function remove() {
    if (!own) return;
    await adopt(await api.deleteOwn(own.id.replace(/^own:/, "")));
    onclose();
  }

  const kinds: [ItemKind, string][] = [["quiz", "Quiz"], ["exam", "Exam"], ["project", "Project"]];
</script>

<div class="scrim" onclick={onclose} aria-hidden="true"></div>
<div class="sheet" role="dialog" aria-label={own ? "Edit deadline" : "Add a deadline"}>
  <h2>{own ? "Edit deadline" : "What's due?"}</h2>

  {#if !own}
    <textarea bind:value={text} rows="3" placeholder="quiz COMP fri, or paste the GC message" aria-label="What's due?"></textarea>
    <div class="bar">
      <button class="ghost" onclick={paste}>Paste</button>
      <button class="ghost" onclick={read} disabled={!text.trim()}>Read it</button>
    </div>
  {/if}

  {#each rows as r, i (i)}
    <fieldset class="draft">
      {#if rows.length > 1}<label class="keep"><input type="checkbox" bind:checked={r.keep} /> Add this one</label>{/if}
      <label>Title <input bind:value={r.title} /></label>
      <label>When is it due? <input type="date" bind:value={r.date} /></label>
      <div class="two">
        <label>Subject
          <select bind:value={r.subject}>
            <option value={null}>None</option>
            {#each subjects as code (code)}<option value={code}>{code}</option>{/each}
          </select>
        </label>
        <label>Kind
          <select bind:value={r.kind}>
            {#each kinds as [k, name] (k)}<option value={k}>{name}</option>{/each}
          </select>
        </label>
      </div>
    </fieldset>
  {/each}

  {#if problem}<p class="problem">{problem}</p>{/if}

  <div class="bar">
    {#if own}<button class="ghost danger" onclick={remove}>Delete</button>{/if}
    <button class="ghost" onclick={onclose}>Cancel</button>
    {#if rows.length}<button class="primary" onclick={save} disabled={!ready}>Save</button>{/if}
  </div>
</div>

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 40;
    background: rgba(0, 0, 0, 0.45);
    animation: fade 0.2s both;
  }
  .sheet {
    --step: 4px;
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 12px);
    z-index: 41;
    display: grid;
    gap: 10px;
    max-height: 80vh;
    overflow-y: auto;
    padding: 18px 16px;
    background: var(--card-2);
    animation: rise 0.35s var(--ease) both;
  }
  h2 {
    margin: 0 0 4px;
    font-family: var(--font-display);
    font-size: min(1.059rem, 32px);
  }
  textarea,
  input,
  select {
    width: 100%;
    min-height: 44px;
    padding: 8px 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
  }
  input[type="checkbox"] {
    min-height: 0;
  }
  label {
    display: grid;
    gap: 4px;
    font-size: min(0.765rem, 23px);
    color: var(--ink-2);
  }
  .keep {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .draft {
    display: grid;
    gap: 8px;
    margin: 0;
    padding: 10px 0 0;
    border: 0;
    border-top: 1px solid var(--edge);
  }
  .two {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .bar {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
  }
  .bar button {
    min-height: 44px;
  }
  .danger {
    margin-right: auto;
    color: var(--bad);
  }
  .problem {
    margin: 0;
    color: var(--bad);
  }
</style>

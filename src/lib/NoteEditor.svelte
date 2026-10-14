<script lang="ts">
  // A full-screen page for one note. It saves while you type (after a short
  // pause) and again on Done, so nothing typed is lost to a quick close.
  import { api } from "./api";
  import { appended, replaced } from "./assis/apply";
  import { assis, indexNotes, installed, noteAi, stop, type NoteMode } from "./assis/assis.svelte";
  import { closable } from "./back";
  import { shareFile } from "./share";
  import { app, refreshNotes } from "./state.svelte";

  let { key, heading, title }: { key: string; heading: string; title: string | null } = $props();

  // svelte-ignore state_referenced_locally
  let text = $state(app.notes.find((n) => n.key === key)?.text ?? "");
  // Freeform notes carry a name the student types; class and day notes are
  // named by what they belong to.
  const named = $derived(key.startsWith("note:"));
  // svelte-ignore state_referenced_locally
  let name = $state(title ?? "");
  let saved = $state(true);
  let problem = $state("");
  let timer: ReturnType<typeof setTimeout> | undefined;

  async function save() {
    clearTimeout(timer);
    try {
      await api.setNote(key, text, named ? name.trim() || null : title);
      saved = true;
      problem = "";
      refreshNotes();
    } catch (e) {
      problem = String(e);
    }
  }

  function typed() {
    saved = false;
    clearTimeout(timer);
    timer = setTimeout(save, 600);
  }

  async function share() {
    if (!saved) await save();
    try {
      const md = await api.notesMarkdown(key);
      if (!md) return;
      await shareFile(`${(named ? name.trim() : heading) || "Note"}.md`, "text/markdown", md);
    } catch (e) {
      problem = String(e);
    }
  }

  async function done() {
    if (!saved) await save();
    if (problem) return;
    indexNotes();
    app.editing = null;
  }

  // Ask AI: LAR reads this note (as it is on screen) and offers text to put in it.
  // Nothing changes until a button is tapped.
  let ta: HTMLTextAreaElement | undefined = $state();
  let bar = $state(false);
  let question = $state("");
  let out = $state("");
  let mode: NoteMode | null = $state(null);
  let range = $state<[number, number]>([0, 0]);
  let before: string | null = $state(null);
  let aiProblem = $state("");
  const working = $derived(assis.busy === "thinking" || assis.busy === "waking");

  async function run(m: NoteMode) {
    if (working) return;
    const [a, b] = [ta?.selectionStart ?? 0, ta?.selectionEnd ?? 0];
    const selection = b > a ? text.slice(a, b) : null;
    aiProblem = "";
    if (m === "explain" && !selection) {
      aiProblem = "Select the words to explain first.";
      return;
    }
    if (m === "ask" && !question.trim()) {
      aiProblem = "Type a question first.";
      return;
    }
    [mode, out, before, range] = [m, "", null, selection ? [a, b] : [0, text.length]];
    try {
      const answer = await noteAi(m, text, selection, m === "ask" ? question : null, (words) => (out += words));
      out = answer;
    } catch (e) {
      out = "";
      mode = null;
      aiProblem = typeof e === "string" ? e : ((e as Error)?.message ?? "Something went wrong. Try again.");
    }
  }

  function insertBelow() {
    text = appended(text, out);
    finish();
  }

  function replace() {
    before = text;
    text = replaced(text, range[0], range[1], out);
    finish(true);
  }

  function undo() {
    if (before === null) return;
    text = before;
    before = null;
    typed();
  }

  function finish(keepUndo = false) {
    typed();
    out = "";
    mode = null;
    if (!keepUndo) before = null;
  }

  function discard() {
    if (working) stop();
    out = "";
    mode = null;
  }
  $effect(() => closable(done));
</script>

<div class="editor" role="dialog" aria-label="Note: {heading}">
  <div class="top">
  <header>
    <div>
      <p class="label">{saved ? "Saved on this phone" : "Saving…"}</p>
      {#if named}
        <input class="name" bind:value={name} oninput={typed} placeholder="Name this note" aria-label="Note name" />
      {:else}
        <h2>{heading}</h2>
      {/if}
    </div>
    <div class="actions">
      {#if installed()}<button class="ghost" onclick={() => (bar = !bar)} aria-expanded={bar}>Ask AI</button>{/if}
      <button class="ghost" onclick={share} disabled={!text.trim()}>Share</button>
      <button onclick={done}>Done</button>
    </div>
  </header>
  {#if bar && installed()}
    <section class="ai" aria-label="Ask AI">
      <div class="chips">
        <button onclick={() => run("summarize")} disabled={working || !text.trim()}>Summarize</button>
        <button onclick={() => run("tidy")} disabled={working || !text.trim()}>Tidy up</button>
        <button onclick={() => run("explain")} disabled={working}>Explain</button>
        <button onclick={() => (assis.open = true)}>Chat</button>
      </div>
      <form onsubmit={(e) => { e.preventDefault(); run("ask"); }}>
        <input bind:value={question} placeholder="Ask about this note…" aria-label="Ask about this note" enterkeyhint="send" autocomplete="off" />
        <button class="go" type="submit" disabled={working || !question.trim()}>Ask</button>
      </form>
      {#if working && !out}<p class="fine">{assis.busy === "waking" ? "Waking up…" : "Thinking…"}</p>{/if}
      {#if out}
        <div class="result" aria-live="polite">
          <p>{out}</p>
          {#if !working}
            <div class="two">
              <button class="go" onclick={insertBelow}>Insert below</button>
              {#if mode === "tidy"}<button onclick={replace}>Replace</button>{/if}
              <button onclick={discard}>Discard</button>
            </div>
          {:else}
            <button onclick={discard}>Stop</button>
          {/if}
        </div>
      {/if}
      {#if before !== null && !out}<button class="undo" onclick={undo}>Undo replace</button>{/if}
      {#if aiProblem}<p class="problem" role="alert">{aiProblem}</p>{/if}
    </section>
  {/if}
  </div>
  <!-- svelte-ignore a11y_autofocus -->
  <textarea bind:this={ta} bind:value={text} oninput={typed} placeholder="Write anything: what was discussed, what's due, what to review." autofocus></textarea>
  {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
</div>

<style>
  .editor {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto 1fr auto;
    gap: 12px;
    padding: calc(var(--safe-top) + 12px) var(--gutter) calc(var(--safe-bottom) + 12px);
    background: var(--ground);
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: flex-end;
    gap: 12px;
  }
  h2 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: min(1.294rem, 29px);
  }
  header > div:first-child {
    min-width: 0;
    flex: 1;
  }
  .actions {
    display: flex;
    gap: 8px;
  }
  .name {
    width: 100%;
    margin-top: 2px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink);
    font-family: var(--font-display);
    font-size: min(1.294rem, 29px);
    font-weight: 700;
  }
  header button.ghost {
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
  }
  header button:disabled {
    opacity: 0.4;
  }
  header button {
    height: 40px;
    padding: 0 16px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
  }
  textarea {
    width: 100%;
    padding: 14px;
    border: 0;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
    line-height: 1.5;
    resize: none;
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--bad);
  }
  .top {
    display: grid;
    gap: 10px;
  }
  .ai {
    display: grid;
    gap: 8px;
    padding: 10px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .chips,
  .two {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .ai button {
    min-height: 40px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .ai button.go {
    background: var(--gold);
    box-shadow: none;
    color: var(--on-gold);
  }
  .ai button:disabled {
    opacity: 0.45;
  }
  .ai form {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 8px;
  }
  .ai input {
    min-width: 0;
    height: 40px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
  }
  .result {
    display: grid;
    gap: 8px;
    max-height: 30vh;
    overflow-y: auto;
  }
  .result p {
    margin: 0;
    white-space: pre-line;
    line-height: 1.4;
    font-size: min(0.882rem, 27px);
  }
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
</style>

<script lang="ts">
  // A full-screen page for one note. It saves while you type (after a short
  // pause) and again on Done, so nothing typed is lost to a quick close.
  import { api } from "./api";
  import { app, refreshNotes } from "./state.svelte";

  let { key, heading, title }: { key: string; heading: string; title: string | null } = $props();

  // svelte-ignore state_referenced_locally
  let text = $state(app.notes.find((n) => n.key === key)?.text ?? "");
  let saved = $state(true);
  let problem = $state("");
  let timer: ReturnType<typeof setTimeout> | undefined;

  async function save() {
    clearTimeout(timer);
    try {
      await api.setNote(key, text, title);
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

  async function done() {
    if (!saved) await save();
    if (!problem) app.editing = null;
  }
</script>

<div class="editor" role="dialog" aria-label="Note: {heading}">
  <header>
    <div>
      <p class="label">{saved ? "Saved on this phone" : "Saving…"}</p>
      <h2>{heading}</h2>
    </div>
    <button onclick={done}>Done</button>
  </header>
  <!-- svelte-ignore a11y_autofocus -->
  <textarea bind:value={text} oninput={typed} placeholder="Write anything: what was discussed, what's due, what to review." autofocus></textarea>
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
    font-size: 22px;
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
    font-size: 16px;
    line-height: 1.5;
    resize: none;
  }
  .problem {
    margin: 0;
    font-size: 13px;
    color: var(--bad);
  }
</style>

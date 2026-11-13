<script lang="ts">
  // The student's notes: new, search, export. On Study and on You (spec 040 C14).
  import { api } from "./api";
  import { photosInShare, previewOf } from "./photos";
  import { shareFile } from "./share";
  import { app, openNote } from "./state.svelte";

  let query = $state("");
  let notesNote = $state("");
  const shown = $derived.by(() => {
    const q = query.trim().toLowerCase();
    return q ? app.notes.filter((n) => `${noteHeading(n.key, n.title)} ${n.text}`.toLowerCase().includes(q)) : app.notes;
  });

  function newNote() {
    openNote(`note:${crypto.randomUUID()}`, "New note", "");
  }

  async function exportAll() {
    notesNote = "";
    try {
      if (app.notes.some((n) => n.photos)) {
        await shareFile("IntPortal notes.zip", "application/zip", await api.notesZip(null));
        notesNote = photosInShare;
      } else await shareFile("IntPortal notes.md", "text/markdown", await api.notesMarkdown(null));
    } catch (e) {
      notesNote = String(e);
    }
  }

  function noteHeading(key: string, title: string | null = null): string {
    if (key.startsWith("note:")) return title?.trim() || "Untitled note";
    if (key.startsWith("class:")) return key.slice(6);
    const [y, m, d] = key.slice(4).split("-").map(Number);
    return new Date(y, m - 1, d).toLocaleDateString(undefined, { weekday: "short", month: "short", day: "numeric" });
  }
</script>

  <section class="card notch block">
    <p class="label">Your notes</p>
    <div class="row">
      <button class="primary" onclick={newNote}>New note</button>
      <button class="ghost" onclick={exportAll} disabled={app.notes.length === 0}>Export all</button>
    </div>
    {#if app.notes.length === 0}
      <p class="fine">Nothing written yet. Open a class on Schedule to keep notes for it, add a note for today on Today, or start a new one here.</p>
    {:else}
      <input class="search" type="search" bind:value={query} placeholder="Search notes" aria-label="Search notes" />
      <ul class="notes">
        {#each shown as n (n.key)}
          <li>
            <button data-source={n.key} onclick={() => openNote(n.key, noteHeading(n.key, n.title), n.title)}>
              <strong>{noteHeading(n.key, n.title)}</strong>
              <span>{previewOf(n)}</span>
            </button>
          </li>
        {/each}
      </ul>
      {#if shown.length === 0}<p class="fine">No note mentions "{query}".</p>{/if}
    {/if}
    {#if notesNote}<p class="fine" role="alert">{notesNote}</p>{/if}
  </section>

<style>
  /* Its two actions: without this they fall back to the system's grey button. */
  .row button {
    min-height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink);
    font-weight: 600;
  }
  .row button:disabled {
    opacity: 0.5;
  }
  .block {
    --step: 4px;
    display: grid;
    gap: 10px;
    padding: 16px;
  }
  .row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .search {
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: var(--text-body);
  }
  .notes {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
  }
  .notes button {
    width: 100%;
    height: auto;
    display: grid;
    gap: 2px;
    padding: 10px 12px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    text-align: left;
  }
  .notes span {
    font-family: var(--font-body, inherit);
    font-weight: 400;
    font-size: var(--text-caption);
    color: var(--ink-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>

<script lang="ts">
  import { app, openNote, setDeadlineAt, setReminderLead, setRoom, setStudyAt, syncNow } from "../state.svelte";
  import { api, isoDate } from "../api";
  import { shareFile } from "../share";
  import { HAND_TUNED, PALETTES, derive } from "../rooms";

  let { onsignout, ongallery }: { onsignout: () => void; ongallery?: () => void } = $props();
  let confirming = $state(false);

  // The last day of classes: remembered, or about a semester from now.
  let lastDay = $state(remembered("lastDay") ?? isoDate(new Date(Date.now() + 17 * 7 * 86_400_000)));
  let exportNote = $state("");

  function remembered(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  async function exportClasses() {
    exportNote = "";
    try {
      localStorage.setItem("lastDay", lastDay);
    } catch {
      // Asked again next time.
    }
    try {
      const ics = await api.exportIcs(isoDate(new Date()), lastDay);
      const done = await shareFile("IntPortal classes.ics", "text/calendar", ics);
      if (done === "shared") exportNote = "Sent. Open it in Calendar to add your classes.";
    } catch (e) {
      exportNote = String(e);
    }
  }

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
      await shareFile("IntPortal notes.md", "text/markdown", await api.notesMarkdown(null));
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

  const rooms = [
    ...HAND_TUNED,
    ...Object.entries(PALETTES).map(([id, p]) => {
      const r = derive(p);
      return { id, name: p.name, swatch: [r["--ground"], r["--card"], r["--gold"]] };
    }),
  ];

  const synced = $derived.by(() => {
    const s = app.snapshot?.last_synced;
    return s ? new Date(Number(s) * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) : "Never";
  });

  async function signOut() {
    await api.signOut();
    onsignout();
  }
</script>

<div class="screen">
  <header>
    <p class="label">Account and look</p>
    <h1>You</h1>
  </header>

  <section class="card notch block">
    <p class="label">Sync</p>
    <div class="line"><span>Last synced</span><strong>{synced}</strong></div>
    <div class="line"><span>Server</span><strong>{app.snapshot?.host ?? "—"}</strong></div>
    <button class="primary" onclick={syncNow} disabled={app.sync === "syncing"}>{app.sync === "syncing" ? "Syncing…" : "Sync now"}</button>
  </section>

  <section class="card notch block">
    <p class="label">Class reminders</p>
    <div class="leads">
      {#each [0, 5, 10, 15, 30] as m (m)}
        <button class:on={app.reminderLead === m} onclick={() => setReminderLead(m)}>{m === 0 ? "Off" : `${m} min`}</button>
      {/each}
    </div>
    <p class="fine">{app.reminderLead ? `A nudge ${app.reminderLead} minutes before each class. A class you mark vacant stays quiet that week.` : "No reminders."}</p>
    <p class="label">Deadlines</p>
    <div class="leads">
      {#each [-1, 18 * 60, 19 * 60, 20 * 60] as m (m)}
        <button class:on={app.deadlineAt === m} onclick={() => setDeadlineAt(m)}>{m < 0 ? "Off" : `${m / 60 - 12} PM`}</button>
      {/each}
    </div>
    <p class="fine">{app.deadlineAt >= 0 ? "The evening before each quiz, exam and project on your syllabus pages." : "No deadline heads-ups."}</p>
    <p class="label">Study</p>
    <div class="leads">
      {#each [-1, 7 * 60, 19 * 60, 21 * 60] as m (m)}
        <button class:on={app.studyAt === m} onclick={() => setStudyAt(m)}>{m < 0 ? "Off" : m < 12 * 60 ? `${m / 60} AM` : `${m / 60 - 12} PM`}</button>
      {/each}
    </div>
    <p class="fine">{app.studyAt >= 0 ? "Only on days your flashcards are due." : "No study reminders."}</p>
    {#if app.queued.error}<p class="queued">Couldn't schedule reminders: {app.queued.error}</p>{/if}
    {#if app.queued.next}
      <p class="queued">Next: <strong>{app.queued.next.title}</strong>, {app.queued.next.at.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" })} · {app.queued.count} this week</p>
    {/if}
  </section>

  <section class="card notch block">
    <p class="label">Room</p>
    <div class="rooms">
      {#each rooms as r (r.id)}
        <button class:on={app.room === r.id} onclick={() => setRoom(r.id)}>
          <span class="swatch">{#each r.swatch as c (c)}<i style:background={c}></i>{/each}</span>
          <span>{r.name}</span>
        </button>
      {/each}
    </div>
  </section>

  <section class="card notch block">
    <p class="label">Calendar</p>
    <p class="fine">Put every class in your phone's calendar, repeating weekly until the last day of classes. Vacant and moved weeks come along.</p>
    <label class="field">Last day of classes <input type="date" bind:value={lastDay} /></label>
    <button class="primary" onclick={exportClasses}>Add classes to calendar</button>
    {#if exportNote}<p class="fine" role="status">{exportNote}</p>{/if}
  </section>

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
            <button onclick={() => openNote(n.key, noteHeading(n.key, n.title), n.title)}>
              <strong>{noteHeading(n.key, n.title)}</strong>
              <span>{n.preview}</span>
            </button>
          </li>
        {/each}
      </ul>
      {#if shown.length === 0}<p class="fine">No note mentions "{query}".</p>{/if}
    {/if}
    {#if notesNote}<p class="fine" role="alert">{notesNote}</p>{/if}
  </section>

  {#if __REVIEW__ && ongallery}
    <button class="ghost" onclick={ongallery}>Open the design gallery</button>
  {/if}

  <section class="card notch block">
    <p class="label">Privacy</p>
    <p class="fine">Your login stays in this phone's keychain. Your schedule, grades and notes stay on this phone; signing out erases them. IntPortal only talks to PUP SIS.</p>
    {#if confirming}
      <div class="row">
        <button class="danger" onclick={signOut}>Sign out and erase</button>
        <button class="ghost" onclick={() => (confirming = false)}>Cancel</button>
      </div>
    {:else}
      <button class="ghost" onclick={() => (confirming = true)}>Sign out</button>
    {/if}
  </section>
</div>

<style>
  .field {
    display: grid;
    gap: 4px;
    font-size: 13px;
    color: var(--ink-3);
  }
  .field input {
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
  .search {
    height: 40px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: 16px;
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
    font-size: 13px;
    color: var(--ink-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
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
  .block {
    --step: 4px;
    display: grid;
    gap: 10px;
    padding: 16px;
  }
  .line {
    display: flex;
    justify-content: space-between;
    font-size: 15px;
    color: var(--ink-2);
  }
  .line strong {
    color: var(--ink);
    font-weight: 600;
  }
  button {
    height: 44px;
    border: 0;
    border-radius: 10px;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 14px;
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .ghost {
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .danger {
    background: var(--bad);
    color: #fff;
  }
  .row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .leads {
    display: grid;
    grid-template-columns: repeat(5, 1fr);
    gap: 6px;
  }
  .leads button {
    height: 38px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-size: 13px;
  }
  .leads button.on {
    background: var(--gold);
    color: var(--on-gold);
    box-shadow: none;
  }
  /* Two rows that scroll sideways: no scroll area nested inside the page. */
  .rooms {
    display: grid;
    grid-auto-flow: column;
    grid-template-rows: repeat(2, auto);
    grid-auto-columns: 30%;
    gap: 8px;
    overflow-x: auto;
    scroll-snap-type: x mandatory;
    scrollbar-width: none;
    padding: 2px;
    margin: -2px;
  }
  .rooms::-webkit-scrollbar {
    display: none;
  }
  .rooms button {
    scroll-snap-align: start;
  }
  .rooms button {
    height: auto;
    display: grid;
    gap: 8px;
    padding: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-family: var(--font-body);
    font-weight: 600;
    font-size: 12px;
    line-height: 1.2;
  }
  .rooms button.on {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .swatch {
    display: flex;
    height: 28px;
    overflow: hidden;
    border-radius: 6px;
  }
  .swatch i {
    flex: 1;
  }
  .queued {
    margin: 0;
    font-size: 13px;
    color: var(--gold);
  }
  .queued strong {
    color: var(--ink);
  }
  .fine {
    margin: 0;
    font-size: 14px;
    color: var(--ink-2);
  }
</style>

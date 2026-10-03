<script lang="ts">
  import { askForCalendar } from "../devcal";
  import { app, openNote, scheduleReminders, setCalendar, setDeadlineAt, setReminderLead, setRoom, setStudyAt, syncNow } from "../state.svelte";
  import { api, isoDate } from "../api";
  import { shareFile } from "../share";
  import { buzz, haptics, setHaptics } from "../haptics";
  import { lock, setLock } from "../lock.svelte";
  import { HAND_TUNED, PALETTES, derive } from "../rooms";
  import Isko from "../Isko.svelte";
  import Lar from "../lar/Lar.svelte";

  let { onsignout, ongallery }: { onsignout: () => void; ongallery?: () => void } = $props();
  let confirming = $state<null | "out" | "erase">(null);

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

  let calendarNote = $state("");
  /** Turning either on asks iOS for calendar access the first time. */
  async function toggleCalendar(which: "calendarEvents" | "calendarClasses", box: HTMLInputElement) {
    calendarNote = "";
    if (box.checked && (await askForCalendar()) !== "granted") {
      box.checked = false;
      calendarNote = "Calendar access is off. Turn it on in the phone's Settings, under IntPortal, then try again.";
      return;
    }
    buzz.tick();
    const problem = await setCalendar(which, box.checked);
    if (problem) calendarNote = `Couldn't update the IntPortal calendar: ${problem}`;
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

  async function eraseAll() {
    await api.signOut();
    await api.eraseEverything();
    onsignout();
  }
</script>

<div class="screen">
  <header class="top">
    <div>
      <p class="label">Account and look</p>
      <h1>You</h1>
    </div>
    <span class="pair"><Isko size={52} pose="stand" /><Lar size={2} cube={false} /></span>
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
    {#if app.notifications === false}
      <p class="fine">Notifications are off for IntPortal, so none of these can reach you.</p>
      <button class="primary" onclick={() => scheduleReminders(true)}>Turn on notifications</button>
      <p class="fine">If nothing happens, turn them on in the phone's Settings, under IntPortal.</p>
    {/if}
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
    <label class="lockrow"><input type="checkbox" checked={haptics.on} onchange={(e) => { setHaptics(e.currentTarget.checked); buzz.tick(); }} /> Haptics</label>
    <p class="fine">Small taps you feel when you mark a class, pull to sync, finish a deck or unlock.</p>
  </section>

  <section class="card notch block">
    <p class="label">Calendar</p>
    <label class="lockrow"><input type="checkbox" checked={app.calendarClasses} onchange={(e) => toggleCalendar("calendarClasses", e.currentTarget)} /> Keep classes in my calendar</label>
    <p class="fine">An IntPortal calendar on this phone holds the next eight weeks of classes. Vacant weeks drop out and moved weeks move. Your other calendars are never touched.</p>
    <label class="lockrow"><input type="checkbox" checked={app.calendarEvents} onchange={(e) => toggleCalendar("calendarEvents", e.currentTarget)} /> Show my own events</label>
    <p class="fine">Today lists your other events, and LAR counts them as busy when he suggests study time.</p>
    {#if calendarNote}<p class="fine" role="status">{calendarNote}</p>{/if}
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
    <p class="fine">Your login stays in this phone's keychain and everything else stays on this phone. IntPortal only talks to PUP SIS.</p>
    <label class="lockrow"><input type="checkbox" checked={lock.enabled} onchange={(e) => { const box = e.currentTarget; setLock(box.checked).then(() => (box.checked = lock.enabled)); }} /> Lock with Face ID or passcode</label>
    <p class="fine">Asks when IntPortal opens or comes back after a minute away, and hides the screen in the app switcher.</p>
    {#if lock.error}<p class="fine">{lock.error}</p>{/if}
    <p class="fine">Each student's notes and decks stay separate on this phone; another student signing in here can't see yours.</p>
    <p class="fine">Signing out removes your login, schedule and grades. Your notes, decks, syllabus pages and goals stay for when you sign back in.</p>
    {#if confirming === "out"}
      <div class="row">
        <button class="danger" onclick={signOut}>Sign out</button>
        <button class="ghost" onclick={() => (confirming = null)}>Cancel</button>
      </div>
    {:else if confirming === "erase"}
      <p class="fine">This deletes every note, deck and syllabus page on this phone too. It can't be undone.</p>
      <div class="row">
        <button class="danger" onclick={eraseAll}>Erase everything</button>
        <button class="ghost" onclick={() => (confirming = null)}>Cancel</button>
      </div>
    {:else}
      <div class="row">
        <button class="ghost" onclick={() => (confirming = "out")}>Sign out</button>
        <button class="ghost" onclick={() => (confirming = "erase")}>Erase everything</button>
      </div>
    {/if}
  </section>

  <p class="about">IskoLAR. You're Isko, and LAR is the Lakbay-Aral Robot who came through the portal to study with you.</p>
</div>

<style>
  .top {
    display: flex;
    align-items: end;
    justify-content: space-between;
  }
  .pair {
    display: flex;
    align-items: end;
    gap: 6px;
  }
  .about {
    margin: 8px 0 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
    text-align: center;
    text-wrap: balance;
  }
  .lockrow {
    display: flex;
    align-items: center;
    gap: 10px;
    font-weight: 600;
  }
  .lockrow input {
    width: 20px;
    height: 20px;
  }
  .field {
    display: grid;
    gap: 4px;
    font-size: min(0.765rem, 23px);
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
    font-size: max(16px, min(0.941rem, 29px));
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
    font-size: min(0.941rem, 29px);
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
    font-size: min(0.765rem, 23px);
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
    font-size: min(1.647rem, 36px);
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
    font-size: min(0.882rem, 27px);
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
    font-size: min(0.824rem, 25px);
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
    font-size: min(0.765rem, 23px);
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
    font-size: min(0.706rem, 22px);
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
    font-size: min(0.765rem, 23px);
    color: var(--gold);
  }
  .queued strong {
    color: var(--ink);
  }
  .fine {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
</style>

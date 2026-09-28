<script lang="ts">
  import { app, openNote, setReminderLead, setRoom, syncNow } from "../state.svelte";
  import { api } from "../api";
  import { HAND_TUNED, PALETTES, derive } from "../rooms";

  let { onsignout, ongallery }: { onsignout: () => void; ongallery?: () => void } = $props();
  let confirming = $state(false);

  function noteHeading(key: string): string {
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
    <p class="label">Your notes</p>
    {#if app.notes.length === 0}
      <p class="fine">Nothing written yet. Open a class on Schedule to keep notes for it, or add a note for today on Today.</p>
    {:else}
      <ul class="notes">
        {#each app.notes as n (n.key)}
          <li>
            <button onclick={() => openNote(n.key, noteHeading(n.key), n.title)}>
              <strong>{noteHeading(n.key)}</strong>
              <span>{n.preview}</span>
            </button>
          </li>
        {/each}
      </ul>
    {/if}
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

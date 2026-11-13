<script lang="ts">
  // You (spec 047 C1–C11): eight quick switches and search on top, then short
  // rows in four groups. Each row opens its own page, closed by a large Back.
  import { askForCalendar } from "../devcal";
  import { adopt, app, forgetThemes, mabiniSyncNow, restoreThemes, themesForBackup, refreshLogins, scheduleReminders, setCalendar, setDeadlineAt, setExtra, setLook, setReminderLead, setRoom, setStudyAt, setTextStyle, syncNow } from "../state.svelte";
  import { api, isoDate, type BackupPreview, type Portal, type Space } from "../api";
  import { onMount } from "svelte";
  import PortalConnect from "../PortalConnect.svelte";
  import NotesCard from "../NotesCard.svelte";
  import { shareFile } from "../share";
  import { friendly } from "../errors";
  import { buzz, haptics, setHaptics } from "../haptics";
  import { sfx, setSound, sound } from "../sound";
  import { lock, setLock, unlockWith } from "../lock.svelte";
  import { HAND_TUNED, PALETTES, derive } from "../rooms";
  import { roles } from "../theme";
  import { closable } from "../back";
  import Lar from "../lar/Lar.svelte";
  import ModelCard from "../assis/ModelCard.svelte";
  import { chatModel, installed as aiOn } from "../assis/assis.svelte";
  import PixelIcon, { type SpriteName } from "../PixelIcon.svelte";
  import { CARD_NAMES, GROUPS, MOVABLE, moveCard, rowProblem, searchSettings, toggleCard, type PageId } from "../you";

  let { onsignout, ongallery }: { onsignout: () => void; ongallery?: () => void } = $props();
  let confirming = $state<null | "out" | "erase">(null);
  let page = $state<PageId | null>(null);
  let query = $state("");
  const hits = $derived(searchSettings(query));

  // Haptics and sounds live outside Svelte's state, so the switches mirror them.
  let hapticsOn = $state(haptics.on);
  let soundOn = $state(sound.on);

  // The theme maker (C12–C19) is its own page, mounted by +page.svelte.
  function openMaker() {
    buzz.select();
    app.themeMaker = true;
  }

  function go(id: PageId) {
    buzz.select();
    page = id;
    query = "";
    confirming = null;
    scrollTo(0, 0);
  }
  function home() {
    page = null;
    scrollTo(0, 0);
  }
  $effect(() => {
    if (page) return closable(home);
  });

  // The last day of classes: remembered, or about a semester from now.
  let lastDay = $state(remembered("lastDay") ?? isoDate(new Date(Date.now() + 17 * 7 * 86_400_000)));
  let exportNote = $state("");

  // Backup and data (spec 047 C9–C11).
  let space = $state<Space | null>(null);
  let backupNote = $state("");
  let backupBad = $state(false);
  let picked = $state<{ text: string; preview: BackupPreview } | null>(null);
  const say = (note: string, bad = false) => ((backupNote = note), (backupBad = bad));
  const size = (n: number) => (n < 1024 ? `${n} B` : n < 1024 ** 2 ? `${(n / 1024).toFixed(1)} KB` : `${(n / 1024 ** 2).toFixed(1)} MB`);
  $effect(() => {
    if (page === "backup") api.spaceUsed().then((s) => (space = s), () => (space = null));
  });
  async function backUp() {
    say("");
    try {
      const text = await api.backupMake(themesForBackup());
      const name = `intportal-backup-${isoDate(new Date())}.json`;
      say((await shareFile(name, "application/json", text)) === "shared" ? "Backup saved." : "");
    } catch (e) {
      say(friendly(e), true);
    }
  }
  async function pickBackup(e: Event & { currentTarget: HTMLInputElement }) {
    const file = e.currentTarget.files?.[0];
    e.currentTarget.value = "";
    picked = null;
    if (!file) return;
    try {
      const text = await file.text();
      picked = { text, preview: await api.backupPreview(text) };
      say("");
    } catch (err) {
      say(friendly(err), true);
    }
  }
  async function restore() {
    if (!picked) return;
    try {
      restoreThemes(await api.backupRestore(picked.text));
      await adopt(await api.snapshot());
      picked = null;
      say("Restored.");
      api.spaceUsed().then((s) => (space = s), () => {});
    } catch (err) {
      say(friendly(err), true);
    }
  }

  function remembered(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }
  function keep(key: string, value: string) {
    try {
      localStorage.setItem(key, value);
    } catch {
      // Asked again next time.
    }
  }

  let calendarNote = $state("");
  /** Turning either on asks iOS for calendar access the first time. */
  async function toggleCalendar(which: "calendarEvents" | "calendarClasses", on: boolean, box?: HTMLInputElement) {
    calendarNote = "";
    if (on && (await askForCalendar()) !== "granted") {
      if (box) box.checked = false;
      calendarNote = "Calendar access is off. Turn it on in the phone's Settings, under IntPortal, then try again.";
      if (!box) page = "calendar";
      return;
    }
    buzz.tick();
    const problem = await setCalendar(which, on);
    if (problem) calendarNote = `Couldn't update the IntPortal calendar: ${problem}`;
  }

  async function exportClasses() {
    exportNote = "";
    keep("lastDay", lastDay);
    try {
      const ics = await api.exportIcs(isoDate(new Date()), lastDay);
      const done = await shareFile("IntPortal classes.ics", "text/calendar", ics);
      if (done === "shared") exportNote = "Sent. Open it in Calendar to add your classes.";
    } catch (e) {
      exportNote = String(e);
    }
  }

  /** A nudge switched off remembers its time, so switching it back on restores it. */
  const lastOr = (key: string, fallback: number) => Number(remembered(key) ?? fallback);

  // C1: the eight quick switches. A lit one is gold on its icon and edge.
  const QUICK: { label: string; icon: SpriteName; on: () => boolean; set: (on: boolean) => void }[] = [
    { label: "Haptics", icon: "buzz", on: () => hapticsOn, set: (on) => { setHaptics((hapticsOn = on)); buzz.tick(); } },
    { label: "Sounds", icon: "sound", on: () => soundOn, set: (on) => { setSound((soundOn = on)); if (on) sfx.done(0); } },
    { label: "Lock", icon: "lock", on: () => lock.enabled, set: (on) => setLock(on) },
    { label: "Ground", icon: "wave", on: () => app.ground, set: (on) => setLook("ground", on) },
    { label: "Classes", icon: "bell", on: () => app.reminderLead > 0, set: (on) => { if (!on) keep("lastLead", String(app.reminderLead)); setReminderLead(on ? lastOr("lastLead", 10) : 0); } },
    { label: "Deadlines", icon: "bell", on: () => app.deadlineAt >= 0, set: (on) => { if (!on) keep("lastDeadlineAt", String(app.deadlineAt)); setDeadlineAt(on ? lastOr("lastDeadlineAt", 19 * 60) : -1); } },
    { label: "Study", icon: "bell", on: () => app.studyAt >= 0, set: (on) => { if (!on) keep("lastStudyAt", String(app.studyAt)); setStudyAt(on ? lastOr("lastStudyAt", 19 * 60) : -1); } },
    { label: "Calendar", icon: "date", on: () => app.calendarClasses, set: (on) => toggleCalendar("calendarClasses", on) },
  ];
  function flip(q: (typeof QUICK)[number]) {
    if (q.label !== "Haptics") buzz.tick();
    q.set(!q.on());
  }

  const rooms = $derived([
    ...HAND_TUNED,
    ...app.themes.map((t) => {
      const r = roles(t.theme);
      return { id: `theme:${t.id}`, name: t.theme.name, swatch: [r["--ground"], r["--card"], r["--gold"]] };
    }),
    ...Object.entries(PALETTES).map(([id, p]) => {
      const r = derive(p);
      return { id, name: p.name, swatch: [r["--ground"], r["--card"], r["--gold"]] };
    }),
  ]);

  const ICON: Record<PageId, SpriteName> = { accounts: "you", theme: "mark", layout: "bullet", motion: "wave", reminders: "bell", calendar: "date", assis: "ai", notes: "note2", backup: "disk", privacy: "lock" };
  const TAB_NAME = { today: "Today", schedule: "Schedule", study: "Study" };
  const LEVEL = { full: "Full", short: "Short", calm: "Calm", off: "Off" };

  /** What each row shows on its right. */
  function value(id: PageId): string {
    const connected = Number(app.sisConnected) + Number(app.mabiniConnected);
    return {
      accounts: connected ? `${connected} connected` : "Not connected",
      theme: rooms.find((r) => r.id === app.room)?.name ?? "",
      layout: `Opens on ${TAB_NAME[app.opensOn]}`,
      motion: `Dive ${LEVEL[app.dive]}`,
      reminders: app.reminderLead ? `${app.reminderLead} min` : "Off",
      calendar: app.calendarClasses ? "On" : "Off",
      assis: aiOn() ? "On" : "Off",
      notes: `${app.notes.length}`,
      backup: "Coming",
      privacy: lock.enabled ? "Locked" : "",
    }[id];
  }
  const problem = (id: PageId) =>
    rowProblem(id, {
      sisRejected: app.sisConnected && app.sisRejected,
      mabiniRejected: app.mabiniConnected && app.mabiniRejected,
      mabiniError: app.mabiniConnected ? app.mabiniError : null,
      notifications: app.notifications,
      remindersOn: app.reminderLead > 0 || app.deadlineAt >= 0 || app.studyAt >= 0,
      queuedError: app.queued.error,
      lockError: lock.error,
    });
  const NAME = Object.fromEntries(GROUPS.flatMap(([, r]) => r)) as Record<PageId, string>;

  const synced = $derived.by(() => {
    const s = app.snapshot?.last_synced;
    return s ? new Date(Number(s) * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) : "Never";
  });

  // The portals the core lists, to offer a connect form for one that isn't.
  let portals = $state<Portal[]>([]);
  onMount(() => {
    api.portals().then((p) => (portals = p)).catch(() => {});
  });
  const portalOf = (id: string) => portals.find((p) => p.id === id);
  const mabiniSynced = $derived.by(() => {
    const s = app.mabini?.last_synced;
    return s ? new Date(s * 1000).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" }) : "Never";
  });

  async function signOut() {
    await api.signOut();
    await refreshLogins();
    confirming = null;
    onsignout();
  }

  async function mabiniOut() {
    await api.mabiniSignOut();
    await refreshLogins();
    onsignout();
  }

  async function eraseAll() {
    await api.signOut();
    await api.mabiniSignOut();
    await api.eraseEverything();
    forgetThemes();
    await refreshLogins();
    onsignout();
  }
</script>

{#snippet row(id: PageId, name: string, sub?: string, summary = true)}
  {@const bad = problem(id)}
  <button class="yrow" onclick={() => go(id)}>
    <span class="yi"><PixelIcon name={ICON[id]} size={18} /></span>
    <span class="tx"><strong>{name}</strong>{#if sub}<small>{sub}</small>{/if}</span>
    {#if bad}<span class="val bad">{bad}</span>{:else if summary && value(id)}<span class="val">{value(id)}</span>{/if}
    <span class="chev"><PixelIcon name="chev" size={11} /></span>
  </button>
{/snippet}

{#snippet seg(label: string, options: [string | number, string][], current: string | number, pick: (v: any) => void)}
  <div class="field">
    <p class="label">{label}</p>
    <div class="seg" role="group" aria-label={label}>
      {#each options as [v, name] (v)}
        <button aria-pressed={current === v} onclick={() => { buzz.select(); pick(v); }}>{name}</button>
      {/each}
    </div>
  </div>
{/snippet}

{#snippet sw(label: string, on: boolean, set: (on: boolean) => void)}
  <label class="sw"><span>{label}</span><input type="checkbox" checked={on} onchange={(e) => { buzz.tick(); set(e.currentTarget.checked); }} /></label>
{/snippet}

{#snippet signOutRow()}
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
  {/if}
{/snippet}

{#if page}
  {#key page}
    <div class="screen ypage">
      <header class="top"><h1>{NAME[page]}</h1></header>

      {#if page === "accounts"}
        <section class="card notch block">
          <p class="label">SIS</p>
          {#if app.sisConnected && app.sisRejected}
            <p class="fine">The SIS turned your login down. Changed your password?</p>
            <!-- The portal list loads after the page opens; the form waits for it. -->
            {#if portalOf("sis")}<PortalConnect portal={portalOf("sis")!} prefill />{/if}
          {:else if app.sisConnected}
            <div class="line"><span>Last synced</span><strong>{synced}</strong></div>
            <div class="line"><span>Server</span><strong>{app.snapshot?.host ?? "—"}</strong></div>
            <button class="primary" onclick={syncNow} disabled={app.sync === "syncing"}>{app.sync === "syncing" ? "Syncing…" : "Sync now"}</button>
          {:else if portalOf("sis")}
            <p class="fine">Add your SIS login for your schedule and grades.</p>
            <PortalConnect portal={portalOf("sis")!} />
          {/if}
        </section>
        <section class="card notch block">
          <p class="label">eMabini</p>
          {#if app.mabiniConnected && app.mabiniRejected}
            <p class="fine">eMabini turned your login down. Changed your password?</p>
            <!-- The portal list loads after the page opens; the form waits for it. -->
            {#if portalOf("mabini")}<PortalConnect portal={portalOf("mabini")!} prefill />{/if}
          {:else if app.mabiniConnected}
            <div class="line"><span>Last synced</span><strong>{mabiniSynced}</strong></div>
            {#if app.mabiniError}<p class="fine">{app.mabiniError}</p>{/if}
            <div class="row">
              <button class="primary" onclick={mabiniSyncNow} disabled={app.mabiniSync === "syncing"}>{app.mabiniSync === "syncing" ? "Syncing…" : "Sync now"}</button>
              <button class="ghost" onclick={() => (app.mabiniPage = true)}>Courses</button>
            </div>
          {:else if portalOf("mabini")}
            <p class="fine">Add your eMabini login for your courses and deadlines.</p>
            <PortalConnect portal={portalOf("mabini")!} />
          {/if}
        </section>
        <p class="fine">Your logins stay in this phone's keychain. IntPortal only talks to PUP SIS and eMabini.</p>
        <p class="fine">Signing out of SIS removes your login, schedule and grades; signing out of eMabini removes its login and courses. Your notes, decks, syllabus pages and goals stay for when you sign back in.</p>
        {#if confirming}
          {@render signOutRow()}
        {:else if app.sisConnected || app.mabiniConnected}
          <div class="row">
            {#if app.sisConnected}<button class="ghost" onclick={() => (confirming = "out")}>Sign out of SIS</button>{/if}
            {#if app.mabiniConnected}<button class="ghost" onclick={mabiniOut}>Sign out of eMabini</button>{/if}
          </div>
        {/if}
      {:else if page === "theme"}
        <button class="primary" onclick={openMaker}>Make a theme</button>
        <div class="rooms">
          {#each rooms as r (r.id)}
            <button class="notch" class:on={app.room === r.id} aria-pressed={app.room === r.id} onclick={() => { buzz.select(); setRoom(r.id); }}>
              <span class="swatch">{#each r.swatch as c, i (i)}<i style:background={c}></i>{/each}</span>
              <span>{r.name}</span>
            </button>
          {/each}
        </div>
        <div class="field">
          <p class="label">Text style</p>
          <div class="styles" role="group" aria-label="Text style">
            <button class:on={app.textStyle === "intportal"} aria-pressed={app.textStyle === "intportal"} onclick={() => setTextStyle("intportal")}><span style:font-family="var(--font-ui)" style:font-weight="700">IntPortal</span></button>
            <button class:on={app.textStyle === "classic"} aria-pressed={app.textStyle === "classic"} onclick={() => setTextStyle("classic")}><span style:font-family='"Montserrat Variable", system-ui, sans-serif' style:font-weight="700">Classic</span></button>
          </div>
        </div>
        <p class="fine">Classic brings back Montserrat and Source Sans, the original look. The pixel numerals and LAR's voice stay as they are.</p>
      {:else if page === "layout"}
        {@render seg("App opens on", [["today", "Today"], ["schedule", "Schedule"], ["study", "Study"]], app.opensOn, (v) => setLook("opensOn", v))}
        {@render seg("Lists", [["comfy", "Comfy"], ["compact", "Compact"]], app.density, (v) => setLook("density", v))}
        <div class="field">
          <p class="label">Today's cards</p>
          <div class="card notch list pad">
            {#each app.cards.order as id, i (id)}
              {@const on = !app.cards.hidden.includes(id)}
              <div class="reorder" class:off={!on}>
                <input type="checkbox" checked={on} aria-label="Show {CARD_NAMES[id]}" onchange={() => { buzz.tick(); setLook("cards", toggleCard(app.cards, id)); }} />
                <span>{CARD_NAMES[id]}</span>
                <button disabled={i === 0} aria-label="Move {CARD_NAMES[id]} up" onclick={() => { buzz.select(); setLook("cards", { ...app.cards, order: moveCard(app.cards.order, i, -1) }); }}><PixelIcon name="up" size={14} /></button>
                <button disabled={i === MOVABLE.length - 1} aria-label="Move {CARD_NAMES[id]} down" onclick={() => { buzz.select(); setLook("cards", { ...app.cards, order: moveCard(app.cards.order, i, 1) }); }}><PixelIcon name="down" size={14} /></button>
              </div>
            {/each}
            <div class="reorder" class:off={app.cards.hidden.includes("events")}>
              <input type="checkbox" checked={!app.cards.hidden.includes("events")} aria-label="Show Your events" onchange={() => { buzz.tick(); setLook("cards", toggleCard(app.cards, "events")); }} />
              <span>Your events <small>in Today's list</small></span>
            </div>
          </div>
        </div>
        <p class="fine">Hiding a card only takes it off Today. Reminders keep working.</p>
      {:else if page === "motion"}
        {@render seg("The dive on opening", [["full", "Full"], ["short", "Short"], ["off", "Off"]], app.dive, (v) => setLook("dive", v))}
        {@render seg("Done effects", [["full", "Full"], ["calm", "Calm"], ["off", "Off"]], app.effects, (v) => setLook("effects", v))}
        <div class="card notch list pad">
          {@render sw("Moving ground", app.ground, (on) => setLook("ground", on))}
          {@render sw("Haptics", hapticsOn, (on) => setHaptics((hapticsOn = on)))}
          {@render sw("Sounds", soundOn, (on) => { setSound((soundOn = on)); if (on) sfx.done(0); })}
        </div>
        <p class="fine">Haptics are small taps you feel when you mark a class, pull to sync, finish a deck or unlock. Sounds are little pixel blips, off by default.</p>
        <p class="fine">If Reduce Motion is on in your phone's settings, it wins over all of these.</p>
      {:else if page === "reminders"}
        {@render seg("Before each class, minutes", [[0, "Off"], [5, "5"], [10, "10"], [15, "15"], [30, "30"]], app.reminderLead, setReminderLead)}
        <p class="fine">{app.reminderLead ? `A nudge ${app.reminderLead} minutes before each class. A class you mark vacant stays quiet that week.` : "No reminders."}</p>
        {@render seg("Deadlines, the evening before", [[-1, "Off"], [18 * 60, "6 PM"], [19 * 60, "7 PM"], [20 * 60, "8 PM"]], app.deadlineAt, setDeadlineAt)}
        <p class="fine">{app.deadlineAt >= 0 ? "The evening before each quiz, exam and project on your syllabus pages." : "No deadline heads-ups."}</p>
        {@render seg("Study, on days cards are due", [[-1, "Off"], [7 * 60, "7 AM"], [19 * 60, "7 PM"], [21 * 60, "9 PM"]], app.studyAt, setStudyAt)}
        <div class="card notch list pad">
          {@render sw("Warm-up in class reminders", app.warmUp, (on) => setExtra("warmUp", on))}
          {@render sw("Note after class", app.afterClass, (on) => setExtra("afterClass", on))}
          {@render sw("Sunday brief", app.brief, (on) => setExtra("brief", on))}
        </div>
        <p class="fine">At most 3 a day besides class reminders, none from 10 PM to 7 AM.</p>
        {#if app.notifications === false}
          <p class="fine">Notifications are off for IntPortal, so none of these can reach you.</p>
          <button class="primary" onclick={() => scheduleReminders(true)}>Turn on notifications</button>
          <p class="fine">If nothing happens, turn them on in the phone's Settings, under IntPortal.</p>
        {/if}
        {#if app.queued.error}<p class="queued">Couldn't schedule reminders: {app.queued.error}</p>{/if}
        {#if app.queued.next}
          <p class="queued">Next: <strong>{app.queued.next.title}</strong>, {app.queued.next.at.toLocaleString(undefined, { weekday: "short", hour: "numeric", minute: "2-digit" })} · {app.queued.count} this week</p>
        {/if}
      {:else if page === "calendar"}
        <div class="card notch list pad">
          <label class="sw"><span>Keep classes in my calendar</span><input type="checkbox" checked={app.calendarClasses} onchange={(e) => toggleCalendar("calendarClasses", e.currentTarget.checked, e.currentTarget)} /></label>
          <label class="sw"><span>Show my own events</span><input type="checkbox" checked={app.calendarEvents} onchange={(e) => toggleCalendar("calendarEvents", e.currentTarget.checked, e.currentTarget)} /></label>
        </div>
        {#if calendarNote}<p class="fine" role="status">{calendarNote}</p>{/if}
        <p class="fine">An IntPortal calendar on this phone holds the next eight weeks of classes. Vacant weeks drop out and moved weeks move. Your other calendars are never touched.</p>
        <p class="fine">Your own events show on Today, and LAR counts them as busy when he suggests study time.</p>
        <p class="fine">Put every class in your phone's calendar, repeating weekly until the last day of classes. Vacant and moved weeks come along.</p>
        <label class="date">Last day of classes <input type="date" bind:value={lastDay} /></label>
        <button class="primary" onclick={exportClasses}>Add classes to calendar</button>
        {#if exportNote}<p class="fine" role="status">{exportNote}</p>{/if}
      {:else if page === "assis"}
        {#if chatModel()}<ModelCard />{:else}<p class="fine">LAR's chat runs on this phone after you download a model. This phone has none to offer yet.</p>{/if}
      {:else if page === "notes"}
        <NotesCard />
      {:else if page === "backup"}
        <section class="card notch block">
          <p class="label">Back up</p>
          <p class="fine">One file with your notes, photos, decks, syllabus pages, goals, marks, your own deadlines and Done marks, subject colours, your study streak and themes, to move to a new phone. Your logins are never in it.</p>
          <p class="fine bad">The file has no password. Anyone who gets it can read your notes. Keep it somewhere private.</p>
          <button class="primary" onclick={backUp}>Back up</button>
        </section>
        <section class="card notch block">
          <p class="label">Restore</p>
          <p class="fine">Pick a backup of your own. You'll see what's in it before anything changes. On a new phone, sign in first.</p>
          <input type="file" accept="application/json,.json" aria-label="Choose a backup file" onchange={pickBackup} />
          {#if picked}
            {@const p = picked.preview}
            <p class="fine">Made {new Date(p.made * 1000).toLocaleDateString()}: {p.notes} notes, {p.decks} decks ({p.cards} cards), {p.syllabus_pages} syllabus pages, {p.own_deadlines} of your own deadlines, {p.themes} themes{p.photos ? `, ${p.photos} photos` : ""}.</p>
            <p class="fine">Restoring replaces the notes, decks, syllabus pages, goals, marks, deadlines, colours and streak on this phone with these.</p>
            <button class="danger" onclick={restore}>Replace with this backup</button>
            <button class="ghost" onclick={() => (picked = null)}>Cancel</button>
          {/if}
        </section>
        {#if backupNote}<p class="fine" class:bad={backupBad} role="status">{backupNote}</p>{/if}
        <section class="card notch block">
          <p class="label">Space used</p>
          {#if space}
            {#each [["Notes", space.notes], ["Photos", space.photos], ["Decks", space.decks], ["The rest", space.other]] as [name, n] (name)}
              <p class="fine">{name}: {size(n as number)}</p>
            {/each}
            <p class="fine">LAR's model is not counted here; it has its own card.</p>
          {:else}
            <p class="fine">Couldn't read the sizes.</p>
          {/if}
        </section>
      {:else if page === "privacy"}
        <div class="card notch list pad">
          <label class="sw"><span>Lock with {unlockWith}</span><input type="checkbox" checked={lock.enabled} onchange={(e) => { const box = e.currentTarget; buzz.tick(); setLock(box.checked).then(() => (box.checked = lock.enabled)); }} /></label>
        </div>
        <p class="fine">Asks when IntPortal opens or comes back after a minute away, and hides the screen in the app switcher.</p>
        {#if lock.error}<p class="fine bad">{lock.error}</p>{/if}
        <p class="fine">Your login stays in this phone's keychain and everything else stays on this phone. IntPortal only talks to PUP SIS and eMabini.</p>
        <p class="fine">Each student's notes and decks stay separate on this phone; another student signing in here can't see yours.</p>
        <p class="fine">Signing out lives in Accounts and keeps your notes, decks, syllabus pages and goals for when you sign back in.</p>
        {#if confirming}
          {@render signOutRow()}
        {:else}
          <button class="ghost bad" onclick={() => (confirming = "erase")}>Erase everything</button>
        {/if}
      {/if}

      <button class="yback notch" onclick={home}><PixelIcon name="chev" size={11} /> You</button>
    </div>
  {/key}
{:else}
  <div class="screen">
    <header class="top">
      <div>
        <p class="label">Account and look</p>
        <h1>You</h1>
      </div>
      <Lar size={2} cube={false} />
    </header>

    <div class="quick">
      {#each QUICK as q (q.label)}
        <button class="notch" aria-pressed={q.on()} onclick={() => flip(q)}>
          <PixelIcon name={q.icon} size={20} accent="currentColor" />
          <span>{q.label}</span>
        </button>
      {/each}
    </div>
    {#if lock.error}<p class="fine bad" role="status">{lock.error}</p>{/if}
    {#if calendarNote}<p class="fine" role="status">{calendarNote}</p>{/if}
    <label class="search">
      <PixelIcon name="search" size={16} accent="currentColor" />
      <input type="search" bind:value={query} placeholder="Search settings" aria-label="Search settings" />
    </label>

    {#if query.trim()}
      {#if hits.length}
        <div class="card notch list">
          {#each hits as s (s.name)}{@render row(s.page, s.name, NAME[s.page], false)}{/each}
        </div>
      {:else}
        <p class="fine">No setting matches "{query}".</p>
      {/if}
    {:else}
      {#each GROUPS as [group, rows] (group)}
        <div class="group">
          <p class="label">{group}</p>
          <div class="card notch list">
            {#each rows as [id, name] (id)}{@render row(id, name)}{/each}
          </div>
        </div>
      {/each}
    {/if}

    {#if __REVIEW__ && ongallery}
      <button class="ghost" onclick={ongallery}>Open the design gallery</button>
    {/if}
    <p class="about">LAR is the Lakbay-Aral Robot who came through the portal to study with you.</p>
  </div>
{/if}

<style>
  .screen {
    display: grid;
    gap: 14px;
  }
  .top {
    display: flex;
    align-items: end;
    justify-content: space-between;
  }
  h1 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: min(1.647rem, 36px);
    font-weight: var(--title-weight);
    letter-spacing: var(--title-track);
  }
  .about {
    margin: 8px 0 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
    text-align: center;
    text-wrap: balance;
  }

  /* C1: quick switches, a lit one gold on its icon and edge, not a gold block. */
  .quick {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 6px;
  }
  .quick button {
    --step: 3px;
    height: auto;
    min-height: 56px;
    padding: 7px 2px 5px;
    display: grid;
    justify-items: center;
    gap: 3px;
    border-radius: 0;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-3);
    font-family: var(--font-body);
    font-size: min(0.647rem, 20px);
    font-weight: 600;
    line-height: 1.05;
    transition:
      translate 0.12s var(--ease),
      box-shadow 0.16s var(--ease),
      color 0.16s var(--ease);
  }
  .quick button[aria-pressed="true"] {
    color: var(--ink);
    box-shadow: inset 0 0 0 1px var(--gold), inset 0 -2px 0 var(--gold);
  }
  .quick button[aria-pressed="true"] :global(svg) {
    color: var(--gold);
  }
  .quick button:active {
    translate: 0 1px;
  }

  .search {
    height: 44px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 0 12px;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-3);
  }
  .search input {
    flex: 1;
    min-width: 0;
    border: 0;
    background: none;
    outline: 0;
    color: var(--ink);
    font: inherit;
    font-size: 16px;
  }

  .group {
    display: grid;
    gap: 4px;
  }
  .group .label {
    margin: 0;
    padding-inline: 2px;
  }
  .list {
    --step: 4px;
    display: grid;
    grid-template-columns: minmax(0, 1fr);
    padding: 2px 0;
  }
  .list > :global(* + *) {
    box-shadow: inset 0 1px 0 var(--edge);
  }
  .list.pad {
    padding: 2px 12px;
  }
  .yrow {
    width: 100%;
    height: auto;
    min-height: 50px;
    padding: 9px 12px;
    border-radius: 0;
    background: none;
    display: flex;
    align-items: center;
    gap: 10px;
    text-align: left;
    color: var(--ink);
    font-family: var(--font-body);
    transition: scale 0.16s var(--ease);
  }
  .yrow:active {
    scale: 0.98;
  }
  .yi {
    width: 26px;
    display: grid;
    place-items: center;
    color: var(--ink-2);
  }
  .tx {
    flex: 1;
    min-width: 0;
  }
  .tx strong {
    display: block;
    font-weight: 600;
    font-size: min(0.882rem, 27px);
    line-height: 1.25;
  }
  .tx small {
    display: block;
    font-weight: 400;
    font-size: min(0.765rem, 23px);
    color: var(--ink-2);
  }
  .val {
    font-weight: 400;
    font-size: min(0.765rem, 23px);
    color: var(--ink-2);
    white-space: nowrap;
  }
  .bad {
    color: var(--bad);
  }
  .val.bad {
    font-weight: 600;
  }
  .chev {
    color: var(--ink-3);
  }
  /* C7: Compact lists keep every target at least 44 pt. */
  :global(:root[data-density="compact"]) .yrow {
    min-height: 44px;
    padding-block: 5px;
  }
  :global(:root[data-density="compact"]) .sw,
  :global(:root[data-density="compact"]) .reorder {
    min-height: 44px;
  }

  /* A page slides in with the shared ease; Reduce Motion skips to rest. */
  .ypage {
    animation: pin 0.26s var(--ease) backwards;
  }
  @keyframes pin {
    from {
      opacity: 0;
      translate: 22px 0;
    }
  }
  .yback {
    --step: 3px;
    height: auto;
    min-height: 50px;
    margin-top: 6px;
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    border-radius: 0;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    font-size: min(0.882rem, 27px);
  }
  .yback :global(svg) {
    rotate: 180deg;
  }

  .field {
    display: grid;
    gap: 6px;
  }
  .field .label {
    margin: 0;
  }
  .seg {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    gap: 2px;
    padding: 3px;
    border-radius: 12px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .seg button {
    height: 44px;
    border-radius: 9px;
    background: none;
    color: var(--ink-2);
    font-size: min(0.765rem, 23px);
    transition:
      background-color 0.16s var(--ease),
      color 0.16s var(--ease);
  }
  .seg button[aria-pressed="true"] {
    background: var(--gold);
    color: var(--on-gold);
  }
  .sw {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 50px;
    font-weight: 600;
  }
  .sw span {
    flex: 1;
  }
  .reorder {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 50px;
  }
  .reorder span {
    flex: 1;
    font-weight: 600;
  }
  .reorder small {
    font-weight: 400;
    color: var(--ink-3);
  }
  .reorder.off span {
    color: var(--ink-3);
  }
  .reorder button {
    width: 44px;
    height: 44px;
    display: grid;
    place-items: center;
    border-radius: 8px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .reorder button:disabled {
    opacity: 0.35;
  }

  .date {
    display: grid;
    gap: 4px;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  .date input {
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
  .block {
    --step: 4px;
    display: grid;
    gap: 10px;
    padding: 16px;
  }
  .block .label {
    margin: 0;
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
    color: var(--ink);
  }
  .primary {
    background: var(--gold);
    color: var(--on-gold);
  }
  .ghost {
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .ghost.bad {
    color: var(--bad);
  }
  .danger {
    background: var(--bad);
    color: var(--white);
  }
  .row {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .styles {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .styles button {
    min-height: 48px;
    background: var(--ground);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .styles button.on {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .rooms {
    display: grid;
    grid-template-columns: repeat(2, 1fr);
    gap: 6px;
  }
  .rooms button {
    height: auto;
    min-height: 56px;
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 10px;
    border-radius: 0;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-family: var(--font-body);
    font-weight: 600;
    font-size: min(0.765rem, 23px);
    line-height: 1.2;
    text-align: left;
  }
  .rooms button.on {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .swatch {
    display: flex;
    flex: none;
  }
  .swatch i {
    width: 12px;
    height: 18px;
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
  .fine.bad {
    color: var(--bad);
  }
</style>

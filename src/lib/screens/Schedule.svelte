<script lang="ts">
  import Scene from "../Scene.svelte";
  import WeekGrid from "../WeekGrid.svelte";
  import { buzz } from "../haptics";
  import { app, adopt, openNote, openSubject } from "../state.svelte";
  import { api, clock, isoDate, subjectColor, WEEKDAYS, type Mark, type Meeting, type Snapshot, type Weekday } from "../api";

  const todayIdx = (new Date().getDay() + 6) % 7;
  let day = $state<Weekday>(WEEKDAYS[todayIdx]);
  let picked = $state<Meeting | null>(null);
  let meetings = $state<Meeting[]>([]);
  let hideVacant = $state(stored("hideVacant") === "1");
  let view = $state<"day" | "week">(stored("scheduleView") === "week" ? "week" : "day");
  let moving = $state<{ day: Weekday; start: string; end: string } | null>(null);
  let problem = $state("");
  const colors = $derived(app.snapshot?.colors ?? {});
  const swatches = [1, 2, 3, 4, 5, 6].map((n) => `var(--s${n})`);

  const monday = (() => {
    const d = new Date();
    d.setDate(d.getDate() - todayIdx);
    return d;
  })();
  const dates = WEEKDAYS.map((_, i) => {
    const d = new Date(monday);
    d.setDate(monday.getDate() + i);
    return d;
  });

  // The core applies marks and moves; re-read whenever the snapshot changes.
  $effect(() => {
    void app.snapshot;
    api.week(isoDate(monday)).then((m) => (meetings = m));
  });

  const list = $derived(meetings.filter((m) => m.session.day === day && !(hideVacant && m.mark === "vacant")));
  const busy = $derived(new Set(meetings.filter((m) => m.mark !== "vacant").map((m) => m.session.day)));

  function stored(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  // Swipe left or right across the day list to move a day.
  let swipeFrom: { x: number; y: number } | null = null;
  function swipeStart(e: TouchEvent) {
    swipeFrom = { x: e.touches[0].clientX, y: e.touches[0].clientY };
  }
  function swipeEnd(e: TouchEvent) {
    if (!swipeFrom) return;
    const dx = e.changedTouches[0].clientX - swipeFrom.x;
    const dy = e.changedTouches[0].clientY - swipeFrom.y;
    swipeFrom = null;
    if (Math.abs(dx) < 60 || Math.abs(dy) > Math.abs(dx)) return;
    const i = WEEKDAYS.indexOf(day) + (dx < 0 ? 1 : -1);
    if (i >= 0 && i < WEEKDAYS.length) {
      day = WEEKDAYS[i];
      buzz.select();
    }
  }

  function setView(v: "day" | "week") {
    view = v;
    try {
      localStorage.setItem("scheduleView", v);
    } catch {
      // Remembered for this session only.
    }
  }

  function toggleVacant() {
    hideVacant = !hideVacant;
    try {
      localStorage.setItem("hideVacant", hideVacant ? "1" : "0");
    } catch {
      // Remembered for this session only.
    }
  }

  const hhmm = (min: number) => `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;
  const minutes = (t: string) => {
    const [h, m] = t.split(":").map(Number);
    return h * 60 + m;
  };

  async function run(change: Promise<Snapshot>) {
    try {
      await adopt(await change);
      buzz.tap();
      picked = null;
      moving = null;
      problem = "";
    } catch (e) {
      problem = String(e);
    }
  }

  const mark = (m: Mark, everyWeek: boolean) => picked && run(api.setMark(picked.id, everyWeek ? null : isoDate(monday), m));
  const color = (c: string | null) => picked && run(api.setColor(picked.session.subject_code, c));
  const move = (everyWeek: boolean) =>
    picked &&
    moving &&
    run(api.setMove(picked.id, everyWeek ? null : isoDate(monday), { day: moving.day, start: minutes(moving.start), end: minutes(moving.end) }));
  function unmove() {
    if (!picked) return;
    const id = picked.id;
    run(api.setMove(id, isoDate(monday), null).then(() => api.setMove(id, null, null)));
  }

  function pick(m: Meeting) {
    picked = m;
    moving = null;
    problem = "";
  }
</script>

<div class="screen">
  <header>
    <p class="label">This week</p>
    <h1>Schedule</h1>
  </header>

  <div class="seg" role="tablist" aria-label="View">
    <button role="tab" class:on={view === "day"} aria-selected={view === "day"} onclick={() => setView("day")}>Day</button>
    <button role="tab" class:on={view === "week"} aria-selected={view === "week"} onclick={() => setView("week")}>Week</button>
  </div>

  {#if view === "week"}
    <WeekGrid meetings={meetings.filter((m) => !(hideVacant && m.mark === "vacant"))} {colors} {todayIdx} onpick={pick} />
    <label class="toggle"><input type="checkbox" checked={hideVacant} onchange={toggleVacant} /> Hide vacant classes</label>
  {:else}
  <div class="days" role="tablist">
    {#each WEEKDAYS as d, i (d)}
      <button role="tab" class:on={day === d} class:today={i === todayIdx} aria-selected={day === d} onclick={() => (day = d)}>
        <span>{d.slice(0, 3)}</span>
        <strong class="num">{dates[i].getDate()}</strong>
        <i class:has={busy.has(d)}></i>
      </button>
    {/each}
  </div>

  <label class="toggle"><input type="checkbox" checked={hideVacant} onchange={toggleVacant} /> Hide vacant classes</label>

  <div class="swipe" ontouchstart={swipeStart} ontouchend={swipeEnd} role="presentation">
  {#if list.length === 0}
    <div class="empty card notch">
      <Scene name="hammock" label="A hammock between two palm trees" />
      <p>No classes on {day}.</p>
    </div>
  {:else}
    <ol>
      {#each list as m (m.id)}
        {@const s = m.session}
        <li>
          <button class="class" data-mark={m.mark} style:--c={subjectColor(s.subject_code, colors)} onclick={() => pick(m)}>
            <span class="time num">{clock(s.start)}<small>{clock(s.end)}</small></span>
            <span class="stripe"></span>
            <span class="what">
              <strong>{s.subject_code}</strong>
              <span>{s.description}</span>
              {#if s.faculty}<em>{s.faculty}</em>{/if}
            </span>
            {#if m.mark !== "in_person"}<span class="tag">{m.mark === "online" ? "Online" : "Vacant"}</span>{/if}
            {#if m.moved}<span class="tag">Moved</span>{/if}
            {#if app.notes.some((n) => n.key === `class:${s.subject_code}`)}<span class="dot" aria-label="Has notes"></span>{/if}
          </button>
        </li>
      {/each}
    </ol>
  {/if}
  </div>
  {/if}
</div>

{#if picked}
  {@const s = picked.session}
  <div class="scrim" role="presentation" onclick={() => (picked = null)}></div>
  <div class="sheet notch" role="dialog" aria-label="Edit {s.subject_code}">
    <p class="label">{s.subject_code} · {s.day.slice(0, 3)} {clock(s.start)}–{clock(s.end)}</p>
    {#if moving}
      <h2>Change its time</h2>
      <div class="when">
        <select bind:value={moving.day} aria-label="Day">
          {#each WEEKDAYS as d (d)}<option value={d}>{d}</option>{/each}
        </select>
        <input type="time" bind:value={moving.start} aria-label="Starts" />
        <input type="time" bind:value={moving.end} aria-label="Ends" />
      </div>
      <div class="opts two">
        <button onclick={() => move(false)}>This week only</button>
        <button onclick={() => move(true)}>Every week</button>
      </div>
      <button class="link" onclick={() => (moving = null)}>Back</button>
    {:else}
      <h2>How is this class meeting?</h2>
      <p class="label">This week only</p>
      <div class="opts">
        <button onclick={() => mark("in_person", false)}>In person</button>
        <button onclick={() => mark("online", false)}>Online</button>
        <button onclick={() => mark("vacant", false)}>Vacant</button>
      </div>
      <p class="label">Every week this term</p>
      <div class="opts">
        <button onclick={() => mark("in_person", true)}>In person</button>
        <button onclick={() => mark("online", true)}>Online</button>
        <button onclick={() => mark("vacant", true)}>Vacant</button>
      </div>
      <div class="opts two">
        <button class="note" onclick={() => { const p = picked!; picked = null; openNote(`class:${p.session.subject_code}`, p.session.subject_code, p.session.description); }}>
          {app.notes.some((n) => n.key === `class:${s.subject_code}`) ? "Class notes" : "Write notes"}
        </button>
        <button class="note" onclick={() => { const p = picked!; picked = null; openSubject(p.session.subject_code, p.session.description); }}>Syllabus & grading</button>
      </div>
      <p class="label">Time</p>
      <div class="opts two">
        <button onclick={() => (moving = { day: s.day, start: hhmm(s.start), end: hhmm(s.end) })}>Change its time</button>
        <button disabled={!picked.moved} onclick={unmove}>Back to SIS time</button>
      </div>
      <p class="label">Colour</p>
      <div class="swatches">
        {#each swatches as c (c)}
          <button class="swatch" class:on={colors[s.subject_code] === c} style:background={c} aria-label="Colour {c.slice(8, 10)}" onclick={() => color(c)}></button>
        {/each}
        <button class="auto" class:on={!colors[s.subject_code]} onclick={() => color(null)}>Auto</button>
      </div>
    {/if}
    {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
  </div>
{/if}

<style>
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
  .days {
    display: grid;
    grid-template-columns: repeat(7, 1fr);
    gap: 6px;
  }
  .days button {
    display: grid;
    justify-items: center;
    gap: 2px;
    padding: 8px 0 6px;
    border: 0;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
  }
  .days span {
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
  }
  .days strong {
    font-size: 17px;
    color: var(--ink);
  }
  .days i {
    width: 4px;
    height: 4px;
  }
  .days i.has {
    background: var(--ink-3);
  }
  .days button.today strong {
    color: var(--gold);
  }
  .days button.on {
    background: var(--gold);
    color: var(--on-gold);
  }
  .days button.on strong {
    color: var(--on-gold);
  }
  .days button.on i.has {
    background: var(--on-gold);
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 8px;
  }
  .class {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 14px;
    border: 0;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    text-align: left;
  }
  .class[data-mark="vacant"] {
    opacity: 0.45;
  }
  .class[data-mark="online"] {
    box-shadow: inset 0 0 0 1.5px var(--c);
  }
  .time {
    display: grid;
    width: 64px;
    flex: none;
    font-size: 13px;
    font-weight: 700;
  }
  .time small {
    font-size: 11px;
    font-weight: 500;
    color: var(--ink-3);
  }
  .stripe {
    width: 3px;
    align-self: stretch;
    border-radius: 2px;
    background: var(--c);
  }
  .what {
    display: grid;
    min-width: 0;
    flex: 1;
  }
  .what strong {
    font-family: var(--font-display);
    font-size: 15px;
  }
  .what span {
    font-size: 14px;
    color: var(--ink-2);
  }
  .what em {
    font-style: normal;
    font-size: 12px;
    color: var(--ink-3);
  }
  .tag {
    flex: none;
    padding: 3px 8px;
    font-family: var(--font-pixel);
    font-size: 12px;
    text-transform: uppercase;
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink-2);
  }
  .empty {
    display: grid;
    justify-items: center;
    gap: 8px;
    padding: 24px;
  }
  .empty p {
    margin: 0;
    color: var(--ink-2);
    font-size: 14px;
  }
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
    padding: 18px 16px;
    background: var(--card-2);
    animation: rise 0.35s var(--ease) both;
  }
  .sheet h2 {
    margin: 0 0 4px;
    font-family: var(--font-display);
    font-size: 18px;
  }
  .opts {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 8px;
  }
  .opts button {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-weight: 600;
  }
  .note {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-weight: 700;
  }
  .dot {
    width: 8px;
    height: 8px;
    flex: none;
    background: var(--gold);
  }
  .swipe {
    display: grid;
    min-height: 240px;
    align-content: start;
  }
  .seg {
    display: grid;
    grid-template-columns: 1fr 1fr;
    padding: 3px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .seg button {
    height: 34px;
    border: 0;
    border-radius: 9px;
    background: none;
    color: var(--ink-2);
    font-family: var(--font-display);
    font-weight: 700;
  }
  .seg button.on {
    background: var(--gold);
    color: var(--on-gold);
  }
  .opts.two {
    grid-template-columns: 1fr 1fr;
  }
  .opts button:disabled {
    opacity: 0.4;
  }
  .toggle {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 14px;
    color: var(--ink-2);
  }
  .when {
    display: grid;
    grid-template-columns: 1.4fr 1fr 1fr;
    gap: 8px;
  }
  .when select,
  .when input {
    height: 44px;
    min-width: 0;
    padding: 0 8px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
  }
  .swatches {
    display: flex;
    gap: 8px;
    align-items: center;
  }
  .swatch {
    width: 36px;
    height: 36px;
    border: 0;
    border-radius: 50%;
  }
  .swatch.on {
    box-shadow: 0 0 0 2px var(--card-2), 0 0 0 4px var(--ink);
  }
  .auto {
    height: 36px;
    padding: 0 12px;
    border: 0;
    border-radius: 18px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    font-weight: 600;
  }
  .auto.on {
    box-shadow: inset 0 0 0 2px var(--ink);
  }
  .link {
    justify-self: start;
    padding: 6px 0;
    border: 0;
    background: none;
    color: var(--ink-2);
    text-decoration: underline;
  }
  .problem {
    margin: 0;
    font-size: 13px;
    color: var(--bad, #e0685a);
  }
  @keyframes rise {
    from { transform: translateY(20px); opacity: 0; }
  }
  @keyframes fade {
    from { opacity: 0; }
  }
</style>

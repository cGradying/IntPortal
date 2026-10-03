<script lang="ts">
  import ClassSheet from "../ClassSheet.svelte";
  import Scene from "../Scene.svelte";
  import ErrorCard from "../ErrorCard.svelte";
  import Skeleton from "../Skeleton.svelte";
  import WeekGrid from "../WeekGrid.svelte";
  import { resource } from "../load.svelte";
  import { buzz } from "../haptics";
  import { app } from "../state.svelte";
  import { api, clock, isoDate, subjectColor, WEEKDAYS, type Meeting, type Weekday } from "../api";

  const todayIdx = (new Date().getDay() + 6) % 7;
  let day = $state<Weekday>(WEEKDAYS[todayIdx]);
  let picked = $state<Meeting | null>(null);
  let hideVacant = $state(stored("hideVacant") === "1");
  let view = $state<"day" | "week">(stored("scheduleView") === "week" ? "week" : "day");
  const colors = $derived(app.snapshot?.colors ?? {});

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
  const week = resource(() => api.week(isoDate(monday)));
  const meetings = $derived(week.current.state === "ready" ? week.current.value : []);
  $effect(() => {
    void app.snapshot;
    week.reload();
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
    if (view !== v) buzz.select();
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

  function pick(m: Meeting) {
    picked = m;
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

  {#if week.current.state === "loading"}
    <Skeleton rows={4} height={64} />
  {:else if week.current.state === "failed"}
    <ErrorCard error={week.current.error} onretry={week.reload} />
  {:else if view === "week"}
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

{#if picked}<ClassSheet meeting={picked} onclose={() => (picked = null)} />{/if}

<style>
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
    font-size: min(0.647rem, 20px);
    font-weight: 600;
    text-transform: uppercase;
  }
  .days strong {
    font-size: min(1rem, 31px);
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
    font-size: min(0.765rem, 23px);
    font-weight: 700;
  }
  .time small {
    font-size: min(0.647rem, 20px);
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
    font-size: min(0.882rem, 27px);
  }
  .what span {
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .what em {
    font-style: normal;
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .tag {
    flex: none;
    padding: 3px 8px;
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
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
    font-size: min(0.824rem, 25px);
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
  .toggle {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  @keyframes rise {
    from { transform: translateY(20px); opacity: 0; }
  }
  @keyframes fade {
    from { opacity: 0; }
  }
</style>

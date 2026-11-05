<script lang="ts">
  import Synced from "../Synced.svelte";
  import ClassSheet from "../ClassSheet.svelte";
  import Scene from "../Scene.svelte";
  import ErrorCard from "../ErrorCard.svelte";
  import Skeleton from "../Skeleton.svelte";
  import WeekGrid from "../WeekGrid.svelte";
  import { resource } from "../load.svelte";
  import { busyFrom } from "../devcal";
  import { weekSpans, type Span } from "../dayrows";
  import { buzz } from "../haptics";
  import { app } from "../state.svelte";
  import { api, clock, isoDate, moment, span, subjectColor, WEEKDAYS, type DeadlineEntry, type Meeting, type Weekday } from "../api";
  import { gapText, gaps, month, movedFrom, phaseOf, pin, stampOf } from "../weekModel";

  const todayIdx = (new Date().getDay() + 6) % 7;
  let day = $state<Weekday>(WEEKDAYS[todayIdx]);
  let picked = $state<Meeting | null>(null);
  let pickedFrom = $state<DOMRect>();
  let hideVacant = $state(stored("hideVacant") === "1");
  let view = $state<"day" | "week">(stored("scheduleView") === "week" ? "week" : "day");
  const colors = $derived(app.snapshot?.colors ?? {});

  // Spec 040 C13: weeks before and after this one; 0 is this week.
  let offset = $state(0);
  const monday = $derived.by(() => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - todayIdx + offset * 7);
    return d;
  });
  const dates = $derived(
    WEEKDAYS.map((_, i) => {
      const d = new Date(monday);
      d.setDate(monday.getDate() + i);
      return d;
    }),
  );
  const weekLabel = $derived(
    offset === 0 ? "This week" : offset === 1 ? "Next week" : offset === -1 ? "Last week" : `Week of ${monday.toLocaleDateString(undefined, { month: "short", day: "numeric" })}`,
  );

  // The core applies marks and moves; re-read whenever the snapshot changes.
  const week = resource(() => api.week(isoDate(monday)));
  const meetings = $derived(week.current.state === "ready" ? week.current.value : []);
  $effect(() => {
    void app.snapshot;
    void monday;
    week.reload();
  });

  // The student's own events for this week, when they asked to see them.
  let spans = $state<Span[]>([]);
  $effect(() => {
    if (!app.calendarEvents) return void (spans = []);
    busyFrom(monday, 7)
      .then((b) => (spans = weekSpans(b, isoDate(monday))))
      .catch(() => (spans = []));
  });

  const list = $derived(meetings.filter((m) => m.session.day === day && !(hideVacant && m.mark === "vacant")));

  // The clock, for what's finished and what's in progress (spec 044 C7, C9).
  let nowDate = $state(new Date());
  $effect(() => {
    const t = setInterval(() => (nowDate = new Date()), 30_000);
    return () => clearInterval(t);
  });
  const nowMin = $derived(nowDate.getHours() * 60 + nowDate.getMinutes());
  const onToday = $derived(offset === 0 && WEEKDAYS.indexOf(day) === todayIdx);

  // One row per class, with free time folded between them and moved classes' old places.
  type DayRow = { kind: "class"; at: number; m: Meeting } | { kind: "gap"; at: number; text: string; now: boolean } | { kind: "moved"; at: number; text: string; code: string };
  const dayRows = $derived.by(() => {
    const rows: DayRow[] = list.map((m) => ({ kind: "class", at: m.session.start, m }));
    for (const g of gaps(list.filter((m) => m.mark !== "vacant").map((m) => m.session), 30)) {
      rows.push({ kind: "gap", at: g.start + 0.5, text: gapText(g, onToday, nowMin), now: onToday && g.start <= nowMin && nowMin < g.end });
    }
    for (const m of meetings) {
      const from = movedFrom(m, app.snapshot?.sessions ?? []);
      if (from?.day === day) rows.push({ kind: "moved", at: from.start, code: m.session.subject_code, text: `${clock(from.start)} · ${m.session.description || m.session.subject_code} moved to ${m.session.day.slice(0, 3)} ${clock(m.session.start)}` });
    }
    return rows.sort((a, b) => a.at - b.at);
  });

  // The next four weeks' deadlines, for the pixel month and the pins under each day (C11).
  let deadlines = $state<DeadlineEntry[]>([]);
  $effect(() => {
    void app.snapshot;
    api.deadlines(moment(), 28).then((d) => (deadlines = d)).catch(() => (deadlines = []));
  });
  const thisMonday = $derived.by(() => {
    const d = new Date();
    d.setHours(0, 0, 0, 0);
    d.setDate(d.getDate() - todayIdx);
    return d;
  });
  const cells = $derived(month(deadlines, thisMonday, isoDate(new Date())));
  const dateKeys = $derived(dates.map(isoDate));
  const busy = $derived(new Set(meetings.filter((m) => m.mark !== "vacant").map((m) => m.session.day)));

  function stored(key: string): string | null {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  }

  // The list follows the finger across days. Past 60 px or a quick flick it springs
  // on to the next day; otherwise it springs back (spec 044 C9a).
  const SPRING = "cubic-bezier(0.34, 1.3, 0.64, 1)";
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let swipeEl = $state<HTMLElement>();
  let swipeFrom: { x: number; y: number; t: number; sideways: boolean | null } | null = null;
  function swipeStart(e: TouchEvent) {
    swipeFrom = { x: e.touches[0].clientX, y: e.touches[0].clientY, t: performance.now(), sideways: null };
  }
  function swipeMove(e: TouchEvent) {
    if (!swipeFrom || !swipeEl || still) return;
    const dx = e.touches[0].clientX - swipeFrom.x;
    const dy = e.touches[0].clientY - swipeFrom.y;
    swipeFrom.sideways ??= Math.hypot(dx, dy) > 8 ? Math.abs(dx) > Math.abs(dy) : null;
    if (swipeFrom.sideways) swipeEl.style.transform = `translateX(${dx}px)`;
  }
  function swipeEnd(e: TouchEvent) {
    if (!swipeFrom) return;
    const { x, y, t, sideways } = swipeFrom;
    const dx = e.changedTouches[0].clientX - x;
    const dy = e.changedTouches[0].clientY - y;
    swipeFrom = null;
    const el = swipeEl;
    const flick = Math.abs(dx) / Math.max(1, performance.now() - t) > 0.5;
    const i = WEEKDAYS.indexOf(day) + (dx < 0 ? 1 : -1);
    const go = sideways !== false && (Math.abs(dx) >= 60 || flick) && Math.abs(dx) > Math.abs(dy) && i >= 0 && i < WEEKDAYS.length;
    if (el) el.style.transform = "";
    if (go) {
      day = WEEKDAYS[i];
      buzz.select();
    }
    if (!el || still || !dx) return;
    const from = go ? -Math.sign(dx) * Math.min(el.offsetWidth, 120) : dx;
    el.animate([{ transform: `translateX(${from}px)` }, { transform: "translateX(0)" }], { duration: 320, easing: SPRING });
  }
  function changeWeek(dir: -1 | 1) {
    offset += dir;
    buzz.select();
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

  function pick(m: Meeting, rect?: DOMRect) {
    picked = m;
    pickedFrom = rect;
  }
</script>

<div class="screen">
  <header>
    <div class="weeks">
      <button class="nav" onclick={() => offset--} aria-label="Previous week">‹</button>
      <p class="label">{weekLabel}</p>
      <button class="nav" onclick={() => offset++} aria-label="Next week">›</button>
      {#if offset !== 0}<button class="nav this" onclick={() => (offset = 0)}>This week</button>{/if}
    </div>
    <div class="title">
      <h1>Schedule</h1>
      <div class="mm" role="img" aria-label="Deadlines over the next four weeks: {cells.filter((c) => c.due).length} days with something due, {cells.filter((c) => c.over).length} overdue">
        <span>Due · 4 wk</span>
        <div>{#each cells as c (c.date)}<i class:due={c.due} class:over={c.over} class:today={c.today} class:wk={c.thisWeek}></i>{/each}</div>
      </div>
    </div>
    <Synced />
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
    <WeekGrid meetings={meetings.filter((m) => !(hideVacant && m.mark === "vacant"))} {colors} todayIdx={offset === 0 ? todayIdx : -1} {spans} onpick={pick} onswipe={changeWeek} dates={dateKeys} {deadlines} />
    <label class="toggle"><input type="checkbox" checked={hideVacant} onchange={toggleVacant} /> Hide vacant classes</label>
  {:else}
  <div class="days" role="tablist">
    {#each WEEKDAYS as d, i (d)}
      <button role="tab" class:on={day === d} class:today={offset === 0 && i === todayIdx} aria-selected={day === d} onclick={() => (day = d)}>
        <span>{d.slice(0, 3)}</span>
        <strong class="num">{dates[i].getDate()}</strong>
        <i class:has={busy.has(d)} class:due={pin(deadlines, dateKeys[i]) === "due"} class:over={pin(deadlines, dateKeys[i]) === "over"}></i>
      </button>
    {/each}
  </div>

  <label class="toggle"><input type="checkbox" checked={hideVacant} onchange={toggleVacant} /> Hide vacant classes</label>

  <div class="swipe" bind:this={swipeEl} ontouchstart={swipeStart} ontouchmove={swipeMove} ontouchend={swipeEnd} role="presentation">
  {#if list.length === 0 && !dayRows.length}
    <div class="empty card notch">
      <Scene name="hammock" label="A hammock between two palm trees" />
      <p>No classes on {day}. Pahinga muna.</p>
    </div>
  {:else}
    <ol>
      {#each dayRows as r (r.kind === "class" ? r.m.id : `${r.kind}${r.at}`)}
        {#if r.kind === "gap"}
          <li class="band" class:on={r.now}><span>{r.text}</span></li>
        {:else if r.kind === "moved"}
          <li class="wasat" style:--c={subjectColor(r.code, colors)}>{r.text}</li>
        {:else}
          {@const m = r.m}
          {@const s = m.session}
          {@const stamp = stampOf(m.mark, m.moved)}
          {@const phase = phaseOf(s, onToday, nowMin)}
          <li>
            <button class="class {phase}" data-mark={m.mark} style:--c={subjectColor(s.subject_code, colors)} style:min-height="{Math.round(58 + Math.max(0, s.end - s.start - 60) * 0.2)}px" onclick={(e) => pick(m, e.currentTarget.getBoundingClientRect())}>
              <span class="time num">{clock(s.start)}<small>{clock(s.end)}</small></span>
              <span class="stripe"></span>
              <span class="what">
                <strong>{s.subject_code}</strong>
                <span>{s.description}</span>
                {#if s.faculty || phase === "now"}<em>{s.faculty}{phase === "now" ? `${s.faculty ? " · " : ""}${span(s.end - nowMin)} left` : ""}</em>{/if}
              </span>
              {#if stamp}<span class="stampy {stamp.kind}">{stamp.text}</span>{/if}
              {#if app.notes.some((n) => n.key === `class:${s.subject_code}`)}<span class="dot" aria-label="Has notes"></span>{/if}
              {#if phase === "now"}<i class="progress" style:--k={(nowMin - s.start) / (s.end - s.start)}></i>{/if}
            </button>
          </li>
        {/if}
      {/each}
    </ol>
  {/if}
  </div>
  {/if}
</div>

{#if picked}<ClassSheet meeting={picked} from={pickedFrom} onclose={() => (picked = null)} />{/if}

<style>
  .screen {
    display: grid;
    gap: 14px;
  }
  h1 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: min(1.647rem, 36px);
    font-weight: var(--title-weight);
    letter-spacing: var(--title-track);
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
    font-family: var(--font-label);
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
  .days i.due {
    background: var(--gold);
  }
  .days i.over {
    background: var(--bad);
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
  .days button.on i.has,
  .days button.on i.due {
    background: var(--on-gold);
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
  }
  /* Tall enough for all its details, with stepped corners (spec 044 C9). */
  .class {
    position: relative;
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 10px 12px;
    border: 0;
    background: linear-gradient(var(--card-2), var(--card));
    box-shadow: inset 0 0 0 1px var(--edge), inset 0 -2px 0 rgb(0 0 0 / 0.1);
    text-align: left;
    overflow: hidden;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  /* A finished class loses its colour, not its text (C7). */
  .class.past {
    background: var(--sunk);
  }
  .class.past .stripe {
    background: color-mix(in srgb, var(--c) 35%, var(--sunk));
  }
  .class.past strong,
  .class.past .what span,
  .class.past .time {
    color: var(--ink-2);
  }
  .class.now {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .progress {
    position: absolute;
    left: 2px;
    bottom: 2px;
    height: 3px;
    width: calc((100% - 4px) * var(--k));
    background: var(--gold);
  }
  .class[data-mark="vacant"] {
    background: repeating-linear-gradient(45deg, var(--card) 0 3px, var(--sunk) 3px 6px);
  }
  .band {
    display: grid;
    place-items: center;
    min-height: 26px;
    border: 1px dashed var(--edge-2);
    font-size: min(0.706rem, 22px);
    font-weight: 600;
    color: var(--ink-2);
  }
  .band.on {
    border: 1px solid var(--gold);
    color: var(--gold);
  }
  .wasat {
    padding: 6px 12px;
    outline: 1px dashed var(--c);
    outline-offset: -1px;
    font-size: min(0.706rem, 22px);
    color: var(--ink-2);
  }
  .stampy {
    flex: none;
    align-self: flex-start;
    padding: 2px 4px;
    rotate: -6deg;
    font: 700 min(0.588rem, 18px) / 1.2 var(--font-pixel);
    letter-spacing: 0.04em;
    background: var(--stamp-paper);
  }
  .stampy.online {
    color: var(--stamp-online);
    box-shadow: inset 0 0 0 1px var(--stamp-online);
  }
  .stampy.vacant {
    color: var(--stamp-vacant);
    box-shadow: inset 0 0 0 1px var(--stamp-vacant);
  }
  .stampy.moved {
    color: var(--stamp-moved);
    outline: 1px dashed var(--stamp-moved);
    outline-offset: -1px;
  }
  .title {
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 12px;
  }
  /* The next four weeks in pixels, beside the title (C11). */
  .mm {
    display: grid;
    gap: 3px;
    justify-items: end;
  }
  .mm span {
    font-family: var(--font-label, var(--font-pixel));
    font-size: min(0.53rem, 16px);
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--ink-3);
  }
  .mm div {
    display: grid;
    grid-template-columns: repeat(7, 6px);
    gap: 2px;
  }
  .mm i {
    width: 6px;
    height: 6px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .mm i.wk {
    background: color-mix(in srgb, var(--ink) 16%, var(--sunk));
  }
  .mm i.due {
    background: var(--gold);
    box-shadow: none;
  }
  .mm i.over {
    background: var(--bad);
    box-shadow: none;
  }
  .mm i.today {
    outline: 1px solid var(--ink);
    outline-offset: 1px;
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
  .weeks {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .nav {
    min-width: 44px;
    min-height: 44px;
    padding: 0 8px;
    border: 0;
    background: none;
    color: var(--ink-2);
    font-size: 1.1rem;
  }
  .nav.this {
    margin-left: auto;
    font-size: min(0.765rem, 23px);
    font-weight: 700;
    color: var(--gold);
  }
</style>

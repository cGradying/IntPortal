<script lang="ts">
  // The week (spec 044): stepped blocks on an hour rail. Days with nothing on
  // them stay as thin ghosts, so a moved class lands where it is expected. Tap a
  // day and it opens wide with the details; any move lets it go back to even
  // (C13). The student's own events sit hatched behind the classes.
  import { clock, subjectColor, WEEKDAYS, type ClassSession, type DeadlineEntry, type Meeting } from "./api";
  import type { Span } from "./dayrows";
  import { buzz } from "./haptics";
  import { blockLines, columns, dragLetsGo, gaps, movedFrom, onColor, phaseOf, pin, stampOf, toggleOpen } from "./weekModel";
  import { span as spanText } from "./api";
  import { app } from "./state.svelte";

  let {
    meetings,
    colors,
    todayIdx,
    onpick,
    onswipe,
    spans = [],
    dates = [],
    deadlines = [],
  }: {
    meetings: Meeting[];
    colors: Record<string, string>;
    todayIdx: number;
    onpick: (m: Meeting, from: DOMRect) => void;
    /** A sideways swipe changes the week: -1 back, 1 on (C10). */
    onswipe?: (dir: -1 | 1) => void;
    spans?: Span[];
    /** Each weekday's date, Monday first, as yyyy-mm-dd. */
    dates?: string[];
    deadlines?: DeadlineEntry[];
  } = $props();

  const HOUR = 44;
  const OPEN = 5.5;
  const SEEN_KEY = "intportal.week.seen";
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const term = $derived(app.snapshot?.sessions ?? []);
  const ghosts = $derived(meetings.map((m) => ({ m, from: movedFrom(m, term) })).filter((g): g is { m: Meeting; from: ClassSession } => !!g.from));
  const days = $derived(columns(meetings, spans.map((s) => s.day), todayIdx, ghosts.map((g) => g.from)));
  const first = $derived(Math.floor(Math.min(7 * 60, ...meetings.map((m) => m.session.start), ...spans.map((s) => s.start)) / 60));
  const last = $derived(Math.ceil(Math.max(17 * 60, ...meetings.map((m) => m.session.end), ...spans.map((s) => s.end)) / 60));
  const hours = $derived(Array.from({ length: last - first }, (_, k) => first + k));
  const y = (min: number) => ((min - first * 60) / 60) * HOUR;

  // The now-line glides: a small step each second, smoothed by CSS (C8). Reduce Motion: each minute.
  let now = $state(new Date());
  $effect(() => {
    const t = setInterval(() => (now = new Date()), reduce ? 60_000 : 1000);
    return () => clearInterval(t);
  });
  const nowMin = $derived(now.getHours() * 60 + now.getMinutes() + now.getSeconds() / 60);
  const label = (h: number) => `${h % 12 || 12}${h < 12 ? "a" : "p"}`;

  // One open day at a time; every other full day shrinks to colour.
  let open = $state(-1);
  const track = (full: boolean, i: number) => (!full ? "7px" : i === open ? `minmax(0, ${OPEN}fr)` : "minmax(0, 1fr)");
  const template = $derived(`28px ${days.map((d) => track(d.full, d.index)).join(" ")}`);

  let start: { x: number; y: number } | null = null;
  let moved = false;
  function down(e: PointerEvent) {
    start = { x: e.clientX, y: e.clientY };
    moved = false;
  }
  function move(e: PointerEvent) {
    if (!start || moved || !dragLetsGo(e.clientX - start.x, e.clientY - start.y)) return;
    moved = true;
    open = -1;
  }
  function up(e: PointerEvent) {
    if (start && moved && Math.abs(e.clientX - start.x) > 60 && Math.abs(e.clientX - start.x) > Math.abs(e.clientY - start.y)) onswipe?.(e.clientX < start.x ? 1 : -1);
    start = null;
  }
  $effect(() => {
    const close = () => (open = -1);
    addEventListener("scroll", close, { passive: true });
    return () => removeEventListener("scroll", close);
  });
  function tapDay(i: number) {
    if (moved) return;
    buzz.select();
    open = toggleOpen(open, i);
  }
  // In the open day a class opens its sheet; elsewhere the tap opens the day (C13).
  function tapBlock(e: Event, m: Meeting, i: number) {
    if (moved) return;
    e.stopPropagation();
    if (i === open) onpick(m, (e.currentTarget as HTMLElement).getBoundingClientRect());
    else tapDay(i);
  }

  // A stamp new to this phone lands with a thunk, once (C5).
  function seenBefore(): Set<string> {
    try {
      return new Set(JSON.parse(localStorage.getItem(SEEN_KEY) ?? "[]"));
    } catch {
      return new Set();
    }
  }
  const seen = seenBefore();
  const stampId = (m: Meeting) => `${m.id}:${m.date}:${m.mark}:${m.moved}`;
  $effect(() => {
    const all = new Set([...seen, ...meetings.filter((m) => stampOf(m.mark, m.moved)).map(stampId)]);
    try {
      localStorage.setItem(SEEN_KEY, JSON.stringify([...all].slice(-200)));
    } catch {
      // They may land again next time. Harmless.
    }
  });
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div class="grid" onpointerdown={down} onpointermove={move} onpointerup={up} onpointercancel={up}>
  <div class="head" style:grid-template-columns={template}>
    <span></span>
    {#each days as { day, index, full } (day)}
      {#if full}
        {@const p = dates[index] ? pin(deadlines, dates[index]) : null}
        <button class="dh" class:today={index === todayIdx} class:open={index === open} aria-pressed={index === open} aria-label="{day}{p === 'over' ? ', overdue deadline' : p ? ', deadline due' : ''}" onclick={() => tapDay(index)}>
          <span>{day.slice(0, 3)}</span><i class="pin {p ?? ''}"></i>
        </button>
      {:else}<span></span>{/if}
    {/each}
  </div>
  <div class="body" class:opened={open >= 0} style:grid-template-columns={template} style:height="{hours.length * HOUR}px" style:--hour="{HOUR}px">
    <div class="hours">
      {#each hours as h (h)}<span style:top="{y(h * 60)}px">{label(h)}</span>{/each}
    </div>
    {#each days as { day, index, full } (day)}
      {#if !full}
        <div class="col ghost" title="{day}: no classes"></div>
      {:else}
        {@const list = meetings.filter((m) => m.session.day === day)}
        <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
        <div class="col" class:today={index === todayIdx} class:open={index === open} onclick={() => tapDay(index)}>
          {#each spans.filter((s) => s.day === index) as s, k (k)}
            <span class="busy" style:top="{y(s.start)}px" style:height="{Math.max(10, y(s.end) - y(s.start) - 2)}px" title={s.title}>{s.title}</span>
          {/each}
          {#each ghosts.filter((g) => g.from.day === day) as g (g.m.id)}
            <span class="ghosted" style:top="{y(g.from.start)}px" style:height="{y(g.from.end) - y(g.from.start) - 2}px" style:--c={subjectColor(g.m.session.subject_code, colors)}>moved</span>
          {/each}
          {#each gaps(list.map((m) => m.session), 45) as g (g.start)}
            <span class="free" style:top="{y(g.start) + 2}px" style:height="{y(g.end) - y(g.start) - 4}px"><b>{spanText(g.end - g.start)} free</b></span>
          {/each}
          {#each list as m (m.id)}
            {@const c = subjectColor(m.session.subject_code, colors)}
            {@const stamp = stampOf(m.mark, m.moved)}
            {@const phase = phaseOf(m.session, index === todayIdx, nowMin)}
            {@const h = y(m.session.end) - y(m.session.start) - 2}
            {@const lines = blockLines(m.session, index === open)}
            {@const thunk = !!stamp && !reduce && !seen.has(stampId(m))}
            <button
              class="block {phase}"
              class:short={h < 64}
              class:jolt={thunk}
              data-mark={m.mark}
              style:top="{y(m.session.start)}px"
              style:height="{Math.max(18, h)}px"
              style:--c={c}
              style:--on={onColor(c)}
              onclick={(e) => tapBlock(e, m, index)}
              aria-label="{m.session.subject_code}, {m.session.description}, {clock(m.session.start)} to {clock(m.session.end)}{m.session.faculty ? `, ${m.session.faculty}` : ''}{stamp ? `, ${stamp.text.toLowerCase()}` : ''}"
            >
              {#if stamp}<span class="stamp {stamp.kind}" class:fresh={thunk}>{stamp.text}</span>{/if}
              {#if lines.code}<small class="code">{lines.code}</small>{/if}
              <strong>{lines.title}</strong>
              {#if lines.meta}<small class="meta"><span>{lines.meta}</span></small>{/if}
            </button>
          {/each}
        </div>
      {/if}
    {/each}
    {#if todayIdx >= 0 && nowMin >= first * 60 && nowMin <= last * 60}
      <i class="now" style:transform="translateY({y(nowMin)}px)"><b>{clock(Math.floor(nowMin))}</b></i>
    {/if}
  </div>
</div>

<style>
  .grid {
    display: grid;
    gap: 4px;
    touch-action: pan-y;
  }
  .head,
  .body {
    display: grid;
    gap: 2px;
    transition: grid-template-columns 0.36s var(--ease);
  }
  .body {
    position: relative;
  }
  .dh {
    display: grid;
    justify-items: center;
    gap: 2px;
    min-width: 0;
    min-height: 32px;
    padding: 2px 0;
    border: 0;
    background: none;
    color: var(--ink-3);
    font-family: var(--font-label, var(--font-pixel));
    font-size: min(0.647rem, 20px);
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    overflow: hidden;
  }
  .dh.today {
    color: var(--gold);
  }
  .dh.open {
    background: var(--gold-soft);
  }
  .pin {
    width: 5px;
    height: 5px;
  }
  .pin.due {
    background: var(--gold);
  }
  .pin.over {
    background: var(--bad);
  }
  .hours,
  .col {
    position: relative;
  }
  .hours span {
    position: absolute;
    right: 3px;
    transform: translateY(-50%);
    font-family: var(--font-ui);
    font-size: min(0.588rem, 18px);
    font-weight: 600;
    color: var(--ink-3);
  }
  .col {
    min-width: 0;
    background: repeating-linear-gradient(var(--edge) 0 1px, transparent 1px var(--hour));
  }
  .col.today {
    background-color: var(--gold-soft);
  }
  .col.ghost {
    opacity: 0.7;
    background: repeating-linear-gradient(45deg, transparent 0 3px, var(--edge) 3px 4px);
  }
  /* Stepped corners, a lit top edge and a shaded foot: a tile, not a rounded chip (C1). */
  .block {
    position: absolute;
    z-index: 1;
    left: 1px;
    right: 1px;
    display: flex;
    flex-direction: column;
    gap: 1px;
    padding: 4px;
    overflow: hidden;
    border: 0;
    background: var(--c);
    color: var(--on);
    text-align: left;
    box-shadow: inset 0 1px 0 rgb(255 255 255 / 0.22), inset 0 -2px 0 rgb(0 0 0 / 0.22);
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% calc(100% - 2px), calc(100% - 2px) calc(100% - 2px), calc(100% - 2px) 100%, 2px 100%, 2px calc(100% - 2px), 0 calc(100% - 2px));
  }
  .block strong {
    font-family: var(--font-display);
    font-size: min(0.647rem, 20px);
    font-weight: 700;
    letter-spacing: -0.02em;
    line-height: 1.12;
    display: -webkit-box;
    -webkit-box-orient: vertical;
    -webkit-line-clamp: 4;
    line-clamp: 4;
    overflow: hidden;
  }
  .block.short strong {
    -webkit-line-clamp: 3;
    line-clamp: 3;
  }
  .code,
  .meta {
    display: none;
    font-family: var(--font-ui);
    font-size: min(0.588rem, 18px);
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
  }
  /* A finished class loses its colour, not its text (C7). */
  .block.past {
    background: color-mix(in srgb, var(--c) 42%, var(--ground));
    color: var(--ink);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .block.now {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  .block[data-mark="vacant"] {
    background: repeating-linear-gradient(45deg, color-mix(in srgb, var(--c) 34%, var(--ground)) 0 3px, color-mix(in srgb, var(--c) 18%, var(--ground)) 3px 6px);
    color: var(--ink);
  }
  .stamp {
    flex: none;
    align-self: flex-start;
    padding: 1px 2px;
    rotate: -6deg;
    font: 700 min(0.47rem, 14px) / 1.2 var(--font-pixel);
    letter-spacing: 0.04em;
    background: var(--stamp-paper);
  }
  .stamp.online {
    color: var(--stamp-online);
    box-shadow: inset 0 0 0 1px var(--stamp-online);
  }
  .stamp.vacant {
    color: var(--stamp-vacant);
    box-shadow: inset 0 0 0 1px var(--stamp-vacant);
  }
  .stamp.moved {
    color: var(--stamp-moved);
    outline: 1px dashed var(--stamp-moved);
    outline-offset: -1px;
  }
  /* C5: the block gives a 2 px shake as its stamp lands. Not drawn under Reduce Motion (jolt is off). */
  .block.jolt {
    animation: jolt var(--t-move) ease-out both;
    /* As the stamp lands: its 0.2 s wait plus its drop. */
    animation-delay: calc(0.2s + var(--t-hero));
  }
  @keyframes jolt {
    25% { translate: 2px 0; }
    50% { translate: -2px 0; }
    75% { translate: 1px 0; }
  }
  .stamp.fresh {
    animation: thunk 0.55s var(--ease) both 0.2s;
  }
  @keyframes thunk {
    0% { scale: 2.2; opacity: 0; }
    55% { scale: 0.92; opacity: 1; }
    80% { scale: 1.04; }
    100% { scale: 1; opacity: 1; }
  }
  /* A day is open: it shows everything, and the rest keep only their colour. */
  .block > * {
    transition: opacity 0.18s 0.2s;
  }
  .opened .col:not(.open) .block > * {
    opacity: 0;
    transition: opacity 0.1s;
  }
  .opened .col:not(.open) .stamp {
    visibility: hidden;
  }
  .col.open .block {
    padding: 4px 6px;
  }
  .col.open .block strong {
    font-size: min(0.765rem, 23px);
    letter-spacing: -0.01em;
    -webkit-line-clamp: 2;
    line-clamp: 2;
  }
  .col.open .block.short strong {
    -webkit-line-clamp: 1;
    line-clamp: 1;
  }
  .col.open .code {
    display: block;
    opacity: 0.9;
  }
  .col.open .meta {
    display: flex;
    gap: 6px;
    margin-top: auto;
  }
  .col.open .stamp {
    position: absolute;
    right: 4px;
    top: 4px;
  }
  .meta span {
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .free {
    position: absolute;
    left: 3px;
    right: 3px;
    display: grid;
    place-items: center;
    border: 1px dashed var(--edge-2);
    opacity: 0;
    pointer-events: none;
    transition: opacity 0.1s;
  }
  .col.open .free {
    opacity: 1;
    transition: opacity 0.2s 0.22s;
  }
  .free b {
    padding: 1px 4px;
    font-family: var(--font-ui);
    font-size: min(0.588rem, 18px);
    font-weight: 600;
    white-space: nowrap;
    color: var(--ink-2);
    background: var(--ground);
  }
  .busy {
    position: absolute;
    left: 1px;
    right: 1px;
    overflow: hidden;
    padding: 2px 3px 0;
    background: repeating-linear-gradient(135deg, var(--card) 0 4px, var(--sunk) 4px 6px);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-3);
    font-size: min(0.529rem, 16px);
    line-height: 1.15;
    pointer-events: none;
  }
  .ghosted {
    position: absolute;
    left: 2px;
    right: 2px;
    padding: 3px;
    overflow: hidden;
    outline: 1px dashed var(--c);
    outline-offset: -1px;
    font-family: var(--font-ui);
    font-size: min(0.588rem, 18px);
    font-weight: 600;
    color: var(--ink-2);
    pointer-events: none;
  }
  /* Behind the blocks, so it never crosses a class's text (C8). */
  .now {
    position: absolute;
    z-index: 0;
    top: 0;
    left: 28px;
    right: 0;
    height: 2px;
    background: var(--gold);
    pointer-events: none;
    transition: transform 1s linear;
  }
  .now b {
    position: absolute;
    right: 100%;
    top: 50%;
    translate: 0 -50%;
    padding: 2px;
    font-family: var(--font-ui);
    font-size: min(0.529rem, 16px);
    font-weight: 700;
    line-height: 1;
    white-space: nowrap;
    color: var(--on-gold);
    background: var(--gold);
  }
</style>

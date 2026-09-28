<script lang="ts">
  import CampusStrip from "../CampusStrip.svelte";
  import Scene from "../Scene.svelte";
  import { app, openNote, openSubject } from "../state.svelte";
  import { api, clock, isoDate, span, subjectColor, type SyllabusItem } from "../api";

  // Re-read the clock whenever the minute ticker refreshes today.
  const now = $derived((app.today, new Date()));
  const greeting = $derived.by(() => {
    const h = now.getHours();
    return h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
  });
  const dateLine = $derived(now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" }));
  const t = $derived(app.today);
  const next = $derived(t?.next ?? null);
  const items = $derived(t?.agenda.items ?? []);
  const colors = $derived(app.snapshot?.colors ?? {});
  const dayKey = $derived(`day:${isoDate(now)}`);

  // Quizzes, exams and projects due this week, from the syllabus pages.
  let due = $state<[string, SyllabusItem][]>([]);
  $effect(() => {
    void app.snapshot;
    api.due(isoDate(new Date()), 7).then((d) => (due = d)).catch(() => {});
  });
  const dueDay = (d: string | null) => {
    if (!d) return "";
    const days = Math.round((new Date(`${d}T00:00`).getTime() - new Date(isoDate(new Date()) + "T00:00").getTime()) / 86_400_000);
    return days === 0 ? "Today" : days === 1 ? "Tomorrow" : new Date(`${d}T00:00`).toLocaleDateString(undefined, { weekday: "short" });
  };
  const describe = (code: string) => app.snapshot?.sessions.find((x) => x.subject_code === code)?.description ?? "";
  const dayNote = $derived(app.notes.find((n) => n.key === dayKey));

  /** Big number and its unit for the hero countdown. */
  const hero = $derived.by(() => {
    if (!next) return null;
    if (next.is_now) {
      const left = next.session.end - (now.getHours() * 60 + now.getMinutes());
      return { big: span(Math.max(0, left)), unit: "left in class" };
    }
    if (next.minutes_away < 60) return { big: String(next.minutes_away), unit: next.minutes_away === 1 ? "minute" : "minutes" };
    const today = t?.countdown?.startsWith("at");
    return { big: clock(next.session.start), unit: today ? `in ${span(next.minutes_away)}` : (t?.countdown ?? "").split(" ")[0] };
  });

  const progress = $derived.by(() => {
    if (!next?.is_now) return 0;
    const m = now.getHours() * 60 + now.getMinutes();
    return (m - next.session.start) / (next.session.end - next.session.start);
  });

  /** Classes with the free stretches between them. */
  const rows = $derived.by(() => {
    const out: ({ kind: "class"; i: (typeof items)[number] } | { kind: "gap"; minutes: number; past: boolean })[] = [];
    items.forEach((i, k) => {
      if (k > 0) {
        const gap = i.session.start - items[k - 1].session.end;
        if (gap >= 15) out.push({ kind: "gap", minutes: gap, past: items[k - 1].phase === "past" && i.phase === "past" });
      }
      out.push({ kind: "class", i });
    });
    return out;
  });
</script>

<div class="screen">
  <header>
    <p class="label">{dateLine}</p>
    <h1>{greeting}</h1>
    <button class="daynote" onclick={() => openNote(dayKey, dateLine)}>{dayNote ? dayNote.preview || "Today's note" : "+ Note for today"}</button>
  </header>

  <section class="hero card notch">
    <CampusStrip litKey={next?.session.subject_code ?? ""} />
    <div class="up">
      {#if next && hero}
        <div class="who">
          <p class="label">{next.is_now ? "In session" : "Up next"}</p>
          <h2 style:color={subjectColor(next.session.subject_code, colors)}>{next.session.subject_code}</h2>
          <p class="desc">{next.session.description}</p>
          <p class="meta">{clock(next.session.start)}–{clock(next.session.end)}{next.session.faculty ? ` · ${next.session.faculty}` : ""}</p>
        </div>
        <div class="count">
          <span class="big num">{hero.big}</span>
          <span class="unit">{hero.unit}</span>
        </div>
      {:else}
        <div class="who">
          <p class="label">Up next</p>
          <h2>Nothing scheduled</h2>
          <p class="desc">Sync to pull your classes from the SIS.</p>
        </div>
      {/if}
    </div>
    {#if next?.is_now}
      <div class="bar" aria-hidden="true"><span style:width="{progress * 100}%"></span></div>
    {/if}
  </section>

  {#if due.length}
    <section class="due card notch">
      <p class="label">Coming up this week</p>
      <ul>
        {#each due as [code, it] (code + it.id)}
          <li>
            <button onclick={() => openSubject(code, describe(code))}>
              <span class="when">{dueDay(it.date)}</span>
              <span class="what"><strong>{it.topic}</strong><small>{code} · {it.kind}</small></span>
            </button>
          </li>
        {/each}
      </ul>
    </section>
  {/if}

  <section class="day">
    <div class="head">
      <p class="label">Today</p>
      {#if t && t.agenda.free_minutes_left > 0}
        <p class="free num">{span(t.agenda.free_minutes_left)} free ahead</p>
      {/if}
    </div>

    {#if items.length === 0}
      <div class="empty card notch">
        <Scene name="hammock" label="A hammock between two palm trees" />
        <p>No classes today. Rest up.</p>
      </div>
    {:else}
      <ol>
        {#each rows as r, k (k)}
          {#if r.kind === "gap"}
            <li class="gap" class:past={r.past}><span class="num">{span(r.minutes)} free</span></li>
          {:else}
            {@const s = r.i.session}
            <li class="class" data-phase={r.i.phase} style:--c={subjectColor(s.subject_code, colors)}>
              <span class="time num">{clock(s.start)}<small>{clock(s.end)}</small></span>
              <span class="stripe"></span>
              <span class="what">
                <strong>{s.subject_code}</strong>
                <span>{s.description}</span>
              </span>
              {#if r.i.phase === "in_session"}<span class="now">Now</span>{/if}
              {#if r.i.mark === "online"}<span class="tag">Online</span>{/if}
              {#if r.i.moved}<span class="tag">Moved</span>{/if}
            </li>
          {/if}
        {/each}
      </ol>
    {/if}

    {#if t?.agenda.tomorrow_first}
      {@const f = t.agenda.tomorrow_first}
      <p class="tomorrow">Tomorrow starts with <strong>{f.subject_code}</strong> at {clock(f.start)}</p>
    {/if}
  </section>
</div>

<style>
  .due {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px 16px;
  }
  .due ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 4px;
  }
  .due button {
    width: 100%;
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 6px 0;
    border: 0;
    background: none;
    color: var(--ink);
    text-align: left;
  }
  .due .when {
    width: 72px;
    flex: none;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 13px;
    color: var(--gold);
  }
  .due .what {
    display: grid;
    min-width: 0;
  }
  .due small {
    font-size: 12px;
    color: var(--ink-3);
  }
  .daynote {
    margin-top: 8px;
    max-width: 100%;
    padding: 6px 12px;
    border: 0;
    border-radius: 14px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
    font-size: 13px;
    text-align: left;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .screen {
    display: grid;
    gap: 18px;
  }
  header h1 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: 28px;
    font-weight: 700;
    letter-spacing: -0.02em;
  }
  .hero {
    --step: 4px;
    overflow: hidden;
    box-shadow: inset 0 0 0 1px var(--edge), var(--shadow);
  }
  .up {
    display: flex;
    gap: 12px;
    align-items: flex-end;
    justify-content: space-between;
    padding: 14px 16px 16px;
  }
  .who {
    min-width: 0;
  }
  .who h2 {
    margin: 4px 0 0;
    font-family: var(--font-display);
    font-size: 24px;
    font-weight: 800;
    letter-spacing: -0.01em;
    color: var(--gold);
  }
  .desc {
    margin: 2px 0 0;
    color: var(--ink);
    font-size: 15px;
    overflow: hidden;
    text-overflow: ellipsis;
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
  }
  .meta {
    margin: 4px 0 0;
    font-size: 13px;
    color: var(--ink-2);
  }
  .count {
    display: grid;
    justify-items: end;
    flex: none;
  }
  .big {
    font-size: 40px;
    font-weight: 800;
    line-height: 1;
    letter-spacing: -0.03em;
  }
  .unit {
    margin-top: 4px;
    font-size: 12px;
    color: var(--ink-2);
  }
  .bar {
    height: 4px;
    background: var(--sunk);
  }
  .bar span {
    display: block;
    height: 100%;
    background: repeating-linear-gradient(90deg, var(--gold) 0 6px, color-mix(in srgb, var(--gold) 70%, transparent) 6px 8px);
    transition: width 1s linear;
  }
  .day {
    display: grid;
    gap: 10px;
  }
  .head {
    display: flex;
    justify-content: space-between;
    align-items: baseline;
  }
  .free {
    margin: 0;
    font-size: 12px;
    font-weight: 600;
    color: var(--gold);
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 8px;
  }
  .class {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .class[data-phase="past"] {
    opacity: 0.5;
  }
  .class[data-phase="in_session"] {
    box-shadow: inset 0 0 0 1.5px var(--gold), 0 6px 18px var(--gold-soft);
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
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .now,
  .tag {
    flex: none;
    padding: 3px 8px;
    font-family: var(--font-pixel);
    font-size: 12px;
    letter-spacing: 0.06em;
    text-transform: uppercase;
  }
  .now {
    background: var(--gold);
    color: var(--on-gold);
  }
  .tag {
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink-2);
  }
  .gap {
    display: flex;
    align-items: center;
    height: 30px;
    padding: 0 14px 0 84px;
    border-radius: 10px;
    background-image: radial-gradient(color-mix(in srgb, var(--gold) 35%, transparent) 1px, transparent 1.2px);
    background-size: 5px 5px;
    color: var(--gold);
    font-size: 12px;
    font-weight: 600;
  }
  .gap.past {
    opacity: 0.35;
  }
  .empty {
    display: grid;
    justify-items: center;
    gap: 8px;
    padding: 22px;
    color: var(--ink-2);
  }
  .empty p,
  .tomorrow {
    margin: 0;
    font-size: 14px;
    color: var(--ink-2);
  }
  .tomorrow strong {
    color: var(--ink);
  }
</style>

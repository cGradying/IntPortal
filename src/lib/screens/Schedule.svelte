<script lang="ts">
  import Scene from "../Scene.svelte";
  import { app, adopt } from "../state.svelte";
  import { api, clock, isoDate, sessionId, subjectColor, WEEKDAYS, type ClassSession, type Mark, type Weekday } from "../api";

  const todayIdx = (new Date().getDay() + 6) % 7;
  let day = $state<Weekday>(WEEKDAYS[todayIdx]);
  let picked = $state<ClassSession | null>(null);
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

  const list = $derived((app.snapshot?.sessions ?? []).filter((s) => s.day === day).sort((a, b) => a.start - b.start));
  const busy = $derived(new Set((app.snapshot?.sessions ?? []).map((s) => s.day)));

  function markOf(s: ClassSession): Mark {
    const id = sessionId(s);
    const m = app.snapshot?.marks;
    return m?.weekly[id]?.[isoDate(monday)] ?? m?.term[id] ?? "in_person";
  }

  async function mark(m: Mark, everyWeek: boolean) {
    if (!picked) return;
    const s = picked;
    picked = null;
    await adopt(await api.setMark(sessionId(s), everyWeek ? null : isoDate(monday), m));
  }
</script>

<div class="screen">
  <header>
    <p class="label">This week</p>
    <h1>Schedule</h1>
  </header>

  <div class="days" role="tablist">
    {#each WEEKDAYS as d, i (d)}
      <button role="tab" class:on={day === d} class:today={i === todayIdx} aria-selected={day === d} onclick={() => (day = d)}>
        <span>{d.slice(0, 3)}</span>
        <strong class="num">{dates[i].getDate()}</strong>
        <i class:has={busy.has(d)}></i>
      </button>
    {/each}
  </div>

  {#if list.length === 0}
    <div class="empty card notch">
      <Scene name="hammock" label="A hammock between two palm trees" />
      <p>No classes on {day}.</p>
    </div>
  {:else}
    <ol>
      {#each list as s (sessionId(s))}
        {@const m = markOf(s)}
        <li>
          <button class="class" data-mark={m} style:--c={subjectColor(s.subject_code, colors)} onclick={() => (picked = s)}>
            <span class="time num">{clock(s.start)}<small>{clock(s.end)}</small></span>
            <span class="stripe"></span>
            <span class="what">
              <strong>{s.subject_code}</strong>
              <span>{s.description}</span>
              {#if s.faculty}<em>{s.faculty}</em>{/if}
            </span>
            {#if m !== "in_person"}<span class="tag">{m === "online" ? "Online" : "Vacant"}</span>{/if}
          </button>
        </li>
      {/each}
    </ol>
  {/if}
</div>

{#if picked}
  <div class="scrim" role="presentation" onclick={() => (picked = null)}></div>
  <div class="sheet notch" role="dialog" aria-label="Mark {picked.subject_code}">
    <p class="label">{picked.subject_code} · {clock(picked.start)}</p>
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
  @keyframes rise {
    from { transform: translateY(20px); opacity: 0; }
  }
  @keyframes fade {
    from { opacity: 0; }
  }
</style>

<script lang="ts">
  // What you can do to one class: mark how it meets this week or every
  // week, move it, colour it, or open its notes and syllabus. Opened by a
  // tap in Schedule and a long press on Today.
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { app, adopt, openNote, openSubject } from "./state.svelte";
  import { api, clock, isoDate, WEEKDAYS, type Mark, type Meeting, type Snapshot, type Weekday } from "./api";

  let { meeting, onclose }: { meeting: Meeting; onclose: () => void } = $props();
  $effect(() => closable(() => onclose()));

  let moving = $state<{ day: Weekday; start: string; end: string } | null>(null);
  let problem = $state("");
  const s = $derived(meeting.session);
  const colors = $derived(app.snapshot?.colors ?? {});
  const swatches = [1, 2, 3, 4, 5, 6].map((n) => `var(--s${n})`);
  // "This week" means the week of this meeting, keyed by its Monday.
  const monday = $derived.by(() => {
    const d = new Date(`${meeting.date}T00:00`);
    d.setDate(d.getDate() - ((d.getDay() + 6) % 7));
    return d;
  });

  const hhmm = (min: number) => `${String(Math.floor(min / 60)).padStart(2, "0")}:${String(min % 60).padStart(2, "0")}`;
  const minutes = (t: string) => {
    const [h, m] = t.split(":").map(Number);
    return h * 60 + m;
  };

  async function run(change: Promise<Snapshot>) {
    try {
      await adopt(await change);
      buzz.tick();
      onclose();
    } catch (e) {
      problem = String(e);
    }
  }

  const mark = (m: Mark, everyWeek: boolean) => run(api.setMark(meeting.id, everyWeek ? null : isoDate(monday), m));
  const color = (c: string | null) => run(api.setColor(meeting.session.subject_code, c));
  const move = (everyWeek: boolean) =>
    moving &&
    run(api.setMove(meeting.id, everyWeek ? null : isoDate(monday), { day: moving.day, start: minutes(moving.start), end: minutes(moving.end) }));
  function unmove() {
    const id = meeting.id;
    run(api.setMove(id, isoDate(monday), null).then(() => api.setMove(id, null, null)));
  }
</script>


<div class="scrim" role="presentation" onclick={onclose}></div>
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
      <button class="note" onclick={() => { const p = meeting; onclose(); openNote(`class:${p.session.subject_code}`, p.session.subject_code, p.session.description); }}>
        {app.notes.some((n) => n.key === `class:${s.subject_code}`) ? "Class notes" : "Write notes"}
      </button>
      <button class="note" onclick={() => { const p = meeting; onclose(); openSubject(p.session.subject_code, p.session.description); }}>Syllabus & grading</button>
    </div>
    <p class="label">Time</p>
    <div class="opts two">
      <button onclick={() => (moving = { day: s.day, start: hhmm(s.start), end: hhmm(s.end) })}>Change its time</button>
      <button disabled={!meeting.moved} onclick={unmove}>Back to SIS time</button>
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

<style>
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
    font-size: min(1.059rem, 32px);
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
  .opts .note {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-weight: 700;
  }
  .opts.two {
    grid-template-columns: 1fr 1fr;
  }
  .opts button:disabled {
    opacity: 0.4;
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
    font-size: min(0.765rem, 23px);
    color: var(--bad, #e0685a);
  }
</style>

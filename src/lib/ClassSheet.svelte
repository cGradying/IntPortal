<script lang="ts">
  // What you can do to one class: mark how it meets this week or every
  // week, move it, colour it, or open its notes and syllabus. Opened by a
  // tap in Schedule and a long press on Today.
  import { closable } from "./back";
  import { buzz } from "./haptics";
  import { app, adopt, openNote, openSubject } from "./state.svelte";
  import { openLink } from "./openLink";
  import { api, clock, isoDate, WEEKDAYS, type Mark, type Meeting, type Snapshot, type Weekday } from "./api";

  let { meeting, onclose, from }: { meeting: Meeting; onclose: () => void; from?: DOMRect } = $props();
  $effect(() => closable(() => close()));

  // A class's sheet grows out of its block and shrinks back into it (spec 045 C26).
  let sheet = $state<HTMLElement>();
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const blockTransform = (el: HTMLElement, r: DOMRect) => {
    const b = el.getBoundingClientRect();
    return `translate(${r.left - b.left}px, ${r.top - b.top}px) scale(${r.width / b.width}, ${r.height / b.height})`;
  };
  $effect(() => {
    if (!sheet || !from || reduce) return;
    sheet.animate([{ transform: blockTransform(sheet, from), transformOrigin: "0 0", opacity: 0.4 }, { transform: "none", transformOrigin: "0 0", opacity: 1 }], { duration: 380, easing: "cubic-bezier(0.22, 1, 0.36, 1)" });
  });
  let closing = false;
  function close() {
    if (closing) return;
    closing = true;
    if (dirty()) void saveInfo();
    if (!sheet || !from || reduce) return onclose();
    sheet.animate([{ transform: "none", transformOrigin: "0 0", opacity: 1 }, { transform: blockTransform(sheet, from), transformOrigin: "0 0", opacity: 0.2 }], { duration: 300, easing: "cubic-bezier(0.5, 0, 0.75, 0)", fill: "forwards" }).onfinish = () => onclose();
  }

  let moving = $state<{ day: Weekday; start: string; end: string } | null>(null);
  let problem = $state("");
  const s = $derived(meeting.session);
  const colors = $derived(app.snapshot?.colors ?? {});
  const info = $derived(app.snapshot?.class_info?.[s.subject_code]);
  // The student's link and description, edited on this sheet (spec 030 C3, C5).
  // Seeded once per subject, so a snapshot refresh never overwrites typing.
  let link = $state("");
  let about = $state("");
  let seeded = "";
  $effect(() => {
    if (seeded === s.subject_code) return;
    seeded = s.subject_code;
    link = info?.link ?? "";
    about = info?.about ?? "";
  });
  let linkProblem = $state("");
  const dirty = () => link.trim() !== (info?.link ?? "") || about.trim() !== (info?.about ?? "");
  /** A refused link doesn't stop the description from saving; the stored link stays. */
  async function saveInfo(l = link) {
    linkProblem = "";
    try {
      await adopt(await api.setClassInfo(s.subject_code, l || null, about || null));
      buzz.tick();
    } catch (e) {
      linkProblem = String(e);
      try {
        await adopt(await api.setClassInfo(s.subject_code, info?.link ?? null, about || null));
      } catch {
        // The description stays on screen; the next blur tries again.
      }
    }
  }
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


<div class="scrim" role="presentation" onclick={close}></div>
<div class="sheet notch" class:grown={!!from} bind:this={sheet} role="dialog" aria-label="Edit {s.subject_code}">
  <p class="label data">{s.subject_code} · {s.day.slice(0, 3)} {clock(s.start)}–{clock(s.end)}</p>
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
      <button class="note" onclick={() => { const p = meeting; close(); openNote(`class:${p.session.subject_code}`, p.session.subject_code, p.session.description); }}>
        {app.notes.some((n) => n.key === `class:${s.subject_code}`) ? "Class notes" : "Write notes"}
      </button>
      <button class="note" onclick={() => { const p = meeting; close(); openSubject(p.session.subject_code, p.session.description); }}>Syllabus & grading</button>
    </div>
    <p class="label">Time</p>
    <div class="opts two">
      <button onclick={() => (moving = { day: s.day, start: hhmm(s.start), end: hhmm(s.end) })}>Change its time</button>
      <button disabled={!meeting.moved} onclick={unmove}>Back to SIS time</button>
    </div>
    <p class="label">Your description</p>
    <textarea rows="2" bind:value={about} onblur={() => saveInfo()} aria-label="Your description"></textarea>
    {#if s.description}<p class="sis">{s.description}</p>{/if}
    <p class="label">Meeting link</p>
    <input type="url" class="field" bind:value={link} onblur={() => saveInfo()} placeholder="https://meet.google.com/…" aria-label="Meeting link" aria-invalid={!!linkProblem} />
    {#if linkProblem}<p class="problem" role="alert">{linkProblem}</p>{/if}
    {#if info?.link}
      <div class="opts two">
        <button class="note" aria-label="Join {s.subject_code} class" onclick={() => { buzz.tick(); openLink(info!.link!, true); }}>Join class</button>
        <button onclick={() => { link = ""; void saveInfo(""); }}>Clear link</button>
      </div>
    {/if}
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
    max-height: calc(100dvh - var(--safe-bottom) - 40px);
    overflow-y: auto;
    background: var(--card-2);
    animation: rise 0.35s var(--ease) both;
  }
  .sheet.grown {
    animation: none;
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
  textarea,
  .field {
    min-width: 0;
    min-height: 44px;
    padding: 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    resize: none;
  }
  .sis {
    margin: 0;
    color: var(--ink-2);
    font-size: min(0.765rem, 23px);
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

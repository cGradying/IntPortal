<script lang="ts">
  import MabiniGrades from "../MabiniGrades.svelte";
  import Confetti from "../Confetti.svelte";
  import ErrorCard from "../ErrorCard.svelte";
  import Scene from "../Scene.svelte";
  import Skeleton from "../Skeleton.svelte";
  import { resource } from "../load.svelte";
  import { app, adopt, openSubject } from "../state.svelte";
  import { buzz } from "../haptics";
  import { api, subjectColor, type Reach, type SubjectGrade } from "../api";

  const loaded = resource(() => api.standing());
  const standing = $derived(loaded.current.state === "ready" ? loaded.current.value : null);
  // The core does the math; re-read whenever the snapshot changes.
  $effect(() => {
    void app.snapshot;
    loaded.reload();
  });

  // Which term the list shows: the current one, or a past one by its label.
  let viewing = $state<string | null>(null);
  const termKey = (r: { school_year: string | null; semester: string | null }) => `${r.semester ?? ""} ${r.school_year ?? ""}`.trim();
  const pastReport = $derived(viewing ? (app.snapshot?.history ?? []).find((r) => termKey(r) === viewing) ?? null : null);
  const report = $derived(pastReport ?? app.snapshot?.grades ?? null);
  const subjects = $derived(report?.subjects ?? []);
  const colors = $derived(app.snapshot?.colors ?? {});
  let loading = $state(false);
  let error = $state("");

  const numeric = (s: SubjectGrade) => {
    const n = parseFloat(s.final_grade);
    return Number.isFinite(n) ? n : null;
  };

  const shownGpa = $derived(viewing ? (standing?.past.find((p) => termKey(p) === viewing)?.gpa ?? null) : (standing?.term_gpa ?? null));
  const posted = $derived(subjects.filter((s) => numeric(s) !== null));
  const units = $derived(posted.reduce((a, s) => a + s.units, 0));
  const best = $derived(!viewing && !!standing?.personal_best);

  // Every term with a GPA, oldest first, the current one last.
  const trend = $derived.by(() => {
    const pts = (standing?.past ?? []).map((p) => ({ label: short(p), v: p.gpa }));
    if (standing?.term_gpa != null) pts.push({ label: "Now", v: standing.term_gpa });
    return pts;
  });

  function short(r: { school_year: string | null; semester: string | null }) {
    const s = (r.semester ?? "").toLowerCase();
    const sem = s.includes("1st") || s.includes("first") ? "1st" : s.includes("2nd") || s.includes("second") ? "2nd" : "Sum";
    return `${sem} ${(r.school_year ?? "").slice(2, 4)}`;
  }

  // A term GPA better than every past term is a personal best (lower is
  // better). It celebrates once per value on this device.
  let celebrate = $state(false);
  $effect(() => {
    if (!best || shownGpa === null) return;
    const key = `best-${shownGpa.toFixed(2)}`;
    let done = false;
    try {
      done = localStorage.getItem("celebrated") === key;
      localStorage.setItem("celebrated", key);
    } catch {
      // Storage off: it may celebrate again next time. Harmless.
    }
    if (!done) celebrate = true;
  });

  // Goals: typed as text so an empty field means "not set".
  let target = $state("");
  let program = $state("");
  let goalError = $state("");
  $effect(() => {
    const g = app.snapshot?.goals;
    target = g?.target_gpa != null ? g.target_gpa.toFixed(2) : "";
    program = g?.program_units != null ? String(g.program_units) : "";
  });
  async function saveGoals() {
    const num = (t: string) => (t.trim() === "" ? null : Number(t));
    try {
      await adopt(await api.setGoals({ target_gpa: num(target), program_units: num(program) }));
      goalError = "";
    } catch (e) {
      goalError = String(e);
    }
  }

  function reachLine(r: Reach): string {
    switch (r.kind) {
      case "settled":
        return "Every grade this term is in.";
      case "out_of_reach":
        return "Out of reach this term, even with 1.00 on everything left.";
      case "secured":
        return "Already secured, whatever the rest turn out to be.";
      case "needs":
        return `Average ${r.average.toFixed(2)} or better on the ${r.subjects === 1 ? "last unposted subject" : `${r.subjects} unposted subjects`}.`;
    }
  }

  // Stamps land once: a grade first seen on this device plays its thunk.
  const SEEN = "stamped";
  let seen = new Set<string>(JSON.parse(localStorage.getItem(SEEN) ?? "[]"));
  const fresh = $derived(new Set(posted.map((s) => key(s)).filter((k) => !seen.has(k))));
  function key(s: SubjectGrade) {
    return `${s.subject_code}-${s.section_code}-${s.final_grade}`;
  }
  $effect(() => {
    if (!fresh.size) return;
    buzz.done();
    const t = setTimeout(() => {
      seen = new Set([...seen, ...fresh]);
      try {
        localStorage.setItem(SEEN, JSON.stringify([...seen]));
      } catch {
        // Stamps just replay next time.
      }
    }, 1500);
    return () => clearTimeout(t);
  });

  async function loadPast() {
    loading = true;
    error = "";
    try {
      await adopt(await api.loadHistory());
    } catch (e) {
      error = String(e);
    } finally {
      loading = false;
    }
  }

  // Trend points in a 100x40 box, lower grades (better) drawn higher.
  const points = $derived.by(() => {
    if (trend.length < 2) return [];
    const vs = trend.map((p) => p.v);
    const lo = Math.min(...vs) - 0.1, hi = Math.max(...vs) + 0.1;
    return trend.map((p, i) => ({ ...p, x: Math.round((i / (trend.length - 1)) * 92) + 4, y: Math.round(((p.v - lo) / (hi - lo)) * 30) + 5 }));
  });
  const path = $derived(points.map((p, i) => `${i ? "L" : "M"}${p.x} ${p.y}`).join(" "));
</script>

<div class="screen">
  <header>
    <p class="label">{report?.semester ?? "This term"}{report?.school_year ? ` · ${report.school_year}` : ""}</p>
    <h1>Grades</h1>
  </header>

  {#if standing?.past.length}
    <div class="terms" role="tablist" aria-label="Term">
      <button role="tab" class:on={!viewing} aria-selected={!viewing} onclick={() => (viewing = null)}>This term</button>
      {#each [...standing.past].reverse() as p (termKey(p))}
        <button role="tab" class:on={viewing === termKey(p)} aria-selected={viewing === termKey(p)} onclick={() => (viewing = termKey(p))}>{short(p)}</button>
      {/each}
    </div>
  {/if}

  <section class="gpa card notch">
    {#if celebrate}<Confetti />{/if}
    <div>
      <p class="label">GPA</p>
      <p class="value num">{shownGpa === null ? "—" : shownGpa.toFixed(2)}{#if best}<span class="pb" class:fresh={celebrate}>Personal best</span>{/if}</p>
      <p class="sub">
        {#if shownGpa === null}No grades posted yet{:else}{posted.length} of {subjects.length} posted · {units} units{/if}
      </p>
    </div>
    {#if path}
      <svg class="trend" viewBox="0 0 100 40" preserveAspectRatio="none" aria-label="GPA across terms">
        <path d={path} fill="none" stroke="var(--gold)" stroke-width="2" vector-effect="non-scaling-stroke" stroke-linejoin="miter" />
        {#each points as p, i (i)}
          <rect x={p.x - 2} y={p.y - 2} width="4" height="4" fill={i === points.length - 1 ? "var(--gold)" : "var(--card)"} stroke="var(--gold)" stroke-width="1" vector-effect="non-scaling-stroke"><title>{p.label}: {p.v.toFixed(2)}</title></rect>
        {/each}
      </svg>
    {/if}
  </section>
  <p class="note">Lower is better on PUP's 1.00–5.00 scale. Weighted by units; INC and DRP don't count.</p>

  {#if !viewing && loaded.current.state === "loading"}
    <Skeleton rows={1} height={150} />
  {:else if !viewing && loaded.current.state === "failed"}
    <ErrorCard error={loaded.current.error} onretry={loaded.reload} />
  {/if}
  {#if standing && !viewing}
    <section class="goals card notch">
      <div class="facts">
        <div><p class="label">Overall GPA</p><p class="big num">{standing.cumulative_gpa?.toFixed(2) ?? "—"}</p></div>
        <div>
          <p class="label">Units done</p>
          <p class="big num">{standing.units_done}{#if standing.goals.program_units}<small> / {standing.goals.program_units}</small>{/if}</p>
        </div>
      </div>
      {#if standing.goals.program_units}
        <div class="bar" role="progressbar" aria-valuemin="0" aria-valuemax={standing.goals.program_units} aria-valuenow={standing.units_done}>
          <i style:width="{Math.min(100, (standing.units_done / standing.goals.program_units) * 100)}%"></i>
        </div>
      {/if}
      {#if standing.reach}
        <p class="reach" data-kind={standing.reach.kind}>
          <strong>For {standing.goals.target_gpa?.toFixed(2)} this term:</strong> {reachLine(standing.reach)}
        </p>
      {/if}
      <div class="inputs">
        <label>Target GPA <input inputmode="decimal" placeholder="1.50" bind:value={target} /></label>
        <label>Program units <input inputmode="numeric" placeholder="150" bind:value={program} /></label>
        <button onclick={saveGoals}>Save</button>
      </div>
      {#if goalError}<p class="note" role="alert">{goalError}</p>{/if}
    </section>
  {/if}

  {#if posted.length === 0}
    <div class="empty card notch">
      <Scene name="mailbox" label="A mailbox asleep with its flag down" />
      <p><strong>No grades posted yet.</strong> They get stamped here the moment your professors post them.</p>
    </div>
  {/if}

  <ol>
    {#each subjects as s (s.subject_code + s.section_code + s.occurrence)}
      {@const n = numeric(s)}
      <li class="row" style:--c={subjectColor(s.subject_code, colors)}>
        <span class="stripe"></span>
        <button class="what" onclick={() => openSubject(s.subject_code, s.description)} aria-label="{s.subject_code} syllabus and grading">
          <strong>{s.subject_code}</strong>
          <span>{s.description}</span>
        </button>
        <span class="units num">{s.units}u</span>
        {#if n !== null}
          <span class="stamp" class:fresh={fresh.has(key(s))} class:fail={n >= 5}>{s.final_grade}</span>
        {:else if s.final_grade}
          <span class="stamp mark">{s.final_grade}</span>
        {:else}
          <span class="pending">Pending</span>
        {/if}
      </li>
    {/each}
  </ol>

  <MabiniGrades />

  {#if !app.snapshot?.history.length}
    <button class="past" onclick={loadPast} disabled={loading}>{loading ? "Walking past terms…" : "Load past terms"}</button>
    {#if error}<p class="note">{error}</p>{/if}
  {/if}
</div>

<style>
  button.what {
    flex: 1;
    padding: 0;
    border: 0;
    background: none;
    color: inherit;
    text-align: left;
  }
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
  .gpa {
    --step: 4px;
    position: relative;
    display: flex;
    align-items: flex-end;
    justify-content: space-between;
    gap: 16px;
    padding: 16px;
  }
  .value {
    margin: 2px 0 0;
    font-size: min(2.824rem, 62px);
    font-weight: 800;
    line-height: 1;
    letter-spacing: -0.03em;
    color: var(--gold);
  }
  .pb {
    display: inline-block;
    margin-left: 12px;
    padding: 3px 7px;
    vertical-align: middle;
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
    font-weight: 700;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--gold);
    box-shadow: inset 0 0 0 2px currentColor;
    transform: rotate(-5deg);
  }
  .pb.fresh {
    animation: thunk 0.55s steps(6) both 0.3s;
  }
  .sub {
    margin: 6px 0 0;
    font-size: min(0.765rem, 23px);
    color: var(--ink-2);
  }
  .trend {
    width: 44%;
    height: 64px;
    flex: none;
  }
  .terms {
    display: flex;
    gap: 6px;
    overflow-x: auto;
  }
  .terms button {
    flex: none;
    padding: 7px 12px;
    border: 0;
    border-radius: 16px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
    font-weight: 600;
    font-size: min(0.765rem, 23px);
  }
  .terms button.on {
    background: var(--gold);
    color: var(--on-gold);
  }
  .goals {
    --step: 4px;
    display: grid;
    gap: 12px;
    padding: 16px;
  }
  .facts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 12px;
  }
  .big {
    margin: 2px 0 0;
    font-size: min(1.529rem, 34px);
    font-weight: 800;
  }
  .big small {
    font-size: min(0.882rem, 27px);
    color: var(--ink-3);
  }
  .bar {
    height: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
  }
  .bar i {
    display: block;
    height: 100%;
    background: repeating-linear-gradient(90deg, var(--gold) 0 6px, color-mix(in srgb, var(--gold) 75%, black) 6px 8px);
  }
  .reach {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .reach[data-kind="out_of_reach"] strong {
    color: var(--bad);
  }
  .reach[data-kind="secured"] strong {
    color: var(--good);
  }
  .inputs {
    display: grid;
    grid-template-columns: 1fr 1fr auto;
    gap: 8px;
    align-items: end;
  }
  .inputs label {
    display: grid;
    gap: 4px;
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .inputs input {
    height: 40px;
    min-width: 0;
    padding: 0 10px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, min(0.941rem, 29px));
  }
  .inputs button {
    height: 40px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-weight: 700;
  }
  .note {
    margin: -4px 2px 0;
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  ol {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 8px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 14px;
    border-radius: 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
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
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .units {
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .stamp {
    flex: none;
    min-width: 54px;
    padding: 4px 6px;
    text-align: center;
    margin-right: 4px;
    font-family: var(--font-display);
    font-variant-numeric: tabular-nums;
    font-weight: 800;
    font-size: min(0.882rem, 27px);
    color: var(--good);
    box-shadow: inset 0 0 0 2px currentColor;
    transform: rotate(-4deg);
  }
  .stamp.fail {
    color: var(--bad);
  }
  .stamp.mark {
    color: var(--ink-2);
  }
  .stamp.fresh {
    animation: thunk 0.55s steps(6) both;
  }
  @keyframes thunk {
    0% { transform: rotate(-12deg) scale(2.2); opacity: 0; }
    60% { transform: rotate(-3deg) scale(0.92); opacity: 1; }
    100% { transform: rotate(-4deg) scale(1); }
  }
  .pending {
    flex: none;
    padding: 4px 10px;
    border-radius: 10px;
    background: var(--sunk);
    font-size: min(0.765rem, 23px);
    font-weight: 600;
    color: var(--ink-2);
  }
  .empty {
    --step: 4px;
    display: grid;
    justify-items: center;
    gap: 8px;
    padding: 18px 20px 20px;
    text-align: center;
  }
  .empty p {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .empty strong {
    color: var(--ink);
  }
  .past {
    justify-self: center;
    padding: 10px 18px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
</style>

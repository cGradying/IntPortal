<script lang="ts">
  import Confetti from "../Confetti.svelte";
  import Scene from "../Scene.svelte";
  import { app, adopt } from "../state.svelte";
  import { api, subjectColor, type GradeReport, type SubjectGrade } from "../api";

  const report = $derived(app.snapshot?.grades ?? null);
  const subjects = $derived(report?.subjects ?? []);
  const colors = $derived(app.snapshot?.colors ?? {});
  let loading = $state(false);
  let error = $state("");

  const numeric = (s: SubjectGrade) => {
    const n = parseFloat(s.final_grade);
    return Number.isFinite(n) ? n : null;
  };

  function gpa(list: SubjectGrade[]): number | null {
    let w = 0, u = 0;
    for (const s of list) {
      const n = numeric(s);
      if (n !== null && s.units > 0) {
        w += n * s.units;
        u += s.units;
      }
    }
    return u ? Math.round((w / u) * 100) / 100 : null;
  }

  const current = $derived(gpa(subjects));
  const posted = $derived(subjects.filter((s) => numeric(s) !== null));
  const units = $derived(posted.reduce((a, s) => a + s.units, 0));

  // Every term with a GPA, oldest first, the current one last.
  const trend = $derived.by(() => {
    const pts = (app.snapshot?.history ?? []).map((r: GradeReport) => ({ label: short(r), v: gpa(r.subjects) })).filter((p) => p.v !== null) as { label: string; v: number }[];
    if (current !== null) pts.push({ label: "Now", v: current });
    return pts;
  });

  function short(r: GradeReport) {
    const s = (r.semester ?? "").toLowerCase();
    const sem = s.includes("1st") || s.includes("first") ? "1st" : s.includes("2nd") || s.includes("second") ? "2nd" : "Sum";
    return `${sem} ${(r.school_year ?? "").slice(2, 4)}`;
  }

  // A term GPA better than every past term is a personal best (lower is
  // better). It celebrates once per value on this device.
  const best = $derived.by(() => {
    const past = (app.snapshot?.history ?? []).map((r) => gpa(r.subjects)).filter((v): v is number => v !== null);
    return current !== null && past.length > 0 && current < Math.min(...past);
  });
  let celebrate = $state(false);
  $effect(() => {
    if (!best || current === null) return;
    const key = `best-${current.toFixed(2)}`;
    let done = false;
    try {
      done = localStorage.getItem("celebrated") === key;
      localStorage.setItem("celebrated", key);
    } catch {
      // Storage off: it may celebrate again next time. Harmless.
    }
    if (!done) celebrate = true;
  });

  // Stamps land once: a grade first seen on this device plays its thunk.
  const SEEN = "stamped";
  let seen = new Set<string>(JSON.parse(localStorage.getItem(SEEN) ?? "[]"));
  const fresh = $derived(new Set(posted.map((s) => key(s)).filter((k) => !seen.has(k))));
  function key(s: SubjectGrade) {
    return `${s.subject_code}-${s.section_code}-${s.final_grade}`;
  }
  $effect(() => {
    if (!fresh.size) return;
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

  <section class="gpa card notch">
    {#if celebrate}<Confetti />{/if}
    <div>
      <p class="label">GPA</p>
      <p class="value num">{current === null ? "—" : current.toFixed(2)}{#if best}<span class="pb" class:fresh={celebrate}>Personal best</span>{/if}</p>
      <p class="sub">
        {#if current === null}No grades posted yet{:else}{posted.length} of {subjects.length} posted · {units} units{/if}
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
        <span class="what">
          <strong>{s.subject_code}</strong>
          <span>{s.description}</span>
        </span>
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

  {#if !app.snapshot?.history.length}
    <button class="past" onclick={loadPast} disabled={loading}>{loading ? "Walking past terms…" : "Load past terms"}</button>
    {#if error}<p class="note">{error}</p>{/if}
  {/if}
</div>

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
    font-size: 48px;
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
    font-size: 12px;
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
    font-size: 13px;
    color: var(--ink-2);
  }
  .trend {
    width: 44%;
    height: 64px;
    flex: none;
  }
  .note {
    margin: -4px 2px 0;
    font-size: 12px;
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
    font-size: 15px;
  }
  .what span {
    font-size: 14px;
    color: var(--ink-2);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .units {
    font-size: 12px;
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
    font-size: 15px;
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
    font-size: 13px;
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
    font-size: 14px;
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
    font-size: 14px;
  }
</style>

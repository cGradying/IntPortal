<script lang="ts">
  // eMabini's per-course grades. Kept apart from the SIS grades: Moodle's
  // grade is whatever the course shows, not the 1.00 to 5.00 scale.
  import { splitCourseName } from "./deadlines";
  import { app } from "./state.svelte";

  const rows = $derived(
    (app.mabini?.grades ?? []).map((g) => ({
      id: g.course_id ?? g.name,
      subject: splitCourseName(g.name).subject,
      section: splitCourseName(g.name).section,
      grade: g.grade,
      progress: app.mabini?.courses.find((c) => c.id === g.course_id)?.progress ?? null,
    })),
  );
</script>

{#if app.mabiniConnected && rows.length}
  <section class="card notch block">
    <p class="label">eMabini courses</p>
    <ul>
      {#each rows as r (r.id)}
        <li>
          <span class="what">
            <strong>{r.subject}</strong>
            {#if r.section}<small>{r.section}</small>{/if}
            {#if r.progress !== null}<span class="bar" aria-label="{Math.round(r.progress)}% done"><i style:width="{r.progress}%"></i></span>{/if}
          </span>
          <span class="grade" class:pending={!r.grade}>{r.grade ?? "Pending"}</span>
        </li>
      {/each}
    </ul>
  </section>
{/if}

<style>
  .block {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px 16px;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 10px;
  }
  li {
    display: flex;
    align-items: center;
    gap: 12px;
  }
  .what {
    display: grid;
    gap: 2px;
    min-width: 0;
    flex: 1;
  }
  small {
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .bar {
    display: block;
    height: 4px;
    margin-top: 4px;
    background: var(--sunk);
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--gold);
  }
  .grade {
    font-family: var(--font-display);
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .grade.pending {
    font-weight: 400;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
</style>

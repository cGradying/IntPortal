<script lang="ts">
  // eMabini in full: deadlines, then courses with progress and grade.
  import type { Course } from "./api";
  import { closable } from "./back";
  import { dueLabel, splitDeadlines, subjectOf, titleOf } from "./deadlines";
  import { openLink } from "./openLink";
  import { app, mabiniSyncNow } from "./state.svelte";

  const close = () => (app.mabiniPage = false);
  $effect(() => closable(close));

  const now = new Date();
  const data = $derived(app.mabini);
  const split = $derived(splitDeadlines(data?.deadlines ?? [], now));
  const deadlines = $derived([...split.overdue, ...split.upcoming]);
  const gradeOf = (c: Course) => data?.grades.find((g) => g.course_id === c.id)?.grade ?? null;
  const terms = $derived.by(() => {
    const by = new Map<string, Course[]>();
    for (const c of data?.courses ?? []) by.set(c.term || "Courses", [...(by.get(c.term || "Courses") ?? []), c]);
    return [...by];
  });
</script>

<div class="page" role="dialog" aria-label="eMabini">
  <header>
    <div>
      <p class="label">eMabini</p>
      <h2>Courses and deadlines</h2>
    </div>
    <button class="ghost" onclick={close}>Done</button>
  </header>

  <div class="body">
    <section class="card notch block">
      <p class="label">Deadlines</p>
      {#if deadlines.length}
        <ul>
          {#each deadlines as d (d.id)}
            <li>
              <button onclick={() => openLink(d.url)}>
                <span class="when" class:late={dueLabel(d, now) === "Overdue"}>{dueLabel(d, now)}</span>
                <span class="what"><strong>{titleOf(d.name)}</strong><small>{subjectOf(d.course)}</small></span>
              </button>
            </li>
          {/each}
        </ul>
      {:else}
        <p class="fine">Nothing due. Walang due, ayos!</p>
      {/if}
    </section>

    {#each terms as [term, courses] (term)}
      <section class="card notch block">
        <p class="label">{term}</p>
        <ul>
          {#each courses as c (c.id)}
            {@const g = gradeOf(c)}
            <li>
              <button onclick={() => openLink(c.url)}>
                <span class="what">
                  <strong>{c.subject}</strong>
                  <small>{c.section}</small>
                  {#if c.progress !== null}<span class="bar" aria-label="{Math.round(c.progress)}% done"><i style:width="{c.progress}%"></i></span>{/if}
                </span>
                <span class="grade" class:pending={!g}>{g ?? "Pending"}</span>
              </button>
            </li>
          {/each}
        </ul>
      </section>
    {:else}
      <p class="fine">No courses yet. Pull to sync, or add an eMabini enrolment in the SIS first.</p>
    {/each}

    <button class="ghost wide" onclick={mabiniSyncNow} disabled={app.mabiniSync === "syncing"}>{app.mabiniSync === "syncing" ? "Syncing…" : "Sync eMabini"}</button>
    {#if app.mabiniError}<p class="fine bad" role="alert">{app.mabiniError}</p>{/if}
  </div>
</div>

<style>
  .page {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto 1fr;
    gap: 12px;
    padding: calc(var(--safe-top) + 12px) var(--gutter) 0;
    background: var(--ground);
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: flex-start;
    gap: 12px;
  }
  h2 {
    margin: 2px 0 0;
    font-family: var(--font-display);
    font-size: min(1.294rem, 29px);
  }
  .body {
    display: grid;
    align-content: start;
    gap: 12px;
    overflow-y: auto;
    padding-bottom: calc(var(--safe-bottom) + 24px);
  }
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
    gap: 4px;
  }
  li button {
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
  .when {
    width: 72px;
    flex: none;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.765rem, 23px);
    color: var(--gold);
  }
  .when.late {
    color: var(--bad);
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
    min-width: 4.5rem;
    text-align: right;
    font-family: var(--font-display);
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .grade.pending {
    font-weight: 400;
    font-size: min(0.765rem, 23px);
    color: var(--ink-3);
  }
  .ghost {
    height: 40px;
    padding: 0 14px;
    border: 0;
    border-radius: 10px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .ghost:disabled {
    opacity: 0.4;
  }
  .wide {
    width: 100%;
  }
  .fine {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .bad {
    color: var(--bad);
  }
</style>

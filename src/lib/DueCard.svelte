<script lang="ts">
  // Spec 041: every deadline in one card on Today: syllabus, eMabini and the
  // student's own. Overdue first, then the week; Done with Undo; Add your own.
  import AddDeadline from "./AddDeadline.svelte";
  import { api, moment, type DeadlineEntry } from "./api";
  import { entryLabel, knowsNothingDue, mabiniState } from "./deadlines";
  import { buzz } from "./haptics";
  import { openLink } from "./openLink";
  import { adopt, app, mabiniSyncNow, openSubject } from "./state.svelte";

  const MAX = 5;
  let list = $state<DeadlineEntry[]>([]);
  let all = $state(false);
  let adding = $state<null | { own?: DeadlineEntry }>(null);
  let undo = $state<DeadlineEntry | null>(null);
  let undoTimer: ReturnType<typeof setTimeout> | undefined;

  $effect(() => {
    void app.snapshot;
    void app.mabini;
    api.deadlines(moment(), all ? 30 : 8).then((d) => (list = d)).catch(() => {});
  });

  const now = $derived((app.today, new Date()));
  const rows = $derived(all ? list : list.slice(0, MAX));
  const mabini = $derived(mabiniState(app.mabiniConnected, app.mabini?.last_synced, app.mabiniError));
  const synced = (s: number | null | undefined) => (s ? new Date(s * 1000).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) : "");
  const describe = (code: string) => app.snapshot?.sessions.find((x) => x.subject_code === code)?.description ?? "";

  function open(d: DeadlineEntry) {
    if (d.url) openLink(d.url);
    else if (d.source === "syllabus" && d.subject) openSubject(d.subject, describe(d.subject), "outline", d.id.split(":").pop());
    else if (d.subject) openSubject(d.subject, describe(d.subject));
    else if (d.source === "own") adding = { own: d };
  }

  async function done(d: DeadlineEntry, isDone = true) {
    if (isDone) buzz.done();
    await adopt(await api.setDone(d.id, isDone));
    clearTimeout(undoTimer);
    undo = isDone ? d : null;
    if (isDone) undoTimer = setTimeout(() => (undo = null), 5000);
  }
</script>

<section class="due card notch" aria-label="Due">
  <div class="head">
    <p class="label">Due</p>
    <button class="add" onclick={() => (adding = {})}>Add</button>
  </div>

  {#if mabini === "never"}
    <p class="state">eMabini hasn't synced yet. <button class="link" onclick={mabiniSyncNow}>Sync</button></p>
  {:else if mabini === "failed"}
    <p class="state">Couldn't reach eMabini. Showing what we had{app.mabini?.last_synced ? ` at ${synced(app.mabini.last_synced)}` : ""}.</p>
  {/if}

  {#if rows.length}
    <ul>
      {#each rows as d (d.id)}
        {@const word = entryLabel(d, now)}
        <li>
          <button class="row" onclick={() => open(d)} aria-label="{d.title}, {d.subject ?? d.course ?? 'no subject'}, due {word}">
            <span class="when" class:late={word === "Overdue"}>{word}</span>
            <span class="what"><strong>{d.title}</strong><small>{d.subject ?? d.course ?? "Your own"}</small></span>
          </button>
          <button class="check" onclick={() => done(d)} aria-label="Mark {d.title} done">✓</button>
        </li>
      {/each}
    </ul>
    {#if list.length > MAX || all}
      <button class="all" onclick={() => (all = !all)}>{all ? "Show less" : "All deadlines"}</button>
    {/if}
  {:else if knowsNothingDue(app.snapshot?.last_synced, mabini, app.mabini?.last_synced, now)}
    <p class="none"><b>LAR</b> Walang due this week. Ayos!</p>
  {:else}
    <p class="none">Nothing due that we know of yet.</p>
  {/if}

  {#if undo}
    <p class="undo" role="status">{undo.title} done. <button class="link" onclick={() => undo && done(undo, false)}>Undo</button></p>
  {/if}
</section>

{#if adding}
  <AddDeadline own={adding.own} onclose={() => (adding = null)} />
{/if}

<style>
  .due {
    --step: 4px;
    display: grid;
    gap: 8px;
    padding: 14px 16px;
  }
  .head {
    display: flex;
    align-items: center;
    justify-content: space-between;
  }
  ul {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 4px;
  }
  li {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .row {
    flex: 1;
    min-width: 0;
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
    min-width: 0;
  }
  .what strong {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  small {
    font-size: min(0.706rem, 22px);
    color: var(--ink-3);
  }
  .check,
  .add {
    min-width: 44px;
    min-height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
    font-family: var(--font-display);
    font-weight: 700;
  }
  .all {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.765rem, 23px);
  }
  .state,
  .undo,
  .none {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .none b {
    margin-right: 6px;
    font-family: var(--font-pixel);
    font-weight: 400;
    letter-spacing: 0.06em;
    color: var(--gold);
  }
  .link {
    min-height: 44px;
    padding: 0 6px;
    border: 0;
    background: none;
    color: var(--gold);
    font-weight: 700;
  }
</style>

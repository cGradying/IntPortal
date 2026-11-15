<script lang="ts">
  // Spec 041: every deadline in one card on Today: syllabus, eMabini and the
  // student's own. Overdue first, then the week; Done with Undo; Add your own.
  import AddDeadline from "./AddDeadline.svelte";
  import { api, moment, type DeadlineEntry } from "./api";
  import { entryLabel, knowsNothingDue, mabiniState } from "./deadlines";
  import { buzz } from "./haptics";
  import { openLink } from "./openLink";
  import { adopt, app, mabiniSyncNow, openSubject } from "./state.svelte";
  import { onDestroy, tick } from "svelte";
  import { flip } from "svelte/animate";
  import { slide } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { barSegments, FLOW_MS } from "./doneRun";
  import { sfx } from "./sound";
  import { longpress } from "./press";
  import { addDone, loadDone, pruneWeek, removeDone, saveDone, UNDO_MS } from "./doneWeek";

  const MAX = 5;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  /** The box fills, the title strikes and the stamp lands; then the row folds away into Done. */
  const FOLD_MS = 700;
  let list = $state<DeadlineEntry[]>([]);
  // The first load is already there when you arrive: rows open only for what changes after it.
  let loaded = false;
  const flow = () => ({ duration: reduce || !loaded ? 0 : FLOW_MS, easing: cubicOut });
  let card: HTMLElement;
  let all = $state(false);
  let adding = $state<null | { own?: DeadlineEntry }>(null);
  // Marked done since this card opened: they stay here, with Undo, until it closes.
  let finished = $state<DeadlineEntry[]>([]);
  // Rows mid-way through the done sequence, by id.
  let marking = $state<Record<string, true>>({});
  // Pressed look for Add, by pointer events: iOS WebKit can leave :active stuck on a button that a sheet opens over.
  let pressing = $state(false);
  let cleared = $state(false);
  // Spec 041 C6: finished this week (kept across launches), and which are still inside the 5 s Undo.
  let week = $state(loadDone(Date.now()));
  let undoing = $state<string[]>([]);
  let showWeek = $state(false);
  const keep = (next: typeof week) => saveDone((week = next));
  // The Undo timers, by id: cleared on Undo and before a re-arm.
  const timers = new Map<string, ReturnType<typeof setTimeout>>();
  const arm = (id: string) => {
    clearTimeout(timers.get(id));
    timers.set(id, setTimeout(() => (timers.delete(id), (undoing = undoing.filter((x) => x !== id))), UNDO_MS));
  };
  onDestroy(() => timers.forEach(clearTimeout));
  // The row whose long press offered Done.
  let offered = $state<string | null>(null);
  let offerTimer: ReturnType<typeof setTimeout> | undefined;
  function offer(id: string) {
    buzz.pull();
    offered = id;
    clearTimeout(offerTimer);
    offerTimer = setTimeout(() => (offered = null), 4000);
  }
  onDestroy(() => clearTimeout(offerTimer));
  // What rests under "Done this week" must still be Done in the core; drop what was un-done elsewhere.
  // Fresh ones (inside the Undo window) are exempt: the core hasn't answered yet.
  $effect(() => {
    const done = app.snapshot?.done;
    if (!done) return;
    const gone = week.filter((x) => !undoing.includes(x.entry.id) && !done.includes(x.entry.id));
    if (gone.length) keep(week.filter((x) => !gone.includes(x)));
  });
  const quick = $derived(week.filter((x) => undoing.includes(x.entry.id)));
  const resting = $derived(week.filter((x) => !undoing.includes(x.entry.id)));

  $effect(() => {
    void app.snapshot;
    void app.mabini;
    api.deadlines(moment(), all ? 30 : 8)
      .then((d) => (list = d))
      .catch(() => {})
      .finally(() => tick().then(() => (loaded = true)));
  });

  const now = $derived((app.today, new Date()));
  const rows = $derived(all ? list : list.slice(0, MAX));
  const segments = $derived(barSegments(list.length, finished.length));
  const mabini = $derived(mabiniState(app.mabiniConnected, app.mabini?.last_synced, app.mabiniError));
  const synced = (s: number | null | undefined) => (s ? new Date(s * 1000).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" }) : "");
  const describe = (code: string) => app.snapshot?.sessions.find((x) => x.subject_code === code)?.description ?? "";

  function open(d: DeadlineEntry) {
    if (d.source === "own") adding = { own: d };
    else if (d.url) openLink(d.url);
    else if (d.source === "syllabus" && d.subject) openSubject(d.subject, describe(d.subject), "outline", d.id.split(":").pop());
    else if (d.subject) openSubject(d.subject, describe(d.subject));
  }

  // The done sequence (spec 045 C18): the box fills, the title strikes, the stamp lands. After a
  // beat the row folds away and rests under the card with Undo. Then everything is still.
  function done(d: DeadlineEntry) {
    if (marking[d.id]) return;
    marking[d.id] = true;
    buzz.done();
    sfx.done();
    setTimeout(() => settle(d), reduce ? 0 : FOLD_MS);
  }

  async function settle(d: DeadlineEntry) {
    list = list.filter((x) => x.id !== d.id);
    finished = [d, ...finished];
    keep(addDone(pruneWeek(week, Date.now()), d, Date.now()));
    undoing = [...undoing, d.id];
    arm(d.id);
    delete marking[d.id];
    sfx.land();
    if (!list.length) cleared = true;
    try {
      await adopt(await api.setDone(d.id, true));
    } catch {
      // Not saved: put it back rather than show a done that isn't.
      buzz.fail();
      finished = finished.filter((x) => x.id !== d.id);
      keep(removeDone(week, d.id));
      clearTimeout(timers.get(d.id));
      undoing = undoing.filter((x) => x !== d.id);
      list = [d, ...list];
    }
  }

  async function undo(d: DeadlineEntry) {
    // The core first: a failed Undo leaves the item where it was.
    try {
      await adopt(await api.setDone(d.id, false));
    } catch {
      buzz.fail();
      return;
    }
    clearTimeout(timers.get(d.id));
    timers.delete(d.id);
    finished = finished.filter((x) => x.id !== d.id);
    keep(removeDone(week, d.id));
    undoing = undoing.filter((x) => x !== d.id);
    cleared = false;
    buzz.tick();
  }
</script>

<section class="due card notch" aria-label="Due" bind:this={card} data-due-card>
  <div class="head">
    <p class="label">Due</p>
    <button
      class="add"
      class:pressed={pressing}
      data-due-add
      onpointerdown={() => (pressing = true)}
      onpointerup={() => (pressing = false)}
      onpointercancel={() => (pressing = false)}
      onpointerleave={() => (pressing = false)}
      onclick={(e) => { pressing = false; e.currentTarget.blur(); adding = {}; }}
    ><i aria-hidden="true"></i>Add</button>
  </div>

  {#if finished.length && segments > 1}
    <div class="prog" role="img" transition:slide={flow()} aria-label="{finished.length} of {segments} done">
      {#each { length: segments } as _, i (i)}<i class:on={i < finished.length}></i>{/each}
      <span class="num">{finished.length} of {segments}</span>
    </div>
  {/if}

  {#if mabini === "never"}
    <p class="state">eMabini hasn't synced yet. <button class="link" onclick={mabiniSyncNow}>Sync</button></p>
  {:else if mabini === "failed"}
    <p class="state">Couldn't reach eMabini. Showing what we had{app.mabini?.last_synced ? ` at ${synced(app.mabini.last_synced)}` : ""}.</p>
  {/if}

  {#if rows.length}
    <ul>
      {#each rows as d (d.id)}
        {@const word = entryLabel(d, now)}
        {@const mark = marking[d.id]}
        <li animate:flip={flow()} in:slide={flow()} out:slide={flow()} data-due-row={d.id}>
          <!-- A long press offers Done (C8); the Done button beside it is the accessible way, with its own label. -->
          <div use:longpress={() => offer(d.id)} class="ri" class:fresh={!!mark}>
          <button class="check" class:on={!!mark} onpointerdown={() => sfx.press()} onclick={() => done(d)} aria-label="Mark {d.title} done"><i></i><span aria-hidden="true">Done</span></button>
          <button class="row" onclick={() => open(d)} aria-label="{d.title}, {d.subject ?? d.course ?? 'no subject'}, due {word}">
            <span class="what"><strong>{d.title}</strong><small><b class="when" class:late={word === "Overdue"}>{word}</b> · {d.subject ?? d.course ?? "Your own"}</small></span>
          </button>
          {#if offered === d.id && !mark}
            <button class="offer" onclick={() => { offered = null; done(d); }}>Mark done</button>
          {/if}
          {#if mark}<span class="stamp" aria-hidden="true">DONE</span>{/if}
          </div>
        </li>
      {/each}
    </ul>
    {#if list.length > MAX || all}
      <button class="all" onclick={() => (all = !all)}>{all ? "Show less" : "All deadlines"}</button>
    {/if}
  {:else if cleared}
    <p class="none clear" in:slide={flow()}><i class="tick" aria-hidden="true"></i>All clear this week.</p>
  {:else if knowsNothingDue(app.sisConnected, app.snapshot?.last_synced, mabini, app.mabini?.last_synced, now) && !finished.length}
    <p class="none"><b>LAR</b> Walang due this week. Ayos!</p>
  {:else if !finished.length}
    <p class="none">Nothing due that we know of yet.</p>
  {/if}

  {#if quick.length}
    <ul>
      {#each quick as { entry: d } (d.id)}
        <li animate:flip={flow()} in:slide={flow()} out:slide={flow()}>
          <div class="ri finished">
          <button class="link" onclick={() => undo(d)} aria-label="Undo {d.title}">Undo</button>
          <span class="what"><s>{d.title}</s><small>{d.subject ?? d.course ?? "Your own"}</small></span>
          <span class="stamp set" aria-hidden="true">DONE</span>
          </div>
        </li>
      {/each}
    </ul>
  {/if}

  {#if resting.length}
    <button class="week" aria-expanded={showWeek} onclick={() => (showWeek = !showWeek)}>Done this week · {resting.length}</button>
    {#if showWeek}
      <ul transition:slide={flow()}>
        {#each resting as { entry: d } (d.id)}
          <li class="past">
            <span class="what"><s>{d.title}</s><small>{d.subject ?? d.course ?? "Your own"}</small></span>
            <button class="link" onclick={() => undo(d)} aria-label="Un-mark {d.title}">Undo</button>
          </li>
        {/each}
      </ul>
    {/if}
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
  .ri {
    position: relative;
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
    font-weight: 700;
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
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    font-size: var(--text-label);
    color: var(--ink-3);
  }
  /* The box: empty, then filled in three steps. */
  /* On the left, clear of the floating cube, and it says what it does (#220): one 44 pt chip, box and word side by side. */
  .check {
    flex: none;
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 0 10px 0 8px;
    font-size: var(--text-label);
    line-height: 1;
    color: var(--ink-2);
  }
  .check i {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 2px var(--ink-3);
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% calc(100% - 2px), calc(100% - 2px) calc(100% - 2px), calc(100% - 2px) 100%, 2px 100%, 2px calc(100% - 2px), 0 calc(100% - 2px));
  }
  .check.on i {
    background: var(--gold);
    box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.25);
    animation: fill var(--t-move) cubic-bezier(0.34, 1.56, 0.64, 1) backwards;
  }
  .check.on i::after {
    content: "";
    width: 12px;
    height: 9px;
    background: var(--on-gold);
    clip-path: polygon(0 50%, 25% 50%, 25% 75%, 37.5% 75%, 37.5% 50%, 62.5% 50%, 62.5% 25%, 75% 25%, 75% 0, 100% 0, 100% 25%, 87.5% 25%, 87.5% 50%, 75% 50%, 75% 75%, 62.5% 75%, 62.5% 100%, 25% 100%, 25% 75%, 0 75%);
  }
  @keyframes fill {
    from { scale: 0.6; }
  }
  .what strong {
    position: relative;
    justify-self: start;
    max-width: 100%;
  }
  .ri.fresh .what strong {
    color: var(--ink-2);
  }
  .ri.fresh .what strong::after {
    content: "";
    position: absolute;
    left: -1px;
    right: -1px;
    top: 52%;
    height: 2px;
    background: var(--ink-2);
    transform-origin: left;
    animation: strike var(--t-quick) var(--ease) var(--t-quick) backwards;
  }
  @keyframes strike {
    from { transform: scaleX(0); }
  }
  .ri.fresh {
    pointer-events: none;
  }
  .stamp {
    position: absolute;
    right: 4px;
    top: 50%;
    translate: 0 -50%;
    rotate: -7deg;
    padding: 1px 6px;
    font: 700 var(--text-label) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--good);
    background: var(--card);
    box-shadow: inset 0 0 0 2px var(--good);
    pointer-events: none;
    animation: thunk var(--t-flow) cubic-bezier(0.22, 1, 0.36, 1) both var(--t-quick);
  }
  .stamp.set {
    position: static;
    translate: none;
    flex: none;
    animation: none;
  }
  @keyframes thunk {
    0% { scale: 1.9; opacity: 0; }
    60% { scale: 0.97; opacity: 1; }
    100% { scale: 1; opacity: 1; }
  }
  .prog {
    display: flex;
    align-items: center;
    gap: 3px;
  }
  .prog i {
    flex: 1;
    height: 6px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    transform-origin: 50% 100%;
  }
  .prog i.on {
    background: var(--gold);
    box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.22);
    animation: seg var(--t-move) var(--ease) backwards;
  }
  .prog span {
    margin-left: 4px;
    font-size: var(--text-label);
    color: var(--ink-2);
  }
  @keyframes seg {
    from { scale: 1 2.6; }
  }
  .offer {
    position: absolute;
    right: 0;
    top: 50%;
    translate: 0 -50%;
    z-index: 2;
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
    animation: thunk var(--t-quick) var(--ease) both;
  }
  .week {
    justify-self: start;
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink-3);
    font-size: var(--text-label);
  }
  .past {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 8px;
    min-height: 44px;
  }
  .finished {
    min-height: 44px;
  }
  .finished .what {
    flex: 1;
  }
  s {
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
    font-weight: 600;
    color: var(--ink-2);
  }
  .clear {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .tick {
    flex: none;
    width: 12px;
    height: 9px;
    background: var(--good);
    clip-path: polygon(0 50%, 25% 50%, 25% 75%, 37.5% 75%, 37.5% 50%, 62.5% 50%, 62.5% 25%, 75% 25%, 75% 0, 100% 0, 100% 25%, 87.5% 25%, 87.5% 50%, 75% 50%, 75% 75%, 62.5% 75%, 62.5% 100%, 25% 100%, 25% 75%, 0 75%);
  }
  /* A gold text button: a small pixel plus, then the word. No box; pressed is opacity only. */
  .add {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 44px;
    min-height: 44px;
    padding: 0 0 0 12px;
    border: 0;
    background: none;
    color: var(--gold);
    font-family: var(--font-display);
    font-weight: 700;
    -webkit-tap-highlight-color: transparent;
  }
  .add i {
    width: 10px;
    height: 10px;
    background: currentColor;
    clip-path: polygon(35% 0, 65% 0, 65% 35%, 100% 35%, 100% 65%, 65% 65%, 65% 100%, 35% 100%, 35% 65%, 0 65%, 0 35%, 35% 35%);
  }
  /* Never the global squash: pressed is the only state, and it ends with the pointer. */
  .add:not(:disabled):active {
    scale: none;
  }
  .add.pressed {
    opacity: 0.6;
  }
  .check {
    min-width: 44px;
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
    font-family: var(--font-display);
    font-weight: 700;
  }
  .all {
    height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-caption);
  }
  .state,
  .none {
    margin: 0;
    font-size: var(--text-sub);
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
    flex: none;
    min-width: 44px;
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--gold);
    font-weight: 700;
  }
</style>

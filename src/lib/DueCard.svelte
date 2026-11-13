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
  import { crossfade, slide } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import Lar from "./lar/Lar.svelte";
  import { burst } from "./burst";
  import { barSegments, comboText, FLOW_MS, nextRun, tierOf, type Run } from "./doneRun";
  import { fieldPulse, sinkTiles } from "./fieldPulse";
  import { sfx } from "./sound";
  import { longpress } from "./press";
  import { addDone, loadDone, pruneWeek, removeDone, saveDone, UNDO_MS } from "./doneWeek";

  const MAX = 5;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  /** The stamp lands, the card lifts, then it drops into Done. */
  const LIFT_MS = 500;
  const MOVE_MS = 700;
  const LAND_MS = 420;
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
  let marking = $state<Record<string, { tier: string; combo: string; lifted: boolean }>>({});
  let run: Run | null = null;
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

  const [send, receive] = crossfade({ duration: reduce ? 0 : 480, easing: cubicOut, fallback: () => ({ duration: 0 }) });

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

  function centre(el: Element) {
    const b = el.getBoundingClientRect();
    return [b.left + b.width / 2, b.top + b.height / 2] as const;
  }

  // The done sequence (spec 045 C18): the box fills, the title strikes, sparks and a ripple through
  // the field, the stamp lands, the row lifts, sheds tiles into the dot grid and glides into Done.
  // Then everything is still.
  function done(d: DeadlineEntry, box: HTMLElement) {
    if (marking[d.id]) return;
    run = nextRun(run, performance.now());
    const { step } = run;
    marking[d.id] = { tier: tierOf(step), combo: comboText(step), lifted: false };
    buzz.done();
    sfx.done(step);
    const [x, y] = centre(box);
    const c = Math.min(step, 4);
    burst(x, y, 8 + 4 * c, 1 + 0.15 * c);
    fieldPulse(x, y, 0.45 + 0.15 * c);
    setTimeout(() => buzz.pull(), 240);
    const row = box.closest("li");
    setTimeout(() => {
      if (marking[d.id]) marking[d.id].lifted = true;
      if (row) sinkTiles(row.getBoundingClientRect(), 10 + 2 * c);
    }, reduce ? 0 : LIFT_MS);
    setTimeout(() => settle(d), reduce ? 0 : MOVE_MS);
  }

  async function settle(d: DeadlineEntry) {
    list = list.filter((x) => x.id !== d.id);
    finished = [d, ...finished];
    keep(addDone(pruneWeek(week, Date.now()), d, Date.now()));
    undoing = [...undoing, d.id];
    arm(d.id);
    delete marking[d.id];
    setTimeout(() => sfx.land(), reduce ? 0 : LAND_MS);
    if (!list.length) setTimeout(allClear, reduce ? 0 : LAND_MS + 60);
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

  function allClear() {
    cleared = true;
    sfx.clear();
    buzz.done();
    const [x, y] = centre(card);
    fieldPulse(x, y, 1.5);
    if (!reduce) [0, 150, 300].forEach((ms) => setTimeout(() => burst(x, y, 16, 1.7), ms));
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
    <button class="add" data-due-add onclick={() => (adding = {})}>Add</button>
  </div>

  {#if finished.length && segments > 1}
    <div class="prog" class:cleared role="img" transition:slide={flow()} aria-label="{finished.length} of {segments} done">
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
          <div use:longpress={() => offer(d.id)} class="ri {mark?.tier ?? ''}" class:fresh={!!mark} class:lift={mark?.lifted} out:send={{ key: d.id }} in:receive={{ key: d.id }}>
          <button class="check" class:on={!!mark} onpointerdown={() => sfx.press()} onclick={(e) => done(d, e.currentTarget)} aria-label="Mark {d.title} done"><i></i><span aria-hidden="true">Done</span></button>
          <button class="row" onclick={() => open(d)} aria-label="{d.title}, {d.subject ?? d.course ?? 'no subject'}, due {word}">
            <span class="when" class:late={word === "Overdue"}>{word}</span>
            <span class="what"><strong>{d.title}</strong><small>{d.subject ?? d.course ?? "Your own"}</small></span>
          </button>
          {#if offered === d.id && !mark}
            <button class="offer" onclick={(e) => { offered = null; const b = e.currentTarget.closest("li")?.querySelector<HTMLElement>(".check"); if (b) done(d, b); }}>Mark done</button>
          {/if}
          {#if mark?.combo}<span class="combo" aria-hidden="true">{mark.combo}</span>{/if}
          {#if mark}<span class="stamp" aria-hidden="true">DONE</span>{/if}
          </div>
        </li>
      {/each}
    </ul>
    {#if list.length > MAX || all}
      <button class="all" onclick={() => (all = !all)}>{all ? "Show less" : "All deadlines"}</button>
    {/if}
  {:else if cleared}
    <p class="none clear" in:slide={flow()}><span class="hop"><Lar size={2} state="happy" gesture="thumbs" cube={false} /></span> All clear for this week.</p>
  {:else if knowsNothingDue(app.snapshot?.last_synced, mabini, app.mabini?.last_synced, now) && !finished.length}
    <p class="none"><b>LAR</b> Walang due this week. Ayos!</p>
  {:else if !finished.length}
    <p class="none">Nothing due that we know of yet.</p>
  {/if}

  {#if quick.length}
    <ul>
      {#each quick as { entry: d } (d.id)}
        <li animate:flip={flow()} in:slide={flow()} out:slide={flow()}>
          <div class="ri finished" in:receive={{ key: d.id }} out:send={{ key: d.id }}>
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
  /* The box: empty, then filled in three steps. */
  /* On the left, clear of the floating cube, and it says what it does (#220). */
  .check {
    flex: none;
    display: grid;
    place-items: center;
    align-content: center;
    gap: 2px;
    padding: 0;
    background: none;
    box-shadow: none;
    font-size: min(0.647rem, 20px);
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
    animation: fill 0.22s cubic-bezier(0.34, 1.56, 0.64, 1) backwards;
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
    animation: strike 0.2s var(--ease) 0.06s backwards;
  }
  @keyframes strike {
    from { transform: scaleX(0); }
  }
  .ri.nudge {
    animation: nudge 0.42s var(--ease) both;
  }
  .ri.shake {
    animation: shake 0.36s ease-out both 0.2s;
  }
  .ri.hard {
    animation: hard 0.42s ease-out both 0.2s;
  }
  .ri {
    transition: scale 0.2s var(--ease);
  }
  .ri.lift {
    z-index: 3;
    scale: 1.02;
  }
  @keyframes nudge {
    35% { translate: 6px 0; }
  }
  @keyframes shake {
    20% { translate: 4px 0; }
    40% { translate: -3px 0; }
    60% { translate: 2px 0; }
    80% { translate: -1px 0; }
  }
  @keyframes hard {
    15% { translate: 6px -1px; rotate: 0.8deg; }
    35% { translate: -5px 0; rotate: -0.8deg; }
    55% { translate: 3px 0; rotate: 0.4deg; }
    75% { translate: -2px 0; }
  }
  .stamp {
    position: absolute;
    right: 4px;
    top: 50%;
    translate: 0 -50%;
    rotate: -7deg;
    padding: 1px 6px;
    font: 700 min(0.706rem, 22px) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--good);
    background: var(--card);
    box-shadow: inset 0 0 0 2px var(--good);
    pointer-events: none;
    animation: thunk 0.36s cubic-bezier(0.22, 1, 0.36, 1) both 0.2s;
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
  .combo {
    position: absolute;
    right: 60px;
    top: 50%;
    font: 700 min(0.765rem, 23px) var(--font-pixel);
    color: var(--gold);
    pointer-events: none;
    animation: combo 0.8s ease-out both 0.08s;
  }
  @keyframes combo {
    0% { opacity: 0; translate: 0 -40%; }
    25% { opacity: 1; translate: 0 -130%; }
    75% { opacity: 1; translate: 0 -170%; }
    100% { opacity: 0; translate: 0 -190%; }
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
    animation: seg 0.3s var(--ease) backwards;
  }
  .prog.cleared i {
    animation: flash 0.6s ease-in-out both;
  }
  .prog span {
    margin-left: 4px;
    font-size: min(0.647rem, 20px);
    color: var(--ink-2);
  }
  @keyframes seg {
    from { scale: 1 2.6; }
  }
  @keyframes flash {
    0%, 50% { background: var(--ink); }
    25%, 75%, 100% { background: var(--gold); }
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
    animation: thunk 0.2s var(--ease) both;
  }
  .week {
    justify-self: start;
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink-3);
    font-size: min(0.706rem, 22px);
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
  .hop {
    display: inline-block;
    animation: hop 0.5s var(--ease) both;
  }
  @keyframes hop {
    40% { translate: 0 -8px; }
    70% { translate: 0 -2px; }
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
  .check {
    background: none;
    box-shadow: none;
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

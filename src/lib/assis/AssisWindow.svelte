<script lang="ts" module>
  /**
   * Where the crystal chip is while LAR's window is about (046 C1d): `here` on the page; `hidden`
   * asleep, drawing nothing, while the window is open.
   */
  export const chip = $state({ at: "here" as "here" | "hidden" });
</script>

<script lang="ts">
  // LAR's window. The chat box is the crystal itself (round three C2), and round four (spec 048) sets
  // the rest: it dithers open out of the chip, a sky header of one fixed size with LAR standing on its
  // dithered edge, his real steps as a pixel trace that folds once he answers, sources lit in pixel
  // corners, and one row of suggestions over the input. Reduce Motion cross-fades.
  // Ported from reference/prototypes/lar-chat/.
  import { onMount, tick, untrack } from "svelte";
  import { closable } from "../back";
  import { visualViewport } from "../viewport.svelte";
  import { buzz } from "../haptics";
  import Lar, { larTheme, type Gesture } from "../lar/Lar.svelte";
  import { SPAWN_SECS, type State } from "../lar/sprite";
  import { activeTheme, app, openDeck, openNote, openSubject } from "../state.svelte";
  import { skyLook } from "../theme";
  import { sourceTarget } from "./sources";
  import { dayLabel, describe, doneWord, folded, isChange, lineDiff, marked, noteLines, pickCaption, followUps, starters as startersFor, whenLabel, type Day, type Suggestion } from "./apply";
  import { tidy } from "./cards";
  import { doing, rows, summary } from "./trace";
  import { api, clock, moment, subjectColor, type DeadlineEntry, type Slot } from "../api";

  type Rect = { x: number; y: number; w: number; h: number };
  import { invoke } from "@tauri-apps/api/core";
  import { cancelDither, runDither } from "./dither-draw";
  import { MORE_MAX, apply, ask, assis, confirmCards, discardCards, dismiss, keepGoing, newChat, pickItem, pickNote, stop, undoChange } from "./assis.svelte";

  let { onclose }: { onclose: () => void } = $props();
  // Android's back gesture and Escape close it; the effect's return unregisters it.
  $effect(() => closable(() => close()));

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // The low-RAM tier keeps the sky still while the model wakes or thinks (048 C8, #189); true until it answers.
  let smallRam = $state(true);
  invoke<boolean>("ai_small_ram").then((small) => (smallRam = small)).catch(() => {});
  const vv = visualViewport();
  // LAR wears the school's colours (or his LAR colour); the sky behind him follows the worn theme (063 C14).
  const theme = larTheme();
  const sky = skyLook(activeTheme(), theme);
  /** A reply's words and the spaces between them; each word is its own box so it can rise in (063 C13). */
  const wordsOf = (text: string) => text.match(/\s+|\S+/g) ?? [];
  const HELLO = "Hi! Ask me about your classes, what's due, your grades, or what's in your notes. I can also save a note or set a reminder, if you say so.";
  const CPS = 45;

  let draft = $state("");
  let log: HTMLElement | undefined = $state();
  // The day, for the first suggestions (spec 048 C17); the nearest due is asked for once, on open.
  let due = $state<DeadlineEntry | null>(null);
  api.deadlines(moment(), 8).then((d) => (due = d.find((e) => !e.overdue) ?? null)).catch(() => {});
  const myDay = $derived<Day>({ now: new Date(), due, note: [...app.notes].filter((n) => n.title).sort((a, b) => b.updated - a.updated)[0] ?? null, next: app.today?.next });
  /** Traces opened again after they folded, by message index. */
  let unfolded = $state<Record<number, boolean>>({});
  /** Change cards whose unchanged lines were opened, by message index. */
  let opened = $state<Record<number, boolean>>({});
  const colors = $derived(app.snapshot?.colors ?? {});
  const last = $derived(assis.chat[assis.chat.length - 1]);
  // Dots show from the moment a message is sent until the first word arrives.
  const waiting = $derived(assis.busy === "waking" || (assis.busy === "thinking" && !last?.text));
  const writing = $derived(assis.busy === "thinking");
  const thinking = $derived(assis.busy === "thinking" || assis.busy === "waking" || assis.busy === "cards");

  // ------------------------------------------------------------ his moment

  // fly: the glass is growing; spawn: the fire; here: he is in.
  let phase = $state<"fly" | "spawn" | "here">(reduce ? "here" : "fly");
  let leaving = $state(false);
  /** His spawn run backwards while he folds away: 1 to 0. */
  let fold = $state<number>();
  let typed = $state(reduce ? HELLO.length : 0);
  let waving = $state(false);
  let cheer = $state(false);
  let dozing = $state(false);

  const mood = $derived<State>(
    phase === "spawn" || fold !== undefined ? "spawn"
    : assis.error ? "error"
    : thinking ? "think"
    : cheer ? "happy"
    : dozing ? "sleep"
    : "idle",
  );
  const gesture = $derived<Gesture>(waving && mood === "idle" ? "wave" : "idle");
  /** One row over the input: the day's before the first message, then the last answer's (C16–C18). */
  const suggestions = $derived<Suggestion[]>(assis.busy ? [] : !assis.chat.length ? startersFor(!!app.editing, myDay) : followUps(assis.chat.findLast((m) => m.from === "lar") ?? {}, myDay, assis.chat.findLast((m) => m.from === "me")?.text));
  const status = $derived(
    assis.busy === "waking" ? (assis.slow ? "Still waking up. This phone is slow." : "Waking up") : assis.busy === "thinking" ? doing(last?.steps ?? [], last?.intent) : assis.busy === "cards" ? "Making cards" : dozing ? "Dozing. Ask me anything." : "On this phone, offline",
  );

  // ------------------------------------------------------------ the glass

  let win: HTMLElement;
  let scrim: HTMLElement;
  let inn: HTMLElement;
  let top: HTMLElement;
  let dock: HTMLElement;
  let input: HTMLInputElement;

  const css = getComputedStyle(document.documentElement);
  const gutter = parseFloat(css.getPropertyValue("--gutter")) || 16;
  const day = css.colorScheme === "light";
  /** Compact: at most 60% of the screen, as in the mockup. */
  const MAX = Math.round(innerHeight * 0.6);
  /**
   * LAR's scale in the header: about 2.4 pt a sprite pixel, rounded so one sprite pixel is a whole number
   * of screen pixels (7 on a 3x iPhone) and he stays sharp. The header is his 40 sprite px from the top of
   * his box to his feet, so his sleep Z, antenna and waving mitt always fit inside it (048 C9).
   */
  const dpr = Math.min(3, devicePixelRatio || 1);
  const LS = Math.floor(2.5 * dpr) / dpr;
  const orb = () => document.querySelector<HTMLElement>("[data-orb]");
  let safeTop = 0;

  /** The chip's place. Without it (the keyboard hides it), the corner it would sit in. */
  function chipRect(): Rect {
    const r = orb()?.getBoundingClientRect();
    if (r?.width) return { x: r.x, y: r.y, w: r.width, h: r.height };
    return { x: innerWidth - gutter - 48, y: vv.top + vv.h - 140, w: 48, h: 48 };
  }

  let open = $state(false);
  /** The dither is drawing the window: the real one is hidden until the swap frame. */
  let dithering = $state(false);
  let pc: HTMLCanvasElement;
  let need = $state(0);
  let home = $state<Rect>(chipRect());
  // The glass sits 2 px outside the chip and the gutter, its bottom on the chip's, and lifts with
  // the keyboard so the input stays in view; it grows upward with the chat, under the status bar.
  // With the keyboard up the chip is hidden and its fallback corner sits ~90 pt high, so the glass
  // rests on the keyboard instead (seen on the 18 Pro sim, 2026-11-09).
  const bottom = $derived(vv.keyboard ? vv.top + vv.h - 8 : Math.min(home.y + home.h + 2, vv.top + vv.h - 8));
  const room = $derived(bottom - (vv.top + safeTop + 8));
  const H = $derived(Math.min(room, Math.max(120, Math.min(need, MAX))));
  const width = $derived(home.x + home.w + 2 - (gutter - 2));
  const box = $derived<Rect>(open ? { x: gutter - 2, y: bottom - H, w: width, h: H } : home);

  const measure = () => (need = top.offsetHeight + inn.offsetHeight + dock.offsetHeight);

  const timers: ReturnType<typeof setTimeout>[] = [];
  const later = (ms: number, f: () => void) => timers.push(setTimeout(f, ms));

  function greet() {
    phase = "here";
    waving = true;
    later(1600, () => (waving = false));
    if (assis.chat.length) return void (typed = HELLO.length);
    const start = performance.now();
    const step = () => {
      typed = Math.min(HELLO.length, Math.floor(((performance.now() - start) / 1000) * CPS));
      if (typed < HELLO.length && !leaving) requestAnimationFrame(step);
    };
    requestAnimationFrame(step);
  }

  onMount(() => {
    safeTop = parseFloat(getComputedStyle(scrim).paddingTop) || 0;
    const watch = new ResizeObserver(measure);
    for (const el of [inn, top, dock]) watch.observe(el);
    measure();
    if (reduce) {
      open = true;
      chip.at = "hidden";
      win.focus({ preventScroll: true });
    } else {
      // The window takes its open box hidden, so the dither lands exactly on it (048 C1–C5).
      dithering = true;
      open = true;
      chip.at = "hidden";
      tick().then(() => {
        measure();
        return tick();
      }).then(() =>
        runDither({ canvas: pc, chip: home, win: box, tokens: win, headerH: top.offsetHeight, mode: "open" }).then(() => {
          dithering = false; // the swap frame: the real window, no cross-fade
          if (leaving) return;
          buzz.tick();
          phase = "spawn";
          win.focus({ preventScroll: true });
          later(SPAWN_SECS * 1000, greet);
        }).finally(() => (dithering = false)),
      );
    }
    return () => {
      timers.forEach(clearTimeout);
      cancelDither();
      watch.disconnect();
      chip.at = "here";
      const o = orb();
      if (o) o.style.opacity = "";
    };
  });

  function done() {
    onclose();
    orb()?.focus({ preventScroll: true });
  }

  function close() {
    if (leaving) return;
    leaving = true;
    input.blur();
    if (reduce) {
      open = false;
      chip.at = "here";
      later(200, done);
      return;
    }
    // He folds back into his fire, then the window dithers away into the chip.
    const folds = phase === "here";
    if (folds) {
      const t0 = performance.now();
      const step = () => {
        fold = Math.max(0, 1 - (performance.now() - t0) / 500);
        if (fold > 0) requestAnimationFrame(step);
      };
      fold = 1;
      requestAnimationFrame(step);
    }
    // Then the dither plays backwards into the chip, outer cells first (048 C6).
    later(folds ? 300 : 0, () => {
      const from = box;
      home = chipRect();
      dithering = true;
      runDither({ canvas: pc, chip: home, win: from, tokens: win, headerH: top.offsetHeight, mode: "close", onLast: () => (chip.at = "here") }) // as the last cells go
        .then(() => {
          open = false;
          done();
        })
        .finally(() => {
          dithering = false;
          chip.at = "here";
        });
    });
  }

  // He cheers when an answer lands, and dozes after a quiet minute.
  let was = assis.busy;
  $effect(() => {
    const now = assis.busy;
    if (was === "thinking" && !now && last?.text) {
      cheer = true;
      later(1400, () => (cheer = false));
    }
    was = now;
  });
  $effect(() => {
    void assis.chat.length;
    void assis.busy;
    void draft;
    dozing = false;
    const t = setTimeout(() => (dozing = true), 60_000);
    return () => clearTimeout(t);
  });

  // ------------------------------------------------------------ where an answer came from

  // An answer with sources lights its From chips, and its card on the page when that is on screen, in
  // pixel corners for 1.4 s (spec 048 C15). Nothing else is drawn outside the glass.
  let lit = assis.busy;
  $effect(() => {
    const now = assis.busy;
    untrack(() => {
      const answer = last;
      if (lit === "thinking" && !now && answer?.from === "lar" && answer.sources?.length) {
        const keys = answer.sources.map((s) => s.key);
        tick().then(() => {
          if (leaving) return;
          const chips = [...([...inn.querySelectorAll(".from")].at(-1)?.children ?? [])] as HTMLElement[];
          const page = [...document.querySelectorAll<HTMLElement>("[data-source]")].filter((e) => keys.includes(e.dataset.source ?? "") && !win.contains(e));
          chips.concat(page).forEach((el, i) => later(i * 90, () => light(el)));
        });
      }
    });
    lit = now;
  });
  function light(el: HTMLElement) {
    el.classList.remove("hit");
    void el.offsetWidth; // restart the corners
    el.classList.add("hit");
    later(1500, () => el.classList.remove("hit"));
  }

  // ------------------------------------------------------------- the chat

  async function send(text: string) {
    draft = "";
    buzz.select();
    const sending = ask(text);
    await tick();
    log?.scrollTo({ top: log.scrollHeight });
    await land(sending);
  }

  /** Once a reply lands, scroll to its end, but never past the top of a card it brought (063 C1: a card opens at its title). */
  async function land(reply?: Promise<unknown>) {
    await reply;
    await tick();
    if (!log) return;
    const card = last?.proposal ? [...inn.querySelectorAll<HTMLElement>(".offer, .rows")].at(-1) : undefined;
    const top = card ? log.scrollTop + card.getBoundingClientRect().top - log.getBoundingClientRect().top - 8 : Infinity;
    log.scrollTo({ top: Math.min(top, log.scrollHeight), behavior: "smooth" });
  }

  /** Apply on a card. "Add a class" opens the class editor, which sits under the chat, so the chat closes (064 C10). */
  async function applyCard(i: number) {
    await apply(i);
    const m = assis.chat[i];
    if (m.proposal?.kind === "new_class" && m.state === "done") onclose();
  }

  /** "Fri 9:00 AM–10:30 AM", where a class meets. */
  const slotLabel = (s: Slot) => `${s.day.slice(0, 3)} ${clock(s.start)}–${clock(s.end)}`;

  /** A suggestion opens its source, fills the field, or asks. */
  function pick(s: Suggestion) {
    if (s.open) show(s.open, s.label.replace(/^Open /, ""));
    else prefill(s);
  }

  function prefill(s: { label: string; fill: boolean; say?: string }) {
    // Starters that need the student's own words fill the field; the rest just ask.
    if (s.fill) draft = s.label;
    else send(s.say ?? s.label);
  }

  /** The window sits above the page, so a source chip closes it and shows the note, deck or subject. */
  function show(key: string, title: string) {
    onclose();
    const t = sourceTarget(key);
    if (t.kind === "deck") openDeck(t.id);
    else if (t.kind === "subject") openSubject(t.code, app.snapshot?.sessions.find((s) => s.subject_code === t.code)?.description ?? "");
    else openNote(key, title);
  }
</script>

<svelte:window onkeydown={(e) => e.key === "Escape" && close()} />

<div class="scrim" class:on={open} bind:this={scrim} role="presentation" onclick={close}></div>
<canvas class="dither" bind:this={pc} aria-hidden="true"></canvas>
<div
  class="win"
  class:open
  class:day
  class:reduce
  class:dithering
  bind:this={win}
  role="dialog"
  tabindex="-1"
  aria-modal="true"
  aria-label="Ask LAR"
  style:left="{box.x}px"
  style:top="{box.y}px"
  style:width="{box.w}px"
  style:height="{box.h}px"
  style:--accent={sky.accent}
  style:--ls="{LS}px"
  style:--r0={sky.ramp[0]}
  style:--r1={sky.ramp[1]}
  style:--r2={sky.ramp[2]}
  style:--r3={sky.ramp[3]}
  style:--r4={sky.ramp[4] ?? sky.accent}
>
  <div class="face">
    <!-- The content keeps its final layout and is revealed as the glass grows, so nothing reflows while it moves. -->
    <div class="body" style:width="{width}px" style:height="{H}px">
      <!-- Spec 048 C7–C11: the sky header, one fixed size; LAR stands on its dithered edge. -->
      <div class="hd" class:still={smallRam && thinking} bind:this={top}>
        <div class="sky" aria-hidden="true"><i></i><i></i><i></i><i></i><i></i><i></i></div>
        <div class="perch" aria-hidden="true">
          <div class="cv">{#if phase !== "fly" && fold !== 0}<Lar size={LS} fit cube={false} shadow={false} state={mood} k={fold} {gesture} {theme} />{/if}</div>
        </div>
        <div class="who">
          <span class="tag">LAR</span>
          <span class="status" class:busy={!!assis.busy} aria-live="polite">{status}{#if assis.busy}<i></i><i></i><i></i>{/if}</span>
        </div>
        <div class="keys">
          {#if assis.chat.length && !assis.busy}
            <button class="key" aria-label="New chat" onclick={newChat}><span class="cap"><svg width="14" height="14" viewBox="0 0 7 7" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M3 0h1v3h3v1H4v3H3V4H0V3h3z" /></svg></span></button>
          {/if}
          <button class="key" aria-label="Close" onclick={close}><span class="cap"><svg width="14" height="14" viewBox="0 0 7 7" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M0 0h1v1H0zM1 1h1v1H1zM2 2h1v1H2zM3 3h1v1H3zM4 4h1v1H4zM5 5h1v1H5zM6 6h1v1H6zM6 0h1v1H6zM5 1h1v1H5zM4 2h1v1H4zM2 4h1v1H2zM1 5h1v1H1zM0 6h1v1H0z" /></svg></span></button>
        </div>
      </div>

      <div class="log" bind:this={log} aria-live="polite">
        <div class="in" bind:this={inn}>
          {#if !assis.chat.length}
            <div class="lar hello">
              <span class="sr">{HELLO}</span>
              <p aria-hidden="true">{HELLO.slice(0, typed)}<i class="caret" class:done={typed >= HELLO.length}></i><span class="rest">{HELLO.slice(typed)}</span></p>
            </div>
          {/if}
          {#each assis.chat as m, i (i)}
            {#if m.from === "me"}
              <p class="me">{m.text}</p>
            {:else}
              {#if m.steps?.length}
                {@const live = i === assis.chat.length - 1 && !!assis.busy}
                {#if !live}
                  <button class="sum" aria-expanded={!!unfolded[i]} onclick={() => (unfolded[i] = !unfolded[i])}><i class="node done" aria-hidden="true"></i><span>{summary(m.steps, m.intent)}</span><svg class="chev" width="8" height="10" viewBox="0 0 4 5" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M0 0h1v1H0zM1 1h1v1H1zM2 2h1v1H2zM1 3h1v1H1zM0 4h1v1H0z" /></svg></button>
                {/if}
                {#if live || unfolded[i]}
                  <ul class="trail" aria-label="What LAR did">
                    {#each rows(m.steps, m.intent, live) as r, k (k)}
                      <li class="step" class:done={r.done}>
                        <i class="node" aria-hidden="true"></i><span>{r.text}</span>
                        {#if r.found}
                          <div class="found">
                            <div class="notes">{#each r.found as f (f.key)}<button class="note" onclick={() => show(f.key, f.title)}>{f.title}</button>{/each}</div>
                            {#if r.quote}<p class="quote">“{r.quote}”</p>{/if}
                          </div>
                        {/if}
                      </li>
                    {/each}
                  </ul>
                {/if}
              {/if}
              {#if m.text}
                <!-- 063 C13: words written while he answers rise in; words already there never move. -->
                {@const live = writing && i === assis.chat.length - 1}
                <div class="lar"><span class="sr">{m.text}</span><p aria-hidden="true">{#each wordsOf(m.text) as w, k (k)}{#if w.trim()}<span class="t" class:w={live}>{w}</span>{:else}{w}{/if}{/each}</p></div>
              {/if}
              {#if m.cut && (m.more ?? 0) < MORE_MAX && assis.chat.findLastIndex((x) => x.from === "lar") === i}<button class="no more" onclick={() => keepGoing(i)} disabled={!!assis.busy}>Keep going</button>{/if}
              {#if m.known}<p class="known"><b>From what I know, not your notes.</b> I might get facts wrong, so double-check anything important.</p>{/if}
              {#if m.sources}
                <div class="chips from">
                  {#each m.sources as src (src.key)}<button class="chip" onclick={() => show(src.key, src.title)}>From: {src.title}</button>{/each}
                </div>
              {/if}
              {#if m.proposal?.kind === "pick_note"}
                <!-- 063 C6: one full-width row per note; a tap marks it and asks again. -->
                <ul class="rows" aria-label="Notes">
                  {#each m.proposal.candidates as c (c.key)}
                    {@const cap = pickCaption(c)}
                    <li>
                      <button class="nrow" class:on={m.picked === c.key} aria-pressed={m.picked === c.key} aria-label={cap ? `${c.name}, ${cap}` : c.name} onclick={() => land(pickNote(i, c.key))} disabled={m.state !== "pending" || !!assis.busy}>
                        <b>{c.name}</b>{#if cap}<small>{cap}</small>{/if}
                        <svg width="8" height="10" viewBox="0 0 4 5" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M0 0h1v1H0zM1 1h1v1H1zM2 2h1v1H2zM1 3h1v1H1zM0 4h1v1H0z" /></svg>
                      </button>
                    </li>
                  {/each}
                </ul>
                {#if m.problem}<p class="problem">{m.problem}</p>{/if}
              {:else if m.proposal?.kind === "pick_item"}
                <!-- 064 C12: the same rows for deadlines, classes and reminders; each says which it is. -->
                <ul class="rows" aria-label="Which one">
                  {#each m.proposal.candidates as c (c.id)}
                    {@const kind = c.item[0].toUpperCase() + c.item.slice(1)}
                    <li>
                      <button class="nrow" class:on={m.picked === c.id} aria-pressed={m.picked === c.id} aria-label="{c.name}, {kind}" onclick={() => land(pickItem(i, c.id))} disabled={m.state !== "pending" || !!assis.busy}>
                        <b>{c.name}</b><small>{kind}</small>
                        <svg width="8" height="10" viewBox="0 0 4 5" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M0 0h1v1H0zM1 1h1v1H1zM2 2h1v1H2zM1 3h1v1H1zM0 4h1v1H0z" /></svg>
                      </button>
                    </li>
                  {/each}
                </ul>
              {:else if m.proposal}
                {@const d = describe(m.proposal)}
                {@const changes = m.proposal.kind === "edit_note" || m.proposal.kind === "rename_note" || m.proposal.kind === "move_note" || m.proposal.kind === "delete_note" || isChange(m.proposal) ? m.proposal.kind : null}
                <div class="offer" class:done={m.state === "done"}>
                  <!-- 063 C5: once applied, this part dims and the line under it stays clear. -->
                  <div class="gist">
                    <div class="head">
                      <p class="label">{d.label}</p>
                      {#if (m.proposal.kind === "save_note" || m.proposal.kind === "add_deadline") && m.proposal.subject}<span class="subj" style:--sc={subjectColor(m.proposal.subject, colors)}>{m.proposal.subject}</span>{/if}
                    </div>
                    {#if m.proposal.kind === "save_note" && m.editing && m.state === "pending"}
                      <!-- 063 C2: two fields, filled with the note. -->
                      <label class="lbl" for="ttl{i}">Title</label>
                      <input id="ttl{i}" class="ed" bind:value={m.proposal.title} />
                      <label class="lbl" for="txt{i}">Note</label>
                      <textarea id="txt{i}" class="ed body" rows={m.proposal.text.split("\n").length + 2} bind:value={m.proposal.text}></textarea>
                    {:else if m.proposal.kind === "save_note"}
                      <!-- 063 C1: the title first, the points as the note editor draws them. -->
                      <p class="ttl">{m.proposal.title}</p>
                      {#if m.proposal.partial}<p class="fine">Made from the last part of our chat</p>{/if}
                      <ul class="pts">
                        {#each noteLines(m.proposal.text) as l, k (k)}{#if l.text}<li class:plain={!l.bullet}>{l.text}</li>{/if}{/each}
                      </ul>
                    {:else if m.proposal.kind === "edit_note"}
                      <!-- 063 C3: word marks inside a changed line; long unchanged runs fold. -->
                      {@const all = marked(lineDiff(m.proposal.before, m.proposal.after))}
                      <ul class="diff" aria-label="Changes to {m.proposal.name}">
                        {#each opened[i] ? all : folded(all) as l, k (k)}
                          {#if l.kind === "fold"}
                            <li class="fold"><button onclick={() => (opened[i] = true)}>{l.n} lines unchanged</button></li>
                          {:else if l.kind === "change"}
                            <li><i aria-hidden="true"></i><span>{#each l.words as w, j (j)}{j ? " " : ""}{#if w.kind === "del"}<s><span class="sr">Removed: </span>{w.text}</s>{:else if w.kind === "add"}<mark><span class="sr">Added: </span>{w.text}</mark>{:else}{w.text}{/if}{/each}</span></li>
                          {:else if l.kind === "del"}
                            <li class="del"><svg width="9" height="9" viewBox="0 0 3 3" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M0 1h3v1H0z" /></svg><s><span class="sr">Removed: </span>{l.text || " "}</s></li>
                          {:else if l.kind === "add"}
                            <li class="add"><svg width="9" height="9" viewBox="0 0 3 3" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M1 0h1v1h1v1H2v1H1V2H0V1h1z" /></svg><mark><span class="sr">Added: </span>{l.text || " "}</mark></li>
                          {:else}
                            <li class="same"><i aria-hidden="true"></i><span>{l.text || " "}</span></li>
                          {/if}
                        {/each}
                      </ul>
                    {:else if m.proposal.kind === "rename_note"}
                      <!-- 063 C4: old over new. -->
                      <div class="swap">
                        <s class="o"><span class="sr">Removed: </span>{m.proposal.name}</s>
                        <p class="n"><span class="sr">Added: </span>{m.proposal.title}</p>
                      </div>
                    {:else if m.proposal.kind === "move_note"}
                      <p class="ttl">{m.proposal.name}</p>
                      <div class="move">
                        {#if m.proposal.from}<s class="subj old" style:--sc={subjectColor(m.proposal.from, colors)}><span class="sr">Removed: </span>{m.proposal.from}</s><svg width="14" height="10" viewBox="0 0 7 5" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M0 2h5v1H0zM4 0h1v1H4zM5 1h1v1H5zM6 2h1v1H6zM5 3h1v1H5zM4 4h1v1H4z" /></svg>{/if}
                        <span class="subj new" style:--sc={subjectColor(m.proposal.subject, colors)}><span class="sr">Added: </span>{m.proposal.subject}</span>
                      </div>
                    {:else if m.proposal.kind === "delete_note"}
                      <p class="ttl">{m.proposal.name}</p>
                      <p class="peek">{m.proposal.preview}</p>
                    {:else if m.proposal.kind === "add_deadline"}
                      <!-- Spec 064: the week's cards, in 063's looks. -->
                      <p class="ttl">{m.proposal.title}</p>
                      <p class="fine">Due {dayLabel(m.proposal.date)}</p>
                    {:else if m.proposal.kind === "change_deadline" && m.proposal.date === m.proposal.was}
                      <div class="swap">
                        <s class="o"><span class="sr">Removed: </span>{m.proposal.name}</s>
                        <p class="n"><span class="sr">Added: </span>{m.proposal.title}</p>
                      </div>
                    {:else if m.proposal.kind === "change_deadline" || m.proposal.kind === "move_reminder"}
                      <p class="ttl">{m.proposal.kind === "move_reminder" ? m.proposal.text : m.proposal.name}</p>
                      <div class="swap">
                        <s class="o"><span class="sr">Removed: </span>{dayLabel(m.proposal.was)}</s>
                        <p class="n"><span class="sr">Added: </span>{dayLabel(m.proposal.date)}</p>
                      </div>
                    {:else if m.proposal.kind === "done_deadline"}
                      <p class="ttl check">
                        <svg width="14" height="12" viewBox="0 0 7 6" shape-rendering="crispEdges" fill="currentColor" aria-hidden="true"><path d="M6 0h1v1H6zM5 1h1v1H5zM4 2h1v1H4zM3 3h1v1H3zM2 4h1v1H2zM1 3h1v1H1zM0 2h1v1H0z" /></svg>
                        <span><span class="sr">Done: </span>{m.proposal.name}</span>
                      </p>
                    {:else if m.proposal.kind === "delete_deadline"}
                      <p class="ttl">{m.proposal.name}</p>
                      <p class="fine">Due {dayLabel(m.proposal.date)}</p>
                    {:else if m.proposal.kind === "mark_class" || m.proposal.kind === "move_class"}
                      <p class="ttl">{m.proposal.name}</p>
                      {#if m.proposal.kind === "move_class"}
                        <div class="swap">
                          <s class="o"><span class="sr">Removed: </span>{slotLabel(m.proposal.was)}</s>
                          <p class="n"><span class="sr">Added: </span>{slotLabel(m.proposal.slot)}</p>
                        </div>
                      {/if}
                      <p class="when"><span aria-hidden="true">{whenLabel(m.proposal.week)}</span><span class="sr">{whenLabel(m.proposal.week, true)}</span></p>
                    {:else if m.proposal.kind === "change_own_class"}
                      {@const was = m.proposal.was}
                      {@const now = m.proposal.class}
                      <p class="ttl">{was.name}</p>
                      {#each [["Name", was.name, now.name], ["Room", was.room, now.room], ["Teacher", was.teacher, now.teacher]].filter(([, a, b]) => a !== b) as [field, a, b] (field)}
                        <div class="swap">
                          <s class="o"><span class="sr">Removed: </span>{field} {a || "none"}</s>
                          <p class="n"><span class="sr">Added: </span>{field} {b}</p>
                        </div>
                      {/each}
                    {:else if m.proposal.kind === "delete_own_class"}
                      <p class="ttl">{m.proposal.name}</p>
                    {:else if m.proposal.kind === "new_class"}
                      <p class="ttl">{m.proposal.name || "A new class"}</p>
                      {#if m.proposal.day || m.proposal.start != null}<p class="fine">{[m.proposal.day, m.proposal.start != null ? clock(m.proposal.start) : ""].filter(Boolean).join(" ")}</p>{/if}
                    {:else if m.proposal.kind === "delete_reminder"}
                      <p class="ttl">{m.proposal.text}</p>
                    {:else}
                      <p class="what">{d.text}</p>
                    {/if}
                  </div>
                  {#if m.state === "pending" && m.cards}
                    <p class="fine">Edit or remove any card. Nothing is saved until you tap the gold button.</p>
                    <ul class="cards">
                      {#each m.cards as c, k (k)}
                        <li>
                          <span>
                            <input class="ed" bind:value={c.front} aria-label="Front of card {k + 1}" />
                            <input class="ed" bind:value={c.back} aria-label="Back of card {k + 1}" />
                          </span>
                          <button class="rm" aria-label="Remove card {k + 1}" onclick={() => m.cards?.splice(k, 1)}>×</button>
                        </li>
                      {/each}
                    </ul>
                    {@const n = tidy(m.cards, []).length}
                    <div class="two">
                      <button class="yes" onclick={() => confirmCards(i)} disabled={!n}>Add {n} {n === 1 ? "card" : "cards"}</button>
                      <button class="no" onclick={() => discardCards(i)}>Discard</button>
                    </div>
                  {:else if m.state === "pending"}
                    <div class="two stick">
                      <button class="yes" class:danger={m.proposal.kind.startsWith("delete_")} onclick={() => applyCard(i)} disabled={assis.busy === "cards"}>{assis.busy === "cards" ? "Making…" : d.yes}</button>
                      {#if m.proposal.kind === "save_note"}
                        <button class="no" onclick={() => (m.editing = !m.editing)}>{m.editing ? "Done" : "Edit"}</button>
                      {:else}
                        <button class="no" onclick={() => dismiss(i)}>{m.proposal.kind.endsWith("_note") || changes || m.proposal.kind === "new_class" ? "Cancel" : "Not now"}</button>
                      {/if}
                    </div>
                  {:else if m.state === "done" && changes}
                    <div class="after">
                      {#if m.undo}
                        <p class="ok">{doneWord(changes)}</p>
                        <button class="no" onclick={() => undoChange(i)}>Undo</button>
                      {:else if m.undone}
                        <p class="fine">Put back</p>
                      {:else if m.notice}
                        <p class="fine">{m.notice}</p>
                      {:else}
                        <p class="ok">{doneWord(changes)}</p>
                      {/if}
                    </div>
                    {#if m.undo && m.notice}<p class="fine">{m.notice}</p>{/if}
                  {:else if m.state === "done" && m.saved}
                    {@const key = m.saved}
                    {@const title = m.proposal.kind === "save_note" ? m.proposal.title : ""}
                    <div class="after">
                      <p class="ok">Saved</p>
                      <button class="tbtn" onclick={() => show(key, title)}>Open note</button>
                    </div>
                  {:else if m.state === "done" && m.notice}
                    <p class="problem">{m.notice}</p>
                  {:else if m.state === "done"}
                    <p class="ok">Done</p>
                  {:else}
                    <p class="fine">Skipped</p>
                  {/if}
                  {#if m.problem}<p class="problem">{m.problem}</p>{/if}
                </div>
              {/if}
            {/if}
          {/each}
          {#if waiting && !last?.steps?.length}
            <div class="lar wait" aria-label="LAR is thinking"><p class="think"><i></i><i></i><i></i></p></div>
          {/if}
        </div>
      </div>

      <div class="dock" bind:this={dock}>
        {#if suggestions.length}
          <div class="sug" role="group" aria-label="Suggestions">
            {#each suggestions as sg, k (sg.label)}<button class="chip" style:--i={k} onclick={() => pick(sg)}>{sg.label}{#if sg.why}<span class="why">{sg.why}</span>{/if}</button>{/each}
          </div>
        {/if}
        <form onsubmit={(e) => { e.preventDefault(); send(draft); }}>
          <label class="well">
            <input bind:this={input} bind:value={draft} placeholder="Ask LAR…" aria-label="Message LAR" enterkeyhint="send" autocomplete="off" />
          </label>
          {#if writing}
            <button class="send" type="button" onclick={stop}>Stop</button>
          {:else}
            <button class="send" type="submit" disabled={!draft.trim() || !!assis.busy}>Send</button>
          {/if}
        </form>
      </div>
    </div>
  </div>
</div>

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    padding-top: var(--safe-top);
    background: rgb(6 3 8 / 0.32);
    opacity: 0;
    transition: opacity var(--t-flow) var(--ease);
  }
  .scrim.on {
    opacity: 1;
  }
  .dither {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    z-index: 62;
    pointer-events: none;
  }
  /* The glass (048 C19): one face in room tokens, a lit top and left edge, a gold rim on the right and
     a 2 pt pixel extrusion to the lower right. */
  .win {
    --g-a: color-mix(in srgb, var(--card), var(--ink) 8%);
    --g-b: color-mix(in srgb, var(--card), var(--ground) 45%);
    --g-rim: color-mix(in srgb, var(--gold) 42%, transparent);
    --g-hi: rgb(168 134 210 / 0.42);
    --g-lo: rgb(0 0 0 / 0.5);
    --g-sheen: rgb(255 236 214 / 0.07);
    --g-ext: rgb(0 0 0 / 0.45);
    --cut: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    --slab: polygon(0 6px, 3px 6px, 3px 3px, 6px 3px, 6px 0, calc(100% - 6px) 0, calc(100% - 6px) 3px, calc(100% - 3px) 3px, calc(100% - 3px) 6px, 100% 6px, 100% calc(100% - 6px), calc(100% - 3px) calc(100% - 6px), calc(100% - 3px) calc(100% - 3px), calc(100% - 6px) calc(100% - 3px), calc(100% - 6px) 100%, 6px 100%, 6px calc(100% - 3px), 3px calc(100% - 3px), 3px calc(100% - 6px), 0 calc(100% - 6px));
    position: fixed;
    z-index: 61;
    color: var(--ink);
    font-family: var(--font-ui);
    opacity: 0;
    /* It grows up with the chat. Opacity is instant: the dither covers the swap, so there is no cross-fade. */
    transition:
      top var(--t-flow) var(--ease),
      height var(--t-flow) var(--ease);
  }
  .win.open {
    opacity: 1;
  }
  .win:focus {
    outline: none;
  }
  /* Hidden under the dither, and laid out once: no eased top or height while it draws (048 Motion). */
  .win.dithering {
    opacity: 0;
    transition: none;
  }
  .win.reduce {
    transition: opacity var(--t-quick) linear;
  }
  .win.day {
    --g-hi: rgb(255 255 255 / 0.95);
    --g-lo: rgb(90 40 50 / 0.16);
    --g-sheen: rgb(255 255 255 / 0.7);
    --g-ext: rgb(90 40 50 / 0.22);
  }
  .face {
    position: absolute;
    inset: 0;
    overflow: hidden;
    background:
      linear-gradient(to bottom, var(--g-hi) 0 1px, transparent 1px),
      linear-gradient(to right, var(--g-hi) 0 1px, transparent 1px),
      linear-gradient(to left, var(--g-rim) 0 1px, transparent 1px),
      linear-gradient(165deg, var(--g-a), var(--g-b));
    box-shadow:
      2px 2px 0 var(--g-ext),
      0 14px 30px -12px rgb(0 0 0 / 0.6);
  }
  .body {
    position: absolute;
    right: 0;
    bottom: 0;
    display: flex;
    flex-direction: column;
  }

  /* ---- the sky header (048 C7–C11): one fixed size, LAR on its dithered edge ---- */
  .hd {
    position: relative;
    z-index: 1; /* over the log, so his feet can stand on the dither */
    flex: none;
    height: calc(var(--ls) * 40);
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 2px 10px 0 0;
    isolation: isolate;
    color: var(--cream);
  }
  .sky {
    position: absolute;
    inset: 0;
    z-index: -1;
    overflow: hidden;
    background: linear-gradient(172deg, var(--r0), var(--r1) 72%, var(--r0));
    box-shadow: inset 0 1px 0 rgb(255 236 214 / 0.2);
  }
  /* The pools of light are one oversized layer that drifts by transform: nothing repaints per frame. */
  .sky::before {
    content: "";
    position: absolute;
    inset: -40%;
    background:
      radial-gradient(30% 40% at 28% 72%, color-mix(in srgb, var(--r3) 70%, transparent), transparent 70%),
      radial-gradient(26% 40% at 76% 28%, color-mix(in srgb, var(--r4) 30%, transparent), transparent 70%),
      radial-gradient(40% 46% at 56% 86%, color-mix(in srgb, var(--r2) 80%, transparent), transparent 75%);
    animation: drift 16s ease-in-out infinite alternate;
    will-change: transform;
  }
  /* The split: a two-row pixel dither from the sky into the glass. */
  .sky::after {
    content: "";
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 6px;
    background: conic-gradient(var(--g-a) 25%, transparent 0 50%, var(--g-a) 0 75%, transparent 0) 0 0 / 6px 6px;
  }
  .sky i {
    position: absolute;
    width: 2px;
    height: 2px;
    background: var(--cream);
    animation: twinkle 2.6s steps(3, jump-none) infinite alternate;
  }
  .sky i:nth-child(1) { left: 44%; top: 14px; }
  .sky i:nth-child(2) { left: 56%; top: 30px; opacity: 0.6; animation-delay: -0.8s; }
  .sky i:nth-child(3) { left: 66%; top: 10px; animation-delay: -1.6s; }
  .sky i:nth-child(4) { left: 74%; top: 40px; opacity: 0.5; animation-delay: -0.4s; }
  .sky i:nth-child(5) { left: 50%; top: 22px; opacity: 0.7; animation-delay: -2s; }
  .sky i:nth-child(6) { left: 62%; top: 46px; opacity: 0.4; animation-delay: -1.2s; }
  /* On the low-RAM tier the sky holds still while the model wakes or thinks (#189). */
  .hd.still .sky::before,
  .hd.still .sky i,
  .hd.still .status::before {
    animation-play-state: paused;
  }
  /* LAR's box from its top to his feet, 48 sprite px wide: nothing of him is cut off (048 C9). */
  .perch {
    position: relative;
    flex: none;
    align-self: stretch;
    width: calc(var(--ls) * 48);
  }
  .cv {
    position: absolute;
    left: calc(var(--ls) * -3);
    top: 0;
  }
  .who {
    flex: 1;
    min-width: 0;
    display: grid;
    gap: 4px;
  }
  .tag {
    font: 600 var(--text-body) / 1 var(--font-pixel);
    letter-spacing: 0.12em;
    color: var(--cream);
    text-shadow: 0 2px 0 rgb(6 3 7 / 0.55);
  }
  .status {
    display: flex;
    align-items: center;
    gap: 6px;
    min-width: 0;
    height: 16px;
    font: 500 var(--text-caption) / 1 var(--font-ui);
    color: rgb(255 246 220 / 0.82);
    text-shadow: 0 1px 0 rgb(6 3 7 / 0.6);
    white-space: nowrap;
    overflow: hidden;
  }
  /* The live pixel: gold and still at rest, blinking while he works. */
  .status::before {
    content: "";
    flex: none;
    width: 6px;
    height: 6px;
    background: var(--r4);
    box-shadow:
      inset 0 2px 0 rgb(255 255 255 / 0.5),
      inset -2px 0 0 rgb(0 0 0 / 0.25);
  }
  .status.busy::before {
    animation: blink 0.8s steps(1, end) infinite;
  }
  .status i,
  .think i {
    display: inline-block;
    flex: none;
    width: 3px;
    height: 3px;
    background: currentColor;
    animation: blink 1s steps(2, jump-none) infinite;
  }
  .status i:nth-of-type(2),
  .think i:nth-of-type(2) {
    animation-delay: 0.2s;
  }
  .status i:nth-of-type(3),
  .think i:nth-of-type(3) {
    animation-delay: 0.4s;
  }
  .keys {
    flex: none;
    display: flex;
  }
  /* One pair of keys: 36 pt pixel-cut caps on 44 pt hit areas, icons on one 7 x 7 grid. */
  .key {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--cream);
  }
  .cap {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    background: rgb(6 3 8 / 0.34);
    clip-path: var(--cut);
    box-shadow:
      inset 0 1px 0 rgb(255 246 220 / 0.16),
      inset 0 -2px 0 rgb(0 0 0 / 0.32);
    transition: background var(--t-quick) var(--ease);
  }
  .cap svg {
    filter: drop-shadow(0 1px 0 rgb(6 3 7 / 0.5));
  }
  .key:active .cap {
    translate: 0 1px;
    background: rgb(6 3 8 / 0.5);
  }

  .log {
    position: relative;
    flex: 1;
    min-height: 0;
    overflow-y: auto;
    overscroll-behavior: contain;
    scrollbar-width: none;
  }
  .log::-webkit-scrollbar {
    display: none;
  }
  .in {
    display: grid;
    gap: 10px;
    align-content: start;
    padding: 2px 12px 10px;
  }
  /* His lines: the obsidian slab, its lit edge catching his portal's accent. */
  .lar {
    justify-self: start;
    max-width: 92%;
    padding: 10px 12px;
    background: var(--void-3);
    color: var(--parch);
    box-shadow:
      inset 0 2px 0 color-mix(in srgb, var(--accent) 45%, var(--slab-edge)),
      inset 0 -2px 0 var(--void-ink);
    clip-path: var(--slab);
    transform-origin: 0 0;
    animation: pop var(--t-move) var(--ease) both;
  }
  .lar p {
    margin: 0;
    font-size: var(--text-sub);
    line-height: 1.4;
    white-space: pre-line;
    overflow-wrap: anywhere;
  }
  .hello {
    position: relative;
  }
  /* Every word is a box, written or not, so a bubble never re-wraps when its words stop arriving. */
  .lar .t {
    display: inline-block;
    max-width: 100%;
  }
  /* 063 C13: a new word rises 4 px and fades in. Reduce Motion: the app's rule makes it just appear. */
  .lar .w {
    animation: rise var(--t-quick) var(--ease) both;
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  /* The not-yet-typed rest keeps its room, so the slab never changes size. */
  .rest {
    visibility: hidden;
  }
  .caret {
    display: inline-block;
    width: 2px;
    height: 1em;
    margin: 0 1px -0.15em;
    background: var(--portal-gold);
  }
  .caret.done {
    animation: blink 1s steps(2, jump-none) 3 both;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  .wait {
    padding: 12px 14px;
  }
  .think {
    color: var(--portal-gold);
  }
  .me {
    justify-self: end;
    max-width: 82%;
    margin: 0;
    padding: 9px 13px;
    border-radius: var(--radius-lg) var(--radius-lg) var(--radius-sm) var(--radius-lg);
    background: color-mix(in srgb, var(--ink) 8%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ink) 13%, transparent);
    font-size: var(--text-sub);
    line-height: 1.35;
    overflow-wrap: anywhere;
    animation: send var(--t-move) var(--ease) both;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  /* The answer came from LAR alone (spec 021 C16): the tag in the other side's voice (Pixel Voice Rule),
     the disclaimer in the reading face, since it is a sentence to take in. */
  .known {
    justify-self: start;
    max-width: 92%;
    margin: -2px 0 0 2px;
    font-size: var(--text-caption);
    line-height: 1.4;
    color: color-mix(in srgb, var(--parch) 60%, transparent);
  }
  .known b {
    display: block;
    font-family: var(--font-label);
    font-size: var(--text-label);
    font-weight: 500;
  }
  .chip {
    min-height: 44px;
    max-width: 100%;
    padding: 6px 12px;
    border: 0;
    border-radius: var(--radius);
    background: color-mix(in srgb, var(--card) 70%, transparent);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink);
    font: 400 var(--text-sub) / 1.3 var(--font-ui);
    text-align: left;
    overflow-wrap: anywhere;
    transition: background var(--t-quick) var(--ease);
    animation: send var(--t-move) calc(var(--i, 0) * 60ms) var(--ease) both;
  }
  .chip:active {
    background: color-mix(in srgb, var(--gold) 20%, var(--card));
  }
  .from .chip {
    font-size: var(--text-caption);
    color: var(--ink-2);
  }
  .offer {
    justify-self: start;
    width: 92%;
    display: grid;
    gap: 6px;
    padding: 12px;
    background: var(--void-lift);
    color: var(--parch);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 30%, transparent);
    clip-path: var(--slab);
    animation: pop var(--t-move) var(--ease) both;
  }
  .gist {
    display: grid;
    gap: 6px;
    min-width: 0;
    transition: opacity var(--t-quick) var(--ease);
  }
  /* 063 C5: an applied card stays where it was, dimmed; the line under it stays clear. */
  .offer.done .gist {
    opacity: 0.7;
  }
  .head {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 4px 8px;
  }
  .head .label {
    flex: 1;
  }
  /* A subject chip: the subject's colour as one square pixel, on a stepped chip. */
  .subj {
    flex: none;
    display: inline-flex;
    align-items: center;
    gap: 5px;
    max-width: 60%;
    padding: 3px 7px;
    font: 500 var(--text-label) / 1.2 var(--font-pixel);
    letter-spacing: 0.04em;
    color: var(--parch);
    text-decoration: none;
    background: rgb(255 246 220 / 0.07);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.14);
    clip-path: var(--cut);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .subj::before {
    content: "";
    flex: none;
    width: 6px;
    height: 6px;
    background: var(--sc);
  }
  .subj.old {
    color: rgb(255 246 220 / 0.55);
    text-decoration: line-through;
  }
  .subj.new {
    color: var(--portal-gold);
    box-shadow: inset 0 0 0 1px var(--portal-gold);
  }
  .ttl {
    margin: 0;
    font: 700 var(--text-headline) / 1.25 var(--font-display);
    letter-spacing: -0.01em;
    overflow-wrap: anywhere;
  }
  /* The points, drawn as the note editor draws them: a gold square, not a typed "- ". */
  .pts {
    display: grid;
    gap: 5px;
    margin: 2px 0 0;
    padding: 0;
    list-style: none;
    font-size: var(--text-sub);
    line-height: 1.4;
    overflow-wrap: anywhere;
  }
  .pts li {
    display: flex;
    gap: 8px;
  }
  .pts li:not(.plain)::before {
    content: "";
    flex: none;
    width: 6px;
    height: 6px;
    margin-top: 0.55em;
    background: var(--portal-gold);
  }
  .pts .plain {
    font-weight: 600;
  }
  .lbl {
    margin: 4px 0 -2px;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(255 246 220 / 0.6);
  }
  .label {
    margin: 0;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--accent);
  }
  .what {
    margin: 0;
    font-size: var(--text-body);
    line-height: 1.35;
    overflow-wrap: anywhere;
  }
  .two {
    display: grid;
    grid-template-columns: 1.3fr 1fr;
    gap: 8px;
    margin-top: 4px;
  }
  /* Save and Edit (and Apply) stay in reach while a long card scrolls past (063 C1). */
  .two.stick {
    position: sticky;
    bottom: 0;
    z-index: 1;
    margin: 4px -12px -12px;
    padding: 10px 12px 12px;
    background: linear-gradient(transparent, var(--void-lift) 12px);
  }
  .after {
    display: grid;
    grid-template-columns: 1fr 1fr;
    align-items: center;
    gap: 8px;
    min-height: 44px;
    margin-top: 4px;
  }
  .tbtn {
    justify-self: end;
    min-height: 44px;
    padding: 0 12px;
    border: 0;
    background: none;
    color: var(--portal-gold);
    font: 600 var(--text-sub) var(--font-ui);
    text-decoration: underline;
    text-underline-offset: 3px;
  }
  /* Gold pixel buttons: stepped corners and the gold lip. */
  .yes {
    height: 44px;
    border: 0;
    background: linear-gradient(180deg, var(--portal-gold-hi), var(--portal-gold) 60%);
    color: var(--on-portal-gold);
    font: 600 var(--text-sub) var(--font-ui);
    box-shadow: inset 0 -3px 0 var(--portal-gold-shade);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .yes:active:not(:disabled) {
    box-shadow: inset 0 3px 0 var(--portal-gold-shade);
    transform: translateY(1px);
  }
  /* Delete is the one red button (063 C4), so it never reads as the everyday gold. */
  .yes.danger {
    background: color-mix(in srgb, var(--rose) 16%, var(--void-lift));
    color: var(--rose);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--rose) 60%, transparent);
  }
  .yes.danger:active:not(:disabled) {
    background: color-mix(in srgb, var(--rose) 26%, var(--void-lift));
    box-shadow: inset 0 0 0 1px var(--rose);
  }
  .no {
    height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(255 246 220 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.14);
    color: var(--parch);
    font: 600 var(--text-sub) var(--font-ui);
  }
  button:disabled {
    opacity: 0.45;
  }
  .cards {
    list-style: none;
    margin: 0;
    padding: 0;
    display: grid;
    gap: 6px;
  }
  .cards li {
    display: flex;
    align-items: center;
    gap: 4px;
  }
  .cards span {
    display: grid;
    flex: 1;
    min-width: 0;
    gap: 6px;
  }
  .more {
    align-self: flex-start;
    margin-top: 6px;
  }
  .diff {
    display: grid;
    margin: 2px 0 0;
    padding: 6px 0;
    list-style: none;
    background: rgb(6 3 7 / 0.35);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.08);
    clip-path: var(--cut);
    font-size: var(--text-sub);
    line-height: 1.4;
  }
  .diff li {
    display: grid;
    grid-template-columns: 9px 1fr;
    gap: 7px;
    padding: 2px 10px 2px 8px;
    overflow-wrap: anywhere;
  }
  .diff li > svg {
    margin-top: 0.45em;
  }
  .diff .same {
    color: rgb(255 246 220 / 0.5);
  }
  .diff .del {
    color: rgb(255 246 220 / 0.6);
  }
  .diff .add {
    color: var(--portal-gold);
  }
  /* Words taken out are struck; words put in are gold (063 C3). */
  .diff s {
    color: rgb(255 246 220 / 0.55);
    text-decoration-color: rgb(255 246 220 / 0.6);
  }
  .diff mark {
    padding: 0 2px;
    background: rgb(245 178 39 / 0.18);
    color: var(--portal-gold);
    box-shadow: inset 0 -2px 0 var(--portal-gold);
  }
  .diff .fold {
    display: flex;
    align-items: center;
    gap: 4px;
    margin: -4px 0;
    padding: 0 8px;
  }
  .diff .fold button {
    min-height: 44px;
    padding: 0 8px;
    border: 0;
    background: none;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    color: rgb(255 246 220 / 0.55);
  }
  .diff .fold::before,
  .diff .fold::after {
    content: "";
    flex: 1;
    height: 2px;
    background: repeating-linear-gradient(90deg, rgb(255 246 220 / 0.25) 0 2px, transparent 2px 6px);
  }
  /* 064 C14: which meeting a class change reaches, "Fri, Dec 5 only" or "Every week". */
  .when {
    margin: 0;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--portal-gold);
  }
  .ttl.check {
    display: flex;
    align-items: center;
    gap: 8px;
  }
  .ttl.check svg {
    flex: none;
    color: var(--good);
  }
  /* Rename: the old name struck and dim, over the new one in gold (063 C4). */
  .swap {
    display: grid;
    gap: 2px;
  }
  .swap .o {
    font-size: var(--text-sub);
    color: rgb(255 246 220 / 0.55);
  }
  .swap .n {
    margin: 0;
    font: 700 var(--text-headline) / 1.25 var(--font-display);
    color: var(--portal-gold);
    overflow-wrap: anywhere;
  }
  .move {
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 8px;
  }
  .move svg {
    color: rgb(255 246 220 / 0.6);
  }
  /* Delete: the note's first lines, fading out under its name. */
  .peek {
    margin: 0;
    padding: 8px 10px;
    background: rgb(6 3 7 / 0.35);
    clip-path: var(--cut);
    font-size: var(--text-sub);
    line-height: 1.4;
    color: rgb(255 246 220 / 0.6);
    white-space: pre-line;
    overflow-wrap: anywhere;
    mask: linear-gradient(#000 55%, transparent);
  }
  /* 063 C6: which note, one full-width row each. */
  .rows {
    justify-self: stretch;
    display: grid;
    gap: 6px;
    margin: -2px 0 0;
    padding: 0;
    list-style: none;
  }
  .nrow {
    width: 100%;
    display: grid;
    grid-template-columns: 1fr auto;
    align-items: center;
    gap: 2px 8px;
    min-height: 56px;
    padding: 8px 12px;
    border: 0;
    text-align: left;
    background: var(--void-lift);
    color: var(--parch);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 30%, transparent);
    clip-path: var(--cut);
    animation: pop var(--t-move) var(--ease) both;
    transition: background var(--t-quick) var(--ease);
  }
  .nrow b {
    font: 600 var(--text-body) / 1.25 var(--font-ui);
    overflow-wrap: anywhere;
  }
  .nrow small {
    grid-column: 1;
    font-size: var(--text-caption);
    color: rgb(255 246 220 / 0.6);
  }
  .nrow svg {
    grid-row: 1 / 3;
    grid-column: 2;
    color: var(--accent);
  }
  .nrow:active:not(:disabled) {
    background: color-mix(in srgb, var(--portal-gold) 18%, var(--void-lift));
  }
  .nrow.on {
    box-shadow: inset 0 0 0 2px var(--portal-gold);
  }
  .nrow.on:disabled {
    opacity: 1;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
  }
  .ed.body {
    height: auto;
    padding: 10px 12px;
    resize: vertical;
  }
  .gist > .ed {
    width: 100%;
  }
  .ed {
    min-width: 0;
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: var(--radius);
    background: var(--void);
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    color: var(--white);
    font: 400 var(--text-input) var(--font-ui);
    caret-color: var(--portal-gold);
    outline: none;
  }
  .ed:focus {
    box-shadow: inset 0 0 0 1.5px var(--accent);
  }
  .rm {
    width: 44px;
    height: 44px;
    border: 0;
    background: none;
    color: rgb(255 246 220 / 0.55);
    font-size: var(--text-headline);
  }
  .ok,
  .fine {
    margin: 0;
    font-size: var(--text-caption);
    color: rgb(255 246 220 / 0.55);
  }
  .ok {
    color: var(--good);
    font-weight: 600;
  }
  .problem {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--rose);
  }

  /* ---- the dock: one row of suggestions over the input (048 C16) ---- */
  .dock {
    flex: none;
    display: grid;
    gap: 2px;
    padding: 0 8px 8px;
  }
  .sug {
    display: flex;
    gap: 6px;
    margin: 0 -8px;
    padding: 4px 12px;
    overflow-x: auto;
    scrollbar-width: none;
    mask: linear-gradient(to right, transparent, #000 12px, #000 calc(100% - 22px), transparent);
  }
  .sug::-webkit-scrollbar {
    display: none;
  }
  .sug .chip {
    flex: none;
    white-space: nowrap;
    min-height: 44px;
  }
  .why {
    margin-left: 6px;
    font-size: var(--text-label);
    color: var(--gold);
  }

  /* ---- the trace (048 C12–C14): a cube per real step, a line of whole pixels between them ---- */
  .trail {
    display: grid;
    margin: 0;
    padding: 2px 0 0 1px;
    list-style: none;
  }
  .step {
    position: relative;
    display: grid;
    grid-template-columns: 14px 1fr;
    column-gap: 9px;
    padding-bottom: 10px;
    font-size: var(--text-caption);
    line-height: 1.4;
    color: var(--ink-2);
    animation: send var(--t-move) var(--ease) both;
  }
  .step:last-child {
    padding-bottom: 2px;
  }
  .step.done > span {
    color: var(--ink);
  }
  .step:not(:last-child)::before {
    content: "";
    position: absolute;
    left: 5px;
    top: 13px;
    bottom: 1px;
    width: 2px;
    background: color-mix(in srgb, var(--gold) 55%, transparent);
    box-shadow: 1px 1px 0 var(--g-ext);
    transform-origin: 50% 0;
    animation: grow 0.24s steps(6, end) both;
  }
  /* A 2 pt packet runs down into each new step. */
  .step:not(:first-child)::after {
    content: "";
    position: absolute;
    left: 6px;
    top: 0;
    width: 2px;
    height: 2px;
    background: var(--cream);
    box-shadow: 0 0 4px var(--gold);
    opacity: 0;
    animation: packet 0.3s steps(6, end);
  }
  .node {
    position: relative;
    width: 8px;
    height: 8px;
    margin: 4px 0 0 2px;
    background: var(--gold);
    box-shadow:
      inset 0 2px 0 rgb(255 246 220 / 0.55),
      inset -2px 0 0 rgb(0 0 0 / 0.28),
      1px 1px 0 var(--g-ext);
    animation: blink 0.8s steps(1, end) infinite;
  }
  .step.done .node,
  .node.done {
    animation: none;
  }
  .step.done .node::after,
  .node.done::after {
    content: "";
    position: absolute;
    left: 2px;
    top: 2px;
    width: 2px;
    height: 2px;
    background: var(--cream);
  }
  .found {
    position: relative;
    grid-column: 2;
    display: grid;
    gap: 6px;
    margin-top: 7px;
  }
  /* A square pixel corner out of the step to what it found. */
  .found::before {
    content: "";
    position: absolute;
    left: -17px;
    top: -3px;
    width: 12px;
    height: 19px;
    border-left: 2px solid color-mix(in srgb, var(--gold) 55%, transparent);
    border-bottom: 2px solid color-mix(in srgb, var(--gold) 55%, transparent);
  }
  .notes {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .note {
    min-height: 32px;
    padding: 0 10px;
    border: 0;
    background: var(--g-a);
    box-shadow:
      inset 0 1px 0 var(--g-hi),
      inset 0 -2px 0 var(--g-ext),
      inset 0 0 0 1px var(--edge-2);
    clip-path: var(--cut);
    color: var(--ink);
    font: 500 var(--text-label) var(--font-ui);
  }
  .quote {
    margin: 0;
    padding-left: 8px;
    box-shadow: inset 2px 0 0 color-mix(in srgb, var(--gold) 55%, transparent);
    font-size: var(--text-caption);
    font-style: italic;
    line-height: 1.4;
    color: var(--ink-2);
    display: -webkit-box;
    -webkit-line-clamp: 2;
    line-clamp: 2;
    -webkit-box-orient: vertical;
    overflow: hidden;
  }
  .sum {
    justify-self: start;
    display: inline-grid;
    grid-template-columns: 14px auto 8px;
    align-items: center;
    column-gap: 9px;
    min-height: 44px;
    margin: -6px 0;
    padding: 0 6px 0 1px;
    border: 0;
    background: none;
    color: var(--ink-2);
    font: 400 var(--text-caption) var(--font-ui);
  }
  .sum .node {
    margin: 0 0 0 2px;
  }
  .chev {
    transition: rotate var(--t-quick) var(--ease);
  }
  .sum[aria-expanded="true"] .chev {
    rotate: 90deg;
  }
  /* Where an answer came from lights up in whole-pixel corners, here and on the page (048 C15). */
  :global(.hit) {
    position: relative;
  }
  :global(.hit)::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: 2;
    pointer-events: none;
    background:
      linear-gradient(var(--gold), var(--gold)) 0 0 / 8px 2px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 0 0 / 2px 8px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 100% 0 / 8px 2px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 100% 0 / 2px 8px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 0 100% / 8px 2px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 0 100% / 2px 8px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 100% 100% / 8px 2px no-repeat,
      linear-gradient(var(--gold), var(--gold)) 100% 100% / 2px 8px no-repeat;
    animation: hit 1.4s steps(7, end) both;
  }
  form {
    flex: 1;
    min-width: 0;
    display: flex;
    gap: 6px;
  }
  .well {
    flex: 1;
    min-width: 0;
    height: 44px;
    display: flex;
    align-items: center;
    padding: 0 12px;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    transition: box-shadow var(--t-quick) var(--ease);
  }
  .well:focus-within {
    box-shadow: inset 0 0 0 1.5px var(--gold);
  }
  .well input {
    flex: 1;
    min-width: 0;
    padding: 0;
    border: 0;
    background: none;
    color: var(--ink);
    font: 400 var(--text-input) var(--font-ui);
    caret-color: var(--gold);
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }
  .well input::placeholder {
    color: var(--ink-3);
  }
  .send {
    flex: none;
    min-width: 56px;
    height: 44px;
    padding: 0 10px;
    border: 0;
    background: var(--gold);
    color: var(--on-gold);
    font: 600 var(--text-sub) var(--font-ui);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    box-shadow: inset 0 -3px 0 rgb(0 0 0 / 0.24);
    transition:
      background-color 0.16s var(--ease),
      color 0.16s var(--ease);
  }
  .send:active:not(:disabled) {
    box-shadow: inset 0 3px 0 rgb(0 0 0 / 0.24);
    translate: 0 1px;
  }
  .send:disabled {
    opacity: 1;
    background: var(--sunk);
    color: var(--ink-3);
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  .win ::selection {
    background: color-mix(in srgb, var(--gold) 40%, transparent);
  }

  @keyframes pop {
    from {
      opacity: 0;
      transform: translateY(6px) scale(0.96);
    }
  }
  @keyframes send {
    from {
      opacity: 0;
      transform: translateY(8px);
    }
  }
  @keyframes drift {
    to {
      transform: translate(12%, -8%);
    }
  }
  @keyframes twinkle {
    from {
      opacity: 0.25;
    }
  }
  @keyframes grow {
    from {
      scale: 1 0;
    }
  }
  @keyframes packet {
    from {
      opacity: 1;
      translate: 0 -14px;
    }
    90% {
      opacity: 1;
    }
    to {
      opacity: 0;
      translate: 0 4px;
    }
  }
  @keyframes hit {
    60% {
      opacity: 1;
    }
    to {
      opacity: 0;
    }
  }
  @keyframes blink {
    50% {
      opacity: 0.2;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .lar,
    .offer,
    .me,
    .chip {
      animation: none;
    }
    .status i,
    .think i,
    .caret.done,
    .sky::before,
    .sky i,
    .status::before,
    .step,
    .step::before,
    .step::after,
    .node {
      animation: none;
    }
  }
</style>

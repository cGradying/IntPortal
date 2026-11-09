<script lang="ts" module>
  /**
   * Where the crystal chip is while LAR's window is about (046 C1d): `here` on the page; `gone`
   * faded out but still drawing, riding the glass as it grows or folds; `hidden` asleep, drawing
   * nothing, while the window is open.
   */
  export const chip = $state({ at: "here" as "here" | "gone" | "hidden" });
</script>

<script lang="ts">
  // LAR's window (picked 2026-11-09, round three C2, the front face): the chat box is the crystal
  // itself, and LAR is inside it. Tapping the chip grows its cube into the window, anchored where
  // the chip sits: the front face becomes a 3x3 grid of glass cells, its top and side kept as a thin
  // edge of depth, in the room's own tokens. It grows upward with the chat. LAR comes out of his
  // fire inside the glass by the input, waves and types his hello. While he thinks, a neuron grows
  // through the cells; an answer with a source sends its axon out to it. Closing folds him back into
  // his fire and the window back into the chip, one eased motion each way. Reduce Motion cross-fades.
  // Ported from reference/prototypes/lar-window/window.html.
  import { onMount, tick, untrack } from "svelte";
  import { closable } from "../back";
  import { visualViewport } from "../viewport.svelte";
  import { buzz } from "../haptics";
  import Lar, { larTheme, type Gesture } from "../lar/Lar.svelte";
  import { SPAWN_SECS, type State } from "../lar/sprite";
  import { app, openDeck, openNote, openSubject } from "../state.svelte";
  import { sourceTarget } from "./sources";
  import { describe, starters as startersFor } from "./apply";
  import { tidy } from "./cards";
  import { cellsOf, mountNeuron, neuronStill, type Neuron, type Rect } from "./neuron";
  import { invoke } from "@tauri-apps/api/core";
  import { apply, ask, assis, confirmCards, discardCards, dismiss, newChat, stop } from "./assis.svelte";

  let { onclose }: { onclose: () => void } = $props();
  // Android's back gesture and Escape close it; the effect's return unregisters it.
  $effect(() => closable(() => close()));

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // The low-RAM tier keeps the neuron still, as the chip keeps its glass (046 C1d2); true until it answers.
  let smallRam = $state(true);
  invoke<boolean>("ai_small_ram").then((small) => (smallRam = small)).catch(() => {});
  const vv = visualViewport();
  const theme = larTheme();
  const HELLO = "Hi! Ask me about your classes, what's due, your grades, or what's in your notes. I can also save a note or set a reminder, if you say so.";
  const CPS = 45;
  /** The glass grows and folds over this long, as in the mockup; the chip rides it for FLIGHT + 80 ms. */
  const FLIGHT = 520;

  let draft = $state("");
  let log: HTMLElement | undefined = $state();
  const starters = $derived(startersFor(!!app.editing));
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
  const status = $derived(
    assis.busy === "waking" ? (assis.slow ? "Still waking up. This phone is slow." : "Waking up") : assis.busy === "thinking" ? "Thinking" : assis.busy === "cards" ? "Making cards" : dozing ? "Dozing. Ask me anything." : "On this phone, offline",
  );

  // ------------------------------------------------------------ the glass

  let win: HTMLElement;
  let scrim: HTMLElement;
  let inn: HTMLElement;
  let top: HTMLElement;
  let dock: HTMLElement;
  let cv: HTMLElement;
  let input: HTMLInputElement;
  let nv: HTMLCanvasElement;
  let neuron: Neuron | null = null;

  const css = getComputedStyle(document.documentElement);
  const gutter = parseFloat(css.getPropertyValue("--gutter")) || 16;
  const day = css.colorScheme === "light";
  /** Compact: at most 60% of the screen, as in the mockup. */
  const MAX = Math.round(innerHeight * 0.6);
  const orb = () => document.querySelector<HTMLElement>("[data-orb]");
  let riding = false;
  let safeTop = 0;

  /** The chip's place. Without it (the keyboard hides it), the corner it would sit in. */
  function chipRect(): Rect {
    const r = orb()?.getBoundingClientRect();
    if (r?.width) return { x: r.x, y: r.y, w: r.width, h: r.height };
    return { x: innerWidth - gutter - 48, y: vv.top + vv.h - 140, w: 48, h: 48 };
  }

  let open = $state(false);
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

  // While the glass moves, the chip rides it and fades, so the swap happens inside one motion:
  // the same button and the same WebGL canvas, scaled, never a second context.
  function ride() {
    const o = orb();
    if (!riding || !o) return;
    const r = win.getBoundingClientRect();
    const c = home;
    const s = Math.min(r.width, r.height) / c.w;
    o.style.transform = `translate(${(r.x + r.width / 2 - c.x - c.w / 2).toFixed(2)}px, ${(r.y + r.height / 2 - c.y - c.h / 2).toFixed(2)}px) scale(${s.toFixed(3)})`;
    requestAnimationFrame(ride);
  }
  function startRide() {
    const o = orb();
    if (reduce || riding || !o) return;
    o.style.transition = "opacity 0.14s linear";
    riding = true;
    requestAnimationFrame(ride);
  }
  function stopRide() {
    riding = false;
    const o = orb();
    if (o) o.style.transform = o.style.transition = "";
  }

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
    neuron = mountNeuron(nv, () => neuronStill(reduce, smallRam));
    const watch = new ResizeObserver(measure);
    for (const el of [inn, top, dock]) watch.observe(el);
    measure();
    if (reduce) {
      open = true;
      chip.at = "hidden";
      input.focus({ preventScroll: true });
    } else {
      void win.offsetWidth; // lay out the folded glass first, so the growth eases from it
      requestAnimationFrame(() => {
        startRide();
        chip.at = "gone";
        open = true;
        later(FLIGHT + 80, () => {
          if (leaving) return;
          stopRide();
          chip.at = "hidden";
          buzz.tick();
          phase = "spawn";
          input.focus({ preventScroll: true });
          later(SPAWN_SECS * 1000, greet);
        });
      });
    }
    return () => {
      timers.forEach(clearTimeout);
      watch.disconnect();
      neuron?.dispose();
      stopRide();
      chip.at = "here";
    };
  });

  function done() {
    onclose();
    orb()?.focus({ preventScroll: true });
  }

  function close() {
    if (leaving) return;
    leaving = true;
    neuron?.clear();
    input.blur();
    if (reduce) {
      open = false;
      chip.at = "here";
      later(200, done);
      return;
    }
    // He folds back into his fire, then the glass folds into the chip.
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
    later(folds ? 300 : 0, () => {
      if (!riding) home = chipRect();
      chip.at = "gone";
      startRide();
      open = false;
      later(400, () => (chip.at = "here"));
      later(FLIGHT + 100, () => {
        stopRide();
        done();
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

  // ------------------------------------------------------------ the neuron

  // His spark is the tip of his antenna: 26 art px in and 11 down in his fitted box, at 2 px each.
  function glass() {
    const c = cv.getBoundingClientRect();
    const r = { x: box.x + 3, y: box.y + 3, w: box.w - 6, h: box.h - 6 };
    return { soma: { x: c.x + 52, y: c.y + 22 }, box: r, cells: cellsOf(box), fan: [-Math.PI * 0.6, -Math.PI * 0.02] as [number, number] };
  }

  /** The sources of an answer: its From chips, and each one's card on the page when it is on screen. */
  function sources(): Rect[] {
    const rect = (el: Element) => {
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height };
    };
    const out = [...([...inn.querySelectorAll(".from")].at(-1)?.children ?? [])].map(rect);
    for (const s of last?.sources ?? []) {
      const el = [...document.querySelectorAll(`[data-source]`)].find((e) => e.getAttribute("data-source") === s.key && !win.contains(e));
      const r = el && rect(el);
      if (r && r.w && r.y + r.h > 0 && r.y < innerHeight) out.push(r);
    }
    return out;
  }

  let thought = false;
  let asked = 0;
  $effect(() => {
    const now = thinking;
    untrack(() => {
      if (now && !thought && phase !== "fly" && !leaving) {
        asked = assis.chat.length;
        // Once the question is in the log, so the glass is measured round it.
        tick().then(() => {
          measure();
          if (thinking && !leaving) neuron?.think(glass());
        });
      } else if (!now && thought) {
        // An answer with a source fires once the glass has settled round it; one without, inside.
        const answer = assis.chat.length > asked ? last : undefined;
        if (answer?.from === "lar" && answer.sources?.length) later(reduce ? 0 : 560, () => !leaving && neuron?.fire(sources()));
        else neuron?.spark();
      }
    });
    thought = now;
  });
  // The keyboard moving the glass leaves the neuron behind: let it go.
  $effect(() => {
    void bottom;
    untrack(() => neuron?.clear());
  });

  // ------------------------------------------------------------- the chat

  async function send(text: string) {
    draft = "";
    buzz.select();
    const sending = ask(text);
    await tick();
    log?.scrollTo({ top: log.scrollHeight });
    await sending;
    await tick();
    log?.scrollTo({ top: log.scrollHeight, behavior: "smooth" });
  }

  function prefill(s: { label: string; fill: boolean }) {
    // Starters that need the student's own words fill the field; the rest just ask.
    if (s.fill) draft = s.label;
    else send(s.label);
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
<div
  class="win"
  class:open
  class:day
  class:reduce
  bind:this={win}
  role="dialog"
  aria-modal="true"
  aria-label="Ask LAR"
  style:left="{box.x}px"
  style:top="{box.y}px"
  style:width="{box.w}px"
  style:height="{box.h}px"
  style:--accent={theme.accent}
>
  <i class="dt gl" aria-hidden="true"></i>
  <i class="ds gl" aria-hidden="true"></i>
  <div class="face gl">
    <!-- The content keeps its final layout and is revealed as the glass grows, so nothing reflows while it moves. -->
    <div class="body" style:width="{width}px" style:height="{H}px">
      <div class="top" bind:this={top}>
        <span class="tag">LAR</span>
        <span class="status" aria-live="polite">{status}{#if assis.busy}<i></i><i></i><i></i>{/if}</span>
        {#if assis.chat.length && !assis.busy}<button class="x first" onclick={newChat}>New chat</button>{/if}
        <button class="x" class:first={!assis.chat.length || !!assis.busy} onclick={close}>Close</button>
      </div>

      <div class="log" bind:this={log} aria-live="polite">
        <div class="in" bind:this={inn}>
          {#if !assis.chat.length && phase === "here"}
            <div class="lar hello">
              <span class="sr">{HELLO}</span>
              <p aria-hidden="true">{HELLO.slice(0, typed)}<i class="caret" class:done={typed >= HELLO.length}></i><span class="rest">{HELLO.slice(typed)}</span></p>
            </div>
            {#if typed >= HELLO.length}
              <div class="chips">
                {#each starters as s, i (s.label)}<button class="chip" style:--i={i} onclick={() => prefill(s)}>{s.label}</button>{/each}
              </div>
            {/if}
          {/if}
          {#each assis.chat as m, i (i)}
            {#if m.from === "me"}
              <p class="me">{m.text}</p>
            {:else}
              {#if m.text}<div class="lar"><p>{m.text}</p></div>{/if}
              {#if m.sources}
                <div class="chips from">
                  {#each m.sources as src (src.key)}<button class="chip" onclick={() => show(src.key, src.title)}>From: {src.title}</button>{/each}
                </div>
              {/if}
              {#if m.proposal}
                {@const d = describe(m.proposal)}
                <div class="offer" class:done={m.state === "done"}>
                  <p class="label">{d.label}</p>
                  <p class="what">{d.text}</p>
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
                    <div class="two">
                      <button class="yes" onclick={() => apply(i)} disabled={assis.busy === "cards"}>{assis.busy === "cards" ? "Making…" : d.yes}</button>
                      <button class="no" onclick={() => dismiss(i)}>Not now</button>
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
          {#if waiting}
            <div class="lar wait" aria-label="LAR is thinking"><p class="think"><i></i><i></i><i></i></p></div>
          {/if}
        </div>
      </div>

      <div class="dock" bind:this={dock}>
        <!-- LAR in the glass: a front-surface sheen sits over him, so he reads as inside it. -->
        <div class="perch" aria-hidden="true">
          <div class="cv" bind:this={cv}>
            {#if phase !== "fly" && fold !== 0}<Lar size={2} fit cube={false} shadow={false} state={mood} k={fold} {gesture} {theme} />{/if}
          </div>
        </div>
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
<canvas class="neuron" bind:this={nv} aria-hidden="true"></canvas>

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
  .neuron {
    position: fixed;
    inset: 0;
    width: 100%;
    height: 100%;
    z-index: 62;
    pointer-events: none;
  }

  /* The glass is the crystal's faces in room tokens: cells with a lit top-left bevel, a dark lower
     edge and a gold rim where they turn away, the same reading as the WebGL cube. */
  .win {
    --g-a: color-mix(in srgb, var(--card), var(--ink) 8%);
    --g-b: color-mix(in srgb, var(--card), var(--ground) 45%);
    --g-rim: color-mix(in srgb, var(--gold) 42%, transparent);
    --g-hi: rgb(168 134 210 / 0.42);
    --g-lo: rgb(0 0 0 / 0.5);
    --g-sheen: rgb(255 236 214 / 0.07);
    --slab: polygon(0 6px, 3px 6px, 3px 3px, 6px 3px, 6px 0, calc(100% - 6px) 0, calc(100% - 6px) 3px, calc(100% - 3px) 3px, calc(100% - 3px) 6px, 100% 6px, 100% calc(100% - 6px), calc(100% - 3px) calc(100% - 6px), calc(100% - 3px) calc(100% - 3px), calc(100% - 6px) calc(100% - 3px), calc(100% - 6px) 100%, 6px 100%, 6px calc(100% - 3px), 3px calc(100% - 3px), 3px calc(100% - 6px), 0 calc(100% - 6px));
    position: fixed;
    z-index: 61;
    color: var(--ink);
    font-family: var(--font-ui);
    opacity: 0;
    /* One eased change of box, so the cube grows into the window and back. */
    transition:
      left 0.52s var(--ease),
      top 0.52s var(--ease),
      width 0.52s var(--ease),
      height 0.52s var(--ease),
      opacity 0.14s linear 0.4s;
  }
  .win.open {
    opacity: 1;
    transition:
      left 0.52s var(--ease),
      top 0.52s var(--ease),
      width 0.52s var(--ease),
      height 0.52s var(--ease),
      opacity 0.14s linear;
  }
  .win.reduce {
    transition: opacity 0.2s linear;
  }
  .win.day {
    --g-hi: rgb(255 255 255 / 0.95);
    --g-lo: rgb(90 40 50 / 0.16);
    --g-sheen: rgb(255 255 255 / 0.7);
  }
  .gl {
    background:
      linear-gradient(to bottom, var(--g-hi) 0 1px, transparent 1px),
      linear-gradient(to right, var(--g-hi) 0 1px, transparent 1px),
      linear-gradient(to top, var(--g-lo) 0 2px, transparent 2px),
      linear-gradient(to left, var(--g-rim) 0 1px, var(--g-lo) 1px 2px, transparent 2px),
      radial-gradient(80% 70% at 28% 18%, var(--g-sheen), transparent 72%),
      linear-gradient(155deg, var(--g-a), var(--g-b));
    background-size: var(--cw, 100%) var(--ch, 100%);
    background-position: 0 100%;
  }
  /* The front face, nine cells; its top and side stay as a thin edge of depth. */
  .face {
    position: absolute;
    inset: 0;
    overflow: hidden;
    --cw: calc(100% / 3);
    --ch: calc(100% / 3);
    box-shadow: 0 12px 26px -10px rgb(0 0 0 / 0.55);
  }
  .dt,
  .ds {
    position: absolute;
    pointer-events: none;
  }
  .dt {
    left: 0;
    bottom: 100%;
    width: 100%;
    height: 8px;
    transform-origin: 0 100%;
    transform: skewX(-45deg);
    --cw: calc(100% / 3);
  }
  .ds {
    left: 100%;
    top: 0;
    width: 8px;
    height: 100%;
    transform-origin: 0 0;
    transform: skewY(-45deg);
    --ch: calc(100% / 3);
  }
  .dt::after,
  .ds::after {
    content: "";
    position: absolute;
    inset: 0;
  }
  .dt::after {
    background: rgb(255 255 255 / 0.06);
  }
  .ds::after {
    background: rgb(0 0 0 / 0.24);
  }
  .body {
    position: absolute;
    right: 0;
    bottom: 0;
    display: flex;
    flex-direction: column;
  }

  .top {
    flex: none;
    display: flex;
    align-items: center;
    gap: 8px;
    height: 44px;
    padding-left: 12px;
  }
  .tag {
    font: 600 min(0.765rem, 23px) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--gold);
  }
  .status {
    min-width: 0;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font: 500 min(0.706rem, 22px) var(--font-pixel);
    letter-spacing: 0.04em;
    color: var(--ink-3);
  }
  .status i,
  .think i {
    display: inline-block;
    width: 3px;
    height: 3px;
    margin-left: 3px;
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
  .x {
    flex: none;
    min-width: 44px;
    height: 44px;
    padding: 0 10px;
    border: 0;
    background: none;
    color: var(--ink-2);
    font: 600 min(0.765rem, 23px) var(--font-ui);
  }
  .x.first {
    margin-left: auto;
  }
  .x + .x {
    padding-left: 4px;
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
    animation: pop 0.28s var(--ease) both;
  }
  .lar p {
    margin: 0;
    font-size: min(0.824rem, 25px);
    line-height: 1.4;
    white-space: pre-line;
    overflow-wrap: anywhere;
  }
  .hello {
    position: relative;
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
    border-radius: 16px 16px 4px 16px;
    background: color-mix(in srgb, var(--ink) 8%, transparent);
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--ink) 13%, transparent);
    font-size: min(0.824rem, 25px);
    line-height: 1.35;
    overflow-wrap: anywhere;
    animation: send 0.28s var(--ease) both;
  }
  .chips {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .chip {
    min-height: 44px;
    max-width: 100%;
    padding: 6px 12px;
    border: 0;
    border-radius: 12px;
    background: color-mix(in srgb, var(--card) 70%, transparent);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink);
    font: 400 min(0.794rem, 24px) / 1.3 var(--font-ui);
    text-align: left;
    overflow-wrap: anywhere;
    transition: background 0.16s var(--ease);
    animation: send 0.3s calc(var(--i, 0) * 60ms) var(--ease) both;
  }
  .chip:active {
    background: color-mix(in srgb, var(--gold) 20%, var(--card));
  }
  .from .chip {
    font-size: min(0.735rem, 23px);
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
    animation: pop 0.28s var(--ease) both;
  }
  .offer.done {
    opacity: 0.7;
  }
  .label {
    margin: 0;
    font: 500 min(0.706rem, 22px) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--accent);
  }
  .what {
    margin: 0;
    font-size: min(0.941rem, 29px);
    line-height: 1.35;
    overflow-wrap: anywhere;
  }
  .two {
    display: grid;
    grid-template-columns: 1.3fr 1fr;
    gap: 8px;
    margin-top: 4px;
  }
  /* Gold pixel buttons: stepped corners and the gold lip. */
  .yes {
    height: 44px;
    border: 0;
    background: linear-gradient(180deg, var(--portal-gold-hi), var(--portal-gold) 60%);
    color: var(--on-portal-gold);
    font: 600 min(0.824rem, 25px) var(--font-ui);
    box-shadow: inset 0 -3px 0 var(--portal-gold-shade);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .yes:active:not(:disabled) {
    box-shadow: inset 0 3px 0 var(--portal-gold-shade);
    transform: translateY(1px);
  }
  .no {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: rgb(255 246 220 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.14);
    color: var(--parch);
    font: 600 min(0.824rem, 25px) var(--font-ui);
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
  .ed {
    min-width: 0;
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--void);
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    color: var(--white);
    font: 400 max(16px, min(0.941rem, 29px)) var(--font-ui);
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
    font-size: min(1.176rem, 26px);
  }
  .ok,
  .fine {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: rgb(255 246 220 / 0.55);
  }
  .ok {
    color: var(--good);
    font-weight: 600;
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: var(--rose);
  }

  /* ---- the dock: LAR stands in the glass by the input ---- */
  .dock {
    flex: none;
    display: flex;
    align-items: flex-end;
    gap: 6px;
    padding: 4px 8px 8px;
  }
  .perch {
    position: relative;
    flex: none;
    width: 80px;
    height: 56px;
    overflow: hidden;
  }
  .perch::after {
    content: "";
    position: absolute;
    inset: 0;
    background:
      linear-gradient(135deg, var(--g-sheen) 0 30%, transparent 55%),
      linear-gradient(transparent 60%, color-mix(in srgb, var(--g-b) 40%, transparent));
    pointer-events: none;
  }
  .cv {
    position: absolute;
    left: -12px;
    top: -14px;
    width: 106px;
    height: 100px;
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
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    transition: box-shadow 0.16s var(--ease);
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
    font: 400 max(16px, min(0.941rem, 29px)) var(--font-ui);
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
    font: 600 min(0.824rem, 25px) var(--font-ui);
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
    .caret.done {
      animation: none;
    }
  }
</style>

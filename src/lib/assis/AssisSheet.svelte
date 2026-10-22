<script lang="ts">
  // Talking to LAR. Opening it is one moment: the cube flies up from the orb
  // to the top of the sheet, LAR comes out of a fire round it, waves, and
  // types his hello. He stays up there, in a little window of his portal's
  // colours, and shows what he is doing (thinking, done, a problem, dozing);
  // his lines sit below on the obsidian slab, yours are quiet. When he
  // offers to do something, a card says exactly what, and nothing changes
  // until you tap the gold button. Closing sends him back into the cube.
  import { onMount, tick } from "svelte";
  import { closable } from "../back";
  import { visualViewport } from "../viewport.svelte";
  import { buzz } from "../haptics";
  import Cube from "../lar/Cube.svelte";
  import Lar, { larTheme, type Gesture } from "../lar/Lar.svelte";
  import { SPAWN_SECS, type State } from "../lar/sprite";
  import { app, openDeck, openNote, openSubject } from "../state.svelte";
  import { sourceTarget } from "./sources";
  import { describe, starters as startersFor } from "./apply";
  import { tidy } from "./cards";
  import { apply, ask, assis, confirmCards, discardCards, dismiss, newChat, stop } from "./assis.svelte";

  let { onclose }: { onclose: () => void } = $props();
  $effect(() => closable(() => close()));

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const vv = visualViewport();
  const theme = larTheme();
  const HELLO = "Hi! Ask me about your classes, what's due, your grades, or what's in your notes. I can also save a note or set a reminder, if you say so.";
  const CPS = 45;

  let draft = $state("");
  let log: HTMLElement | undefined = $state();
  const starters = $derived(startersFor(!!app.editing));
  const last = $derived(assis.chat[assis.chat.length - 1]);
  // Dots show from the moment a message is sent until the first word arrives.
  const waiting = $derived(assis.busy === "waking" || (assis.busy === "thinking" && !last?.text));
  const writing = $derived(assis.busy === "thinking");

  // ------------------------------------------------------------ his moment

  // fly: the cube is on its way up; spawn: the fire; here: he is in.
  let phase = $state<"fly" | "spawn" | "here">(reduce ? "here" : "fly");
  let leaving = $state(false);
  let typed = $state(reduce ? HELLO.length : 0);
  let waving = $state(false);
  let cheer = $state(false);
  let dozing = $state(false);
  let sheet: HTMLElement;
  let perch: HTMLElement;
  let flier: HTMLElement | undefined = $state();

  const mood = $derived<State>(
    phase === "spawn" ? "spawn"
    : assis.error ? "error"
    : assis.busy === "thinking" || assis.busy === "waking" || assis.busy === "cards" ? "think"
    : cheer ? "happy"
    : dozing ? "sleep"
    : "idle",
  );
  const gesture = $derived<Gesture>(waving && mood === "idle" ? "wave" : "idle");
  const status = $derived(
    assis.busy === "waking" ? "Waking up" : assis.busy === "thinking" ? "Thinking" : assis.busy === "cards" ? "Making cards" : dozing ? "Dozing. Ask me anything." : "On this phone, offline",
  );

  // Where the orb and his perch are, as centres in px. The sheet is still
  // mid-rise when this is read, so its own offset is taken out.
  function spots() {
    const orb = document.querySelector("[data-orb]")?.getBoundingClientRect();
    const p = perch.getBoundingClientRect();
    const lift = new DOMMatrix(getComputedStyle(sheet).transform).f;
    const from = orb ? { x: orb.x + orb.width / 2, y: orb.y + orb.height / 2 } : { x: innerWidth - 44, y: innerHeight - 140 };
    // His cube rides at about a third of the way down his box.
    return { from, to: { x: p.x + p.width / 2, y: p.y + p.height * 0.36 - lift } };
  }

  /** The cube along an arc from `a` to `b`, shrinking to the size he holds it. */
  function fly(a: { x: number; y: number }, b: { x: number; y: number }, shrink: [number, number], ms: number) {
    if (!flier) return Promise.resolve();
    const half = flier.offsetWidth / 2;
    const at = (x: number, y: number, s: number) => ({ transform: `translate(${x - half}px, ${y - half}px) scale(${s})` });
    const mid = { x: (a.x + b.x) / 2 - 24, y: Math.min(a.y, b.y) - 70 };
    const anim = flier.animate([at(a.x, a.y, shrink[0]), { ...at(mid.x, mid.y, (shrink[0] + shrink[1]) / 2 + 0.15), offset: 0.55 }, at(b.x, b.y, shrink[1])], {
      duration: ms,
      easing: "cubic-bezier(0.45, 0, 0.2, 1)",
      fill: "forwards",
    });
    return anim.finished.then(
      () => {},
      () => {},
    );
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
    if (!reduce) {
      const { from, to } = spots();
      fly(from, to, [1, 0.5], 560).then(() => {
        if (leaving) return;
        buzz.tick();
        phase = "spawn";
        later(SPAWN_SECS * 1000, greet);
      });
    }
    return () => timers.forEach(clearTimeout);
  });

  async function close() {
    if (leaving) return;
    if (reduce || phase !== "here") return onclose();
    leaving = true;
    const { from, to } = spots();
    await tick();
    await fly(to, from, [0.5, 1], 420);
    onclose();
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

  /** The sheet sits above the page, so a source chip closes it and shows the note, deck or subject. */
  function show(key: string, title: string) {
    onclose();
    const t = sourceTarget(key);
    if (t.kind === "deck") openDeck(t.id);
    else if (t.kind === "subject") openSubject(t.code, app.snapshot?.sessions.find((s) => s.subject_code === t.code)?.description ?? "");
    else openNote(key, title);
  }
</script>

<div class="scrim" class:leaving role="presentation" onclick={close}></div>
<!-- A frame that is exactly the visual viewport, so the keyboard shrinks it and
     the sheet stays inside it, whatever the page scrolled to. -->
<div class="frame" class:typing={vv.keyboard} style:top="{vv.top}px" style:height="{vv.h}px">
  <div
    class="sheet"
    class:leaving
    bind:this={sheet}
    role="dialog"
    aria-label="Ask LAR"
    style:--r0={theme.ramp[0]}
    style:--r1={theme.ramp[1]}
    style:--r2={theme.ramp[2]}
    style:--r3={theme.ramp[3]}
    style:--accent={theme.accent}
  >
    <header class="stage" class:small={vv.keyboard}>
      <div class="sky" aria-hidden="true"></div>
      <div class="perch" bind:this={perch}>
        {#if phase !== "fly" && !leaving}<Lar size={2} fit state={mood} {gesture} {theme} />{/if}
      </div>
      <div class="who">
        <span class="tag">LAR</span>
        <span class="status" aria-live="polite">{status}{#if assis.busy}<i></i><i></i><i></i>{/if}</span>
      </div>
      <div class="head">
        {#if assis.chat.length && !assis.busy}<button class="link" onclick={newChat}>New chat</button>{/if}
        <button class="link" onclick={close}>Close</button>
      </div>
    </header>

    <div class="log" bind:this={log} aria-live="polite">
      {#if !assis.chat.length && phase === "here"}
        <div class="lar hello">
          <span class="sr">{HELLO}</span>
          <p aria-hidden="true">{HELLO.slice(0, typed)}<i class="caret" class:done={typed >= HELLO.length}></i><span class="rest">{HELLO.slice(typed)}</span></p>
        </div>
        {#if typed >= HELLO.length}
          <div class="starters">
            {#each starters as s, i (s.label)}<button style:--i={i} onclick={() => prefill(s)}>{s.label}</button>{/each}
          </div>
        {/if}
      {/if}
      {#each assis.chat as m, i (i)}
        {#if m.from === "me"}
          <p class="me">{m.text}</p>
        {:else}
          {#if m.text}<div class="lar"><p>{m.text}</p></div>{/if}
          {#if m.sources}
            <div class="from">
              {#each m.sources as src (src.key)}<button onclick={() => show(src.key, src.title)}>From: {src.title}</button>{/each}
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
                      <button class="x" aria-label="Remove card {k + 1}" onclick={() => m.cards?.splice(k, 1)}>×</button>
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

    <form onsubmit={(e) => { e.preventDefault(); send(draft); }}>
      <label class="well">
        <input bind:value={draft} placeholder="Ask LAR…" aria-label="Message LAR" enterkeyhint="send" autocomplete="off" />
      </label>
      {#if writing}
        <button class="send" type="button" onclick={stop}>Stop</button>
      {:else}
        <button class="send" type="submit" disabled={!draft.trim() || !!assis.busy}>Send</button>
      {/if}
    </form>
    <p class="fine foot">Runs on this phone. Nothing leaves it.</p>
  </div>
</div>

{#if !reduce && (phase === "fly" || leaving)}
  <div class="flier" bind:this={flier} aria-hidden="true"><Cube size={4} speed={3} {theme} /></div>
{/if}

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgb(6 3 7 / 0.55);
    animation: fade 0.25s both;
  }
  .scrim.leaving {
    animation: unfade 0.4s 0.1s both;
  }
  .frame {
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    z-index: 61;
    display: flex;
    align-items: flex-end;
    padding: calc(var(--safe-top) + 8px) 0 calc(var(--safe-bottom) + 12px);
    pointer-events: none;
  }
  .frame.typing {
    padding-bottom: 8px;
  }
  /* LAR's side of the portal: the night card, stepped, with a gold hairline. */
  .sheet {
    --sheet: #140c16;
    pointer-events: auto;
    position: relative;
    width: 100%;
    max-height: 100%;
    height: min(82%, 680px);
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto auto;
    background: var(--sheet);
    color: #f4ecd8;
    font-family: var(--font-ui);
    box-shadow: inset 0 0 0 1px rgb(245 178 39 / 0.16);
    clip-path: polygon(0 8px, 4px 8px, 4px 4px, 8px 4px, 8px 0, calc(100% - 8px) 0, calc(100% - 8px) 4px, calc(100% - 4px) 4px, calc(100% - 4px) 8px, 100% 8px, 100% calc(100% - 8px), calc(100% - 4px) calc(100% - 8px), calc(100% - 4px) calc(100% - 4px), calc(100% - 8px) calc(100% - 4px), calc(100% - 8px) 100%, 8px 100%, 8px calc(100% - 4px), 4px calc(100% - 4px), 4px calc(100% - 8px), 0 calc(100% - 8px));
    animation: rise 0.45s var(--ease) both;
  }
  .sheet.leaving {
    animation: fall 0.32s cubic-bezier(0.5, 0, 0.75, 0) both;
  }

  /* ---- the stage: his window, in his portal's colours ---- */
  .stage {
    position: relative;
    height: 124px;
    display: grid;
    grid-template-columns: auto minmax(0, 1fr) auto;
    align-items: end;
    gap: 4px;
    padding: 0 6px 0 4px;
    isolation: isolate;
    transition: height 0.25s var(--ease);
  }
  .stage.small {
    height: 104px;
  }
  /* Whimsical light: soft pools of the portal's ramp and accent drifting
     past each other, a few pixel stars, and a dithered edge into the card. */
  .sky {
    position: absolute;
    inset: 0;
    z-index: -1;
    background:
      radial-gradient(42% 70% at 20% 100%, color-mix(in srgb, var(--r3) 75%, transparent), transparent 70%),
      radial-gradient(38% 80% at 80% 0%, color-mix(in srgb, var(--accent) 40%, transparent), transparent 70%),
      radial-gradient(60% 90% at 60% 110%, color-mix(in srgb, var(--r2) 80%, transparent), transparent 75%),
      linear-gradient(170deg, var(--r0), var(--r1) 70%, var(--r0));
    background-size: 180% 160%, 200% 180%, 160% 140%, 100% 100%;
    background-position: 0% 100%, 100% 0%, 50% 100%, 0 0;
    animation: drift 16s ease-in-out infinite alternate;
  }
  .sky::before {
    content: "";
    position: absolute;
    top: 18px;
    left: 30%;
    width: 2px;
    height: 2px;
    background: #fff6dc;
    box-shadow:
      48px 6px rgb(255 246 220 / 0.7),
      120px 30px rgb(255 246 220 / 0.5),
      -40px 44px rgb(255 246 220 / 0.6),
      150px -6px rgb(255 246 220 / 0.8),
      86px 58px rgb(255 246 220 / 0.4),
      190px 40px rgb(255 246 220 / 0.6);
    animation: twinkle 2.4s steps(3, jump-none) infinite alternate;
  }
  .sky::after {
    content: "";
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    height: 8px;
    background: conic-gradient(var(--sheet) 25%, transparent 0 50%, var(--sheet) 0 75%, transparent 0) 0 0 / 8px 8px;
  }
  .perch {
    width: 106px;
    height: 100px;
    margin-bottom: 6px;
  }
  .who {
    display: grid;
    gap: 2px;
    align-self: center;
    margin-top: 18px;
    min-width: 0;
  }
  .tag {
    font: 700 min(0.824rem, 25px) var(--font-pixel);
    letter-spacing: 0.08em;
    color: #f5b227;
    text-shadow: 0 1px 0 rgb(6 3 7 / 0.6);
  }
  .status {
    font-size: min(0.765rem, 23px);
    color: rgb(255 246 220 / 0.8);
    text-shadow: 0 1px 0 rgb(6 3 7 / 0.6);
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
  .head {
    align-self: start;
    display: flex;
    margin-top: 6px;
  }
  .link {
    min-width: 44px;
    height: 44px;
    padding: 0 8px;
    border: 0;
    background: none;
    color: #fff6dc;
    font: 600 min(0.765rem, 23px) var(--font-ui);
    text-shadow: 0 1px 0 rgb(6 3 7 / 0.6);
  }

  /* ---- the conversation ---- */
  .log {
    display: grid;
    align-content: start;
    gap: 10px;
    overflow-y: auto;
    overscroll-behavior: contain;
    padding: 12px 14px 4px;
    scrollbar-width: none;
  }
  .log::-webkit-scrollbar {
    display: none;
  }
  /* His lines: the obsidian slab, its lit edge catching his portal's accent. */
  .lar {
    justify-self: start;
    max-width: 90%;
    padding: 10px 12px;
    background: #170b1a;
    color: #f4e8d6;
    box-shadow:
      inset 0 2px 0 color-mix(in srgb, var(--accent) 45%, #3a2446),
      inset 0 -2px 0 #060307;
    clip-path: polygon(0 6px, 3px 6px, 3px 3px, 6px 3px, 6px 0, calc(100% - 6px) 0, calc(100% - 6px) 3px, calc(100% - 3px) 3px, calc(100% - 3px) 6px, 100% 6px, 100% calc(100% - 6px), calc(100% - 3px) calc(100% - 6px), calc(100% - 3px) calc(100% - 3px), calc(100% - 6px) calc(100% - 3px), calc(100% - 6px) 100%, 6px 100%, 6px calc(100% - 3px), 3px calc(100% - 3px), 3px calc(100% - 6px), 0 calc(100% - 6px));
    transform-origin: 0 0;
    animation: pop 0.24s steps(4, jump-end) both;
  }
  .lar p {
    margin: 0;
    font-size: min(0.882rem, 27px);
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
    background: #f5b227;
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
    color: #f5b227;
  }
  .me {
    justify-self: end;
    max-width: 82%;
    margin: 0;
    padding: 9px 13px;
    border-radius: 16px 16px 4px 16px;
    background: rgb(255 246 220 / 0.07);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.1);
    font-size: min(0.882rem, 27px);
    line-height: 1.35;
    overflow-wrap: anywhere;
    animation: send 0.28s var(--ease) both;
  }
  .starters {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .starters button,
  .from button {
    min-height: 40px;
    max-width: 100%;
    padding: 6px 12px;
    border: 0;
    border-radius: 12px;
    background: rgb(255 246 220 / 0.05);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.14);
    color: rgb(255 246 220 / 0.9);
    font: 400 min(0.824rem, 25px) / 1.3 var(--font-ui);
    text-align: left;
    overflow-wrap: anywhere;
    transition: background 0.16s var(--ease);
  }
  .starters button {
    animation: send 0.3s calc(var(--i) * 60ms) var(--ease) both;
  }
  .starters button:active,
  .from button:active {
    background: color-mix(in srgb, var(--accent) 16%, transparent);
  }
  .from {
    display: flex;
    flex-wrap: wrap;
    gap: 6px;
  }
  .from button {
    font-size: min(0.765rem, 23px);
    color: rgb(255 246 220 / 0.7);
  }
  .offer {
    justify-self: start;
    width: 92%;
    display: grid;
    gap: 6px;
    padding: 12px;
    background: #1c1220;
    box-shadow: inset 0 0 0 1px color-mix(in srgb, var(--accent) 30%, transparent);
    clip-path: polygon(0 6px, 3px 6px, 3px 3px, 6px 3px, 6px 0, calc(100% - 6px) 0, calc(100% - 6px) 3px, calc(100% - 3px) 3px, calc(100% - 3px) 6px, 100% 6px, 100% calc(100% - 6px), calc(100% - 3px) calc(100% - 6px), calc(100% - 3px) calc(100% - 3px), calc(100% - 6px) calc(100% - 3px), calc(100% - 6px) 100%, 6px 100%, 6px calc(100% - 3px), 3px calc(100% - 3px), 3px calc(100% - 6px), 0 calc(100% - 6px));
    animation: pop 0.24s steps(4, jump-end) both;
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
  .yes,
  .send {
    height: 44px;
    border: 0;
    background: linear-gradient(180deg, #ffc94a, #f5b227 60%);
    color: #1b1406;
    font: 600 min(0.824rem, 25px) var(--font-ui);
    box-shadow: inset 0 -3px 0 #b87a10;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .yes:active:not(:disabled),
  .send:active:not(:disabled) {
    box-shadow: inset 0 3px 0 #b87a10;
    transform: translateY(1px);
  }
  .no {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: rgb(255 246 220 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(255 246 220 / 0.14);
    color: #f4ecd8;
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
    background: #0b0710;
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    color: #fff;
    font: 400 max(16px, min(0.941rem, 29px)) var(--font-ui);
    caret-color: #f5b227;
    outline: none;
  }
  .ed:focus {
    box-shadow: inset 0 0 0 1.5px var(--accent);
  }
  .x {
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
    color: #58c792;
    font-weight: 600;
  }
  .problem {
    margin: 0;
    font-size: min(0.765rem, 23px);
    color: #f0a090;
  }

  /* ---- the composer: the sign-in field's well, the gold pixel Send ---- */
  form {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 8px;
    padding: 8px 12px 0;
  }
  .well {
    display: flex;
    border-radius: 12px;
    background: #0b0710;
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    transition: box-shadow 0.16s var(--ease);
  }
  .well:focus-within {
    box-shadow: inset 0 0 0 1.5px var(--accent);
  }
  .well input {
    flex: 1;
    min-width: 0;
    height: 46px;
    padding: 0 14px;
    border: 0;
    background: none;
    color: #fff;
    font: 400 max(16px, min(0.941rem, 29px)) var(--font-ui);
    caret-color: #f5b227;
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }
  .well input::placeholder {
    color: rgb(255 246 220 / 0.45);
  }
  .send {
    height: 46px;
    padding: 0 18px;
  }
  .foot {
    padding: 6px 14px 12px;
    text-align: center;
  }
  .sheet ::selection {
    background: color-mix(in srgb, var(--accent) 40%, transparent);
  }

  /* The cube on its way between the orb and his hands, over everything. */
  .flier {
    position: fixed;
    left: 0;
    top: 0;
    z-index: 70;
    pointer-events: none;
    will-change: transform;
  }

  @keyframes fade {
    from {
      opacity: 0;
    }
  }
  @keyframes unfade {
    to {
      opacity: 0;
    }
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(32px);
    }
  }
  @keyframes fall {
    to {
      opacity: 0;
      transform: translateY(40px);
    }
  }
  @keyframes pop {
    from {
      opacity: 0.2;
      transform: scale(0.9);
    }
  }
  @keyframes send {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  @keyframes drift {
    to {
      background-position: 100% 60%, 0% 40%, 20% 80%, 0 0;
    }
  }
  @keyframes twinkle {
    to {
      opacity: 0.35;
    }
  }
  @keyframes blink {
    50% {
      opacity: 0.2;
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .sheet,
    .sheet.leaving,
    .lar,
    .offer,
    .me,
    .starters button {
      animation: fade 0.2s both;
    }
    .sky,
    .sky::before,
    .status i,
    .think i,
    .caret.done {
      animation: none;
    }
  }
</style>

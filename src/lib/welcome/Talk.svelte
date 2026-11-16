<script lang="ts">
  // The talk (spec 049): a new student's first screen is a conversation with LAR, on its own
  // page, before the portal. LAR sits at the top; under him a thread. His lines type themselves
  // into slabs, the student answers with the chips at the bottom, and Back takes the last answer
  // away. The conversation itself is data (intro.ts); this draws it, keeps what the student says
  // (profile.ts) and runs each answer's act. When LAR says "pasok na tayo" he goes back into his
  // fire and Landing builds the portal where he stood.
  import { onMount, tick } from "svelte";
  import { fly } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import Lar from "../lar/Lar.svelte";
  import MiniPortal from "../MiniPortal.svelte";
  import ClockCard from "./ClockCard.svelte";
  import DueRow from "./DueRow.svelte";
  import GpaCard from "./GpaCard.svelte";
  import FlashCard from "./FlashCard.svelte";
  import SignalCard from "./SignalCard.svelte";
  import Nudge from "./Nudge.svelte";
  import type { Portal } from "../api";
  import type { Gesture, State } from "../lar/sprite";
  import { animate } from "../quiet";
  import { closable } from "../back";
  import { buzz } from "../haptics";
  import { allowReminders, app, setRoom } from "../state.svelte";
  import { CAMPUSES, MAX_NAME, cleanName, setCampus, setFocus, setName, type Focus } from "../profile";
  import { FOCUS, LOOKS, isDarkLook, play, type Act, type Answer, type Reply } from "./intro";

  let { portal, portals, onend }: { portal: Portal; portals: Portal[]; /** The talk is over: on to the portal, and to its wall for another school. */ onend: (o: { wall: boolean }) => void } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  /** Seconds: LAR's own arrival, a slab's grow, the beat between two lines; then characters a second. */
  const HELLO = 0.9;
  const GROW = 0.2;
  const GAP = 0.3;
  const CPS = 42;

  let answers = $state<Answer[]>([]);
  const now = $derived(play(answers));
  /** How many of the thread's items are fully on screen, whether the next has begun, and how much of it is typed. */
  let shown = $state(0);
  let begun = $state(false);
  let typed = $state(0);
  const ready = $derived(shown >= now.items.length);
  const visible = $derived(now.items.slice(0, shown + (begun ? 1 : 0)));
  /** A reply of the step that is asking: by id, or its gold one. */
  const opt = (id?: string) => now.step.replies.find((r) => (id ? r.id === id : r.gold))!;

  let root: HTMLElement;
  let thread = $state<HTMLElement>();
  let lines = $state<HTMLElement>();
  let dock = $state<HTMLElement>();
  let leaving = $state(false);

  // LAR: he comes out of his fire, hops for an answer he likes, and goes back in at the end.
  let lar = $state<State>(reduce ? "idle" : "spawn");
  let gesture = $state<Gesture>("idle");
  let k = $state<number | undefined>();
  let calm: ReturnType<typeof setTimeout> | undefined;
  function react(act?: Act | "nod") {
    clearTimeout(calm);
    lar = act === "think" ? "think" : act === "nod" ? "idle" : "happy";
    gesture = act === "nod" ? "thumbs" : "idle";
    calm = setTimeout(() => ((lar = "idle"), (gesture = "idle")), act === "think" ? 2200 : 1500);
  }

  // The thread types itself, one item after another, and holds still while the app is hidden.
  onMount(() => {
    if (reduce) return;
    let at = -1;
    const hello = setTimeout(() => lar === "spawn" && (lar = "idle"), 1100);
    const stop = animate((ms) => {
      const t = ms / 1000;
      if (at < 0) at = t + HELLO;
      if (leaving && k !== undefined) return;
      const item = now.items[shown];
      if (!item || t < at) return;
      if (!begun) return void ((begun = true), (typed = 0), (at = t));
      const n = item.who === "lar" ? Math.floor((t - at - GROW) * CPS) : Infinity;
      if (item.who !== "lar" ? t - at > GROW : n >= item.text.length) {
        shown += 1;
        begun = false;
        at = t + GAP;
      } else typed = Math.max(0, n);
    }, () => root);
    return () => (stop(), clearTimeout(hello), clearTimeout(calm));
  });
  /** Everything said so far is on screen at once: Reduce Motion, or a tap on the thread. */
  function settle() {
    shown = now.items.length;
    begun = false;
  }
  $effect(() => {
    if (reduce) settle();
  });

  // The thread keeps its newest line in view, clear of the replies lying over its foot.
  let dockH = $state(0);
  let pad = $state(64);
  $effect(() => {
    const h = dockH;
    if (!h || h === pad) return;
    const drop = pad - h;
    pad = h;
    // A shorter reply set lets the thread down: it eases there instead of dropping.
    if (drop > 0 && !reduce) lines?.animate([{ transform: `translateY(${-drop}px)` }, { transform: "none" }], { duration: 320, easing: "cubic-bezier(0.22, 1, 0.36, 1)" });
  });
  $effect(() => {
    void [shown, begun, pad];
    tick().then(() => thread?.scrollTo({ top: thread.scrollHeight, behavior: reduce ? "auto" : "smooth" }));
  });
  // The newest reply set takes the focus, so a keyboard or VoiceOver lands on it.
  $effect(() => {
    void now.step.id;
    if (ready && !leaving && answers.length) tick().then(() => dock?.focus({ preventScroll: true }));
  });

  // What the student is in the middle of saying.
  let draft = $state("");
  let picks = $state<Focus[]>([]);
  const look = $derived(LOOKS.find((l) => l.room === app.room));
  const worn = $derived(isDarkLook(app.room));
  let notice = $state(false);

  function answer(reply: Reply, value?: string) {
    if (!ready || leaving) return;
    buzz.select();
    const step = now.step.id;
    if (step === "name") setName(value ?? "");
    if (step === "campus") setCampus(value ?? null);
    if (step === "focus") setFocus(picks);
    if (reply.act === "remind") remind();
    if (reply.act === "quiet") {
      app.reminderLead = 0;
      try {
        localStorage.setItem("reminderLead", "0");
      } catch {
        // Asked again on You.
      }
    }
    answers = [...answers, { reply: reply.id, value }];
    react(reply.act ?? "nod");
  }
  async function remind() {
    notice = true;
    buzz.done();
    setTimeout(() => (notice = false), 4200);
    await allowReminders();
  }
  function sendName(e: Event) {
    e.preventDefault();
    const name = cleanName(draft);
    if (name) answer(opt("named"), name);
  }
  function pick(f: Focus) {
    buzz.select();
    picks = picks.includes(f) ? picks.filter((p) => p !== f) : [...picks, f];
  }
  function wear(room: string) {
    buzz.select();
    setRoom(room);
    react();
  }

  function back() {
    if (!answers.length || leaving) return;
    buzz.select();
    answers = answers.slice(0, -1);
    shown = Math.min(shown, now.items.length);
    begun = false;
  }
  // Android's back takes the last answer away.
  $effect(() => {
    if (answers.length && !leaving) return closable(back);
  });

  /** On to the portal: the thread fades and LAR goes back into his fire. */
  function leave() {
    if (leaving) return;
    leaving = true;
    const out = { wall: now.wall };
    if (reduce) return onend(out);
    clearTimeout(calm);
    gesture = "idle";
    lar = "spawn";
    const from = performance.now();
    const stop = animate((ms) => {
      k = Math.max(0, 1 - (ms - from) / 650);
      if (k > 0) return;
      stop();
      onend(out);
    }, () => root);
  }
  $effect(() => {
    if (!now.done || !ready || leaving) return;
    const id = setTimeout(leave, reduce ? 900 : 700);
    return () => clearTimeout(id);
  });

  // A few still stars on the night ground; every fifth one twinkles.
  let seed = 7;
  const rnd = () => (seed = (seed * 16807) % 2147483647) / 2147483647;
  const STARS = Array.from({ length: 36 }, (_, i) => ({ x: rnd() * 100, y: rnd() ** 1.6 * 100, big: rnd() < 0.3, a: 0.25 + rnd() * 0.5, tw: i % 5 === 0 ? rnd() * 4 : -1 }));
</script>

<section bind:this={root} class="talk" class:worn class:leaving aria-label="A talk with LAR" style:--portal-accent={portal.theme.accent}>
  <div class="sky" aria-hidden="true">
    {#each STARS as s, i (i)}<i class:big={s.big} class:tw={s.tw >= 0} style:left="{s.x}%" style:top="{s.y}%" style:opacity={s.a} style:animation-delay="{s.tw}s"></i>{/each}
  </div>

  <header class="bar">
    <button type="button" class="back" class:hide={!answers.length} aria-label="Back: take back my last answer" tabindex={answers.length ? 0 : -1} onclick={back}>
      <svg viewBox="0 0 4 7" aria-hidden="true" shape-rendering="crispEdges"><path d="M3 0h1v1H3zM2 1h1v1H2zM1 2h1v1H1zM0 3h1v1H0zM1 4h1v1H1zM2 5h1v1H2zM3 6h1v1H3z" fill="currentColor" /></svg>
    </button>
    <button type="button" class="skip" onclick={leave}>Skip to sign in</button>
  </header>

  <div class="who">
    <Lar size={4} state={lar} {gesture} {k} />
    <p class="tag"><b>LAR</b><span>Lakbay-Aral Robot</span></p>
  </div>

  <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_noninteractive_element_interactions -->
  <div bind:this={thread} class="thread" role="log" aria-live="polite" aria-label="Your talk with LAR" style:--pad="{pad}px" onclick={() => !ready && settle()}>
    <div bind:this={lines} class="lines">
      {#each visible as item, i (i)}
        {#if item.who === "lar"}
          <!-- Screen readers get the whole line at once; the typed copy is only for the eyes. -->
          <p class="msg lar">
            <span class="sr">LAR: {item.text}</span>
            <span class="slab" aria-hidden="true">{#if i < shown}{item.text}{:else}{item.text.slice(0, typed)}<i class="caret"></i><span class="rest">{item.text.slice(typed)}</span>{/if}</span>
          </p>
        {:else if item.who === "you"}
          <p class="msg you"><span class="sr">You: </span><span class="mine">{item.text}</span></p>
        {:else}
          <div class="msg card" inert={item.step !== now.step.id || leaving}>
            {#if item.card === "today"}<ClockCard live={item.step === now.step.id && !leaving} onreact={react} />
            {:else if item.card === "deadlines"}<DueRow onreact={react} />
            {:else if item.card === "grades"}<GpaCard />
            {:else if item.card === "study"}<FlashCard onreact={react} />
            {:else if item.card === "offline"}<SignalCard onreact={react} />
            {:else}
              <Nudge {portal} name={now.name} />
              {#if app.notifications === false}<p class="aside">Your phone said no. You can allow them later in Settings.</p>{/if}
            {/if}
          </div>
        {/if}
      {/each}
    </div>
  </div>

  {#if ready && !now.done && !leaving}
    {#key now.step.id}
      <div bind:this={dock} bind:clientHeight={dockH} class="dock" role="group" aria-label="Your reply" tabindex="-1">
        {#if now.step.ask === "name"}
          <form class="row" onsubmit={sendName}>
            <input class="field" bind:value={draft} maxlength={MAX_NAME} placeholder="Your name" aria-label="Your name" autocomplete="given-name" autocapitalize="words" enterkeyhint="send" spellcheck="false" />
            <button class="go" disabled={!cleanName(draft)}>{opt("named").label}</button>
          </form>
          <div class="row">
            <button type="button" class="chip" onclick={() => answer(opt("skip"))}>{opt("skip").label}</button>
            <small class="aside">Optional. It stays on this phone.</small>
          </div>
        {:else if now.step.ask === "campus"}
          <div class="campuses" role="group" aria-label="PUP campus">
            {#each CAMPUSES as c (c)}<button type="button" class="chip" onclick={() => answer(opt("pup"), c)}>{c}</button>{/each}
          </div>
          {#if portals.length > 1}
            <div class="row">
              <button type="button" class="chip" onclick={() => answer(opt("other"))}><span class="glyph"><MiniPortal portal={portals.find((p) => p.id !== "sis") ?? portals[1]} /></span>{opt("other").label}</button>
            </div>
          {/if}
        {:else if now.step.ask === "focus"}
          <div class="grid two">
            {#each FOCUS as f (f.id)}<button type="button" class="chip" class:picked={picks.includes(f.id)} aria-pressed={picks.includes(f.id)} onclick={() => pick(f.id)}>{f.label}</button>{/each}
          </div>
          <button type="button" class="go" onclick={() => (picks.length ? answer(opt("picked"), picks.join(",")) : answer(opt("all")))}>{opt(picks.length ? "picked" : "all").label}</button>
        {:else if now.step.ask === "look"}
          <div class="grid three">
            {#each LOOKS as l (l.room)}
              <button type="button" class="chip" class:picked={app.room === l.room} aria-pressed={app.room === l.room} onclick={() => wear(l.room)}>
                <svg class="tones" viewBox="0 0 24 14" aria-hidden="true" shape-rendering="crispEdges">{#each l.swatch as c, j (j)}<rect x={j * 8} width="8" height="14" fill={c} />{/each}</svg>
                {l.name}
              </button>
            {/each}
          </div>
          <button type="button" class="go" onclick={() => answer(opt(), look?.name)}>{opt().label}</button>
        {:else}
          <div class="row">
            {#each now.step.replies as r (r.id)}<button type="button" class={r.gold ? "go" : "chip"} onclick={() => answer(r)}>{r.label}</button>{/each}
          </div>
        {/if}
      </div>
    {/key}
  {/if}

  {#if notice}
    <div class="note-slot" transition:fly={{ y: reduce ? 0 : -120, duration: reduce ? 160 : 550, easing: cubicOut }}><Nudge {portal} name={now.name} /></div>
  {/if}
</section>

<style>
  /* Bar, LAR, thread: the thread takes whatever height is left, and the replies lie over its foot. */
  .talk {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto auto minmax(0, 1fr);
    padding: calc(var(--safe-top) + 10px) var(--gutter) 0;
    color: var(--parch);
    font-family: var(--font-ui);
    /* Night and stars, nothing else, as on the landing (spec 010 C3); a dark look colours it. */
    background-color: var(--void);
    transition: background-color var(--t-flow) var(--ease);
  }
  .talk.worn {
    background-color: var(--ground);
  }
  ::selection {
    background: rgb(245 178 39 / 0.35);
  }
  .sky {
    position: absolute;
    inset: 0;
    overflow: hidden;
    pointer-events: none;
    transition: opacity var(--t-hero) var(--ease);
  }
  .sky i {
    position: absolute;
    width: 2px;
    height: 2px;
    background: var(--parch);
  }
  .sky i.big {
    width: 3px;
    height: 3px;
  }
  .sky i.tw {
    animation: twinkle 3.4s steps(1) infinite;
  }
  :global(:root[data-hidden]) .sky i.tw {
    animation-play-state: paused;
  }
  @keyframes twinkle {
    50% {
      opacity: 0.1;
    }
  }

  .bar {
    position: relative;
    display: flex;
    align-items: center;
    justify-content: space-between;
    min-height: 44px;
    transition: opacity var(--t-flow) var(--ease);
  }
  .hide {
    visibility: hidden;
  }
  .back {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    margin-left: -10px;
    border: 0;
    border-radius: var(--radius);
    background: none;
    color: rgb(244 236 216 / 0.8);
  }
  .back svg {
    width: 8px;
    height: 14px;
  }
  .skip {
    min-height: 44px;
    margin-right: -6px;
    padding: 0 6px;
    border: 0;
    border-radius: var(--radius);
    background: none;
    color: rgb(244 236 216 / 0.72);
    font: 600 var(--text-caption) var(--font-ui);
  }
  .back:focus-visible,
  .skip:focus-visible,
  .chip:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }

  /* LAR, large, with his name under him. */
  .who {
    position: relative;
    display: grid;
    justify-items: center;
    gap: 14px;
    padding: 14px 0 10px;
    pointer-events: none;
  }
  .tag {
    display: flex;
    align-items: baseline;
    gap: 8px;
    margin: 0;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
    transition: opacity var(--t-flow) var(--ease);
  }
  .tag b {
    font: 400 var(--text-body) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--portal-gold);
  }

  .thread {
    position: relative;
    display: flex;
    flex-direction: column;
    min-height: 0;
    margin-inline: calc(var(--gutter) * -1);
    padding: 16px var(--gutter) calc(var(--pad) + var(--safe-bottom) + 28px);
    overflow-y: auto;
    overscroll-behavior: contain;
    scrollbar-width: none;
    mask-image: linear-gradient(to bottom, transparent, #000 20px);
    transition: opacity var(--t-flow) var(--ease);
  }
  .thread::-webkit-scrollbar {
    display: none;
  }
  /* A short thread starts at the top, under LAR, and grows down toward the replies. */
  .lines {
    display: grid;
    gap: 8px;
    width: 100%;
    max-width: 30rem;
    margin: 0 auto;
  }
  .msg {
    margin: 0;
    min-width: 0;
  }
  /* LAR's lines: his obsidian slab, growing out of his side in whole steps like the rest of him. */
  .lar {
    justify-self: start;
    max-width: 86%;
  }
  .slab {
    display: block;
    padding: 9px 12px;
    background: var(--void-3);
    box-shadow:
      inset 0 2px 0 var(--slab-edge),
      inset 0 -2px 0 var(--void-ink);
    font: 400 var(--text-body) / 1.4 var(--font-ui);
    color: var(--parch);
    text-wrap: pretty;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    transform-origin: 0 0;
    animation: grow 0.2s steps(4, end) both;
  }
  @keyframes grow {
    from {
      transform: scale(0.2);
    }
  }
  /* The not-yet-typed rest keeps its room, so a slab never changes size. */
  .rest {
    visibility: hidden;
  }
  .caret {
    position: relative;
    display: inline-block;
    width: 0;
    height: 1em;
    vertical-align: -0.14em;
  }
  .caret::after {
    content: "";
    position: absolute;
    left: 1px;
    top: 0;
    width: 3px;
    height: 100%;
    background: var(--portal-gold);
    animation: blink 0.5s steps(1) infinite;
  }
  @keyframes blink {
    50% {
      opacity: 0;
    }
  }
  .card {
    width: min(100%, 22rem);
    padding-block: 2px 4px;
    transform-origin: 0 0;
    animation: grow 0.2s steps(4, end) both;
  }
  .card[inert] {
    opacity: 0.6;
    transition: opacity var(--t-flow) var(--ease);
  }
  /* The student's lines: quiet and round, rising from the replies they were picked from. */
  .you {
    justify-self: end;
    max-width: 80%;
    animation: rise var(--t-move) var(--ease) both;
  }
  .mine {
    display: block;
    padding: 9px 14px;
    border-radius: var(--radius-lg);
    background: rgb(244 236 216 / 0.12);
    font: 500 var(--text-body) / 1.4 var(--font-ui);
    color: var(--cream);
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(18px);
    }
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  .aside {
    margin: 0;
    font: 400 var(--text-caption) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  .card .aside {
    margin-top: 6px;
  }

  /* The replies, in thumb reach; each new set slides up. */
  .dock {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    display: grid;
    gap: 8px;
    width: 100%;
    max-width: calc(30rem + var(--gutter) * 2);
    margin: 0 auto;
    padding: 0 var(--gutter) calc(var(--safe-bottom) + 12px);
    outline: none;
    animation: rise var(--t-flow) var(--ease) both;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 8px;
    min-width: 0;
  }
  .grid {
    display: grid;
    gap: 8px;
  }
  .grid.two {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
  .grid.three {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
  .chip {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 8px;
    min-width: 0;
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: var(--void-lift);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--parch);
    white-space: nowrap;
    transition: box-shadow var(--t-quick) var(--ease);
  }
  .grid.three .chip {
    padding: 0 8px;
    gap: 6px;
    font-size: var(--text-caption);
  }
  .chip:active {
    background: var(--void-3);
  }
  /* Gold says "this one": a picked focus, the worn look. */
  .chip.picked {
    box-shadow: inset 0 0 0 1.5px var(--portal-gold);
    color: var(--cream);
  }
  /* Two rows of campuses that scroll sideways; the far edge fades to say there is more. */
  .campuses {
    display: grid;
    grid-auto-flow: column;
    grid-template-rows: repeat(2, auto);
    justify-content: start;
    gap: 8px;
    margin-inline: calc(var(--gutter) * -1);
    padding: 2px var(--gutter);
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scrollbar-width: none;
    mask-image: linear-gradient(to right, #000 calc(100% - 36px), transparent);
  }
  .campuses::-webkit-scrollbar {
    display: none;
  }
  .glyph {
    width: 10px;
    height: 14px;
  }
  .tones {
    flex: none;
    display: block;
    width: 24px;
    height: 14px;
    box-shadow: 0 0 0 1px rgb(244 236 216 / 0.25);
  }
  /* The name: the landing's own well, with LAR's question as its label. */
  .field {
    flex: 1;
    min-width: 0;
    height: 50px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: var(--void);
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    color: var(--white);
    font: 400 var(--text-input) / 1.25 var(--font-ui);
    caret-color: var(--portal-gold);
    outline: none;
    -webkit-appearance: none;
    appearance: none;
    transition: box-shadow var(--t-quick) var(--ease);
  }
  .field::placeholder {
    color: rgb(244 236 216 / 0.55);
  }
  .field:focus {
    box-shadow: inset 0 0 0 1.5px var(--portal-gold);
  }
  /* The one gold action: the landing's portal button. */
  .go {
    flex: 1;
    min-width: 0;
    height: 50px;
    padding: 0 20px;
    border: 0;
    background: var(--portal-gold);
    color: var(--on-portal-gold);
    font: 600 var(--text-body) var(--font-ui);
    letter-spacing: 0.01em;
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
    box-shadow: inset 0 -3px 0 var(--portal-gold-shade);
  }
  form .go {
    flex: none;
  }
  .go:focus-visible {
    outline: none;
    box-shadow:
      inset 0 0 0 3px var(--cream),
      inset 0 -3px 0 var(--portal-gold-shade);
  }
  .go:active {
    box-shadow: inset 0 3px 0 var(--portal-gold-shade);
    transform: translateY(1px);
  }
  .go:disabled {
    opacity: 0.45;
  }
  .note-slot {
    position: fixed;
    top: calc(var(--safe-top) + 8px);
    left: var(--gutter);
    right: var(--gutter);
    z-index: 62;
    filter: drop-shadow(0 10px 30px rgb(0 0 0 / 0.5));
  }

  /* The handoff: the talk fades, and LAR alone goes back into his fire. */
  .leaving .bar,
  .leaving .tag,
  .leaving .thread,
  .leaving .sky {
    opacity: 0;
  }
  @media (prefers-reduced-motion: reduce) {
    .slab,
    .card,
    .you,
    .dock {
      animation: none;
    }
    .sky i.tw {
      animation: none;
    }
    .caret {
      display: none;
    }
  }
</style>

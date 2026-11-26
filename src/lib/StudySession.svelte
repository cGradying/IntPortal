<script lang="ts" module>
  export type { Mode } from "./study/game";
</script>

<script lang="ts">
  // One pass through due cards, played as a game (spec 055; the owner's picks, 2026-11-17):
  // the card on the calm room with a dithered pile (Deck B), LAR as a companion over a combo
  // HUD and two-step results (Run A), and a soft clock that heats the swirl (Heat B).
  // One deck's due cards (every card when none is due, as practice), or every deck's at once,
  // oldest due first (spec 040 C9). Flashcards take the student's own rating; typed and
  // multiple-choice answers rate themselves: right is Good, wrong is Again. A missed card comes
  // back once, three cards later, as practice: only its first answer is scheduled.
  // Quiz deals each card as Choice, Type or true or false, from the same parts (spec 063 C7–C10).
  import { friendly } from "./errors";
  import { closable } from "./back";
  import WhyButton from "./assis/WhyButton.svelte";
  import Lar from "./lar/Lar.svelte";
  import PixelNum from "./PixelNum.svelte";
  import { api, isoDate, type Card, type Deck, type Rating } from "./api";
  import { app } from "./state.svelte";
  import { buzz } from "./haptics";
  import { sfx } from "./sound";
  import { dueQueue, type Entry } from "./dueQueue";
  import { dueIn, interval } from "./interval";
  import { ms, reduced as still, tokens } from "./motion";
  import { clockSecs, fresh, mult, play, readBest, requeue, saveBest, toNext, type Answer, type Face, type Mode } from "./study/game";
  import { claimFor, faceFor, optionsFor } from "./study/quiz";
  import { bursts, kick, swirl, table } from "./study/fx";
  import { chip } from "./assis/AssisWindow.svelte";
  import { onMount } from "svelte";
  import type { State as LarState } from "./lar/sprite";

  let { decks, mode, onclose, title, all = false, limit = 0 }: { decks: Deck[]; mode: Mode; onclose: () => void; title?: string; all?: boolean; limit?: number } = $props();
  $effect(() => closable(() => onclose()));

  type Item = Entry & { again: boolean };
  type Seg = "todo" | "ok" | "miss" | "re";
  type Logged = { key: string; entry: Entry; rating: Rating; due: number | null; missed: boolean };

  const now = Math.floor(Date.now() / 1000);
  // svelte-ignore state_referenced_locally
  const mixed = all || decks.length > 1;
  // svelte-ignore state_referenced_locally
  const due: Entry[] = dueQueue(decks, now);
  // svelte-ignore state_referenced_locally
  const firstPass: Entry[] = (mixed ? due : shuffle(due.length ? due : decks[0].cards.map((card) => ({ deck: decks[0], card })))).slice(0, limit || undefined);
  // svelte-ignore state_referenced_locally
  const name = title ?? decks[0]?.name ?? "";
  // svelte-ignore state_referenced_locally
  const bestOf = mixed ? "all" : (decks[0]?.id ?? "all");
  // Effects follow You's Motion setting (047 C8) and Reduce Motion: full, calm (no shake, fewer bits) or off.
  const fx = still() ? "off" : app.effects;
  const moving = fx !== "off";
  // Short phones (an SE, a 568-tall screen): LAR steps down a size so the card and its answers fit one screen.
  const SHORT = "(max-height: 760px)";
  let short = $state(typeof matchMedia === "function" && matchMedia(SHORT).matches);
  // --t-hero: a card's deal and a missed card's tuck.
  const hero = () => ms(getComputedStyle(document.documentElement).getPropertyValue("--t-hero"), 550);

  let practice = $state(due.length === 0);
  let queue = $state<Item[]>([]);
  let segs = $state<Seg[]>([]);
  let pos = $state(0);
  let deal = $state(0);
  let run = $state(fresh());
  let stage = $state<"play" | "tally" | "list">("play");
  let log = $state<Logged[]>([]);
  let best = $state(0);
  let newBest = $state(false);
  let filter = $state<"all" | "missed" | "right">("all");

  // The card in front.
  let shown = $state(false);
  let ready = $state(false);
  let locked = $state(false);
  let missed = $state(false);
  let typed = $state("");
  let verdict = $state<null | boolean>(null);
  let options = $state<string[]>([]);
  let picked = $state<string | null>(null);
  let hints = $state<string[] | null>(null);
  // How the card in front is shown: the mode itself, or in a Quiz the face it was dealt.
  // svelte-ignore state_referenced_locally
  let face = $state<Face>(mode === "quiz" ? "choice" : mode);
  let claim = $state<{ claim: string; truth: boolean } | null>(null);
  let faces: Face[] = [];
  let claims = { t: 0, f: 0 };
  let problem = $state("");
  let t0 = 0;
  let lifted = false;
  let leaving: Answer = "right";
  let timer = 0;

  // LAR's line and state (Run A's companion), in light Taglish (PRODUCT.md voice).
  let line = $state("");
  let lar = $state<LarState>("idle");
  let larTimer = 0;
  function say(text: string, state: LarState = "idle", ms = 0) {
    line = text;
    lar = state;
    clearTimeout(larTimer);
    if (ms) larTimer = window.setTimeout(() => (lar = "idle"), ms);
  }
  const pickOne = (xs: string[]) => xs[Math.floor(Math.random() * xs.length)];

  const item = $derived(queue[pos] as Item | undefined);
  const card = $derived(item?.card as Card);
  const deck = $derived(item?.deck ?? decks[0]);
  const m = $derived(mult(run.streak));
  const next = $derived(toNext(run.streak));
  const okCount = $derived(segs.filter((s) => s === "ok").length);
  // Misses first, then in the order they came.
  const shownLog = $derived(log.filter((l) => (filter === "all" ? true : filter === "missed" ? l.missed : !l.missed)).sort((x, y) => Number(y.missed) - Number(x.missed)));
  const missedLog = $derived(log.filter((l) => l.missed));
  const RATES: [Rating, string][] = [["again", "Again"], ["hard", "Hard"], ["good", "Good"], ["easy", "Easy"]];
  const word = (r: Rating) => RATES.find(([k]) => k === r)![1];

  function shuffle<T>(xs: T[]): T[] {
    const a = [...xs];
    for (let i = a.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [a[i], a[j]] = [a[j], a[i]];
    }
    return a;
  }

  function begin(entries: Entry[], asPractice: boolean, hello: string) {
    clearTimeout(timer);
    lifted = false;
    practice = asPractice;
    queue = entries.map((e) => ({ ...e, again: false }));
    segs = entries.map(() => "todo");
    pos = 0;
    run = fresh();
    log = [];
    stage = "play";
    filter = "all";
    newBest = false;
    best = readBest(bestOf);
    faces = [];
    claims = { t: 0, f: 0 };
    disp = 0;
    tally = 0;
    table.heat = 0;
    kick();
    say(hello);
    show();
  }

  // The next card: reset its state, deal it, load its intervals or options, and start the clock when it lands.
  function show() {
    clearTimeout(timer);
    resetCard();
    deal++;
    const it = queue[pos];
    if (!it) return;
    const c = it.card;
    face = mode === "quiz" ? faceFor(faces, c) : mode;
    faces.push(face);
    claim = face === "tf" ? claimFor(c, claims) : null;
    if (mode === "flash" && !practice && !it.again) api.reviewPreview(c.memory).then((ss) => { if (card === c) hints = ss.map(interval); }, () => {});
    // A card with its own three wrong answers offers them (C7); the rest take other cards' backs.
    const own = face === "choice" ? optionsFor(c) : null;
    if (own) options = own;
    else if (face === "choice") {
      const at = it.deck.cards.findIndex((x) => x.id === c.id);
      // If the core can't pick distractors, three other backs from the deck keep the card answerable.
      const local = () => shuffle(it.deck.cards.filter((x) => x.id !== c.id && x.back !== c.back).map((x) => x.back)).slice(0, 3);
      api.distractors(it.deck.cards, at, pos).then((ds) => { if (card === c) options = shuffle([c.back, ...ds]); }, () => { if (card === c) options = shuffle([c.back, ...local()]); });
    }
    timer = window.setTimeout(dealt, moving ? hero() : tokens().quick);
  }

  function resetCard() {
    shown = false;
    ready = false;
    locked = false;
    missed = false;
    typed = "";
    verdict = null;
    picked = null;
    problem = "";
    hints = null;
    options = [];
    ring = 0;
    t0 = 0;
  }

  // The deal ends: the soft clock starts (spec 055 C6).
  function dealt() {
    // When the answers would sit under the class bar or the tabs ([data-chrome]), scroll once,
    // just enough to clear them and never past the score panel; the back row is one scroll up (C15).
    if (!lifted) {
      lifted = true;
      const answers = root.querySelector(".opts, .rates, .typed");
      const panel = root.querySelector(".panel");
      const floor = Math.min(innerHeight, ...[...document.querySelectorAll("[data-chrome]")].map((e) => e.getBoundingClientRect().top).filter((y) => y > innerHeight / 2));
      if (answers && panel) {
        const need = answers.getBoundingClientRect().bottom - (floor - 8);
        const room = panel.getBoundingClientRect().top - 8;
        // A panel above the screen (Practice misses from a scrolled list) comes back down to the top.
        const by = room < 0 ? room : Math.min(need, room);
        if (by > 0 || room < 0) window.scrollBy({ top: by });
      }
    }
    ready = true;
    t0 = performance.now();
    loop();
  }

  function flip() {
    if (!ready || shown || mode !== "flash") return;
    buzz.tick();
    shown = true;
  }

  async function answer(kind: Answer, rating: Rating) {
    if (!item || locked || !ready) return;
    clearTimeout(timer);
    locked = true;
    const it = item;
    const secs = (performance.now() - t0) / 1000;
    let dueAt: number | null = null;
    try {
      // Practice (nothing was due, or a card coming back) leaves the schedule alone.
      if (!practice && !it.again) dueAt = (await api.reviewCard(it.deck.id, it.card.id, rating, isoDate(new Date()))).deck.cards.find((c) => c.id === it.card.id)?.memory.due ?? null;
    } catch (e) {
      problem = friendly(e);
      locked = false;
      picked = null;
      verdict = null;
      return;
    }
    if (!alive) return;
    const key = `${it.deck.id}/${it.card.id}`;
    if (!log.some((l) => l.key === key)) log.push({ key, entry: { deck: it.deck, card: it.card }, rating, due: dueAt, missed: kind === "miss" });
    const p = play(run, kind, secs, face);
    run = p.run;
    if (table.heat !== run.heat) {
      table.heat = run.heat;
      kick();
    }
    leaving = kind;
    if (kind === "miss") {
      segs[pos] = "miss";
      if (!it.again) {
        queue = requeue(queue, pos, { ...it, again: true });
        segs = requeue(segs, pos, "re" as Seg);
      }
      missed = true;
      buzz.fail();
      sfx.miss();
      say("Balikan natin 'to.", "error", 1100);
      // A flashcard rated Again has shown its answer already; it tucks back on its own.
      if (mode === "flash") timer = window.setTimeout(advance, hero());
      return;
    }
    segs[pos] = "ok";
    bump = 1;
    burstFromCard(p.tierUp ? 40 : 18);
    if (p.tierUp) {
      trauma = fx === "full" ? 0.7 : 0;
      buzz.press();
      sfx.tier(run.streak - 1);
      say(["", "", "Tatlo na!", "Anim na!", "Sampu na!"][m], "happy", 1400);
    } else {
      buzz.tick();
      if (kind === "right") sfx.right(Math.max(0, run.streak - 1));
      say(kind === "hard" ? "Okay, dahan-dahan." : p.quick ? "Bilis mo!" : pickOne(["Tama!", "Galing!", "Sige pa!", "Ayos!"]), "happy", 1000);
    }
    loop();
    timer = window.setTimeout(advance, mode === "flash" ? tokens().move : hero());
  }

  function advance() {
    // Only an answered card moves on, so a double tap on Next can't skip the next one.
    if (!locked) return;
    clearTimeout(timer);
    pos++;
    if (pos >= queue.length) return finish();
    show();
    if (pos === queue.length - 1) say("Huling isa!");
  }

  async function check() {
    if (!typed.trim() || locked || !ready) return;
    try {
      verdict = await api.checkAnswer(card, typed);
    } catch (e) {
      problem = friendly(e);
      return;
    }
    answer(verdict ? "right" : "miss", verdict ? "good" : "again");
  }

  function choose(o: string) {
    if (picked || locked || !ready) return;
    picked = o;
    verdict = o === card.back;
    answer(verdict ? "right" : "miss", verdict ? "good" : "again");
  }

  // True or false: the claim on the card is right or it isn't.
  function judge(says: boolean) {
    if (picked || locked || !ready || !claim) return;
    picked = says ? "True" : "False";
    verdict = says === claim.truth;
    answer(verdict ? "right" : "miss", verdict ? "good" : "again");
  }

  function finish() {
    stage = "tally";
    table.heat = 0;
    buzz.done();
    if (!practice && run.score > best) {
      newBest = best > 0;
      saveBest(bestOf, run.score);
    }
    tallyFrom = performance.now();
    say(newBest ? "Bagong rekord!" : missedLog.length ? "Balikan natin ang mali." : "Ang galing mo!", "happy", 1800);
    loop();
  }

  // ---- motion: deal from the pile, fly off right, tuck back under (Deck B) ----
  const spring = (k: number) => (k >= 1 ? 1 : 1 - Math.exp(-6.5 * k) * Math.cos(k * 9));
  function dealIn(_n: Element) {
    if (!moving) return { duration: tokens().quick, css: (k: number) => `opacity:${k}` };
    return {
      duration: hero(),
      css: (k: number) => {
        const s = spring(k);
        const f = 1 - (1 - Math.min(1, Math.max(0, (k - 0.3) / 0.6))) ** 3;
        return `transform: translate(${-14 * (1 - s)}px, ${36 * (1 - s)}px) rotate(${-8 * (1 - s)}deg) scale(${0.82 + 0.18 * s}) rotateY(${180 * (1 - f)}deg)`;
      },
    };
  }
  function leave(_n: Element) {
    const kind = leaving;
    if (!moving) return { duration: tokens().quick, css: (k: number) => `opacity:${k}` };
    return {
      duration: tokens().move,
      css: (k: number, u: number) =>
        kind === "miss"
          ? `transform: translate(${-10 * u}px, ${30 * u}px) scale(${1 - 0.18 * u}) rotateY(${180 * u}deg); opacity:${k}`
          : `transform: translate(${110 * u}%, ${-30 * u}px) rotate(${16 * u}deg); opacity:${k}`,
    };
  }

  // Tilt toward the finger (up to 8°), springing back on release.
  let rx = $state(0);
  let ry = $state(0);
  let tableEl = $state<HTMLElement>();
  function aim(e: PointerEvent) {
    if (!moving || !ready || locked) return;
    const r = tableEl!.getBoundingClientRect();
    ry = Math.max(-1, Math.min(1, (e.clientX - r.left - r.width / 2) / (r.width / 2))) * 8;
    rx = -Math.max(-1, Math.min(1, (e.clientY - r.top - r.height / 2) / (r.height / 2))) * 8;
  }
  const rest = () => (rx = ry = 0);

  // ---- one loop: the score counting, its bump, the shake, the clock ring and the tally ----
  let root: HTMLElement;
  let fxCv: HTMLCanvasElement;
  let pops: ReturnType<typeof bursts> | null = null;
  let disp = $state(0);
  let bump = $state(0);
  let trauma = 0;
  let shake = $state("");
  let ring = $state(0);
  let tallyFrom = 0;
  let tally = $state(0);
  let raf = 0;
  let prev = 0;
  let alive = true;
  let hiddenAt = 0;
  function loop() {
    if (!raf) {
      prev = performance.now();
      raf = requestAnimationFrame(tick);
    }
  }
  function tick(nowMs: number) {
    raf = 0;
    if (document.hidden) return;
    const dt = Math.min(0.05, (nowMs - prev) / 1000);
    prev = nowMs;
    let busy = false;
    if (disp !== run.score) {
      disp = !moving || Math.abs(run.score - disp) < 0.5 ? run.score : disp + (run.score - disp) * (1 - Math.exp(-dt * 9));
      busy = true;
    }
    if (bump > 0.01) {
      bump = moving ? bump * Math.exp(-dt * 8) : 0;
      busy = true;
    } else bump = 0;
    if (trauma > 0) {
      trauma = Math.max(0, trauma - dt * 1.6);
      const k = trauma * trauma * 8;
      shake = trauma ? `${((Math.random() - 0.5) * 2 * k).toFixed(1)}px ${((Math.random() - 0.5) * 2 * k).toFixed(1)}px` : "";
      busy = true;
    }
    if (stage === "play" && ready && !locked && t0) {
      ring = Math.min(1, (nowMs - t0) / 1000 / clockSecs(face));
      busy ||= ring < 1;
    }
    if (stage === "tally" && tally !== run.score) {
      const k = moving ? Math.min(1, (nowMs - tallyFrom) / 1100) : 1;
      tally = Math.round(run.score * (1 - (1 - k) ** 3));
      busy = true;
    }
    if (busy) raf = requestAnimationFrame(tick);
  }

  function burstFromCard(n: number) {
    if (!pops || fx === "off") return;
    const slot = root.querySelector(".slot");
    if (!slot) return;
    const a = root.getBoundingClientRect();
    const b = slot.getBoundingClientRect();
    pops.burst(b.left - a.left + b.width / 2, b.top - a.top + b.height / 2, fx === "calm" ? Math.round(n / 3) : n);
  }

  onMount(() => {
    table.still = !moving;
    pops = bursts(fxCv);
    // LAR is already at the table, so his floating crystal steps aside and stops covering Next (C2).
    const was = chip.at;
    chip.at = "hidden";
    // The soft clock only counts time the app is on screen.
    const wake = () => {
      if (document.hidden) hiddenAt = performance.now();
      else {
        // Only a card that was already on the table while hidden gets its clock moved.
        if (hiddenAt && t0 && t0 < hiddenAt) t0 += performance.now() - hiddenAt;
        hiddenAt = 0;
        loop();
      }
    };
    document.addEventListener("visibilitychange", wake);
    const mq = matchMedia(SHORT);
    const fit = () => (short = mq.matches);
    mq.addEventListener("change", fit);
    begin(firstPass, practice, "Tara, simulan natin!");
    return () => {
      alive = false;
      mq.removeEventListener("change", fit);
      document.removeEventListener("visibilitychange", wake);
      cancelAnimationFrame(raf);
      clearTimeout(timer);
      clearTimeout(larTimer);
      pops?.stop();
      table.heat = 0;
      chip.at = was;
    };
  });
</script>

<div class="session" bind:this={root} role="dialog" aria-label="Studying {name}" style:translate={shake || null}>
  <header>
    <button class="back" onclick={onclose}>‹ {name}</button>
    <p class="label num">{stage === "play" ? `${Math.min(pos + 1, queue.length)} / ${queue.length}` : "Results"}{practice ? " · practice" : ""}</p>
  </header>
  <div class="segs" role="progressbar" aria-label="Cards done" aria-valuemin={0} aria-valuemax={segs.length} aria-valuenow={okCount}>
    {#each segs as s, i (i)}<i class={s} class:cur={stage === "play" && i === pos}></i>{/each}
  </div>

  {#if stage === "play" && item}
    <div class="panel notch">
      <canvas class="sw" use:swirl aria-hidden="true"></canvas>
      <div class="hud">
        {#key m}<b class="stamp" class:on={m > 1} aria-label="Combo times {m}">x{m}</b>{/key}
        <div class="meter">
          <span class="track" aria-hidden="true"><i style:width="{(next?.frac ?? 1) * 100}%"></i></span>
          <span class="to">{next ? `x${m + 1} in ${next.need}` : "Max combo"}</span>
        </div>
        <svg class="clock" class:late={ring > 0.5} viewBox="0 0 30 30" width="26" height="26" aria-hidden="true">
          <circle cx="15" cy="15" r="11" class="rb" />
          <circle cx="15" cy="15" r="11" class="rp" transform="rotate(-90 15 15)" style:stroke-dashoffset={(69.1 * ring).toFixed(1)} />
        </svg>
        <span class="heat" role="img" aria-label="Heat {run.heat + 1} of 4">{#each [0, 1, 2, 3] as h (h)}<i class:on={h <= run.heat}></i>{/each}</span>
        <span class="score" style:scale={moving ? 1 + 0.35 * bump : null}><PixelNum text={String(Math.round(disp))} size={3} /></span>
      </div>
    </div>

    <div class="comp">
      <Lar size={short ? 2 : 3} state={lar} />
      <p class="bub" aria-live="polite">{line}</p>
    </div>

    <div class="table" role="group" aria-label="Card" bind:this={tableEl} onpointermove={aim} onpointerdown={aim} onpointerleave={rest} onpointerup={(e) => e.pointerType !== "mouse" && rest()}>
      <div class="pile" aria-hidden="true">
        {#if queue.length - pos > 2}<div class="under b2 notch"><canvas use:swirl></canvas></div>{/if}
        {#if queue.length - pos > 1}<div class="under b1 notch"><canvas use:swirl></canvas></div>{/if}
      </div>
      {#key deal}
        <!-- The tap lands on the slot, which holds still once dealt: a press near the card's edge tilts
             the card out from under the finger, so a click on the card itself would miss. Keys still
             reach the button. -->
        <!-- svelte-ignore a11y_click_events_have_key_events, a11y_no_static_element_interactions -->
        <div class="slot" in:dealIn|global out:leave onclick={flip}>
          <div class="sway" class:on={moving && !locked} style:--amp="{0.8 + run.heat * 0.5}deg">
            <div class="tilt" class:shake={missed && fx === "full"} style:--rx="{rx}deg" style:--ry="{ry}deg">
              <div class="cover notch" aria-hidden="true"><canvas use:swirl></canvas></div>
              {#if mode === "flash"}
                <button class="flipper" class:shown aria-label={shown ? undefined : `${card.front}. Tap to show the meaning`}>
                  <span class="side face notch" aria-hidden={shown}>
                    <span class="label">{mixed ? deck.name : "Term"}</span>
                    <span class="term">{card.front}</span>
                    <span class="fine">Tap to show the meaning</span>
                  </span>
                  <span class="side rev face notch" aria-hidden={!shown}>
                    <span class="label">{mixed ? deck.name : "Term"}</span>
                    <span class="term">{card.front}</span>
                    <span class="answer">{card.back}</span>
                  </span>
                </button>
              {:else}
                <section class="face notch solo">
                  <span class="label">{face === "tf" ? card.front : mixed ? deck.name : face === "type" ? "Type the term" : "Pick the meaning"}</span>
                  {#if face === "type"}<span class="mean">{card.back}</span>{:else if face === "tf"}<span class="mean">{claim?.claim}</span>{:else}<span class="term">{card.front}</span>{/if}
                  {#if face === "type" && verdict === false}<span class="reveal">It's <b>{card.front}</b>.</span>{/if}
                  {#if face === "tf" && picked && !claim?.truth}<span class="reveal">It's <b>{card.back}</b>.</span>{/if}
                </section>
              {/if}
            </div>
          </div>
        </div>
      {/key}
    </div>

    {#if mode === "flash"}
      <div class="rates">
        {#each RATES as [r, label], i (r)}
          <button class="tile" class:again={r === "again"} disabled={!shown || locked} onclick={() => answer(r === "again" ? "miss" : r === "hard" ? "hard" : "right", r)} aria-label={hints ? `${label}, next in ${hints[i]}` : label}>
            <b>{label}</b><small aria-hidden="true">{hints?.[i] ?? ""}</small>
          </button>
        {/each}
      </div>
    {:else if face === "type"}
      <div class="typed">
        <input bind:value={typed} readonly={locked} class:ok={verdict === true} class:no={verdict === false} autocapitalize="off" spellcheck="false" placeholder="Type the term" aria-label="Your answer" oninput={() => { if (!locked) say("Isipin mo muna…", "think", 1600); }} onkeydown={(e) => e.key === "Enter" && (missed ? advance() : check())} />
        <button class="tile go" onclick={check} disabled={!typed.trim() || locked}>Check</button>
      </div>
    {:else if face === "tf" && claim}
      <div class="opts tf" role="group" aria-label="Is it true?">
        {#each [true, false] as t (t)}
          {@const label = t ? "True" : "False"}
          <button class="tile opt" class:ok={picked !== null && t === claim.truth} class:no={picked === label && t !== claim.truth} class:shake={picked === label && t !== claim.truth && fx === "full"} disabled={picked !== null && label !== picked && t !== claim.truth} onclick={() => judge(t)}>{label}</button>
        {/each}
      </div>
    {:else}
      <div class="opts">
        {#each options as o (o)}
          <button class="tile opt" class:ok={picked !== null && o === card.back} class:no={picked === o && o !== card.back} class:shake={picked === o && o !== card.back && fx === "full"} disabled={picked !== null && o !== picked && o !== card.back} onclick={() => choose(o)}>{o}</button>
        {/each}
      </div>
    {/if}

    {#if missed && mode !== "flash"}
      <div class="foot">
        <WhyButton front={card.front} back={card.back} typed={face === "type" ? typed : face === "tf" ? (claim?.truth ? "" : (claim?.claim ?? "")) : (picked ?? "")} subject={deck.subject} />
        <button class="tile go" onclick={advance}>Next</button>
      </div>
    {/if}
  {:else if stage === "tally"}
    <section class="res card notch">
      <div class="who"><Lar size={3} state={lar} /><p class="bub" aria-live="polite">{line}</p></div>
      <p class="label">{name}</p>
      <div class="big"><PixelNum text={String(tally)} size={6} /><span class="label">pts</span></div>
      {#if newBest}<b class="newbest">New best</b>{/if}
      <dl class="stats">
        <div><dt>Best combo</dt><dd>x{mult(run.top)} · {run.top} in a row</dd></div>
        <div><dt>Accuracy</dt><dd>{run.tries ? Math.round((run.rights / run.tries) * 100) : 0}%</dd></div>
        <div><dt>Right first try</dt><dd>{log.filter((l) => !l.missed).length} / {log.length}</dd></div>
        {#if !practice}<div><dt>{newBest ? "Previous best" : "Personal best"}</dt><dd>{newBest ? best : Math.max(best, run.score)}</dd></div>{/if}
      </dl>
      <p class="fine">{practice ? "Practice round: the schedule is unchanged." : "FSRS has scheduled each card for when you're about to forget it."}</p>
      <button class="tile go" onclick={() => (stage = "list")}>See the cards</button>
    </section>
  {:else}
    <section class="list">
      <div class="tabs" role="group" aria-label="Show">
        {#each [["all", "All"], ["missed", "Missed"], ["right", "Right"]] as [k, l] (k)}
          <button aria-pressed={filter === k} onclick={() => (filter = k as typeof filter)}>{l}</button>
        {/each}
      </div>
      <ul class="recap card notch">
        {#each shownLog as l, i (l.key)}
          <li style:--i={Math.min(i, 8)}>
            <span class="what"><b>{l.entry.card.front}</b><small>{l.entry.card.back}</small></span>
            <span class="chip" class:again={l.missed}>{word(l.rating)}{l.due !== null ? `, ${dueIn(l.due - now)}` : ""}</span>
            {#if l.missed}<span class="why"><WhyButton front={l.entry.card.front} back={l.entry.card.back} typed="" subject={l.entry.deck.subject} /></span>{/if}
          </li>
        {:else}
          <li class="none">{filter === "missed" ? "Nothing missed. A clean run." : "No cards here."}</li>
        {/each}
      </ul>
      <div class="acts">
        <button class="tile go" disabled={!missedLog.length} onclick={() => begin(missedLog.map((l) => l.entry), true, "Balikan natin ang mali.")}>{missedLog.length ? `Practice misses (${missedLog.length})` : "No misses to practice"}</button>
        <button class="tile" onclick={onclose}>{mixed ? "Back to Study" : "Back to the deck"}</button>
      </div>
    </section>
  {/if}
  {#if problem}<p class="problem" role="alert">{problem}</p>{/if}
  <canvas class="fx" bind:this={fxCv} aria-hidden="true"></canvas>
</div>

<style>
  /* One centred column on tablets and desktop windows: a card wider than a phone reads stretched. */
  .session {
    position: relative;
    display: grid;
    gap: 10px;
    width: 100%;
    max-width: 560px;
    margin-inline: auto;
    animation: enter var(--t-flow) var(--ease) backwards;
  }
  @keyframes enter {
    from { opacity: 0; translate: 28px 0; }
  }
  header {
    display: flex;
    justify-content: space-between;
    align-items: center;
  }
  .back {
    height: 44px;
    padding: 0;
    border: 0;
    background: none;
    color: var(--gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-body);
  }

  /* One stepped segment per card; a miss is striped and its return is added (Run A). */
  .segs {
    display: flex;
    gap: 3px;
    height: 12px;
  }
  .segs i {
    flex: 1;
    min-width: 4px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    transition: background var(--t-quick) var(--ease);
  }
  .segs i.ok {
    background: var(--gold);
    box-shadow: inset 0 -3px 0 rgb(0 0 0 / 0.22);
  }
  .segs i.miss {
    background: repeating-linear-gradient(135deg, var(--bad) 0 3px, var(--sunk) 3px 6px);
  }
  .segs i.re {
    box-shadow: inset 0 0 0 1.5px var(--bad);
  }
  .segs i.cur {
    box-shadow: inset 0 0 0 2px var(--gold);
  }

  /* The score panel: the swirl behind, darkened so the numbers always read (Deck B). */
  .panel {
    --step: 3px;
    position: relative;
    isolation: isolate;
    min-height: 56px;
    background: #170509;
  }
  .panel::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: -1;
    background: rgb(11 7 16 / 0.55);
  }
  .sw,
  .cover canvas,
  .under canvas {
    position: absolute;
    inset: 0;
    z-index: -2;
    width: 100%;
    height: 100%;
    image-rendering: pixelated;
  }
  .hud {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 56px;
    padding: 0 12px;
    color: var(--parch);
  }
  .stamp {
    flex: none;
    min-width: 44px;
    padding: 2px 6px;
    text-align: center;
    font: 700 var(--text-title) var(--font-pixel);
    color: var(--parch);
    opacity: 0.6;
    box-shadow: inset 0 0 0 2px currentColor;
    rotate: -4deg;
    animation: pop var(--t-move) var(--ease-spring) backwards;
  }
  .stamp.on {
    color: var(--portal-gold);
    opacity: 1;
  }
  @keyframes pop {
    from { scale: 1.8; }
  }
  .meter {
    flex: 1;
    min-width: 0;
    display: grid;
    gap: 4px;
  }
  .track {
    display: block;
    height: 8px;
    background: rgb(11 7 16 / 0.8);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.22);
  }
  .track i {
    display: block;
    height: 100%;
    background: var(--portal-gold);
    transition: width var(--t-move) var(--ease);
  }
  .to {
    font: 500 var(--text-micro) var(--font-pixel);
    letter-spacing: var(--label-track);
    color: rgb(244 236 216 / 0.75);
  }
  .clock {
    flex: none;
  }
  .clock circle {
    fill: none;
    stroke-width: 4;
  }
  .clock .rb {
    stroke: rgb(244 236 216 / 0.18);
  }
  .clock .rp {
    stroke: var(--portal-gold);
    stroke-dasharray: 69.1;
  }
  .clock.late .rp {
    stroke: rgb(244 236 216 / 0.45);
  }
  .heat {
    flex: none;
    display: flex;
    gap: 2px;
  }
  .heat i {
    width: 6px;
    height: 12px;
    background: rgb(244 236 216 / 0.16);
  }
  .heat i.on:nth-child(1) { background: #b5412a; }
  .heat i.on:nth-child(2) { background: #e08a35; }
  .heat i.on:nth-child(3) { background: #f3cf6a; }
  .heat i.on:nth-child(4) { background: #fff1b8; }
  .score {
    flex: none;
    min-width: 40px;
    display: flex;
    justify-content: flex-end;
    color: var(--portal-gold);
    transform-origin: right center;
  }

  /* LAR at the top, talking (Run A). */
  .comp,
  .who {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 72px;
  }
  .bub {
    flex: 1;
    min-width: 0;
    margin: 0;
    padding: 10px 12px;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    font: 600 var(--text-body) / 1.2 var(--font-pixel);
    color: var(--ink);
  }

  /* The table: a pile of dithered backs under the card in front, on the calm room. */
  .table {
    display: grid;
    perspective: 900px;
    overflow-x: clip;
    padding-bottom: 16px;
    touch-action: manipulation;
  }
  .pile,
  .slot {
    grid-area: 1 / 1;
  }
  .pile {
    position: relative;
  }
  /* The pile: two backs squared under the card, each a little narrower, so it reads as a deck. */
  .under {
    --step: 4px;
    isolation: isolate;
    position: absolute;
    inset: 0;
    background: #170509;
    box-shadow: inset 0 0 0 2px #cca128;
  }
  .b1 {
    inset: 7px 8px -7px;
  }
  .b2 {
    inset: 14px 16px -14px;
    filter: brightness(0.7);
  }
  .slot,
  .sway,
  .tilt {
    display: grid;
    transform-style: preserve-3d;
  }
  .sway {
    --sway-t: 4.2s;
  }
  .sway.on {
    animation: sway var(--sway-t) ease-in-out infinite;
  }
  @keyframes sway {
    25% { rotate: var(--amp); }
    75% { rotate: calc(var(--amp) * -1); }
  }
  .tilt {
    transform: rotateX(var(--rx)) rotateY(var(--ry));
    transition: transform var(--t-quick) var(--ease);
  }
  .tilt.shake,
  .opt.shake {
    animation: shake var(--t-hero) linear;
  }
  @keyframes shake {
    15% { translate: -8px 0; }
    30% { translate: 7px 0; }
    45% { translate: -5px 0; }
    60% { translate: 4px 0; }
    75% { translate: -2px 0; }
  }
  .cover {
    --step: 4px;
    grid-area: 1 / 1;
    position: relative;
    isolation: isolate;
    background: #170509;
    box-shadow: inset 0 0 0 2px #cca128;
    /* Behind the card's own back face, so while the card is face-down (the deal) the swirl
       covers the answer side instead of fighting it for the same plane. */
    transform: translateZ(-2px) rotateY(180deg);
    -webkit-backface-visibility: hidden;
    backface-visibility: hidden;
  }
  .cover canvas {
    z-index: -1;
  }
  .flipper {
    grid-area: 1 / 1;
    display: grid;
    width: 100%;
    min-height: 0;
    padding: 0;
    border: 0;
    border-radius: 0;
    background: none;
    box-shadow: none;
    text-align: left;
    transform-style: preserve-3d;
    -webkit-backface-visibility: hidden;
    backface-visibility: hidden;
    transition: transform var(--t-hero) var(--ease-spring);
  }
  .flipper.shown {
    transform: rotateY(180deg);
  }
  .side {
    grid-area: 1 / 1;
    -webkit-backface-visibility: hidden;
    backface-visibility: hidden;
  }
  .side.rev {
    transform: rotateY(180deg);
  }
  .face {
    --step: 4px;
    position: relative;
    display: grid;
    gap: 8px;
    min-height: 196px;
    align-content: center;
    padding: 20px;
    background: linear-gradient(180deg, var(--card-2), var(--card));
    box-shadow: inset 0 0 0 1px var(--edge-2), inset 0 -4px 0 var(--edge);
    color: var(--ink);
  }
  .solo {
    grid-area: 1 / 1;
    -webkit-backface-visibility: hidden;
    backface-visibility: hidden;
  }
  .term {
    font-family: var(--font-display);
    font-weight: 800;
    font-size: var(--text-display);
    letter-spacing: -0.02em;
    line-height: 1.1;
    overflow-wrap: anywhere;
  }
  .mean {
    font-size: var(--text-headline);
    font-weight: 600;
    line-height: 1.3;
  }
  .answer {
    margin-top: 8px;
    padding-top: 12px;
    border-top: 1px solid var(--edge);
    font-size: var(--text-headline);
  }
  .reveal {
    font-size: var(--text-body);
    color: var(--ink-2);
  }
  .reveal b {
    color: var(--gold);
  }
  .fine {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--ink-3);
  }

  /* Answers: big tiles with the gold lip that press in (Run A). */
  .tile {
    --step: 3px;
    min-height: 56px;
    padding: 8px 12px 12px;
    border: 0;
    border-radius: 0;
    background: linear-gradient(var(--card-2), var(--card));
    box-shadow: inset 0 0 0 1px var(--edge-2), inset 0 -5px 0 color-mix(in srgb, var(--gold) 68%, var(--card));
    color: var(--ink);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-body);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    transition: translate var(--t-quick) var(--ease), background var(--t-quick) var(--ease);
  }
  .tile:active:not(:disabled) {
    translate: 0 3px;
  }
  .tile:disabled {
    opacity: 0.45;
  }
  .tile.go {
    background: var(--gold);
    color: var(--on-gold);
    box-shadow: inset 0 3px 0 rgb(255 255 255 / 0.3), inset 0 -5px 0 rgb(0 0 0 / 0.25);
  }
  .tile.ok,
  .tile.ok:disabled {
    opacity: 1;
    background: var(--gold);
    color: var(--on-gold);
  }
  .tile.no,
  .tile.no:disabled {
    opacity: 1;
    box-shadow: inset 0 0 0 2.5px var(--bad);
  }
  .rates {
    display: grid;
    grid-template-columns: repeat(4, 1fr);
    gap: 6px;
  }
  .rates .tile {
    display: grid;
    place-content: center;
    gap: 2px;
    min-height: 64px;
    padding: 6px 2px 10px;
  }
  .rates .again {
    color: var(--bad);
  }
  /* The interval under each rating; the line is kept even while it loads, so nothing jumps. */
  .rates small {
    min-height: 1lh;
    font-size: var(--text-label);
    font-weight: 600;
    color: var(--ink-3);
  }
  .opts {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 8px;
  }
  .opt {
    min-height: 76px;
    text-align: left;
    font-family: var(--font-body);
    font-weight: 600;
    font-size: var(--text-sub);
    line-height: 1.25;
  }
  /* True or false: two full-width tiles, stacked, in thumb reach (spec 063 C9). */
  .tf {
    grid-template-columns: 1fr;
  }
  .tf .opt {
    min-height: 60px;
    text-align: center;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: var(--text-body);
  }
  .typed {
    display: grid;
    grid-template-columns: 1fr auto;
    gap: 8px;
  }
  input {
    min-width: 0;
    height: 56px;
    padding: 0 12px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    color: var(--ink);
    font: inherit;
    font-size: var(--text-input);
  }
  input:focus {
    outline: none;
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  input.ok {
    box-shadow: inset 0 0 0 2px var(--gold);
  }
  input.no {
    box-shadow: inset 0 0 0 2px var(--bad);
  }
  .foot {
    display: grid;
    gap: 8px;
  }

  /* Results, two steps: the tally, then the cards (Run A). */
  .res {
    --step: 4px;
    display: grid;
    gap: 12px;
    padding: 16px;
    position: relative;
  }
  .res .label {
    margin: 0;
  }
  .big {
    display: flex;
    align-items: flex-end;
    gap: 8px;
    color: var(--gold);
  }
  .newbest {
    position: absolute;
    right: 16px;
    top: 104px;
    padding: 3px 8px;
    font: 700 var(--text-label) var(--font-pixel);
    letter-spacing: var(--label-track);
    text-transform: uppercase;
    color: var(--gold);
    box-shadow: inset 0 0 0 2px currentColor;
    rotate: -7deg;
    animation: thunk var(--t-hero) var(--ease) backwards;
  }
  @keyframes thunk {
    from { scale: 2.2; opacity: 0; }
  }
  .stats {
    margin: 0;
    display: grid;
  }
  .stats div {
    display: flex;
    justify-content: space-between;
    align-items: center;
    min-height: 40px;
    box-shadow: inset 0 1px 0 var(--edge);
  }
  .stats dt {
    color: var(--ink-2);
  }
  .stats dd {
    margin: 0;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
  }
  .list {
    display: grid;
    gap: 8px;
  }
  .tabs {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 4px;
  }
  .tabs button {
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink-2);
    font: 600 var(--text-sub) var(--font-pixel);
  }
  .tabs button[aria-pressed="true"] {
    background: var(--gold);
    color: var(--on-gold);
  }
  .recap {
    --step: 4px;
    list-style: none;
    margin: 0;
    padding: 4px 12px;
    display: grid;
  }
  /* The recap lists itself once, a row at a time. */
  .recap li {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    gap: 2px 8px;
    align-items: center;
    padding: 10px 0;
    animation: row var(--t-move) var(--ease) calc(var(--i) * 45ms) backwards;
  }
  .recap li + li {
    box-shadow: inset 0 1px 0 var(--edge);
  }
  @keyframes row {
    from { opacity: 0; translate: 0 8px; }
  }
  .what {
    display: grid;
    min-width: 0;
  }
  .what b {
    font-weight: 700;
  }
  .what small {
    font-size: var(--text-caption);
    color: var(--ink-2);
  }
  .chip {
    font: 500 var(--text-label) var(--font-pixel);
    padding: 3px 7px;
    color: var(--ink-2);
    box-shadow: inset 0 0 0 1px var(--edge-2);
  }
  .chip.again {
    color: var(--bad);
    box-shadow: inset 0 0 0 1.5px var(--bad);
  }
  .why {
    grid-column: 1 / -1;
  }
  .none {
    color: var(--ink-2);
  }
  .acts {
    display: grid;
    gap: 6px;
  }
  .problem {
    margin: 0;
    font-size: var(--text-caption);
    color: var(--bad);
  }
  /* Short screens: tighter rows and a shorter card, so a question and its answers share one screen. */
  @media (max-height: 760px) {
    .session {
      gap: 8px;
    }
    .hud {
      min-height: 48px;
    }
    .comp {
      min-height: 0;
    }
    .bub {
      padding: 6px 10px;
      font-size: var(--text-sub);
    }
    .face {
      min-height: clamp(120px, 24vh, 196px);
      padding: 14px 16px;
    }
    .term {
      font-size: var(--text-title);
    }
    .opt {
      min-height: 60px;
    }
    .rates .tile {
      min-height: 56px;
    }
  }
  .fx {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
    image-rendering: pixelated;
  }
</style>

<script lang="ts">
  import { friendly } from "./errors";
  // The landing. The tile portal builds itself (spec 010), LAR steps out
  // below it, then the sign-in card rises. Signing in pulses the frame;
  // signed in, it opens onto a swirl in the portal's own colours, and Step
  // through dives in and lands on Today. A returning student skips the
  // build. The portal takes whatever room the card leaves, so it fits every
  // phone's shape.
  import { onMount, untrack } from "svelte";
  import PortalStage from "./PortalStage.svelte";
  import type { Context } from "./lar/LarFlight.svelte";
  import { api, isoDate, type CampusResolution, type Portal, type PortalField, type Tries } from "./api";
  import { DOWN, FALLBACK_SIS, REJECTED, maskStudentNumber, portalCopy, triesLine, validate } from "./portals";
  import { FALLBACK } from "./errors";
  import DateWheels from "./DateWheels.svelte";
  import { closable } from "./back";
  import { openLink } from "./openLink";
  import { portalApiFor } from "./portalApi";
  import { buzz } from "./haptics";
  import { landingAt, restAt } from "./landing";
  import { adopt, allowReminders, app, refreshLogins, setRoom, syncNow } from "./state.svelte";
  import MiniPortal from "./MiniPortal.svelte";
  import PixelNum from "./PixelNum.svelte";
  import { fade, fly, slide } from "svelte/transition";
  import { cubicOut } from "svelte/easing";
  import { CAMPUSES, MAX_NAME, getCampus, getName, setCampus, setName } from "./profile";
  import { CLASS, CLOCK, LOOKS, PAGES, RATINGS, SIGNIN, TERMS, campusLine, clock, countdown, fillName, helloLine, step as stepPage, swipe, todayAt } from "./welcome/intro";
  import { plot, spoken } from "./gpaTrend";
  import { dueIn } from "./interval";
  import { stageFor } from "./tiles";
  import type { DiveStart } from "./dive";

  let { signedIn, onenter, ondive }: { signedIn: boolean; onenter: () => void; ondive: (s: DiveStart) => void } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const returning = untrack(() => signedIn);
  // Where the portal opens: the sign-in card, or straight to Step through.
  let rest = $state<"signin" | "hub">(returning ? "hub" : "signin");
  // A student new to the app pages through the intro, one feature a page, then signs in (spec 049).
  // Once they have reached the form or looked around, later launches open on the form (kept on the phone).
  const WELCOMED = "intportal.welcomed";
  const seen = (() => {
    try {
      return localStorage.getItem(WELCOMED) === "1";
    } catch {
      return false;
    }
  })();
  const intro = !returning && !seen;
  function welcomed() {
    try {
      localStorage.setItem(WELCOMED, "1");
    } catch {
      // Private mode: the intro shows again next launch.
    }
  }
  let page = $state(0);
  /** Which way the last turn went: 1 forward, -1 back. */
  let dir = $state(1);
  /** The page that is leaving, for its short exit. */
  let gone = $state(-1);
  let goneTimer: ReturnType<typeof setTimeout> | undefined;
  const here = $derived(PAGES[page]);
  /** The form is on screen: no intro, or its last page. */
  const signin = $derived(!intro || page === SIGNIN);
  function turn(to: number) {
    if (to === page || to < 0 || to > SIGNIN) return;
    dir = to > page ? 1 : -1;
    gone = page;
    clearTimeout(goneTimer);
    goneTimer = setTimeout(() => (gone = -1), 200);
    page = to;
    buzz.select();
    if (to === SIGNIN) welcomed();
  }
  const next = () => turn(stepPage(page, 1));
  const back = () => turn(stepPage(page, -1));
  // A dark look the student picked (here or in You) colours the landing's ground too;
  // a light one leaves the landing on the night ground, which the portal needs (010 C45).
  const DARK = new Set(LOOKS.map((l) => l.room));
  const worn = $derived(DARK.has(app.room));

  // Each page arrives on the stage as one motion: the portal rings out from its centre, LAR flies
  // to the page's spot and says its line, and the copy rises in from the side it came from (049 C6).
  $effect(() => {
    const p = PAGES[page];
    if (!intro || !resting) return;
    untrack(() => {
      stageEl?.ring();
      stageEl?.visit(p.spot);
      if (p.lar) stageEl?.say(fillName(p.lar, name));
    });
  });
  // Android's back turns back a page (049 C2); a sheet over the form closes first.
  $effect(() => {
    if (intro && page > 0 && rest === "signin" && !busy) return closable(back);
  });

  // Hello (049 C8): what to call them. LAR answers once the typing pauses.
  let name = $state(getName());
  let naming = $state(false);
  let nameTimer: ReturnType<typeof setTimeout> | undefined;
  function typedName(v: string) {
    name = v.slice(0, MAX_NAME);
    setName(name);
    clearTimeout(nameTimer);
    const line = helloLine(name);
    if (line) nameTimer = setTimeout(() => (stageEl?.say(line), stageEl?.cheer()), 450);
  }

  // Your school (049 C5): a PUP campus, or another school from the portal wall.
  let school = $state(getCampus());
  function pickCampus(c: string) {
    school = c;
    setCampus(c);
    portalId = "sis";
    buzz.select();
    stageEl?.ring();
    stageEl?.say(campusLine(c));
    stageEl?.cheer();
  }
  function pickPortal(i: number) {
    portalId = portals[i].id;
    error = "";
    if (intro && here.id === "school" && portalId !== "sis") {
      school = `school:${portalId}`;
      setCampus(school);
      stageEl?.say(`${portals[i].name}! Sige, doon tayo.`);
    }
  }

  // Today (049 C9): a sample clock the student drags; it ticks on by itself while the page is up.
  let clockAt = $state(CLOCK.start);
  const live = $derived(todayAt(clockAt));
  const through = $derived(Math.round(((clockAt - CLASS.start) / (CLASS.end - CLASS.start)) * 100));
  $effect(() => {
    if (!intro || here.id !== "today") return;
    const id = setInterval(() => !document.hidden && (clockAt = Math.min(CLOCK.to, clockAt + 1)), 1000);
    return () => clearInterval(id);
  });
  let lastPhase = todayAt(CLOCK.start).phase;
  $effect(() => {
    const ph = live.phase;
    if (ph !== lastPhase) untrack(() => buzz.tick());
    lastPhase = ph;
  });
  const span = (at: number) => ((at - CLOCK.from) / (CLOCK.to - CLOCK.from)) * 100;

  // Deadlines (049 C10): the app's Done on one sample row, then the row folds away.
  let due = $state<"open" | "done" | "gone">("open");
  function tickDue() {
    if (due !== "open") return;
    due = "done";
    buzz.done();
    stageEl?.say("Ayos! Tapos na 'yan.");
    setTimeout(() => (due = "gone"), reduce ? 500 : 1300);
  }
  const fold = (node: Element) => (reduce ? fade(node, { duration: 160 }) : slide(node, { duration: 360 }));

  // Grades and Study (049 C11).
  const trend = plot(TERMS);
  let flipped = $state(false);
  let rated = $state<(typeof RATINGS)[number] | null>(null);
  function flip() {
    flipped = !flipped;
    rated = null;
    buzz.select();
  }
  function rate(r: (typeof RATINGS)[number]) {
    rated = r;
    buzz.tick();
  }

  // Offline and private (049 C12).
  let offline = $state(false);
  function toggleSignal() {
    offline = !offline;
    buzz.select();
    if (offline) stageEl?.say("Walang signal? Bukas pa rin lahat.");
  }

  // Your look (049 C13): worn at once by the whole landing, and kept for the app.
  function wear(room: string) {
    buzz.select();
    setRoom(room);
    stageEl?.say("Ayan, bagay. Ganyan na ang kulay ng app mo, kahit mag-sign in ka na.");
  }

  // Reminders (049 C14): the phone is asked, and a sample slides down from the top.
  let reminded = $state<"on" | "off" | null>(null);
  let notice = $state(false);
  async function allow() {
    reminded = "on";
    notice = true;
    buzz.done();
    setTimeout(() => (notice = false), 4200);
    await allowReminders();
  }
  function notNow() {
    reminded = "off";
    app.reminderLead = 0;
    try {
      localStorage.setItem("reminderLead", "0");
    } catch {
      // Asked again on You.
    }
    next();
  }

  // A horizontal swipe on the page turns it; a control that drags sideways keeps its own swipe.
  let pagesEl = $state<HTMLElement>();
  $effect(() => {
    const el = pagesEl;
    if (!el || !intro) return;
    let from: { x: number; y: number } | null = null;
    const down = (e: PointerEvent) => {
      from = (e.target as Element).closest("input, .scroll") ? null : { x: e.clientX, y: e.clientY };
    };
    const up = (e: PointerEvent) => {
      if (!from) return;
      const d = swipe(e.clientX - from.x, e.clientY - from.y);
      from = null;
      if (d === 1 && page < SIGNIN) next();
      else if (d === -1) back();
    };
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointerup", up);
    return () => (el.removeEventListener("pointerdown", down), el.removeEventListener("pointerup", up));
  });
  let busy = $state(false);
  let error = $state("");
  let typing = $state(false);
  let studno = $state("");
  let birthday = $state("");
  let password = $state("");
  let showPw = $state(false);
  // The birthdate wheels' sheet (011 C1), and an SIS that didn't answer (C9).
  let wheels = $state(false);
  let down = $state(false);
  // How the login is kept, on a small sheet the fine print opens (011 C11).
  let kept = $state(false);
  // Android's back closes the wheels and the sheet, never the app under them.
  $effect(() => {
    if (wheels) return closable(() => (wheels = false));
  });
  $effect(() => {
    if (kept) return closable(() => (kept = false));
  });
  /** The student number as typed, masked; the caret stays put unless the mask moved text (C4). */
  function typedStudno(el: HTMLInputElement) {
    const masked = maskStudentNumber(el.value);
    if (masked !== el.value) {
      const back = el.value.length - (el.selectionStart ?? el.value.length);
      el.value = masked;
      const at = Math.max(0, masked.length - back);
      el.setSelectionRange(at, at);
    }
    studno = masked;
  }
  // The password hides again whenever the app leaves the screen (C5).
  onMount(() => {
    const hide = () => document.hidden && (showPw = false);
    document.addEventListener("visibilitychange", hide);
    return () => document.removeEventListener("visibilitychange", hide);
  });
  // Set by a failed check; each field then clears its own mark once it is fixed.
  let tried = $state(false);

  let t = $state(0);
  let steppedAt = $state<number | null>(null);
  let leaving = $state(false);
  let stageEl = $state<PortalStage>();
  const moment = $derived(landingAt(t, { returning, reduce, steppedAt }));
  const resting = $derived(moment.phase === "rest");
  const stage = $derived(stageFor({ busy, open: rest === "hub" }));
  let cardH = $state(0);
  let cardMin = $state(0);
  $effect(() => {
    // A frame later: growing the card inside its own resize callback is a ResizeObserver loop.
    const h = cardH;
    if (h > cardMin) requestAnimationFrame(() => (cardMin = Math.max(cardMin, h)));
  });

  // The portals the core lists; the card below follows the chosen one.
  let portals = $state<Portal[]>([FALLBACK_SIS]);
  let portalId = $state("sis");
  const portal = $derived(portals.find((p) => p.id === portalId) ?? portals[0]);
  const copy = $derived(portalCopy(portal.id));
  const ready = $derived(portal.status === "ready");
  const otherSchool = $derived(school?.startsWith("school:") ? portals.find((p) => `school:${p.id}` === school) : undefined);

  let tries = $state<Tries | null>(null);
  const triesText = $derived(tries ? triesLine(tries, portal, Date.now() / 1000) : "");
  const locked = $derived(!!tries && tries.left <= 0);
  onMount(() => {
    api.portals().then((p) => p.length && (portals = p)).catch(() => {});
  });
  $effect(() => {
    const id = portalId;
    tries = null;
    portalApiFor(id).tries().then((t) => id === portalId && (tries = t)).catch(() => {});
  });

  let campus = $state<CampusResolution>({ kind: "incomplete" });
  $effect(() => {
    const n = studno;
    api.campus(n).then((r) => (campus = r)).catch(() => {});
  });

  // LAR's face and flight follow what's happening; he talks for himself.
  const ctx = $derived<Context>(error ? "error" : busy ? "busy" : rest === "hub" ? "signed" : typing ? "typing" : "idle");

  onMount(() => {
    let raf = 0;
    const start = performance.now();
    const frame = (now: number) => {
      t = (now - start) / 1000;
      if (moment.phase === "entered") {
        if (signedIn) syncNow();
        onenter();
        return;
      }
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  });

  const values = $derived({ student_number: studno, birthdate: birthday, password });
  const why = $derived(validate(portal, values));
  const started = $derived(!!(studno || birthday || password));
  const bad = (field: PortalField) => tried && !!validate({ ...portal, fields: [field] }, values);

  async function submit(e?: Event) {
    e?.preventDefault();
    if (busy || locked) return;
    down = false;
    error = validate(portal, values);
    tried = !!error;
    if (error) return;
    busy = true;
    try {
      await portalApiFor(portal.id).signIn({ student_number: studno, birthdate: birthday, password });
      password = "";
      rest = "hub";
      buzz.done();
    } catch (err) {
      const said = friendly(err);
      // No host answered: the down state, with Try again; it spends no try (C9).
      down = /^couldn't reach the SIS/i.test(String((err as { message?: string })?.message ?? err)) || said.startsWith("Can't reach the SIS");
      // A rejection in words we can't read gets ours (C8).
      // Mabini has no birthdate, so its line doesn't ask for one.
      error = down ? DOWN : said === FALLBACK ? (portal.fields.includes("birthdate") ? REJECTED : REJECTED.replace(", birthdate and", " and")) : said;
      buzz.fail();
    } finally {
      busy = false;
      portalApiFor(portal.id).tries().then((t) => (tries = t)).catch(() => {});
    }
  }

  async function demo() {
    error = "";
    try {
      await adopt(await api.demo(isoDate(new Date())));
      await refreshLogins();
      // The demo is SIS data, so the carousel shows SIS whatever was picked.
      portalId = "sis";
      rest = "hub";
      welcomed();
      buzz.done();
      try {
        localStorage.setItem("demo", "1");
      } catch {
        // Then demo mode just lasts this launch.
      }
    } catch (err) {
      error = friendly(err);
    }
  }

  function step() {
    if (!resting || leaving) return;
    buzz.release();
    leaving = true;
    const from = reduce ? null : stageEl?.leaveInfo();
    // Without Reduce Motion and with a portal on screen, the dive takes over (spec 010 C27).
    if (from) return ondive({ first: true, portal, from });
    steppedAt = Math.max(t, restAt({ returning, reduce, steppedAt: null }));
  }
</script>

{#snippet notification(at: "top" | "rest")}
  <!-- A sample of the nudge, as the phone would show it (049 C14). -->
  <div class="note {at}" aria-hidden={at === "rest"}>
    <span class="note-icon"><MiniPortal portal={portal} /></span>
    <span class="note-text">
      <span class="note-head"><b>IntPortal</b><small>now</small></span>
      <span class="note-title">{CLASS.code} in 10 minutes</span>
      <span class="note-body">{CLASS.room}, {CLASS.title}. Tara na{name ? `, ${name}` : ""}!</span>
    </span>
  </div>
{/snippet}

{#snippet todayView()}
  <!-- Inside the portal's mouth (049 C9): the sample class, counting down as the student drags the clock. -->
  <span class="tv" data-phase={live.phase} aria-live="polite">
    {#key live.phase}<span class="tv-lab">{live.label}</span>{/key}
    <span class="tv-code">{CLASS.code}</span>
    <span class="tv-sub">{CLASS.title} · {CLASS.room} · 7:30 to 9:00 AM</span>
    <span class="tv-left">
      <small>{live.sub}</small>
      {#if live.phase !== "over"}<b><PixelNum text={countdown(live.left)} size={4} /></b>{/if}
    </span>
    <span class="tv-bar" aria-hidden="true"><i style:width="{Math.max(0, Math.min(100, through))}%"></i></span>
  </span>
{/snippet}

<section class="landing" class:leaving class:worn>
  {#if intro && rest !== "hub"}
    <!-- The intro's top row: Back, nine pixel bars, Skip (049 C2). -->
    <header class="bar" class:on={resting}>
      <button type="button" class="back" class:hide={page === 0} aria-label="Back" tabindex={page === 0 ? -1 : 0} onclick={back}>
        <svg viewBox="0 0 4 7" aria-hidden="true" shape-rendering="crispEdges"><path d="M3 0h1v1H3zM2 1h1v1H2zM1 2h1v1H1zM0 3h1v1H0zM1 4h1v1H1zM2 5h1v1H2zM3 6h1v1H3z" fill="currentColor" /></svg>
      </button>
      <div class="steps" role="img" aria-label="Step {page + 1} of {PAGES.length}: {here.title}">
        {#each PAGES as p, i (p.id)}<i class:past={i < page} class:on={i === page}></i>{/each}
      </div>
      <button type="button" class="skip" class:hide={page === SIGNIN} tabindex={page === SIGNIN ? -1 : 0} onclick={() => turn(SIGNIN)}>Skip to sign in</button>
    </header>
  {:else}
    <header class="brand" class:on={resting}>
      <h1>Student <span>IntPortal</span></h1>
      {#if !ready}<p class="pitch">{portal.school} is next. For now, IntPortal works with PUP.</p>{/if}
    </header>
  {/if}

  <!-- C16: while the frame builds, the portal stands larger in the middle of the screen; it lifts into its place as the form rises. -->
  <div class="lift" class:up={resting} style:--drop="{Math.round(cardMin / 2)}px">
  <PortalStage
    bind:this={stageEl}
    {portals}
    index={Math.max(0, portals.indexOf(portal))}
    onselect={pickPortal}
    locked={busy || rest === "hub" || (!signin && here.id !== "school")}
    {stage}
    {returning}
    still={typing || naming}
    showLar={resting}
    {leaving}
    {ctx}
    quiet={!signin}
    steady={intro && rest !== "hub"}
    mouth={!signin && resting && here.acts.includes("mouth") ? todayView : undefined}
  />
  </div>

  <!-- In the layout from the start, so the portal's room never jumps when it shows. -->
  <div class="dock" class:on={resting} class:hub={rest === "hub"} class:bare={!signin && rest !== "hub"} inert={!resting}>
      {#if rest === "hub"}
        <button class="step" onclick={step}>Step through</button>
        <p class="hint">{app.sisConnected ? `PUP SIS · via ${(app.snapshot?.host ?? "sis8").split(".")[0]}` : copy.hint}</p>
        <!-- 011 C10: signed in, but the SIS has no schedule for this term yet; the student still goes in. -->
        {#if app.sisConnected && app.snapshot && !app.snapshot.sessions.length && !returning}<p class="hint empty">Signed in, but your schedule isn't up yet.</p>{/if}
      {:else}
      <!-- Every page shares one cell, so the tallest sets the height and turning a page never moves the portal (049 C3). -->
      <div class="pages" bind:this={pagesEl} style:--dir={dir} style:--portal-accent={portal.theme.accent}>
        {#if intro}
          {#each PAGES.slice(0, SIGNIN) as p, i (p.id)}
            <section class="page" class:on={i === page} class:off={i === gone} inert={i !== page} aria-labelledby="intro-{p.id}">
              {#if p.id === "hello"}
                <h2 class="mark" id="intro-hello">Student <span>IntPortal</span></h2>
              {:else}
                <h2 id="intro-{p.id}">{p.title}</h2>
              {/if}
              <p class="lede">{p.line}</p>
              <div class="demo">
                {#if p.id === "hello"}
                  <div class="field" class:filled={!!name}>
                    <input id="f-name" value={name} maxlength={MAX_NAME} autocomplete="given-name" autocapitalize="words" enterkeyhint="next" spellcheck="false"
                      oninput={(e) => typedName(e.currentTarget.value)} onfocus={() => (naming = true)} onblur={() => (naming = false)}
                      onkeydown={(e) => e.key === "Enter" && (e.currentTarget.blur(), next())} />
                    <label for="f-name">What should I call you?</label>
                  </div>
                  <small class="aside">Optional. It stays on this phone.</small>
                {:else if p.id === "school"}
                  <div class="campuses scroll" role="radiogroup" aria-label="PUP campus">
                    {#each CAMPUSES as c (c)}
                      <button type="button" class="chip" role="radio" aria-checked={school === c} class:picked={school === c} onclick={() => pickCampus(c)}>{c}</button>
                    {/each}
                  </div>
                  {#if portals.length > 1}
                    <button type="button" class="chip other" class:picked={!!otherSchool} aria-pressed={!!otherSchool} onclick={(e) => stageEl?.openWall(e.currentTarget.getBoundingClientRect())}>
                      <span class="glyph"><MiniPortal portal={otherSchool ?? portals[1]} /></span>{otherSchool ? otherSchool.name : "Another school"}
                    </button>
                  {/if}
                {:else if p.id === "today"}
                  <label class="clock" for="f-clock"><span>Sample time</span><b>{clock(clockAt)}</b></label>
                  <input id="f-clock" class="slider" type="range" min={CLOCK.from} max={CLOCK.to} step="60" value={clockAt} aria-valuetext={clock(clockAt)}
                    style:--a="{span(CLASS.start)}%" style:--b="{span(CLASS.end)}%" oninput={(e) => (clockAt = +e.currentTarget.value)} />
                  <span class="scale" aria-hidden="true"><span>{clock(CLOCK.from)}</span><span>Class</span><span>{clock(CLOCK.to)}</span></span>
                {:else if p.id === "deadlines"}
                  {#if due !== "gone"}
                    <div class="due" class:done={due === "done"} out:fold>
                      <button type="button" class="check" class:on={due === "done"} aria-label="Mark Lab report 3 done" onclick={tickDue}><i></i></button>
                      <span class="what"><strong>Lab report 3</strong><small><b>Tomorrow</b> · {CLASS.code}</small></span>
                      {#if due === "done"}<span class="stamp" aria-hidden="true">DONE</span>{/if}
                    </div>
                  {:else}
                    <p class="clear" in:fade={{ duration: 200 }}>All clear. <button type="button" class="link" onclick={() => (due = "open")}>Put it back</button></p>
                  {/if}
                {:else if p.id === "study"}
                  <div class="gpa" role="img" aria-label="Sample: {spoken(TERMS)}">
                    <span class="gpa-num"><PixelNum text={TERMS.at(-1)!.v.toFixed(2)} size={3} /><small>GPA, up from {TERMS.at(-2)!.v.toFixed(2)}</small></span>
                    <svg class="trend" viewBox="0 0 100 40" aria-hidden="true">
                      {#each trend.guides as g (g.v)}<line class="guide" x1="0" x2="100" y1={g.y} y2={g.y} />{/each}
                      <polyline pathLength="1" points={trend.points.map((q) => `${q.x},${q.y}`).join(" ")} />
                      {#each trend.points as q, k (k)}<rect x={q.x - 2} y={q.y - 2} width="4" height="4" style:animation-delay="{0.5 + k * 0.12}s" />{/each}
                    </svg>
                  </div>
                  <button type="button" class="flash" class:flipped aria-pressed={flipped} aria-label={flipped ? "Answer: O(log n). Tap to turn back." : "Binary search runs in what time? Tap to see the answer."} onclick={flip}>
                    <span class="face ask" aria-hidden="true">Binary search runs in…</span>
                    <span class="face ans" aria-hidden="true">O(log n)</span>
                  </button>
                  <div class="rate" aria-live="polite">
                    {#if rated}
                      <p class="back-in">Comes back {dueIn(rated.secs)}.</p>
                    {:else if flipped}
                      {#each RATINGS as r (r.id)}<button type="button" class="rate-b" onclick={() => rate(r)}>{r.label}<small>{r.short}</small></button>{/each}
                    {:else}
                      <p class="aside">Tap the card to see the answer.</p>
                    {/if}
                  </div>
                {:else if p.id === "offline"}
                  <button type="button" class="signal" role="switch" aria-checked={offline} onclick={toggleSignal}>
                    <span class="bars" class:out={offline} aria-hidden="true"><i></i><i></i><i></i><i></i></span>
                    <span>No signal</span>
                    <span class="switch" aria-hidden="true"><i></i></span>
                  </button>
                  <ul class="kept-rows" aria-label={offline ? "Still open, from this phone" : "Up to date"}>
                    {#each ["Schedule", "Grades", "Notes"] as w (w)}
                      <li><i class="tick" aria-hidden="true"></i>{w}</li>
                    {/each}
                  </ul>
                  <p class="aside" aria-live="polite">{offline ? "Still open, from this phone." : "Up to date."}</p>
                {:else if p.id === "look"}
                  <div class="looks">
                    {#each LOOKS as l (l.room)}
                      <button type="button" class="chip" class:picked={app.room === l.room} aria-pressed={app.room === l.room} onclick={() => wear(l.room)}>
                        <svg class="tones" viewBox="0 0 24 14" aria-hidden="true" shape-rendering="crispEdges">{#each l.swatch as c, j (j)}<rect x={j * 8} width="8" height="14" fill={c} />{/each}</svg>
                        {l.name}
                      </button>
                    {/each}
                  </div>
                {:else if p.id === "reminders"}
                  {#if !reminded}{@render notification("rest")}{/if}
                  {#if reminded === "on"}
                    <p class="okay">{app.notifications === false ? "Your phone said no. You can allow them later in Settings." : "Reminders are on. They start after you sign in."}</p>
                  {:else if !reminded}
                    <button type="button" class="link soft" onclick={notNow}>Not now</button>
                  {/if}
                {/if}
              </div>
              {#if p.id === "reminders" && !reminded}
                <button type="button" class="go" onclick={allow}>Allow reminders</button>
              {:else}
                <button type="button" class="go" onclick={next}>Next</button>
              {/if}
            </section>
          {/each}
        {/if}
        <!-- The card keeps the tallest height it has had, so swiping between portals never resizes the portal above it. -->
        <form class="card page" class:on={signin} class:off={gone === SIGNIN} inert={!signin} style:--portal-accent={portal.theme.accent} style:min-height="{cardMin}px" bind:offsetHeight={cardH} onsubmit={submit} onfocusin={() => (typing = true)} onfocusout={() => (typing = false)}>
          {#key portal.id}<div class="swap">
          {#if !ready}
            <div class="soon">
              <b>{portal.school}</b>
              <p>Its portal opens soon. IntPortal will connect here once it's ready; for now, SIS and Mabini work.</p>
            </div>
            <button type="button" class="ghost" onclick={demo}>Look around</button>
          {:else}
          <div class="field" class:filled={!!studno} class:bad={bad("student_number")}>
            <input id="f-studno" value={studno} oninput={(e) => typedStudno(e.currentTarget)} placeholder="2026-00000-MN-0" autocapitalize="characters" autocomplete="username" inputmode="text" spellcheck="false" aria-invalid={bad("student_number")} />
            <label for="f-studno">Student number</label>
          </div>
          {#if campus.kind === "known"}<small class="campus">{campus.campus.name} · campus found</small>
          {:else if campus.kind === "unknown_code"}<small class="campus dim">{campus.code} · campus not confirmed yet, sign-in still works</small>{/if}
          <!-- Birthdate and password share a row, so the portal above keeps its height (011 C1). -->
          <div class="pair" class:solo={!portal.fields.includes("birthdate")}>
            {#if portal.fields.includes("birthdate")}
              <div class="field date" class:empty={!birthday} class:bad={bad("birthdate")}>
                <button type="button" id="f-birthday" class="pick" aria-haspopup="dialog" onclick={() => (wheels = true)}>{birthday ? new Date(birthday + "T00:00").toLocaleDateString(undefined, { month: "short", day: "numeric", year: "numeric" }) : ""}</button>
                <label for="f-birthday">Birthdate</label>
                {#if !birthday}<i aria-hidden="true">mm / dd / yyyy</i>{/if}
              </div>
            {/if}
            <div class="field" class:filled={!!password} class:bad={bad("password")}>
              <input id="f-password" type={showPw ? "text" : "password"} bind:value={password} autocomplete="current-password" aria-invalid={bad("password")} />
              <label for="f-password">Password</label>
              <button type="button" class="eye" aria-label="Show password" aria-pressed={showPw} onclick={() => (showPw = !showPw)}>{showPw ? "Hide" : "Show"}</button>
            </div>
          </div>
          <button class="go" disabled={busy || locked || !!why} aria-describedby={why && started ? "f-why" : undefined}>{busy ? "Signing in…" : "Sign in"}</button>
          <!-- Why Sign in is still off, once something is typed (C7). -->
          {#if why && started && !error}<p class="why" id="f-why">{why}</p>{/if}
          {#if triesText}<p class="tries" class:out={locked} aria-live="polite">{triesText}</p>{/if}
          {#if error}<p class="error" class:down role="alert">{error}</p>{/if}
          {#if down}<button type="button" class="retry" onclick={() => submit()}>Try again</button>{/if}
          <p class="fine">
            Your login stays on this phone.
            <button type="button" class="link" aria-haspopup="dialog" onclick={() => (kept = true)}>How</button>
            <span aria-hidden="true">·</span>
            <button type="button" class="link" onclick={() => openLink(copy.reset, true)}>Forgot password?</button>
            <!-- The way into the demo once the welcome is behind you; iOS has no Back to reach it (010 C39). -->
            <span aria-hidden="true">·</span>
            <button type="button" class="link" onclick={demo} disabled={busy}>{intro ? "Look around first" : "Look around"}</button>
          </p>
          {/if}
          </div>{/key}
        </form>
      </div>
      {/if}
  </div>
  {#if notice}
    <div class="note-slot" transition:fly={{ y: reduce ? 0 : -120, duration: reduce ? 160 : 550, easing: cubicOut }}>{@render notification("top")}</div>
  {/if}
  {#if wheels}
    <DateWheels value={birthday} onclose={() => (wheels = false)} ondone={(iso) => ((birthday = iso), (wheels = false), buzz.tick())} />
  {/if}
  {#if kept}
    <div class="scrim" role="presentation" onclick={() => (kept = false)}></div>
    <div class="kept" role="dialog" aria-modal="true" aria-labelledby="kept-title">
      <h2 id="kept-title">How your login is kept</h2>
      <dl>
        <dt>It stays on this phone.</dt>
        <dd>Your login is saved in the phone's keychain, where the phone keeps its own passwords.</dd>
        <dt>It goes to {copy.system} and nowhere else.</dt>
        <dd>IntPortal signs in for you, the way you would in a browser. There is no IntPortal account and no IntPortal server.</dd>
        <dt>After that, it works offline.</dt>
        <dd>Your schedule, grades and notes are kept on the phone, so they open without signal.</dd>
      </dl>
      <button class="ghost" onclick={() => (kept = false)}>Done</button>
    </div>
  {/if}
</section>

<style>
  /* Wordmark, portal, card: the portal row takes whatever height is left. */
  .landing {
    position: fixed;
    inset: 0;
    z-index: 50;
    display: grid;
    grid-template-rows: auto minmax(0, 1fr) auto;
    gap: 8px;
    padding: calc(var(--safe-top) + 10px) var(--gutter) calc(var(--safe-bottom) + 12px);
    color: var(--parch);
    /* Night and the portal's stars, nothing else: no dots, no pools, no reflection (spec 010 C3). */
    --land: var(--void);
    background-color: var(--land);
    transition: background-color var(--t-flow) var(--ease);
  }
  .landing.worn {
    --land: var(--ground);
  }
  .brand {
    text-align: center;
    pointer-events: none;
    opacity: 0;
    transform: translateY(-6px);
    transition:
      opacity 0.6s var(--ease),
      transform 0.6s var(--ease);
  }
  .brand.on {
    opacity: 1;
    transform: none;
  }
  h1 {
    margin: 0;
    font-family: var(--font-wordmark);
    font-size: var(--text-display);
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--portal-gold);
  }
  h1 span {
    color: var(--cream);
  }
  .pitch {
    margin: 4px auto 0;
    font: 400 var(--text-sub) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.78);
    text-wrap: balance;
  }
  .lift {
    display: grid;
    min-height: 0;
    transform: translateY(var(--drop)) scale(1.3);
    transition: transform var(--t-hero) var(--ease);
  }
  .lift.up {
    transform: none;
  }
  /* The school's name comes with the form, not before. */
  .lift:not(.up) :global(.quick),
  .lift:not(.up) :global(.plate) {
    opacity: 0;
    transition: none;
  }
  /* ... and only once the lift has put them in their place, so they never cross the form. */
  .lift.up :global(.quick),
  .lift.up :global(.plate) {
    transition: opacity var(--t-move) var(--ease) var(--t-hero);
  }
  .dock {
    display: grid;
    gap: 10px;
    opacity: 0;
    transform: translateY(40px);
    transition:
      opacity 0.7s var(--ease),
      transform 0.7s var(--ease);
    /* On the unclipped parent: the card's clip-path would cut its own shadow. */
    filter: drop-shadow(0 -10px 30px rgb(0 0 0 / 0.5));
  }
  .dock.on {
    opacity: 1;
    transform: none;
  }
  /* Text straight on the ground casts no shadow. */
  .dock.bare {
    filter: none;
  }
  .dock.hub {
    justify-items: center;
    padding-bottom: 28px;
  }
  .leaving .dock,
  .leaving .brand {
    opacity: 0;
    transform: translateY(16px);
    transition:
      opacity 0.25s ease-in,
      transform 0.25s ease-in;
  }
  .card {
    display: grid;
    gap: 12px;
    padding: 16px 16px 12px;
    background: var(--void-2);
    box-shadow: inset 0 0 0 1px rgb(245 178 39 / 0.16);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  /* The fields follow the phone's own login pattern: a rounded well, the label
     inside it floating up once there is something to say. */
  .field {
    position: relative;
    border-radius: var(--radius);
    background: var(--void);
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    transition: box-shadow var(--t-quick) var(--ease);
  }
  .field:focus-within {
    box-shadow: inset 0 0 0 1.5px var(--portal-accent, var(--portal-gold));
  }
  .field.bad {
    box-shadow: inset 0 0 0 1.5px var(--rose);
  }
  input {
    display: block;
    width: 100%;
    min-width: 0;
    height: 54px;
    padding: 20px 14px 4px;
    border: 0;
    border-radius: var(--radius);
    background: transparent;
    box-shadow: none;
    color: var(--white);
    font: 400 var(--text-input) / 1.25 var(--font-ui);
    caret-color: var(--portal-gold);
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }
  .field:has(.eye) input {
    padding-right: 66px;
  }
  .field label {
    position: absolute;
    left: 14px;
    top: 17px;
    font: 400 var(--text-input) / 1.25 var(--font-ui);
    color: rgb(244 236 216 / 0.55);
    transform-origin: 0 0;
    pointer-events: none;
    transition:
      transform 0.16s var(--ease),
      color 0.16s var(--ease);
  }
  /* Floated: focus, a value, the browser's autofill, or a date (it always shows a format). */
  .field:focus-within label,
  .field.filled label,
  .field.date label,
  .field:has(input:-webkit-autofill) label {
    transform: translateY(-10px) scale(0.75);
  }
  .field:focus-within label {
    color: var(--portal-accent, var(--portal-gold));
  }
  .field.bad label {
    color: var(--rose);
  }
  /* The example shows only once the label is up. */
  input::placeholder {
    color: rgb(255 255 255 / 0.4);
    opacity: 0;
    transition: opacity var(--t-quick) var(--ease);
  }
  input:focus::placeholder {
    opacity: 1;
  }
  /* Autofill paints its own yellow; keep the well dark. */
  input:-webkit-autofill {
    -webkit-text-fill-color: var(--white);
    box-shadow: 0 0 0 100px var(--void) inset;
  }
  /* iOS draws an empty date field as a blank slab; give it a hint, and hide the
     browser's own format text so the two never stack. */
  /* The birthdate opens its wheels (011 C1): a field that reads like the others. */
  .pick {
    display: block;
    width: 100%;
    height: 54px;
    padding: 20px 14px 4px;
    border: 0;
    border-radius: var(--radius);
    background: transparent;
    color: var(--white);
    font: 400 var(--text-input) / 1.25 var(--font-ui);
    text-align: left;
  }
  .pick:focus-visible {
    outline: none;
  }
  .field.date:has(.pick:focus-visible) {
    box-shadow: inset 0 0 0 1.5px var(--portal-accent, var(--portal-gold));
  }
  .date i {
    position: absolute;
    left: 14px;
    bottom: 11px;
    display: none;
    font: 400 var(--text-input) / 1.25 var(--font-ui);
    color: rgb(255 255 255 / 0.4);
    pointer-events: none;
  }
  .date.empty i {
    display: block;
  }
  /* A quiet text toggle, with a 44 px hit area inside the field. */
  .eye {
    position: absolute;
    top: 5px;
    right: 2px;
    min-width: 44px;
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: var(--radius);
    background: none;
    color: rgb(244 236 216 / 0.7);
    font: 600 var(--text-sub) var(--font-ui);
  }
  .eye:focus-visible {
    outline: 2px solid var(--portal-accent, var(--portal-gold));
    outline-offset: -2px;
  }
  .swap {
    display: grid;
    gap: 10px;
    animation: swap var(--t-move) var(--ease);
  }
  @keyframes swap {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  .card {
    align-content: center;
  }
  /* In the intro's cell the card keeps its own height, at the bottom, so the portal above stays put. */
  .card.page {
    align-self: end;
  }
  .soon {
    display: grid;
    gap: 6px;
    padding: 12px 4px;
    text-align: center;
    color: rgb(244 236 216 / 0.7);
  }
  .soon b {
    font-family: var(--font-display);
    font-size: var(--text-body);
    color: var(--cream);
  }
  .soon p {
    margin: 0;
    font-family: var(--font-ui);
    font-size: var(--text-sub);
    text-wrap: balance;
  }
  .tries {
    margin: 0;
    text-align: center;
    font-family: var(--font-pixel);
    font-size: var(--text-label);
    color: var(--portal-accent, var(--portal-gold));
  }
  .tries.out {
    color: var(--rose);
  }
  ::selection {
    background: rgb(245 178 39 / 0.35);
  }
  .campus {
    font-family: var(--font-pixel);
    font-size: var(--text-label);
    color: var(--portal-gold);
  }
  .campus.dim {
    color: rgb(244 236 216 / 0.55);
  }
  .go,
  .step {
    height: 50px;
    border: 0;
    background: var(--portal-gold);
    color: var(--on-portal-gold);
    font-family: var(--font-ui);
    font-weight: 600;
    font-size: var(--text-body);
    letter-spacing: 0.01em;
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
    box-shadow: inset 0 -3px 0 var(--portal-gold-shade);
  }
  .go:focus-visible,
  .step:focus-visible {
    outline: none;
    box-shadow:
      inset 0 0 0 3px var(--cream),
      inset 0 -3px 0 var(--portal-gold-shade);
  }
  .ghost:focus-visible,
  .link:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }
  .go:active,
  .step:active {
    box-shadow: inset 0 3px 0 var(--portal-gold-shade);
    transform: translateY(1px);
  }
  .go:disabled {
    opacity: 0.7;
    cursor: progress;
  }
  .step {
    min-width: 220px;
    padding: 0 28px;
  }
  .retry {
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.08);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    color: var(--parch);
    font: 600 var(--text-input) var(--font-ui);
  }
  .why {
    margin: 0;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
    text-align: center;
  }
  .error.down {
    color: var(--parch);
  }
  .error {
    margin: 0;
    font-family: var(--font-ui);
    font-size: var(--text-sub);
    color: var(--rose);
  }
  .fine {
    margin: 0;
    font-family: var(--font-ui);
    font-size: var(--text-label);
    text-align: center;
    text-wrap: balance;
    color: rgb(244 236 216 / 0.5);
  }
  .hint {
    margin: 0;
    font-family: var(--font-pixel);
    font-size: var(--text-label);
    letter-spacing: 0.08em;
    color: rgb(244 236 216 / 0.5);
  }
  .hint.empty {
    font: 400 var(--text-sub) / 1.35 var(--font-ui);
    letter-spacing: 0;
    color: rgb(244 236 216 / 0.72);
    text-align: center;
  }
  .pair {
    display: grid;
    grid-template-columns: minmax(0, 1fr) minmax(0, 1fr);
    gap: 10px;
  }
  .pair.solo {
    grid-template-columns: minmax(0, 1fr);
  }
  /* The intro (spec 049). Its top row: Back, nine pixel bars, Skip. */
  .bar {
    display: grid;
    grid-template-columns: 1fr auto 1fr;
    align-items: center;
    min-height: 44px;
    opacity: 0;
    transition: opacity var(--t-hero) var(--ease);
  }
  .bar.on {
    opacity: 1;
  }
  .hide {
    visibility: hidden;
  }
  .back {
    justify-self: start;
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
  .steps {
    display: flex;
    gap: 4px;
  }
  .steps i {
    width: 10px;
    height: 4px;
    background: rgb(244 236 216 / 0.16);
    transition:
      width var(--t-move) var(--ease),
      background-color var(--t-move) var(--ease);
  }
  .steps i.past {
    background: rgb(244 236 216 / 0.5);
  }
  .steps i.on {
    width: 18px;
    background: var(--portal-gold);
  }
  .skip {
    justify-self: end;
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
  .chip:focus-visible,
  .check:focus-visible,
  .flash:focus-visible,
  .rate-b:focus-visible,
  .signal:focus-visible,
  .slider:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }

  /* Every page in one cell: the tallest sets the height, so the portal above never moves (C3). */
  .pages {
    display: grid;
    min-width: 0;
    touch-action: pan-y;
  }
  .page {
    grid-area: 1 / 1;
    min-width: 0;
    visibility: hidden;
  }
  .page.on {
    visibility: visible;
  }
  /* Content sits together just over Next; the room a shorter page leaves goes to the portal side. */
  section.page {
    display: grid;
    align-content: end;
    gap: 10px;
    padding: 2px 2px 0;
  }
  /* One motion per turn: the copy rises in from the side it came from, a beat apart (C6). */
  .page.on > * {
    animation: arrive var(--t-hero) var(--ease) backwards;
  }
  .page.on > :nth-child(2) {
    animation-delay: 40ms;
  }
  .page.on > :nth-child(3) {
    animation-delay: 80ms;
  }
  .page.on > :nth-child(4) {
    animation-delay: 120ms;
  }
  @keyframes arrive {
    from {
      opacity: 0;
      translate: calc(var(--dir, 1) * 28px) 6px;
    }
  }
  .page.off {
    visibility: visible;
    pointer-events: none;
    animation: depart var(--t-quick) ease-in both;
  }
  @keyframes depart {
    to {
      opacity: 0;
      translate: calc(var(--dir, 1) * -20px) 0;
    }
  }
  section.page h2 {
    margin: 0;
    font: var(--title-weight, 800) var(--text-title) / 1.15 var(--font-display);
    letter-spacing: var(--title-track, -0.02em);
    color: var(--cream);
    text-wrap: balance;
  }
  section.page h2.mark {
    font-family: var(--font-wordmark);
    font-weight: 700;
    letter-spacing: -0.01em;
    color: var(--portal-gold);
  }
  .mark span {
    color: var(--cream);
  }
  .lede {
    margin: 0;
    max-width: 34em;
    font: 400 var(--text-sub) / 1.4 var(--font-ui);
    color: rgb(244 236 216 / 0.74);
    text-wrap: pretty;
  }
  .demo {
    display: grid;
    align-content: start;
    gap: 8px;
    margin-bottom: 6px;
    min-width: 0;
  }
  .aside {
    margin: 0;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.55);
  }
  .chip {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
    padding: 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--parch);
    white-space: nowrap;
    transition: box-shadow var(--t-quick) var(--ease);
  }
  .chip:active {
    background: rgb(244 236 216 / 0.12);
  }
  /* Gold says "you are here": the picked campus, the worn look. */
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
    padding: 2px;
    margin: -2px;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scroll-snap-type: x proximity;
    scrollbar-width: none;
    touch-action: pan-x;
    mask-image: linear-gradient(to right, #000 calc(100% - 28px), transparent);
  }
  .campuses::-webkit-scrollbar {
    display: none;
  }
  .campuses .chip {
    scroll-snap-align: start;
  }
  .chip.other {
    justify-self: start;
  }
  .glyph {
    width: 10px;
    height: 14px;
  }

  /* Today: a clock to drag, the class's own stretch lit on its track. */
  .clock {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  .clock b {
    font: 600 var(--text-body) var(--font-ui);
    font-variant-numeric: tabular-nums;
    color: var(--cream);
  }
  .slider {
    width: 100%;
    height: 44px;
    margin: 0;
    padding: 0;
    background: transparent;
    -webkit-appearance: none;
    appearance: none;
    touch-action: none;
  }
  .slider::-webkit-slider-runnable-track {
    height: 6px;
    background: linear-gradient(to right, rgb(244 236 216 / 0.16) var(--a), var(--portal-accent) var(--a) var(--b), rgb(244 236 216 / 0.16) var(--b));
  }
  .slider::-moz-range-track {
    height: 6px;
    background: linear-gradient(to right, rgb(244 236 216 / 0.16) var(--a), var(--portal-accent) var(--a) var(--b), rgb(244 236 216 / 0.16) var(--b));
  }
  .slider::-webkit-slider-thumb {
    width: 22px;
    height: 22px;
    margin-top: -8px;
    border: 0;
    background: var(--cream);
    box-shadow: inset 0 -3px 0 rgb(0 0 0 / 0.25);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    -webkit-appearance: none;
    appearance: none;
  }
  .slider::-moz-range-thumb {
    width: 22px;
    height: 22px;
    border: 0;
    border-radius: 0;
    background: var(--cream);
  }
  .scale {
    display: flex;
    justify-content: space-between;
    margin-top: -6px;
    font: 400 var(--text-caption) var(--font-ui);
    font-variant-numeric: tabular-nums;
    color: rgb(244 236 216 / 0.5);
  }
  .scale span:nth-child(2) {
    color: var(--portal-accent);
  }
  /* The view in the portal's mouth. */
  .tv {
    display: grid;
    gap: 6px;
  }
  .tv-lab {
    justify-self: start;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: var(--accent);
    animation: tvpop var(--t-move) var(--ease) backwards;
  }
  .tv[data-phase="now"] .tv-lab {
    color: var(--portal-gold);
  }
  @keyframes tvpop {
    from {
      opacity: 0;
      scale: 0.7;
    }
  }
  .tv-code {
    font: 700 var(--text-headline) var(--font-display);
    color: var(--cream);
  }
  .tv-sub {
    font: 400 var(--text-caption) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.7);
  }
  .tv-left {
    display: grid;
    gap: 4px;
    margin-top: 6px;
    color: var(--cream);
  }
  .tv-left small {
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  .tv-bar {
    height: 4px;
    margin-top: 6px;
    background: rgb(244 236 216 / 0.12);
  }
  .tv-bar i {
    display: block;
    height: 100%;
    background: var(--accent);
    transition: width var(--t-move) var(--ease);
  }

  /* Deadlines: the app's own Done (DueCard), on one sample row. */
  .due {
    position: relative;
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr);
    align-items: center;
    min-height: 58px;
    padding-right: 12px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.05);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
  }
  .check {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    margin-left: 4px;
    padding: 0;
    border: 0;
    border-radius: var(--radius);
    background: none;
  }
  .check i {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    background: var(--void);
    box-shadow: inset 0 0 0 2px rgb(244 236 216 / 0.55);
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% calc(100% - 2px), calc(100% - 2px) calc(100% - 2px), calc(100% - 2px) 100%, 2px 100%, 2px calc(100% - 2px), 0 calc(100% - 2px));
  }
  .check.on i {
    background: var(--portal-gold);
    box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.25);
    animation: fill var(--t-move) var(--ease-spring) backwards;
  }
  .check.on i::after {
    content: "";
    width: 12px;
    height: 9px;
    background: var(--on-portal-gold);
    clip-path: polygon(0 50%, 25% 50%, 25% 75%, 37.5% 75%, 37.5% 50%, 62.5% 50%, 62.5% 25%, 75% 25%, 75% 0, 100% 0, 100% 25%, 87.5% 25%, 87.5% 50%, 75% 50%, 75% 75%, 62.5% 75%, 62.5% 100%, 25% 100%, 25% 75%, 0 75%);
  }
  @keyframes fill {
    from {
      scale: 0.6;
    }
  }
  .what {
    display: grid;
    gap: 2px;
    min-width: 0;
    padding-left: 6px;
  }
  .what strong {
    position: relative;
    justify-self: start;
    font: 600 var(--text-body) var(--font-ui);
    color: var(--cream);
    transition: color var(--t-quick) var(--ease);
  }
  .what small {
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  .what small b {
    font-weight: 600;
    color: var(--portal-accent);
  }
  .due.done .what strong {
    color: rgb(244 236 216 / 0.55);
  }
  .due.done .what strong::after {
    content: "";
    position: absolute;
    left: -1px;
    right: -1px;
    top: 52%;
    height: 2px;
    background: rgb(244 236 216 / 0.55);
    transform-origin: left;
    animation: strike var(--t-quick) var(--ease) backwards;
    animation-delay: 160ms;
  }
  @keyframes strike {
    from {
      transform: scaleX(0);
    }
  }
  .stamp {
    position: absolute;
    right: 10px;
    top: 50%;
    translate: 0 -50%;
    rotate: -7deg;
    padding: 1px 6px;
    font: 700 var(--text-label) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--good);
    background: var(--void-2);
    box-shadow: inset 0 0 0 2px var(--good);
    pointer-events: none;
    animation: thunk var(--t-flow) var(--ease) both;
    animation-delay: 160ms;
  }
  @keyframes thunk {
    0% {
      scale: 1.9;
      opacity: 0;
    }
    60% {
      scale: 0.97;
      opacity: 1;
    }
    100% {
      scale: 1;
      opacity: 1;
    }
  }
  .clear {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 58px;
    margin: 0;
    font: 600 var(--text-sub) var(--font-ui);
    color: rgb(244 236 216 / 0.8);
  }
  .clear .link {
    margin: 0;
    font-weight: 400;
  }

  /* Grades and Study. */
  .gpa {
    display: flex;
    align-items: center;
    gap: 14px;
    color: var(--cream);
  }
  .gpa-num {
    display: grid;
    gap: 4px;
  }
  .gpa-num small {
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
    white-space: nowrap;
  }
  .trend {
    flex: 1;
    min-width: 0;
    height: 40px;
  }
  .trend polyline {
    fill: none;
    stroke: var(--portal-accent);
    stroke-width: 1.4;
    stroke-linejoin: round;
    stroke-dasharray: 1;
    stroke-dashoffset: 1;
  }
  .page.on .trend polyline {
    animation: draw calc(var(--t-hero) * 2) var(--ease) forwards;
    animation-delay: 200ms;
  }
  @keyframes draw {
    to {
      stroke-dashoffset: 0;
    }
  }
  .trend .guide {
    stroke: rgb(244 236 216 / 0.12);
    stroke-width: 0.5;
    stroke-dasharray: 1 2;
  }
  .trend rect {
    fill: var(--cream);
    opacity: 0;
  }
  .page.on .trend rect {
    animation: dot var(--t-move) var(--ease) forwards;
  }
  @keyframes dot {
    to {
      opacity: 1;
    }
  }
  .flash {
    position: relative;
    height: 56px;
    padding: 0;
    border: 0;
    background: none;
    perspective: 600px;
  }
  .face {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    padding: 0 14px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.07);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.14);
    backface-visibility: hidden;
    -webkit-backface-visibility: hidden;
    transition: transform var(--t-flow) var(--ease);
  }
  .ask {
    font: 500 var(--text-body) var(--font-ui);
    color: rgb(244 236 216 / 0.88);
  }
  .ans {
    transform: rotateY(180deg);
  }
  .flash .ans {
    font: 700 var(--text-headline) var(--font-display);
    color: var(--cream);
  }
  .flipped .ask {
    transform: rotateY(-180deg);
  }
  .flipped .ans {
    transform: rotateY(0);
  }
  .rate {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
  }
  .rate-b {
    flex: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    color: var(--parch);
    font: 600 var(--text-sub) var(--font-ui);
    animation: arrive var(--t-move) var(--ease) backwards;
  }
  .rate-b small {
    font: 500 var(--text-label) var(--font-pixel);
    color: var(--portal-accent);
  }
  .back-in,
  .okay {
    margin: 0;
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--cream);
  }

  /* Offline: the signal drops out, the rows stay lit. */
  .signal {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 52px;
    padding: 0 12px 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    color: var(--parch);
    font: 600 var(--text-body) var(--font-ui);
  }
  .bars {
    display: inline-flex;
    align-items: flex-end;
    gap: 2px;
    width: 18px;
    height: 14px;
  }
  .bars i {
    width: 3px;
    background: var(--cream);
    transition:
      translate var(--t-move) var(--ease),
      opacity var(--t-move) var(--ease);
  }
  .bars i:nth-child(1) {
    height: 4px;
  }
  .bars i:nth-child(2) {
    height: 7px;
    transition-delay: 40ms;
  }
  .bars i:nth-child(3) {
    height: 10px;
    transition-delay: 80ms;
  }
  .bars i:nth-child(4) {
    height: 14px;
    transition-delay: 120ms;
  }
  .bars.out i {
    translate: 0 8px;
    opacity: 0;
  }
  .bars.out i:nth-child(1) {
    opacity: 0.35;
    translate: 0;
  }
  .switch {
    position: relative;
    margin-left: auto;
    width: 44px;
    height: 26px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.16);
    transition: background-color var(--t-quick) var(--ease);
  }
  .switch i {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 20px;
    height: 20px;
    border-radius: var(--radius-sm);
    background: var(--cream);
    transition: translate var(--t-move) var(--ease-spring);
  }
  [aria-checked="true"] .switch {
    background: var(--cream);
  }
  [aria-checked="true"] .switch i {
    translate: 18px 0;
    background: var(--void);
  }
  .kept-rows {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  .kept-rows li {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 40px;
    padding: 0 10px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.04);
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--cream);
  }
  .tick {
    width: 12px;
    height: 9px;
    background: var(--good);
    clip-path: polygon(0 50%, 25% 50%, 25% 75%, 37.5% 75%, 37.5% 50%, 62.5% 50%, 62.5% 25%, 75% 25%, 75% 0, 100% 0, 100% 25%, 87.5% 25%, 87.5% 50%, 75% 50%, 75% 75%, 62.5% 75%, 62.5% 100%, 25% 100%, 25% 75%, 0 75%);
  }

  /* Your look. */
  .looks {
    display: flex;
    flex-wrap: wrap;
    gap: 8px;
  }
  .tones {
    display: block;
    width: 24px;
    height: 14px;
    box-shadow: 0 0 0 1px rgb(244 236 216 / 0.25);
  }

  /* Reminders: the sample nudge, at rest in the page and sliding down from the top. */
  .note {
    display: grid;
    grid-template-columns: 36px minmax(0, 1fr);
    gap: 10px;
    padding: 10px 12px;
    border-radius: var(--radius-lg);
    background: var(--void-lift);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
    font-family: var(--font-ui);
  }
  .note-slot {
    position: fixed;
    top: calc(var(--safe-top) + 8px);
    left: var(--gutter);
    right: var(--gutter);
    z-index: 62;
    filter: drop-shadow(0 10px 30px rgb(0 0 0 / 0.5));
  }
  .note-icon {
    display: grid;
    place-items: center;
    width: 36px;
    height: 36px;
    border-radius: var(--radius);
    background: var(--void);
  }
  .note-icon :global(svg) {
    width: 15px;
    height: 21px;
  }
  .note-text {
    display: grid;
    min-width: 0;
  }
  .note-head {
    display: flex;
    align-items: baseline;
    gap: 8px;
    font: 600 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.7);
  }
  .note-head small {
    margin-left: auto;
    font-weight: 400;
    color: rgb(244 236 216 / 0.5);
  }
  .note-title {
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--cream);
  }
  .note-body {
    font: 400 var(--text-sub) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.78);
  }
  .link.soft {
    justify-self: center;
    margin: -6px 0 0;
    padding: 0 12px;
    font: 600 var(--text-sub) var(--font-ui);
    color: rgb(244 236 216 / 0.78);
    text-decoration: none;
  }
  .ghost {
    min-height: 50px;
    padding: 0 12px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.2);
    color: var(--parch);
    font: 600 var(--text-sub) var(--font-ui);
  }
  .ghost:disabled {
    opacity: 0.5;
  }
  .link {
    /* The words are small; the target is not. */
    min-height: 44px;
    margin: -14px 0;
    padding: 0 4px;
    border: 0;
    background: none;
    color: rgb(244 236 216 / 0.82);
    font: inherit;
    text-decoration: underline;
    text-underline-offset: 3px;
  }
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    background: rgb(5 2 8 / 0.6);
  }
  .kept {
    position: fixed;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 12px);
    z-index: 61;
    display: grid;
    gap: 14px;
    padding: 18px 16px 14px;
    border-radius: var(--radius-lg);
    background: var(--void-2);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.14), 0 -12px 40px rgb(0 0 0 / 0.5);
    font-family: var(--font-ui);
    animation: rise var(--t-flow) var(--ease) backwards;
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(16px);
    }
  }
  .kept h2 {
    margin: 0;
    font: 700 var(--text-headline) var(--font-ui);
    color: var(--cream);
  }
  .kept dl {
    display: grid;
    gap: 2px;
    margin: 0;
  }
  .kept dt {
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--parch);
  }
  .kept dd {
    margin: 0 0 10px;
    font: 400 var(--text-sub) / 1.4 var(--font-ui);
    color: rgb(244 236 216 / 0.72);
  }
  @media (prefers-reduced-motion: reduce) {
    .swap {
      animation: none;
    }
    /* Reduce Motion: no slide; the page that leaves is simply gone (C17). */
    .page.off {
      visibility: hidden;
    }
    .field,
    .field label,
    input::placeholder {
      transition: none;
    }
    .dock,
    .brand {
      animation: none;
      transition: none;
    }
  }
</style>

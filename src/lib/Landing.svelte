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
  import { adopt, app, refreshLogins, setRoom, syncNow } from "./state.svelte";
  import WelcomeTour from "./welcome/WelcomeTour.svelte";
  import { TOUR, type Act } from "./welcome/tour";
  import { stageFor } from "./tiles";
  import type { DiveStart } from "./dive";

  let { signedIn, onenter, ondive }: { signedIn: boolean; onenter: () => void; ondive: (s: DiveStart) => void } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const returning = untrack(() => signedIn);
  // Where the portal opens: the sign-in card, or straight to Step through.
  let rest = $state<"signin" | "hub">(returning ? "hub" : "signin");
  // A student new to the app first reads what it is, then asks for the form (010 C42).
  // Once they have, or have looked around, they go straight to the form next time.
  const WELCOMED = "intportal.welcomed";
  const seen = (() => {
    try {
      return localStorage.getItem(WELCOMED) === "1";
    } catch {
      return false;
    }
  })();
  let welcome = $state(!returning && !seen);
  function welcomed() {
    try {
      localStorage.setItem(WELCOMED, "1");
    } catch {
      // Private mode: the welcome shows again next launch.
    }
  }
  // A dark look the student picked (here or in You) colours the landing's ground and dots too;
  // a light one leaves the landing on the night ground, which the portal needs (010 C45).
  const DARK = new Set(TOUR.flatMap((s) => s.items).flatMap((i) => (i.act.kind === "room" ? [i.act.room] : [])));
  const worn = $derived(DARK.has(app.room));
  /** A tour item, done on the stage itself: the portal peeks, LAR talks, the room changes (010 C45). */
  function act(a: Act, from: DOMRect) {
    buzz.select();
    if (a.kind === "peek") stageEl?.peekTo(a.page);
    else if (a.kind === "say") stageEl?.say(a.line);
    else if (a.kind === "school") stageEl?.openWall(from);
    else {
      setRoom(a.room);
      stageEl?.say("Ayan, bagay. Ganyan na ang kulay ng app mo, kahit mag-sign in ka na.");
    }
  }
  function begin() {
    welcome = false;
    welcomed();
    buzz.tick();
  }
  // Back from the form goes back to the welcome it came from.
  $effect(() => {
    if (!welcome && !seen && rest === "signin" && !busy) return closable(() => (welcome = true));
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

<section class="landing dots" class:leaving class:worn>
  <header class="brand" class:on={resting}>
    <h1>Student <span>IntPortal</span></h1>
    {#if !ready}<p class="pitch">{portal.school} is next. For now, IntPortal works with PUP.</p>{/if}
  </header>

  <!-- C16: while the frame builds, the portal stands larger in the middle of the screen; it lifts into its place as the form rises. -->
  <div class="lift" class:up={resting} style:--drop="{Math.round(cardMin / 2)}px">
  <PortalStage
    bind:this={stageEl}
    {portals}
    index={Math.max(0, portals.indexOf(portal))}
    onselect={(i) => ((portalId = portals[i].id), (error = ""))}
    locked={busy || rest === "hub"}
    {stage}
    {returning}
    still={typing}
    showLar={resting}
    {leaving}
    {ctx}
    quiet={welcome}
  />
  </div>

  <!-- In the layout from the start, so the portal's room never jumps when it shows. -->
  <div class="dock" class:on={resting} class:hub={rest === "hub"} class:bare={welcome && rest !== "hub"} inert={!resting}>
      {#if rest === "hub"}
        <button class="step" onclick={step}>Step through</button>
        <p class="hint">{app.sisConnected ? `PUP SIS · via ${(app.snapshot?.host ?? "sis8").split(".")[0]}` : copy.hint}</p>
        <!-- 011 C10: signed in, but the SIS has no schedule for this term yet; the student still goes in. -->
        {#if app.sisConnected && app.snapshot && !app.snapshot.sessions.length && !returning}<p class="hint empty">Signed in, but your schedule isn't up yet.</p>{/if}
      {:else if welcome}
        <!-- What the app is in one line, then a tour the student can poke at, before any form (010 C42, C45). -->
        <div class="welcome">
          <h2>Your PUP schedule, grades and deadlines, on your phone.</h2>
          <WelcomeTour room={app.room === "system" ? "night" : app.room} onact={act} />
          {#if error}<p class="error" role="alert">{error}</p>{/if}
          <button type="button" class="go" onclick={begin}>Sign in with SIS</button>
          <button type="button" class="link soft" onclick={demo}>Look around first</button>
        </div>
      {:else}
        <!-- The card keeps the tallest height it has had, so swiping between portals never resizes the portal above it. -->
        <form class="card" style:--portal-accent={portal.theme.accent} style:min-height="{cardMin}px" bind:offsetHeight={cardH} onsubmit={submit} onfocusin={() => (typing = true)} onfocusout={() => (typing = false)}>
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
            <button type="button" class="link" onclick={demo} disabled={busy}>Look around</button>
          </p>
          {/if}
          </div>{/key}
        </form>
      {/if}
  </div>
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
    /* The app's own ground. Its dots are squares on the portal's tile pitch, placed by PortalStage,
       so the portal is this grid lit up (spec 010 C3). Before the scene loads they sit at 14 px. */
    --land: var(--void);
    --land-dot: rgb(232 176 74 / 0.13);
    background-color: var(--land);
    background-image: conic-gradient(from 270deg at var(--grid-dot, 1.5px) var(--grid-dot, 1.5px), var(--land-dot) 90deg, transparent 0);
    transition: background-color var(--t-flow) var(--ease);
    background-size: var(--grid-pitch, 14px) var(--grid-pitch, 14px);
    background-position: var(--grid-x, 0) var(--grid-y, 0);
  }
  .landing.worn {
    --land: var(--ground);
    --land-dot: color-mix(in srgb, var(--gold) 16%, transparent);
  }
  /* The app's drifting pools, held still and dim here: on the landing the portal is the light. */
  .landing.dots::before,
  .landing.dots::after {
    animation: none;
    opacity: calc(var(--aura-o, 1) * 0.4);
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
  /* The welcome: no card, the page's own ground under one headline, three facts and one gold. */
  .welcome {
    display: grid;
    gap: 14px;
    padding: 4px 4px 0;
    animation: swap var(--t-flow) var(--ease);
  }
  .welcome h2 {
    margin: 0;
    font: 700 var(--text-title) / 1.2 var(--font-display);
    letter-spacing: -0.02em;
    color: var(--cream);
    text-wrap: balance;
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
    .swap,
    .welcome {
      animation: none;
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

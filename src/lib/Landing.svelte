<script lang="ts">
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
  import { FALLBACK_SIS, portalCopy, triesLine, validate } from "./portals";
  import { portalApiFor } from "./portalApi";
  import { buzz } from "./haptics";
  import { landingAt, restAt } from "./landing";
  import { adopt, app, refreshLogins, syncNow } from "./state.svelte";
  import { stageFor } from "./tiles";

  let { signedIn, onenter }: { signedIn: boolean; onenter: () => void } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const returning = untrack(() => signedIn);
  // Where the portal opens: the sign-in card, or straight to Step through.
  let rest = $state<"signin" | "hub">(returning ? "hub" : "signin");
  let busy = $state(false);
  let error = $state("");
  let typing = $state(false);
  let studno = $state("");
  let birthday = $state("");
  let password = $state("");
  let showPw = $state(false);
  // Set by a failed check; each field then clears its own mark once it is fixed.
  let tried = $state(false);

  let t = $state(0);
  let steppedAt = $state<number | null>(null);
  const moment = $derived(landingAt(t, { returning, reduce, steppedAt }));
  const resting = $derived(moment.phase === "rest");
  const stage = $derived(stageFor({ busy, open: rest === "hub" }));
  let cardH = $state(0);
  let cardMin = $state(0);
  $effect(() => {
    if (cardH > cardMin) cardMin = cardH;
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
  const bad = (field: PortalField) => tried && !!validate({ ...portal, fields: [field] }, values);

  async function submit(e: Event) {
    e.preventDefault();
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
      error = String(err);
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
      buzz.done();
    } catch (err) {
      error = String(err);
    }
  }

  function step() {
    if (!resting || steppedAt !== null) return;
    buzz.release();
    steppedAt = Math.max(t, restAt({ returning, reduce, steppedAt: null }));
  }
</script>

<section class="landing" class:leaving={steppedAt !== null}>
  <header class="brand" class:on={resting}>
    <h1>Student <span>IntPortal</span></h1>
  </header>

  <PortalStage
    {portals}
    index={Math.max(0, portals.indexOf(portal))}
    onselect={(i) => ((portalId = portals[i].id), (error = ""))}
    locked={busy || rest === "hub"}
    {stage}
    {returning}
    still={typing}
    showLar={resting}
    leaving={steppedAt !== null}
    {ctx}
  />

  <!-- In the layout from the start, so the portal's room never jumps when it shows. -->
  <div class="dock" class:on={resting} class:hub={rest === "hub"} inert={!resting}>
      {#if rest === "hub"}
        <button class="step" onclick={step}>Step through</button>
        <p class="hint">{app.sisConnected ? `PUP SIS · via ${(app.snapshot?.host ?? "sis8").split(".")[0]}` : copy.hint}</p>
      {:else}
        <!-- The card keeps the tallest height it has had, so swiping between portals never resizes the portal above it. -->
        <form class="card" style:--portal-accent={portal.theme.accent} style:min-height="{cardMin}px" bind:offsetHeight={cardH} onsubmit={submit} onfocusin={() => (typing = true)} onfocusout={() => (typing = false)}>
          {#key portal.id}<div class="swap">
          {#if !ready}
            <div class="soon">
              <b>{portal.school}</b>
              <p>Its portal opens soon. IntPortal will connect here once it's ready; for now, SIS and Mabini work.</p>
            </div>
          {:else}
          <div class="field" class:filled={!!studno} class:bad={bad("student_number")}>
            <input id="f-studno" bind:value={studno} placeholder="2026-00000-MN-0" autocapitalize="characters" autocomplete="username" inputmode="text" spellcheck="false" aria-invalid={bad("student_number")} />
            <label for="f-studno">Student number</label>
          </div>
          {#if campus.kind === "known"}<small class="campus">{campus.campus.name} · campus found</small>
          {:else if campus.kind === "unknown_code"}<small class="campus dim">{campus.code} · campus not confirmed yet, sign-in still works</small>{/if}
          {#if portal.fields.includes("birthdate")}
            <div class="field date" class:empty={!birthday} class:bad={bad("birthdate")}>
              <input id="f-birthday" type="date" bind:value={birthday} aria-invalid={bad("birthdate")} />
              <label for="f-birthday">Birthdate</label>
              <i aria-hidden="true">mm / dd / yyyy</i>
            </div>
          {/if}
          <div class="field" class:filled={!!password} class:bad={bad("password")}>
            <input id="f-password" type={showPw ? "text" : "password"} bind:value={password} autocomplete="current-password" aria-invalid={bad("password")} />
            <label for="f-password">Password</label>
            <button type="button" class="eye" aria-label="Show password" aria-pressed={showPw} onclick={() => (showPw = !showPw)}>{showPw ? "Hide" : "Show"}</button>
          </div>
          <button class="go" disabled={busy || locked}>{busy ? "Signing in…" : "Sign in"}</button>
          {#if triesText}<p class="tries" class:out={locked} aria-live="polite">{triesText}</p>{/if}
          {#if error}<p class="error" role="alert">{error}</p>{/if}
          <p class="fine">{copy.keychainNote}</p>
          {/if}
          {#if __REVIEW__}
            <button type="button" class="demo" onclick={demo}>Look around with demo data</button>
          {/if}
          </div>{/key}
        </form>
      {/if}
  </div>
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
    color: #f4ecd8;
    background: #060607;
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
    font-family: var(--font-display);
    font-size: min(1.529rem, 34px);
    font-weight: 700;
    letter-spacing: -0.01em;
    color: #f5b227;
  }
  h1 span {
    color: #fff5dc;
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
    background: #140c16;
    box-shadow: inset 0 0 0 1px rgb(245 178 39 / 0.16);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  /* The fields follow the phone's own login pattern: a rounded well, the label
     inside it floating up once there is something to say. */
  .field {
    position: relative;
    border-radius: 10px;
    background: #0b0710;
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.14);
    transition: box-shadow 0.16s var(--ease);
  }
  .field:focus-within {
    box-shadow: inset 0 0 0 1.5px var(--portal-accent, #f5b227);
  }
  .field.bad {
    box-shadow: inset 0 0 0 1.5px #f0a090;
  }
  input {
    display: block;
    width: 100%;
    min-width: 0;
    height: 54px;
    padding: 20px 14px 4px;
    border: 0;
    border-radius: 10px;
    background: transparent;
    box-shadow: none;
    color: #fff;
    font: 400 max(16px, min(0.941rem, 29px)) / 1.25 var(--font-ui);
    caret-color: #f5b227;
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
    font: 400 max(16px, min(0.941rem, 29px)) / 1.25 var(--font-ui);
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
    color: var(--portal-accent, #f5b227);
  }
  .field.bad label {
    color: #f0a090;
  }
  /* The example shows only once the label is up. */
  input::placeholder {
    color: rgb(255 255 255 / 0.4);
    opacity: 0;
    transition: opacity 0.16s var(--ease);
  }
  input:focus::placeholder {
    opacity: 1;
  }
  /* Autofill paints its own yellow; keep the well dark. */
  input:-webkit-autofill {
    -webkit-text-fill-color: #fff;
    box-shadow: 0 0 0 100px #0b0710 inset;
  }
  /* iOS draws an empty date field as a blank slab; give it a hint, and hide the
     browser's own format text so the two never stack. */
  .date input {
    display: flex;
    align-items: center;
  }
  .date input::-webkit-date-and-time-value {
    text-align: left;
  }
  .date.empty:not(:focus-within) input::-webkit-datetime-edit {
    opacity: 0;
  }
  .date i {
    position: absolute;
    left: 14px;
    bottom: 11px;
    display: none;
    font: 400 max(16px, min(0.941rem, 29px)) / 1.25 var(--font-ui);
    color: rgb(255 255 255 / 0.4);
    pointer-events: none;
  }
  .date.empty:not(:focus-within) i {
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
    border-radius: 8px;
    background: none;
    color: rgb(244 236 216 / 0.7);
    font: 600 min(0.824rem, 25px) var(--font-ui);
  }
  .eye:focus-visible {
    outline: 2px solid var(--portal-accent, #f5b227);
    outline-offset: -2px;
  }
  .swap {
    display: grid;
    gap: 10px;
    animation: swap 0.32s var(--ease);
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
    font-size: min(0.941rem, 29px);
    color: #fff5dc;
  }
  .soon p {
    margin: 0;
    font-family: var(--font-ui);
    font-size: min(0.824rem, 25px);
    text-wrap: balance;
  }
  .tries {
    margin: 0;
    text-align: center;
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
    color: var(--portal-accent, #f5b227);
  }
  .tries.out {
    color: #f0a090;
  }
  ::selection {
    background: rgb(245 178 39 / 0.35);
  }
  .campus {
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
    color: #f5b227;
  }
  .campus.dim {
    color: rgb(244 236 216 / 0.55);
  }
  .go,
  .step {
    height: 50px;
    border: 0;
    background: #f5b227;
    color: #1b1406;
    font-family: var(--font-ui);
    font-weight: 600;
    font-size: min(0.941rem, 29px);
    letter-spacing: 0.01em;
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
    box-shadow: inset 0 -3px 0 #b87a10;
  }
  .go:focus-visible,
  .step:focus-visible {
    outline: none;
    box-shadow:
      inset 0 0 0 3px #fff6dc,
      inset 0 -3px 0 #b87a10;
  }
  .demo:focus-visible {
    outline: 2px solid #f5b227;
    outline-offset: 3px;
  }
  .go:active,
  .step:active {
    box-shadow: inset 0 3px 0 #b87a10;
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
  .error {
    margin: 0;
    font-family: var(--font-ui);
    font-size: min(0.824rem, 25px);
    color: #f0a090;
  }
  .fine {
    margin: 0;
    font-family: var(--font-ui);
    font-size: min(0.706rem, 22px);
    text-align: center;
    text-wrap: balance;
    color: rgb(244 236 216 / 0.5);
  }
  .hint {
    margin: 0;
    font-family: var(--font-pixel);
    font-size: min(0.706rem, 22px);
    letter-spacing: 0.08em;
    color: rgb(244 236 216 / 0.5);
  }
  .demo {
    border: 0;
    font-family: var(--font-ui);
    background: none;
    color: rgb(245 178 39 / 0.85);
    font-size: min(0.765rem, 23px);
    text-decoration: underline;
    text-underline-offset: 3px;
  }
  @media (prefers-reduced-motion: reduce) {
    .swap {
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

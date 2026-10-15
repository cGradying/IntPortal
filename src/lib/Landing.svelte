<script lang="ts">
  // The landing. The portal builds itself from pentominoes, the swirl
  // ignites, LAR comes through and pulls out three stones that show what's on
  // the other side, then the sign-in card rises. Signed in, Step through
  // dives into the swirl and lands on Today. A returning student skips the
  // build. The scene runs on one clock through landing.ts.
  import { onMount, untrack } from "svelte";
  import PortalStage from "./PortalStage.svelte";
  import type { Gesture } from "./lar/Lar.svelte";
  import type { Mood } from "./lar/sprite";
  import { api, isoDate, type CampusResolution, type Portal, type Tries } from "./api";
  import { FALLBACK_SIS, portalCopy, triesLine, validate } from "./portals";
  import { portalApiFor } from "./portalApi";
  import { buzz } from "./haptics";
  import { landingAt, restAt } from "./landing";
  import { adopt, app, refreshLogins, syncNow } from "./state.svelte";

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

  let t = $state(0);
  let steppedAt = $state<number | null>(null);
  const moment = $derived(landingAt(t, { returning, reduce, steppedAt }));
  const resting = $derived(moment.phase === "rest");
  // The card needs room, so the portal sits higher above it; once signed
  // in, the camera moves in and the portal comes down to meet Step through.
  const frameFor = (at: "signin" | "hub") => (at === "hub" ? { lift: 0.083, span: 11.4 } : { lift: 0.2, span: 16.5 });
  let lift = $state(frameFor(returning ? "hub" : "signin").lift);
  let span = $state(frameFor(returning ? "hub" : "signin").span);

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

  // LAR's face and hands follow what's happening.
  const mood = $derived<Mood>(error ? "wow" : busy || typing ? "focus" : rest === "hub" ? "happy" : "open");
  const gesture = $derived<Gesture>(moment.phase === "glimpse" ? "reach" : rest === "hub" || moment.phase === "arrival" ? "wave" : "idle");
  const line = $derived(
    error
      ? "Hindi pumasok. Check the details and try again."
      : rest === "hub"
        ? returning
          ? "Welcome back, iskolar. Tara?"
          : "Ayos! Your schedule and grades are in."
        : copy.lar,
  );

  onMount(() => {
    let raf = 0;
    const start = performance.now();
    let placed = moment.placed;
    let lit = false;
    const frame = (now: number) => {
      t = (now - start) / 1000;
      const want = frameFor(rest);
      lift += (want.lift - lift) * 0.08;
      span += (want.span - span) * 0.08;
      const m = moment;
      if (m.placed > placed) buzz.tick();
      placed = m.placed;
      if (m.phase === "igniting" && !lit) {
        lit = true;
        buzz.done();
      }
      if (m.phase === "entered") {
        if (signedIn) syncNow();
        onenter();
        return;
      }
      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => cancelAnimationFrame(raf);
  });

  async function submit(e: Event) {
    e.preventDefault();
    error = validate(portal, { student_number: studno, birthdate: birthday, password });
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
  <PortalStage {moment} {t} {lift} {span} {mood} {gesture} still={typing} />

  <header class="brand" class:on={resting}>
    <h1>Student <span>IntPortal</span></h1>
  </header>

  {#if resting}
    <div class="dock" class:hub={rest === "hub"}>
      <p class="say" aria-live="polite"><b>LAR</b> {line}</p>
      {#if rest === "hub"}
        <button class="step" onclick={step}>Step through</button>
        <p class="hint">{app.sisConnected ? `PUP SIS · via ${(app.snapshot?.host ?? "sis8").split(".")[0]}` : copy.hint}</p>
      {:else}
        <form class="card" style:--portal-accent={portal.theme.accent} onsubmit={submit} onfocusin={() => (typing = true)} onfocusout={() => (typing = false)}>
          {#if portals.length > 1}
            <div class="switch" role="group" aria-label="Portal">
              {#each portals as p (p.id)}
                <button type="button" class:on={p.id === portalId} aria-pressed={p.id === portalId} onclick={() => ((portalId = p.id), (error = ""))}>
                  <i style:background={p.theme.accent} aria-hidden="true"></i>{p.name}{#if p.status !== "ready"}<small>Opens soon</small>{/if}
                </button>
              {/each}
            </div>
          {/if}
          {#if !ready}
            <p class="soon">{portal.name} opens soon.</p>
          {:else}
          <label>
            <span>Student number</span>
            <input bind:value={studno} placeholder="2026-00000-MN-0" autocapitalize="characters" autocomplete="username" inputmode="text" spellcheck="false" />
            {#if campus.kind === "known"}<small class="campus">{campus.campus.name} · campus found</small>
            {:else if campus.kind === "unknown_code"}<small class="campus dim">{campus.code} · campus not confirmed yet, sign-in still works</small>{/if}
          </label>
          <div class="pair" class:single={!portal.fields.includes("birthdate")}>
            {#if portal.fields.includes("birthdate")}
              <label class="date" class:empty={!birthday}>
                <span>Birthdate</span>
                <input type="date" bind:value={birthday} />
                <i aria-hidden="true">mm / dd / yyyy</i>
              </label>
            {/if}
            <label>
              <span>Password</span>
              <input type="password" bind:value={password} autocomplete="current-password" />
            </label>
          </div>
          <button class="go" disabled={busy || locked}>{busy ? "Signing in…" : "Sign in"}</button>
          {#if triesText}<p class="tries" class:out={locked} aria-live="polite">{triesText}</p>{/if}
          {#if error}<p class="error" role="alert">{error}</p>{/if}
          <p class="fine">{copy.keychainNote}</p>
          {/if}
          {#if __REVIEW__}
            <button type="button" class="demo" onclick={demo}>Look around with demo data</button>
          {/if}
        </form>
      {/if}
    </div>
  {/if}
</section>

<style>
  .landing {
    position: fixed;
    inset: 0;
    z-index: 50;
    color: #f4ecd8;
    background: #0b0710;
  }
  .brand {
    position: absolute;
    top: calc(var(--safe-top) + 10px);
    left: 0;
    right: 0;
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
    position: absolute;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 12px);
    display: grid;
    gap: 10px;
    animation: rise 0.7s var(--ease) both;
    /* On the unclipped parent: the card's clip-path would cut its own shadow. */
    filter: drop-shadow(0 -10px 30px rgb(0 0 0 / 0.5));
  }
  .dock.hub {
    justify-items: center;
    bottom: calc(var(--safe-bottom) + 40px);
  }
  @keyframes rise {
    from {
      transform: translateY(40px);
      opacity: 0;
    }
  }
  .leaving .dock,
  .leaving .brand {
    opacity: 0;
    transform: translateY(16px);
    transition:
      opacity 0.25s ease-in,
      transform 0.25s ease-in;
  }
  .say {
    margin: 0;
    padding: 10px 12px;
    background: #170b1a;
    box-shadow:
      inset 0 2px 0 #3a2446,
      inset 0 -2px 0 #060307;
    font-size: min(0.824rem, 25px);
    line-height: 1.35;
    color: #f4e8d6;
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
  }
  .hub .say {
    text-align: center;
  }
  .say b {
    margin-right: 6px;
    font-family: var(--font-pixel);
    font-weight: 400;
    letter-spacing: 0.06em;
    color: #f5b227;
  }
  .card {
    display: grid;
    gap: 12px;
    padding: 16px 16px 12px;
    background: #140c16;
    box-shadow: inset 0 0 0 1px rgb(245 178 39 / 0.16);
    clip-path: polygon(0 4px, 4px 4px, 4px 0, calc(100% - 4px) 0, calc(100% - 4px) 4px, 100% 4px, 100% calc(100% - 4px), calc(100% - 4px) calc(100% - 4px), calc(100% - 4px) 100%, 4px 100%, 4px calc(100% - 4px), 0 calc(100% - 4px));
  }
  label {
    display: grid;
    gap: 5px;
    min-width: 0;
  }
  label > span {
    font-size: min(0.706rem, 22px);
    font-weight: 600;
    letter-spacing: 0.06em;
    text-transform: uppercase;
    color: rgb(244 236 216 / 0.6);
  }
  .pair {
    display: grid;
    grid-template-columns: 1fr 1fr;
    gap: 10px;
  }
  input {
    width: 100%;
    min-width: 0;
    height: 46px;
    padding: 0 12px;
    border: 0;
    border-radius: 0;
    background: #0b0710;
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.1);
    color: #fff;
    font: max(16px, min(0.941rem, 29px)) var(--font-body);
    caret-color: #f5b227;
    outline: none;
    -webkit-appearance: none;
    appearance: none;
  }
  /* iOS draws an empty date field as a blank slab; give it a hint. */
  .date {
    position: relative;
  }
  .date input {
    display: flex;
    align-items: center;
  }
  .date input::-webkit-date-and-time-value {
    text-align: left;
  }
  .date i {
    position: absolute;
    left: 12px;
    bottom: 13px;
    display: none;
    font-style: normal;
    color: rgb(255 255 255 / 0.58);
    pointer-events: none;
  }
  .date.empty i {
    display: block;
  }
  input::placeholder {
    color: rgb(255 255 255 / 0.58);
  }
  input:focus {
    box-shadow: inset 0 0 0 2px var(--portal-accent, #f5b227);
  }
  .pair.single {
    grid-template-columns: 1fr;
  }
  .switch {
    display: grid;
    grid-auto-flow: column;
    grid-auto-columns: 1fr;
    gap: 6px;
  }
  .switch button {
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 7px;
    height: 40px;
    border: 0;
    background: #0b0710;
    box-shadow: inset 0 0 0 1px rgb(255 255 255 / 0.1);
    color: rgb(244 236 216 / 0.7);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .switch button.on {
    color: #fff5dc;
    box-shadow: inset 0 0 0 2px var(--portal-accent, #f5b227);
  }
  .switch i {
    width: 8px;
    height: 8px;
  }
  .switch small {
    font-family: var(--font-pixel);
    font-weight: 400;
    font-size: min(0.647rem, 20px);
    color: rgb(244 236 216 / 0.5);
  }
  .soon {
    margin: 0;
    padding: 18px 0;
    text-align: center;
    color: rgb(244 236 216 / 0.7);
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
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.941rem, 29px);
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
  }
  .step {
    min-width: 220px;
    padding: 0 28px;
  }
  .error {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: #f0a090;
  }
  .fine {
    margin: 0;
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
    background: none;
    color: rgb(245 178 39 / 0.85);
    font-size: min(0.765rem, 23px);
    text-decoration: underline;
    text-underline-offset: 3px;
  }
  @media (prefers-reduced-motion: reduce) {
    .dock,
    .brand {
      animation: none;
      transition: none;
    }
  }
</style>

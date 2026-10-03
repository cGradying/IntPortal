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
  import { api, isoDate, type CampusResolution, type Login } from "./api";
  import { buzz } from "./haptics";
  import { landingAt, restAt } from "./landing";
  import { adopt, app, syncNow } from "./state.svelte";

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
  // The card needs room, so the portal sits higher above it.
  let lift = $state(returning ? 0.08 : 0.2);

  let campus = $state<CampusResolution>({ kind: "incomplete" });
  $effect(() => {
    const n = studno;
    api.campus(n).then((r) => (campus = r)).catch(() => {});
  });
  const campusOk = $derived(campus.kind !== "incomplete");

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
        : "Hi, I'm LAR. Sign in with your SIS login and I'll bring everything over.",
  );

  onMount(() => {
    let raf = 0;
    const start = performance.now();
    let placed = moment.placed;
    let lit = false;
    const frame = (now: number) => {
      t = (now - start) / 1000;
      const target = rest === "hub" ? 0.08 : 0.2;
      lift += (target - lift) * 0.08;
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
    error = "";
    if (!campusOk) return (error = "Student number looks like 2026-00000-MN-0.");
    const [y, m, d] = birthday.split("-").map(Number);
    if (!y) return (error = "Add your birthdate.");
    if (!password) return (error = "Add your password.");
    busy = true;
    try {
      const login: Login = { student_number: studno.trim().toUpperCase(), birth_month: m, birth_day: d, birth_year: y, password };
      await adopt(await api.signIn(login));
      password = "";
      rest = "hub";
      buzz.done();
    } catch (err) {
      error = String(err);
      buzz.fail();
    } finally {
      busy = false;
    }
  }

  async function demo() {
    error = "";
    try {
      await adopt(await api.demo(isoDate(new Date())));
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
  <PortalStage {moment} {t} {lift} {mood} {gesture} still={typing} />

  <header class="brand" class:on={resting}>
    <h1>Student <span>IntPortal</span></h1>
  </header>

  {#if resting}
    <div class="dock" class:hub={rest === "hub"}>
      <p class="say" aria-live="polite"><b>LAR</b> {line}</p>
      {#if rest === "hub"}
        <button class="step" onclick={step}>Step through</button>
        <p class="hint">PUP SIS · via {(app.snapshot?.host ?? "sis8").split(".")[0]}</p>
      {:else}
        <form class="card" onsubmit={submit} onfocusin={() => (typing = true)} onfocusout={() => (typing = false)}>
          <label>
            <span>Student number</span>
            <input bind:value={studno} placeholder="2026-00000-MN-0" autocapitalize="characters" autocomplete="username" inputmode="text" spellcheck="false" />
            {#if campus.kind === "known"}<small class="campus">{campus.campus.name} · campus found</small>
            {:else if campus.kind === "unknown_code"}<small class="campus dim">{campus.code} · campus not confirmed yet, sign-in still works</small>{/if}
          </label>
          <div class="pair">
            <label>
              <span>Birthdate</span>
              <input type="date" bind:value={birthday} />
            </label>
            <label>
              <span>Password</span>
              <input type="password" bind:value={password} autocomplete="current-password" />
            </label>
          </div>
          <button class="go" disabled={busy}>{busy ? "Signing in…" : "Sign in"}</button>
          {#if error}<p class="error" role="alert">{error}</p>{/if}
          <p class="fine">Your login stays in this phone's keychain. IntPortal only talks to PUP SIS.</p>
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
    font-size: min(1.294rem, 29px);
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
    box-shadow:
      inset 0 0 0 1px rgb(245 178 39 / 0.16),
      0 -12px 40px rgb(0 0 0 / 0.5);
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
  }
  input::placeholder {
    color: rgb(255 255 255 / 0.32);
  }
  input:focus {
    box-shadow: inset 0 0 0 2px #f5b227;
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

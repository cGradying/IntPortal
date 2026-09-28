<script lang="ts">
  import { untrack } from "svelte";
  import Portal from "./Portal.svelte";
  import { api, isoDate, type CampusResolution, type Login } from "./api";
  import { adopt, app, syncNow } from "./state.svelte";

  let { signedIn, onenter }: { signedIn: boolean; onenter: () => void } = $props();

  // The portal opens where launch found it; sign-in moves it to the hub.
  let rest = $state<"signin" | "hub">(untrack(() => signedIn) ? "hub" : "signin");
  let warp = $state<() => void>();
  let busy = $state(false);
  let error = $state("");
  let studno = $state("");
  let birthday = $state("");
  let password = $state("");

  let campus = $state<CampusResolution>({ kind: "incomplete" });
  $effect(() => {
    const n = studno;
    api.campus(n).then((r) => (campus = r)).catch(() => {});
  });
  const campusOk = $derived(campus.kind !== "incomplete");

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
    } catch (e) {
      error = String(e);
    } finally {
      busy = false;
    }
  }

  async function demo() {
    error = "";
    try {
      await adopt(await api.demo(isoDate(new Date())));
      rest = "hub";
    } catch (e) {
      error = String(e);
    }
  }

  function step() {
    warp?.();
  }

  function entered() {
    if (signedIn) syncNow();
    onenter();
  }
</script>

<section class="landing">
  <Portal {rest} {busy} bind:warp onwarped={entered} />

  <header class="brand">
    <h1>Student <span>IntPortal</span></h1>
    <p>PUP SIS, in your pocket</p>
  </header>

  {#if rest === "hub"}
    <div class="hub">
      <button class="step" onclick={step}>Step through</button>
      <p class="hint">PUP SIS · via {(app.snapshot?.host ?? "sis8").split(".")[0]}</p>
    </div>
  {:else}
    <form class="sheet notch" onsubmit={submit}>
      <label>
        <span class="label">Student number</span>
        <input bind:value={studno} placeholder="2026-00000-MN-0" autocapitalize="characters" autocomplete="username" inputmode="text" spellcheck="false" />
        {#if campus.kind === "known"}<small class="campus">{campus.campus.name} · campus found</small>
        {:else if campus.kind === "unknown_code"}<small class="campus dim">{campus.code} · campus not confirmed yet, sign-in still works</small>{/if}
      </label>
      <label>
        <span class="label">Birthdate</span>
        <input type="date" bind:value={birthday} />
      </label>
      <label>
        <span class="label">Password</span>
        <input type="password" bind:value={password} autocomplete="current-password" />
      </label>
      <button class="go" disabled={busy}>{busy ? "Signing in…" : "Login now"}</button>
      {#if error}<p class="error" role="alert">{error}</p>{/if}
      <p class="fine">Locked in your phone's keychain. This portal only ever talks to PUP SIS.</p>
      {#if __REVIEW__}
        <button type="button" class="demo" onclick={demo}>Look around with demo data</button>
      {/if}
    </form>
  {/if}
</section>

<style>
  .landing {
    position: fixed;
    inset: 0;
    z-index: 50;
    color: #f4ecd8;
  }
  .brand {
    position: absolute;
    top: calc(var(--safe-top) + 36px);
    left: 0;
    right: 0;
    text-align: center;
    pointer-events: none;
  }
  h1 {
    margin: 0;
    font-family: var(--font-display);
    font-size: 30px;
    font-weight: 700;
    letter-spacing: -0.01em;
    color: #f5b227;
  }
  h1 span {
    color: #fff5dc;
  }
  .brand p {
    margin: 6px 0 0;
    font-size: 14px;
    color: rgba(244, 236, 216, 0.55);
  }
  .hub {
    position: absolute;
    left: 0;
    right: 0;
    bottom: calc(var(--safe-bottom) + 56px);
    display: grid;
    justify-items: center;
    gap: 12px;
  }
  .step {
    min-width: 200px;
    min-height: 52px;
    border: 0;
    background: #f5b227;
    color: #1b1406;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 17px;
    clip-path: polygon(0 6px, 3px 6px, 3px 3px, 6px 3px, 6px 0, calc(100% - 6px) 0, calc(100% - 6px) 3px, calc(100% - 3px) 3px, calc(100% - 3px) 6px, 100% 6px, 100% calc(100% - 6px), calc(100% - 3px) calc(100% - 6px), calc(100% - 3px) calc(100% - 3px), calc(100% - 6px) calc(100% - 3px), calc(100% - 6px) 100%, 6px 100%, 6px calc(100% - 3px), 3px calc(100% - 3px), 3px calc(100% - 6px), 0 calc(100% - 6px));
    animation: breathe 2.4s var(--ease) infinite;
  }
  @keyframes breathe {
    50% { filter: brightness(1.12); transform: translateY(-1px); }
  }
  .hint {
    margin: 0;
    font-family: var(--font-pixel);
    font-size: 13px;
    letter-spacing: 0.08em;
    color: rgba(244, 236, 216, 0.5);
  }
  .sheet {
    --step: 4px;
    position: absolute;
    left: var(--gutter);
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 16px);
    display: grid;
    gap: 12px;
    padding: 20px 18px 16px;
    background: rgba(22, 14, 20, 0.92);
    box-shadow: inset 0 0 0 1px rgba(245, 178, 39, 0.18);
    backdrop-filter: blur(10px);
    animation: rise 0.6s var(--ease) both;
  }
  @keyframes rise {
    from { transform: translateY(24px); opacity: 0; }
  }
  label {
    display: grid;
    gap: 6px;
  }
  .label {
    color: rgba(244, 236, 216, 0.55);
  }
  input {
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: 8px;
    background: rgba(255, 255, 255, 0.06);
    box-shadow: inset 0 0 0 1px rgba(255, 255, 255, 0.08);
    color: #fff;
    font: 16px var(--font-body);
    outline: none;
  }
  input::placeholder {
    color: rgba(255, 255, 255, 0.28);
  }
  input:focus {
    box-shadow: inset 0 0 0 1.5px #f5b227;
  }
  .campus.dim {
    color: rgba(244, 236, 216, 0.55);
  }
  .campus {
    font-family: var(--font-pixel);
    font-size: 12px;
    color: #f5b227;
  }
  .go {
    height: 48px;
    margin-top: 4px;
    border: 0;
    border-radius: 10px;
    background: #f5b227;
    color: #1b1406;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 16px;
  }
  .go:disabled {
    opacity: 0.7;
  }
  .error {
    margin: 0;
    font-size: 14px;
    color: #f0a090;
  }
  .fine {
    margin: 0;
    font-size: 12px;
    text-align: center;
    color: rgba(244, 236, 216, 0.45);
  }
  .demo {
    border: 0;
    background: none;
    color: rgba(245, 178, 39, 0.8);
    font-size: 13px;
    text-decoration: underline;
    text-underline-offset: 3px;
  }
</style>

<script lang="ts">
  import { FALLBACK, friendly } from "./errors";
  // Connect one portal from inside the app: the fields it asks for, its tries
  // line, its own words. Same rules as the landing card, in the app's look.
  import { onMount } from "svelte";
  import { api, type Portal, type Tries } from "./api";
  import { refreshLogins } from "./state.svelte";
  import { buzz } from "./haptics";
  import { portalApiFor } from "./portalApi";
  import { REJECTED, portalCopy, triesLine, validate } from "./portals";

  // `prefill`: start from the saved student number, to fix a rejected login (spec 040 C5).
  let { portal, prefill = false }: { portal: Portal; prefill?: boolean } = $props();

  let studno = $state("");
  let birthday = $state("");
  let password = $state("");
  let busy = $state(false);
  let error = $state("");
  let tries = $state<Tries | null>(null);
  const copy = $derived(portalCopy(portal.id));
  const triesText = $derived(tries ? triesLine(tries, portal, Date.now() / 1000) : "");
  const locked = $derived(!!tries && tries.left <= 0);

  const refreshTries = () => portalApiFor(portal.id).tries().then((t) => (tries = t)).catch(() => {});
  onMount(() => {
    refreshTries();
    if (prefill) api.loginHint(portal.id).then((n) => (studno ||= n ?? "")).catch(() => {});
  });

  async function submit(e: Event) {
    e.preventDefault();
    error = validate(portal, { student_number: studno, birthdate: birthday, password });
    if (error) return;
    busy = true;
    try {
      await portalApiFor(portal.id).signIn({ student_number: studno, birthdate: birthday, password });
      password = "";
      buzz.done();
      refreshLogins();
    } catch (err) {
      // A rejection in the portal's own words gets ours.
      const said = friendly(err);
      error = said === FALLBACK ? (portal.fields.includes("birthdate") ? REJECTED : REJECTED.replace(", birthdate and", " and")) : said;
      buzz.fail();
    } finally {
      busy = false;
      refreshTries();
    }
  }
</script>

<form onsubmit={submit} style:--portal-accent={portal.theme.accent}>
  <label>
    <span class="label">Student number</span>
    <input bind:value={studno} placeholder="2026-00000-MN-0" autocapitalize="characters" autocomplete="username" spellcheck="false" />
  </label>
  {#if portal.fields.includes("birthdate")}
    <label>
      <span class="label">Birthdate</span>
      <input type="date" bind:value={birthday} />
    </label>
  {/if}
  <label>
    <span class="label">Password</span>
    <input type="password" bind:value={password} autocomplete="current-password" />
  </label>
  <button class="primary" disabled={busy || locked}>{busy ? "Signing in…" : `Sign in to ${portal.name}`}</button>
  {#if triesText}<p class="fine tries" aria-live="polite">{triesText}</p>{/if}
  {#if error}<p class="fine bad" role="alert">{error}</p>{/if}
  <p class="fine">{copy.keychainNote}</p>
</form>

<style>
  form {
    display: grid;
    gap: 10px;
  }
  label {
    display: grid;
    gap: 5px;
  }
  input {
    height: 44px;
    padding: 0 12px;
    border: 0;
    border-radius: 10px;
    background: var(--sunk);
    box-shadow: inset 0 0 0 1px var(--edge);
    color: var(--ink);
    font: inherit;
    font-size: max(16px, var(--text-body));
  }
  input:focus {
    outline: none;
    box-shadow: inset 0 0 0 2px var(--portal-accent, var(--gold));
  }
  .primary {
    height: 44px;
    border: 0;
    border-radius: 10px;
    background: var(--gold);
    color: var(--on-gold);
    font-family: var(--font-display);
    font-weight: 700;
    font-size: min(0.824rem, 25px);
  }
  .primary:disabled {
    opacity: 0.7;
  }
  .fine {
    margin: 0;
    font-size: min(0.824rem, 25px);
    color: var(--ink-2);
  }
  .tries {
    color: var(--portal-accent, var(--gold));
  }
  .bad {
    color: var(--bad);
  }
</style>

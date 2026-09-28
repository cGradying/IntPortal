<script lang="ts">
  import Jeepney from "./Jeepney.svelte";
  import { app, syncNow } from "./state.svelte";

  let open = $state(false);
  let arrived = $state(false);
  // A finished sync parks the jeepney for a beat before the glance returns.
  let seen = app.syncCount;
  $effect(() => {
    if (app.syncCount === seen) return;
    seen = app.syncCount;
    arrived = true;
    const t = setTimeout(() => (arrived = false), 2400);
    return () => clearTimeout(t);
  });
  const trip = $derived(app.sync === "syncing" ? "drive" : arrived ? "arrived" : app.sync === "failed" ? "stalled" : null);
  const kind = $derived(app.sync === "syncing" ? "syncing" : (app.today?.glance.kind ?? "day_done"));
  const line = $derived(app.today?.glance_line ?? "IntPortal");

  function ago(secs: string | null | undefined): string {
    if (!secs) return "never";
    const m = Math.round((Date.now() / 1000 - Number(secs)) / 60);
    return m < 1 ? "just now" : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`;
  }
</script>

<div class="wrap">
  <button class="island" class:open data-kind={kind} onclick={() => (open = !open)} aria-expanded={open}>
    <span class="row">
      {#if trip}
        <Jeepney mode={trip} />
      {:else}
      <svg class="glyph" viewBox="0 0 7 9" shape-rendering="crispEdges" aria-hidden="true">
        <path d="M0 0h7v9H0z" fill="#34203f" />
        <path d="M1 1h5v7H1z" fill="#170b1a" />
        <path class="swirl a" d="M2 2h3v1H2zM1 4h2v1H1zM4 5h2v1H4zM2 6h3v1H2z" />
        <path class="swirl b" d="M3 3h2v1H3zM2 5h2v1H2zM4 2h1v2H4z" />
      </svg>
      {/if}
      <span class="line" aria-live="polite">{kind === "syncing" ? "On the way to SIS…" : trip === "arrived" ? "Synced · everything's fresh" : line}</span>
      {#if kind === "in_session"}<span class="live" aria-hidden="true"></span>{/if}
    </span>
    {#if open}
      <span class="more">
        <span>Synced {ago(app.snapshot?.last_synced)} · {app.snapshot?.host ?? "sis"}</span>
        <span
          class="sync"
          role="button"
          tabindex="0"
          onclick={(e) => {
            e.stopPropagation();
            syncNow();
          }}
          onkeydown={(e) => e.key === "Enter" && syncNow()}>Sync now</span
        >
      </span>
    {/if}
  </button>
</div>

<style>
  .wrap {
    position: fixed;
    top: calc(var(--safe-top) + 6px);
    left: 0;
    right: 0;
    z-index: 30;
    display: flex;
    justify-content: center;
    pointer-events: none;
  }
  .island {
    pointer-events: auto;
    max-width: calc(100% - 2 * var(--gutter));
    min-height: 38px;
    padding: 8px 16px 8px 12px;
    border: 0;
    border-radius: 19px;
    background: var(--island);
    color: #f1f1f3;
    box-shadow: 0 8px 24px rgba(0, 0, 0, 0.35), inset 0 0 0 1px rgba(255, 255, 255, 0.06);
    transition: border-radius 0.35s var(--ease), padding 0.35s var(--ease);
  }
  .island.open {
    border-radius: 20px;
    padding-bottom: 12px;
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  .glyph {
    width: 14px;
    height: 18px;
    flex: none;
  }
  .swirl.a {
    fill: #941c30;
  }
  .swirl.b {
    fill: #cca128;
  }
  [data-kind="syncing"] .swirl,
  [data-kind="in_session"] .swirl {
    animation: churn 0.5s steps(2) infinite;
  }
  .swirl.b {
    animation-delay: 0.25s;
  }
  @keyframes churn {
    50% { fill: #faebb3; }
  }
  [data-kind="sync_trouble"] .swirl {
    fill: #3a2a33;
  }
  .line {
    font-family: var(--font-display);
    font-size: 14px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  [data-kind="sync_trouble"] .line {
    color: #f0a090;
  }
  .live {
    width: 8px;
    height: 8px;
    flex: none;
    background: #f5b227;
    animation: blink 1.6s steps(1) infinite;
  }
  @keyframes blink {
    50% { opacity: 0.3; }
  }
  .more {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 14px;
    margin-top: 10px;
    padding-top: 10px;
    border-top: 1px solid rgba(255, 255, 255, 0.08);
    font-size: 13px;
    color: #a9a9b1;
    animation: fade 0.25s var(--ease) both;
  }
  @keyframes fade {
    from { opacity: 0; transform: translateY(-4px); }
  }
  .sync {
    padding: 6px 12px;
    border-radius: 12px;
    background: #f5b227;
    color: #1b1406;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 12px;
  }
</style>

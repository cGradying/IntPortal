<script lang="ts">
  // The glance. On a Dynamic Island iPhone it is a black capsule that wraps
  // the hardware island and grows a chin under the camera, the way the system
  // grows a Live Activity; a tap widens it. Elsewhere it is a dock above the
  // tab bar that grows up.
  import Jeepney from "./Jeepney.svelte";
  import { ago, glanceView, type GlanceView } from "./glance";
  import { app, syncNow } from "./state.svelte";

  let {
    mode,
    preview,
    startOpen = false,
  }: { mode: "island" | "dock"; preview?: GlanceView; startOpen?: boolean } = $props();

  // svelte-ignore state_referenced_locally
  let open = $state(startOpen);
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

  const view = $derived(
    preview ?? glanceView(app.today?.glance, app.today?.glance_line, app.sync === "syncing", arrived, app.sync === "failed"),
  );
</script>

<div class="wrap" data-mode={mode} class:preview>
  <button class="glance" class:open data-tone={view.tone} onclick={() => (open = !open)} aria-expanded={open} aria-label={view.line}>
    <span class="row">
      <span class="lead">
        {#if view.trip}
          <Jeepney mode={view.trip} />
        {:else}
          <svg class="glyph" class:churn={view.tone === "live"} viewBox="0 0 7 9" shape-rendering="crispEdges" aria-hidden="true">
            <path d="M0 0h7v9H0z" fill="#34203f" />
            <path d="M1 1h5v7H1z" fill="#170b1a" />
            <path class="swirl a" d="M2 2h3v1H2zM1 4h2v1H1zM4 5h2v1H4zM2 6h3v1H2z" />
            <path class="swirl b" d="M3 3h2v1H3zM2 5h2v1H2zM4 2h1v2H4z" />
          </svg>
        {/if}
      </span>
      <span class="line" aria-live="polite">{mode === "dock" ? view.line : view.label}</span>
      <span class="trail">
        {#if view.tone === "live"}<span class="live" aria-hidden="true"></span>{/if}
        {view.short}
      </span>
    </span>
    {#if open}
      <span class="more">
        {#if mode === "island"}<span class="big" aria-live="polite">{view.line}</span>{/if}
        <span class="meta">
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
      </span>
    {/if}
  </button>
</div>

<style>
  .wrap {
    position: fixed;
    left: 0;
    right: 0;
    z-index: 30;
    display: flex;
    justify-content: center;
    pointer-events: none;
  }
  .wrap.preview {
    position: relative;
    top: auto;
    bottom: auto;
    z-index: auto;
  }
  .wrap.preview .glance.open {
    width: 100%;
  }
  /* Hardware islands differ: about 126 x 37 pt at 11 pt down on the 14 to 17
     Pro, 94 x 36 at 14 pt down on the 18 Pro. The capsule covers the largest
     (126 wide, 10 to 50 pt) and stays narrower than the gap between the clock
     and the signal icons, so content goes in a chin below the camera. */
  [data-mode="island"] {
    top: 10px;
  }
  [data-mode="dock"] {
    bottom: calc(var(--safe-bottom) + 76px);
    padding: 0 var(--gutter);
  }
  .glance {
    pointer-events: auto;
    border: 0;
    color: #f1f1f3;
    text-align: left;
  }
  [data-mode="island"] .glance {
    width: 146px;
    padding: 40px 11px 8px;
    border-radius: 22px;
    background: #000;
    transition:
      width 0.5s cubic-bezier(0.3, 1.35, 0.4, 1),
      border-radius 0.5s var(--ease),
      padding 0.5s var(--ease);
  }
  [data-mode="island"] .glance.open {
    width: calc(100vw - 16px);
    max-width: 420px;
    padding: 44px 20px 16px;
    border-radius: 36px;
  }
  [data-mode="dock"] .glance {
    width: 100%;
    max-width: 480px;
    min-height: 48px;
    padding: 8px 14px 8px 12px;
    border-radius: 24px;
    background: var(--island);
    box-shadow:
      0 10px 28px rgba(0, 0, 0, 0.35),
      inset 0 0 0 1px rgba(255, 255, 255, 0.07);
  }
  .row {
    display: flex;
    align-items: center;
    gap: 10px;
  }
  [data-mode="island"] .row {
    gap: 6px;
    height: 24px;
  }
  [data-mode="island"] .line,
  [data-mode="island"] .trail {
    font-size: 11px;
  }
  /* The churning glyph already says "in session" in the narrow chin. */
  [data-mode="island"] .live {
    display: none;
  }
  .lead {
    display: flex;
    align-items: center;
    flex: none;
  }
  [data-mode="island"] .lead :global(.lane) {
    width: 30px;
  }
  [data-mode="island"] .glyph {
    width: 11px;
    height: 14px;
  }
  .glyph {
    width: 14px;
    height: 18px;
  }
  .swirl.a {
    fill: #941c30;
  }
  .swirl.b {
    fill: #cca128;
  }
  .churn .swirl {
    animation: churn 0.5s steps(2) infinite;
  }
  .swirl.b {
    animation-delay: 0.25s;
  }
  @keyframes churn {
    50% { fill: #faebb3; }
  }
  [data-tone="trouble"] .swirl {
    fill: #3a2a33;
  }
  .line {
    flex: 1;
    min-width: 0;
    font-family: var(--font-display);
    font-size: 14px;
    font-weight: 600;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .open .line {
    white-space: normal;
  }
  .trail {
    display: flex;
    align-items: center;
    gap: 6px;
    flex: none;
    font-family: var(--font-display);
    font-size: 14px;
    font-weight: 700;
    font-variant-numeric: tabular-nums;
    color: #f5b227;
  }
  [data-tone="trouble"] .trail {
    color: #f0a090;
  }
  .live {
    width: 7px;
    height: 7px;
    background: #f5b227;
    animation: blink 1.6s steps(1) infinite;
  }
  @keyframes blink {
    50% { opacity: 0.3; }
  }
  .more {
    display: grid;
    gap: 12px;
    margin-top: 10px;
    animation: fade 0.3s var(--ease) 0.08s backwards;
  }
  [data-mode="dock"] .more {
    padding-top: 10px;
    border-top: 1px solid rgba(255, 255, 255, 0.08);
  }
  @keyframes fade {
    from { opacity: 0; transform: translateY(-4px); }
  }
  .big {
    font-family: var(--font-display);
    font-size: 17px;
    font-weight: 700;
    line-height: 1.3;
  }
  .meta {
    display: flex;
    justify-content: space-between;
    align-items: center;
    gap: 14px;
    font-size: 13px;
    color: #a9a9b1;
  }
  .sync {
    flex: none;
    padding: 7px 14px;
    border-radius: 14px;
    background: #f5b227;
    color: #1b1406;
    font-family: var(--font-display);
    font-weight: 700;
    font-size: 12px;
  }
  @media (prefers-reduced-motion: reduce) {
    .glance,
    .more {
      transition: none;
      animation: none;
    }
  }
</style>

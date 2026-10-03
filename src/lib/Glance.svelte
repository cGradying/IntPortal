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
      <!-- Beside the camera there's room for the countdown or the glyph, not both. -->
      {#if view.trip || !(mode === "island" && view.short)}<span class="lead">
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
      </span>{/if}
      <span class="line" aria-live="polite">{mode === "dock" ? view.line : view.label}</span>
      <span class="trail">
        {#if view.tone === "live"}<span class="live" aria-hidden="true"></span>{/if}
        {mode === "island" ? view.short.replace(/(\d:\d\d)[AP]M$/, "$1") : view.short}
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
  /* One band, the height of the hardware island (126 x 37 pt at 11 pt down
     on the 14 to 17 Pro, 94 x 36 at 14 pt down on the 18 Pro), like the
     system's compact Live Activity. The signal icons sit under 30 pt right
     of the island but the clock leaves 35 to 52 pt on its left, so the
     glyph and countdown go left of the camera and the capsule only rounds
     off on the right. */
  [data-mode="island"] {
    --lead: clamp(34px, 50vw - 172px, 48px);
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
    position: relative;
    width: calc(126px + 6px + var(--lead));
    /* Keeps the camera hole centred: the wrap centres the margin box. */
    margin-right: calc(var(--lead) - 6px);
    padding: 0 0 0 8px;
    border-radius: 20px;
    background: #000;
    transition:
      width 0.5s cubic-bezier(0.3, 1.35, 0.4, 1),
      border-radius 0.5s var(--ease),
      padding 0.5s var(--ease);
  }
  /* iOS keeps taps in the status bar for scroll-to-top, and the band sits
     inside it, so an invisible strip under the band takes the tap. */
  [data-mode="island"] .glance:not(.open)::after {
    content: "";
    position: absolute;
    top: 100%;
    left: 0;
    right: 0;
    height: 28px;
  }
  [data-mode="island"] .glance.open {
    width: calc(100vw - 16px);
    max-width: 420px;
    margin-right: 0;
    padding: 50px 20px 16px;
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
    gap: 5px;
    height: 40px;
  }
  /* Open, the status bar sits across the top; the content starts below it. */
  [data-mode="island"] .open .row {
    display: none;
  }
  [data-mode="island"] .open .more {
    margin-top: 0;
  }
  /* The words don't fit beside the camera; the open island has them. */
  [data-mode="island"] .line {
    display: none;
  }
  [data-mode="island"] .trail {
    gap: 4px;
    font-size: 12px;
  }
  /* 402 pt phones leave about 35 pt left of the camera. */
  @media (max-width: 429px) {
    [data-mode="island"] .glance:not(.open) {
      padding-left: 6px;
    }
    [data-mode="island"] .glance:not(.open) .trail {
      font-size: 11px;
      letter-spacing: -0.02em;
    }
  }
  .lead {
    display: flex;
    align-items: center;
    flex: none;
  }
  [data-mode="island"] .lead :global(.lane) {
    width: min(30px, calc(var(--lead) - 14px));
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

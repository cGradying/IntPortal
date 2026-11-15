<script lang="ts">
  import MiniPortal from "../MiniPortal.svelte";
  import { TOUR, type Act, type StopId } from "./tour";

  let { room, onact }: { room: string; onact: (act: Act, from: DOMRect) => void } = $props();

  const uid = $props.id();
  const GAP = 20;
  const SCHOOL = { theme: { ramp: ["#170509", "#540a1c", "#941c30", "#cca128", "#faebb3"], accent: "#e8b04a" } };

  let open = $state<StopId>("inside");
  let widths = $state<number[]>(TOUR.map(() => 0));
  let tabs = $state<HTMLButtonElement[]>([]);

  const at = $derived(TOUR.findIndex((s) => s.id === open));
  // Reading every width re-measures when any tab resizes (a font loading late); offsetLeft keeps the bar on the pixel grid.
  const left = $derived(widths.reduce((a, w) => a + w, 0) && tabs[at] ? tabs[at].offsetLeft : 0);

  function key(e: KeyboardEvent) {
    const step = e.key === "ArrowRight" ? 1 : e.key === "ArrowLeft" ? -1 : 0;
    if (!step) return;
    e.preventDefault();
    const next = (at + step + TOUR.length) % TOUR.length;
    open = TOUR[next].id;
    tabs[next].focus();
  }
</script>

<div class="tour">
  <div class="tabs" role="tablist" tabindex="-1" style:gap="{GAP}px" onkeydown={key}>
    {#each TOUR as stop, i (stop.id)}
      <button
        type="button"
        class="tab"
        role="tab"
        id="{uid}-tab-{stop.id}"
        aria-selected={stop.id === open}
        aria-controls="{uid}-panel-{stop.id}"
        tabindex={stop.id === open ? 0 : -1}
        bind:this={tabs[i]}
        bind:offsetWidth={widths[i]}
        onclick={() => (open = stop.id)}>{stop.tab}</button
      >
    {/each}
    <span class="bar" aria-hidden="true" style:transform="translateX({left}px) scaleX({widths[at]})"></span>
  </div>

  <!-- Every stop is laid out in the same cell, so the tallest one sets the height and switching never moves the page. -->
  <div class="panels">
    {#each TOUR as stop (stop.id)}
      <div class="panel" class:on={stop.id === open} role="tabpanel" id="{uid}-panel-{stop.id}" aria-labelledby="{uid}-tab-{stop.id}">
        <p class="lead">{stop.lead}</p>
        <div class="items">
          {#each stop.items as item (item.id)}
            {@const act = item.act}
            <button
              type="button"
              class="chip"
              class:worn={act.kind === "room" && act.room === room}
              aria-pressed={act.kind === "room" ? act.room === room : undefined}
              onclick={(e) => onact(act, e.currentTarget.getBoundingClientRect())}
            >
              {#if act.kind === "peek"}
                <svg class="eye" viewBox="0 0 7 5" aria-hidden="true" shape-rendering="crispEdges"
                  ><path fill="currentColor" d="M2 0h3v1H2zM1 1h1v1H1zM5 1h1v1H5zM0 2h1v1H0zM3 2h1v1H3zM6 2h1v1H6zM1 3h1v1H1zM5 3h1v1H5zM2 4h3v1H2z" /></svg
                >
              {:else if act.kind === "say"}
                <span class="lit" aria-hidden="true"></span>
              {:else if act.kind === "room" && item.swatch}
                <svg class="tones" viewBox="0 0 24 14" aria-hidden="true" shape-rendering="crispEdges">
                  {#each item.swatch as c, j (j)}<rect x={j * 8} width="8" height="14" fill={c} />{/each}
                </svg>
              {:else if act.kind === "school"}
                <span class="glyph"><MiniPortal portal={SCHOOL} /></span>
              {/if}
              {item.label}
            </button>
          {/each}
        </div>
      </div>
    {/each}
  </div>
</div>

<style>
  .tour {
    display: grid;
    gap: 8px;
    min-width: 0;
  }
  .tabs {
    position: relative;
    display: flex;
    outline: none;
  }
  .tab {
    min-height: 44px;
    padding: 0;
    border: 0;
    background: none;
    font: 600 var(--text-sub) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
    white-space: nowrap;
  }
  .tab[aria-selected="true"] {
    color: var(--cream);
  }
  .tab:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }
  .bar {
    position: absolute;
    left: 0;
    bottom: 6px;
    width: 1px;
    height: 2px;
    background: var(--portal-gold);
    transform-origin: left;
    transition: transform var(--t-move) var(--ease);
  }
  .panels {
    display: grid;
  }
  .panel {
    grid-area: 1 / 1;
    display: grid;
    align-content: start;
    gap: 10px;
    visibility: hidden;
  }
  .panel.on {
    visibility: visible;
    animation: rise var(--t-move) var(--ease);
  }
  .lead {
    margin: 0;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  /* One row per stop, scrolled sideways, so the portal above keeps its room; the far edge fades
     to say there is more. */
  .items {
    display: flex;
    gap: 8px;
    overflow-x: auto;
    overscroll-behavior-x: contain;
    scroll-snap-type: x proximity;
    scrollbar-width: none;
    padding: 2px;
    margin: -2px;
    mask-image: linear-gradient(to right, #000 calc(100% - 28px), transparent);
  }
  .items::-webkit-scrollbar {
    display: none;
  }
  .chip {
    flex: none;
    scroll-snap-align: start;
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
  }
  .chip:active {
    background: rgb(244 236 216 / 0.12);
  }
  .chip:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }
  .chip.worn {
    box-shadow: inset 0 0 0 1.5px var(--portal-gold);
  }
  .eye {
    width: 14px;
    height: 10px;
    color: var(--portal-gold);
  }
  .lit {
    width: 6px;
    height: 6px;
    background: var(--portal-gold);
  }
  .tones {
    display: block;
    width: 24px;
    height: 14px;
    box-shadow: 0 0 0 1px rgb(244 236 216 / 0.25);
  }
  .glyph {
    width: 10px;
    height: 14px;
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(4px);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .bar {
      transition: none;
    }
    .panel.on {
      animation: none;
    }
  }
</style>

<script lang="ts">
  // The Offline demo (spec 049 C8): a No signal switch. The bars drop out one by one, and
  // Schedule, Grades and Notes stay lit.
  import { buzz } from "../haptics";

  let { onreact }: { onreact?: () => void } = $props();

  let offline = $state(false);
  function toggle() {
    offline = !offline;
    buzz.select();
    if (offline) onreact?.();
  }
</script>

<div class="offline">
  <button type="button" class="signal" role="switch" aria-checked={offline} onclick={toggle}>
    <span class="bars" class:out={offline} aria-hidden="true"><i></i><i></i><i></i><i></i></span>
    <span>No signal</span>
    <span class="switch" aria-hidden="true"><i></i></span>
  </button>
  <ul aria-label={offline ? "Still open, from this phone" : "Up to date"}>
    {#each ["Schedule", "Grades", "Notes"] as w (w)}
      <li><i class="tick" aria-hidden="true"></i>{w}</li>
    {/each}
  </ul>
  <p class="aside" aria-live="polite">{offline ? "Still open, from this phone." : "Up to date."}</p>
</div>

<style>
  .offline {
    display: grid;
    gap: 8px;
  }
  .signal {
    display: flex;
    align-items: center;
    gap: 12px;
    min-height: 52px;
    padding: 0 12px 0 14px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    color: var(--parch);
    font: 600 var(--text-body) var(--font-ui);
  }
  .signal:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }
  .bars {
    display: inline-flex;
    align-items: flex-end;
    gap: 2px;
    width: 18px;
    height: 14px;
  }
  .bars i {
    width: 3px;
    background: var(--cream);
    transition:
      translate var(--t-move) var(--ease),
      opacity var(--t-move) var(--ease);
  }
  .bars i:nth-child(1) {
    height: 4px;
  }
  .bars i:nth-child(2) {
    height: 7px;
    transition-delay: 40ms;
  }
  .bars i:nth-child(3) {
    height: 10px;
    transition-delay: 80ms;
  }
  .bars i:nth-child(4) {
    height: 14px;
    transition-delay: 120ms;
  }
  .bars.out i {
    translate: 0 8px;
    opacity: 0;
  }
  .bars.out i:nth-child(1) {
    opacity: 0.35;
    translate: 0;
  }
  .switch {
    position: relative;
    margin-left: auto;
    width: 44px;
    height: 26px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.16);
    transition: background-color var(--t-quick) var(--ease);
  }
  .switch i {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 20px;
    height: 20px;
    border-radius: var(--radius-sm);
    background: var(--cream);
    transition: translate var(--t-move) var(--ease-spring);
  }
  [aria-checked="true"] .switch {
    background: var(--cream);
  }
  [aria-checked="true"] .switch i {
    translate: 18px 0;
    background: var(--void);
  }
  ul {
    display: grid;
    grid-template-columns: repeat(3, minmax(0, 1fr));
    gap: 6px;
    margin: 0;
    padding: 0;
    list-style: none;
  }
  li {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 40px;
    padding: 0 10px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.04);
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--cream);
  }
  .tick {
    flex: none;
    width: 12px;
    height: 9px;
    background: var(--good);
    clip-path: polygon(0 50%, 25% 50%, 25% 75%, 37.5% 75%, 37.5% 50%, 62.5% 50%, 62.5% 25%, 75% 25%, 75% 0, 100% 0, 100% 25%, 87.5% 25%, 87.5% 50%, 75% 50%, 75% 75%, 62.5% 75%, 62.5% 100%, 25% 100%, 25% 75%, 0 75%);
  }
  .aside {
    margin: 0;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
</style>

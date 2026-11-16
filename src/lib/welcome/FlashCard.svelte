<script lang="ts">
  // The Study demo (spec 049 C8): a card that flips on a tap, and three ratings that say when it
  // comes back (interval.ts).
  import { buzz } from "../haptics";
  import { dueIn } from "../interval";
  import { RATINGS } from "./intro";

  let { onreact }: { onreact?: () => void } = $props();

  let flipped = $state(false);
  let rated = $state<(typeof RATINGS)[number] | null>(null);
  function flip() {
    flipped = !flipped;
    rated = null;
    buzz.select();
  }
  function rate(r: (typeof RATINGS)[number]) {
    rated = r;
    buzz.tick();
    onreact?.();
  }
</script>

<div class="study">
  <button type="button" class="flash" class:flipped aria-pressed={flipped} aria-label={flipped ? "Answer: O(log n). Tap to turn back." : "Binary search runs in what time? Tap to see the answer."} onclick={flip}>
    <span class="face ask" aria-hidden="true">Binary search runs in…</span>
    <span class="face ans" aria-hidden="true">O(log n)</span>
  </button>
  <div class="rate" aria-live="polite">
    {#if rated}
      <p class="back-in">Comes back {dueIn(rated.secs)}.</p>
    {:else if flipped}
      {#each RATINGS as r (r.id)}<button type="button" class="rate-b" onclick={() => rate(r)}>{r.label}<small>{r.short}</small></button>{/each}
    {:else}
      <p class="aside">Tap the card to see the answer.</p>
    {/if}
  </div>
</div>

<style>
  .study {
    display: grid;
    gap: 8px;
  }
  .flash {
    position: relative;
    height: 64px;
    padding: 0;
    border: 0;
    background: none;
    perspective: 600px;
  }
  .flash:focus-visible,
  .rate-b:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }
  .face {
    position: absolute;
    inset: 0;
    display: grid;
    place-items: center;
    padding: 0 14px;
    border-radius: var(--radius);
    background: var(--void-lift);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.14);
    backface-visibility: hidden;
    -webkit-backface-visibility: hidden;
    transition: transform var(--t-flow) var(--ease);
  }
  .ask {
    font: 500 var(--text-body) var(--font-ui);
    color: rgb(244 236 216 / 0.88);
  }
  .ans {
    transform: rotateY(180deg);
    font: 700 var(--text-headline) var(--font-display);
    color: var(--cream);
  }
  .flipped .ask {
    transform: rotateY(-180deg);
  }
  .flipped .ans {
    transform: rotateY(0);
  }
  .rate {
    display: flex;
    align-items: center;
    gap: 8px;
    min-height: 44px;
  }
  .rate-b {
    flex: 1;
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: 6px;
    min-height: 44px;
    border: 0;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.06);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.16);
    color: var(--parch);
    font: 600 var(--text-sub) var(--font-ui);
    animation: in var(--t-move) var(--ease) backwards;
  }
  @keyframes in {
    from {
      opacity: 0;
      transform: translateY(6px);
    }
  }
  .rate-b small {
    font: 500 var(--text-label) var(--font-pixel);
    color: var(--portal-accent);
  }
  .back-in {
    margin: 0;
    font: 600 var(--text-sub) var(--font-ui);
    color: var(--cream);
  }
  .aside {
    margin: 0;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
</style>

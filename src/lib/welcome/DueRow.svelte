<script lang="ts">
  // The Deadlines demo (spec 049 C8): the app's own Done on one sample row. The box fills, the
  // title is struck, the DONE stamp lands; then the row folds away and All clear offers it back.
  import { fade, slide } from "svelte/transition";
  import { buzz } from "../haptics";
  import { CLASS } from "./intro";

  let { onreact }: { onreact?: () => void } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  let due = $state<"open" | "done" | "gone">("open");
  function tick() {
    if (due !== "open") return;
    due = "done";
    buzz.done();
    onreact?.();
    setTimeout(() => (due = "gone"), reduce ? 500 : 1300);
  }
  const fold = (node: Element) => (reduce ? fade(node, { duration: 160 }) : slide(node, { duration: 360 }));
</script>

<div class="slot">
  {#if due !== "gone"}
    <div class="due" class:done={due === "done"} out:fold>
      <button type="button" class="check" class:on={due === "done"} aria-label="Mark Lab report 3 done" onclick={tick}><i></i></button>
      <span class="what"><strong>Lab report 3</strong><small><b>Tomorrow</b>, {CLASS.code}</small></span>
      {#if due === "done"}<span class="stamp" aria-hidden="true">DONE</span>{/if}
    </div>
  {:else}
    <p class="clear" in:fade={{ duration: 200 }}>All clear. <button type="button" class="link" onclick={() => (due = "open")}>Put it back</button></p>
  {/if}
</div>

<style>
  /* The row's room stays when it folds, so the thread under it never jumps. */
  .slot {
    min-height: 58px;
  }
  .due {
    position: relative;
    display: grid;
    grid-template-columns: 44px minmax(0, 1fr);
    align-items: center;
    min-height: 58px;
    padding-right: 12px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.05);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
  }
  .check {
    display: grid;
    place-items: center;
    width: 44px;
    height: 44px;
    margin-left: 4px;
    padding: 0;
    border: 0;
    border-radius: var(--radius);
    background: none;
  }
  .check:focus-visible,
  .link:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: 2px;
  }
  .check i {
    display: grid;
    place-items: center;
    width: 20px;
    height: 20px;
    background: var(--void);
    box-shadow: inset 0 0 0 2px rgb(244 236 216 / 0.55);
    clip-path: polygon(0 2px, 2px 2px, 2px 0, calc(100% - 2px) 0, calc(100% - 2px) 2px, 100% 2px, 100% calc(100% - 2px), calc(100% - 2px) calc(100% - 2px), calc(100% - 2px) 100%, 2px 100%, 2px calc(100% - 2px), 0 calc(100% - 2px));
  }
  .check.on i {
    background: var(--portal-gold);
    box-shadow: inset 0 -2px 0 rgb(0 0 0 / 0.25);
    animation: fill var(--t-move) var(--ease-spring) backwards;
  }
  .check.on i::after {
    content: "";
    width: 12px;
    height: 9px;
    background: var(--on-portal-gold);
    clip-path: polygon(0 50%, 25% 50%, 25% 75%, 37.5% 75%, 37.5% 50%, 62.5% 50%, 62.5% 25%, 75% 25%, 75% 0, 100% 0, 100% 25%, 87.5% 25%, 87.5% 50%, 75% 50%, 75% 75%, 62.5% 75%, 62.5% 100%, 25% 100%, 25% 75%, 0 75%);
  }
  @keyframes fill {
    from {
      scale: 0.6;
    }
  }
  .what {
    display: grid;
    gap: 2px;
    min-width: 0;
    padding-left: 6px;
  }
  .what strong {
    position: relative;
    justify-self: start;
    font: 600 var(--text-body) var(--font-ui);
    color: var(--cream);
    transition: color var(--t-quick) var(--ease);
  }
  .what small {
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  .what small b {
    font-weight: 600;
    color: var(--portal-accent);
  }
  .due.done .what strong {
    color: rgb(244 236 216 / 0.55);
  }
  .due.done .what strong::after {
    content: "";
    position: absolute;
    left: -1px;
    right: -1px;
    top: 52%;
    height: 2px;
    background: rgb(244 236 216 / 0.55);
    transform-origin: left;
    animation: strike var(--t-quick) var(--ease) backwards;
    animation-delay: 160ms;
  }
  @keyframes strike {
    from {
      transform: scaleX(0);
    }
  }
  .stamp {
    position: absolute;
    right: 10px;
    top: 50%;
    translate: 0 -50%;
    rotate: -7deg;
    padding: 1px 6px;
    font: 700 var(--text-label) var(--font-pixel);
    letter-spacing: 0.08em;
    color: var(--good);
    background: var(--void-2);
    box-shadow: inset 0 0 0 2px var(--good);
    pointer-events: none;
    animation: thunk var(--t-flow) var(--ease) both;
    animation-delay: 160ms;
  }
  @keyframes thunk {
    0% {
      scale: 1.9;
      opacity: 0;
    }
    60% {
      scale: 0.97;
      opacity: 1;
    }
    100% {
      scale: 1;
      opacity: 1;
    }
  }
  .clear {
    display: flex;
    align-items: center;
    gap: 10px;
    min-height: 58px;
    margin: 0;
    font: 600 var(--text-sub) var(--font-ui);
    color: rgb(244 236 216 / 0.8);
  }
  .link {
    min-height: 44px;
    padding: 0 4px;
    border: 0;
    background: none;
    color: rgb(244 236 216 / 0.82);
    font: 400 var(--text-sub) var(--font-ui);
    text-decoration: underline;
    text-underline-offset: 3px;
  }
</style>

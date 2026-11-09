<script lang="ts">
  // Spec 010 C35: after the dive lands, the day says hello, slowly, then
  // Today rises under it. A tap skips the wait; it never cuts loading short.
  import { HELLO_CAP_MS, dateLine, greeting, helloTimes } from "./greeting";

  // `ready` is Today's data, not just Today mounted: the hello must not lift onto a skeleton.
  let { start, ready, ondone }: { start: boolean; ready: boolean; ondone: () => void } = $props();

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const now = new Date();
  const lines = [`${greeting(now)}.`, `Today is ${dateLine(now)}.`];
  const T = helloTimes(reduce);

  let shown = $state(false);
  let held = $state(false);
  let leaving = $state(false);
  // Past the cap, Today shows what is cached rather than the hello waiting on.
  let capped = $state(false);

  $effect(() => {
    if (!start) return;
    // One frame on the hidden state first, so the words have somewhere to rise from.
    requestAnimationFrame(() => requestAnimationFrame(() => (shown = true)));
    const id = setTimeout(() => (held = true), T.hold);
    const cap = setTimeout(() => (capped = true), HELLO_CAP_MS);
    return () => (clearTimeout(id), clearTimeout(cap));
  });

  $effect(() => {
    if (!held || !(ready || capped) || leaving) return;
    leaving = true;
    const root = document.documentElement;
    root.dataset.entering = "";
    setTimeout(ondone, T.out);
    setTimeout(() => delete root.dataset.entering, T.out + 900);
  });

  const skip = () => shown && (held = true);
  const delay = (line: number, word: number) => `${T.in[line] + (reduce ? 0 : word * 70)}ms`;
</script>

<div class="cover dots" class:shown class:leaving class:reduce onpointerdown={skip} role="presentation" style:--out="{T.out}ms">
  <div class="hello">
    {#each lines as line, li (li)}
      <p class={li === 0 ? "l1" : "l2"}>
        {#each line.split(" ") as word, wi (wi)}<span class="w" style:transition-delay={delay(li, wi)}>{word}</span>{" "}{/each}
      </p>
    {/each}
  </div>
</div>

<style>
  .cover {
    position: fixed;
    inset: 0;
    z-index: 75;
    display: grid;
    align-content: center;
    padding: 0 calc(var(--gutter) + 14px) 12vh;
    background: var(--ground);
    transition: opacity var(--out) var(--ease);
  }
  .cover.leaving {
    opacity: 0;
    pointer-events: none;
  }
  .hello {
    position: relative;
    display: grid;
    gap: 10px;
    transition: translate var(--out) var(--ease);
  }
  .leaving .hello {
    translate: 0 -22px;
  }
  p {
    margin: 0;
    text-wrap: balance;
  }
  .l1 {
    font-family: var(--font-display);
    font-size: min(2.2rem, 44px);
    line-height: 1.04;
    font-weight: var(--title-weight);
    letter-spacing: var(--title-track);
    color: var(--ink);
  }
  .l2 {
    font-size: min(1.15rem, 26px);
    line-height: 1.3;
    font-weight: 500;
    color: var(--ink-2);
  }
  .w {
    display: inline-block;
    opacity: 0;
    translate: 0 14px;
    filter: blur(6px);
    transition:
      opacity 0.65s var(--ease),
      translate 0.65s var(--ease),
      filter 0.65s var(--ease);
  }
  .shown .w {
    opacity: 1;
    translate: 0 0;
    filter: none;
  }
  .reduce .w {
    translate: 0 0;
    filter: none;
    transition: opacity 0.4s linear;
  }
  .reduce .hello {
    transition: none;
  }
</style>

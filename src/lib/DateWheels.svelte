<script lang="ts">
  // The birthdate as three wheels, month, day and year (spec 011 C1–C3), in a
  // sheet over the landing. Each wheel snaps row by row with one selection tick
  // per row; the day wheel only offers the days that month has.
  import { onMount, tick as settle } from "svelte";
  import { buzz } from "./haptics";
  import { birthYears, daysIn } from "./portals";

  let { value, ondone, onclose }: { value: string; ondone: (iso: string) => void; onclose: () => void } = $props();

  const ROW = 40;
  const MONTHS = Array.from({ length: 12 }, (_, i) => new Date(2000, i, 1).toLocaleDateString(undefined, { month: "long" }));
  const years = birthYears(new Date());
  // svelte-ignore state_referenced_locally
  const [y0, m0, d0] = value ? value.split("-").map(Number) : [years[6], 1, 1];
  let month = $state(m0);
  let day = $state(d0);
  let year = $state(years.includes(y0) ? y0 : years[6]);
  const days = $derived(daysIn(month, year));
  // A shorter month pulls the day back to its last.
  $effect(() => {
    if (day > days) day = days;
  });

  let mw: HTMLDivElement;
  let dw: HTMLDivElement;
  let yw: HTMLDivElement;

  /** A wheel's row from its scroll; each new row ticks once. */
  const at = (el: HTMLDivElement, n: number) => Math.max(0, Math.min(n - 1, Math.round(el.scrollTop / ROW)));
  function onMonth() {
    const m = at(mw, 12) + 1;
    if (m !== month) (month = m), buzz.select();
  }
  function onDay() {
    const d = at(dw, days) + 1;
    if (d !== day) (day = d), buzz.select();
  }
  function onYear() {
    const y = years[at(yw, years.length)];
    if (y !== year) (year = y), buzz.select();
  }

  onMount(async () => {
    await settle();
    mw.scrollTop = (month - 1) * ROW;
    dw.scrollTop = (day - 1) * ROW;
    yw.scrollTop = years.indexOf(year) * ROW;
    doneBtn.focus();
  });

  let doneBtn: HTMLButtonElement;
  /** Turn a wheel to row `i`; its scroll handler picks the value and ticks. */
  const go = (el: HTMLDivElement, i: number) => el.scrollTo({ top: i * ROW, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
  /** Arrow keys, Page keys, Home and End turn a wheel (and VoiceOver's increment and decrement, which send arrows). */
  function key(e: KeyboardEvent, el: HTMLDivElement, n: number, at: number) {
    const to = { ArrowUp: at - 1, ArrowDown: at + 1, PageUp: at - 5, PageDown: at + 5, Home: 0, End: n - 1 }[e.key];
    if (to === undefined) return;
    e.preventDefault();
    go(el, Math.max(0, Math.min(n - 1, to)));
  }
  const iso = $derived(`${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`);
</script>

<svelte:window onkeydown={(e) => e.key === "Escape" && onclose()} />
<button class="scrim" aria-label="Close" onclick={onclose}></button>
<div class="sheet" role="dialog" aria-modal="true" aria-label="Birthdate">
  <header>
    <b>Birthdate</b>
    <button class="done" bind:this={doneBtn} onclick={() => ondone(iso)}>Done</button>
  </header>
  <div class="wheels">
    <i class="band" aria-hidden="true"></i>
    <!-- Each wheel is a slider: swipe it, tap a row, or use the arrow keys; VoiceOver swipes up and down. -->
    <div class="wheel" bind:this={mw} onscroll={onMonth} role="slider" aria-label="Month" aria-valuemin={1} aria-valuemax={12} aria-valuenow={month} aria-valuetext={MONTHS[month - 1]} tabindex="0" onkeydown={(e) => key(e, mw, 12, month - 1)}>
      {#each MONTHS as m, i (m)}<div class="row" class:on={month === i + 1} aria-hidden="true" onclick={() => go(mw, i)}>{m}</div>{/each}
    </div>
    <div class="wheel narrow" bind:this={dw} onscroll={onDay} role="slider" aria-label="Day" aria-valuemin={1} aria-valuemax={days} aria-valuenow={day} tabindex="0" onkeydown={(e) => key(e, dw, days, day - 1)}>
      {#each Array.from({ length: days }, (_, i) => i + 1) as d (d)}<div class="row" class:on={day === d} aria-hidden="true" onclick={() => go(dw, d - 1)}>{d}</div>{/each}
    </div>
    <div class="wheel narrow" bind:this={yw} onscroll={onYear} role="slider" aria-label="Year" aria-valuemin={years.at(-1)} aria-valuemax={years[0]} aria-valuenow={year} tabindex="0" onkeydown={(e) => key(e, yw, years.length, years.indexOf(year))}>
      {#each years as y, i (y)}<div class="row" class:on={year === y} aria-hidden="true" onclick={() => go(yw, i)}>{y}</div>{/each}
    </div>
  </div>
</div>

<style>
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 60;
    border: 0;
    background: rgb(0 0 0 / 0.45);
  }
  .sheet {
    position: fixed;
    left: 0;
    right: 0;
    bottom: 0;
    z-index: 61;
    padding: 14px var(--gutter) calc(var(--safe-bottom) + 16px);
    background: var(--void-2);
    box-shadow: inset 0 1px 0 rgb(245 178 39 / 0.16);
    clip-path: polygon(0 8px, 8px 8px, 8px 0, calc(100% - 8px) 0, calc(100% - 8px) 8px, 100% 8px, 100% 100%, 0 100%);
    color: var(--parch);
    animation: rise 0.3s var(--ease) both;
  }
  @keyframes rise {
    from {
      translate: 0 40px;
      opacity: 0;
    }
  }
  header {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 8px;
  }
  header b {
    font: 700 min(1rem, 26px) var(--font-display);
  }
  .done {
    min-height: 44px;
    padding: 0 18px;
    border: 0;
    border-radius: 10px;
    background: var(--portal-gold);
    color: #2a1700;
    font: 600 max(16px, min(0.941rem, 29px)) var(--font-ui);
  }
  /* Five rows show; the middle one is the pick, under a gold band. */
  .wheels {
    position: relative;
    display: grid;
    grid-template-columns: 1.6fr 0.8fr 1fr;
    gap: 6px;
    height: 200px;
  }
  .band {
    position: absolute;
    left: 0;
    right: 0;
    top: 80px;
    height: 40px;
    border-radius: 10px;
    background: rgb(245 178 39 / 0.12);
    box-shadow: inset 0 0 0 1px rgb(245 178 39 / 0.35);
    pointer-events: none;
  }
  .wheel {
    height: 200px;
    overflow-y: scroll;
    scroll-snap-type: y mandatory;
    scrollbar-width: none;
    padding: 80px 0;
    mask-image: linear-gradient(transparent, #000 30%, #000 70%, transparent);
    outline: none;
    border-radius: 10px;
  }
  .wheel:focus-visible {
    box-shadow: inset 0 0 0 1.5px var(--portal-gold);
  }
  .wheel::-webkit-scrollbar {
    display: none;
  }
  .row {
    height: 40px;
    display: grid;
    place-items: center;
    scroll-snap-align: center;
    font: 400 max(17px, min(1rem, 30px)) var(--font-ui);
    color: rgb(244 236 216 / 0.55);
    font-variant-numeric: tabular-nums;
  }
  .row.on {
    color: var(--white);
    font-weight: 600;
  }
  @media (prefers-reduced-motion: reduce) {
    .sheet {
      animation: none;
    }
  }
</style>

<script lang="ts">
  // The Today demo (spec 049 C8): one sample class counting down, and a clock the student drags.
  // Crossing the class's start turns Up next into In session.
  import PixelNum from "../PixelNum.svelte";
  import { buzz } from "../haptics";
  import { CLASS, CLOCK, clock, countdown, todayAt } from "./intro";

  let { live = true, onreact }: { /** It is the step on screen: the clock ticks. */ live?: boolean; onreact?: () => void } = $props();

  let at = $state(CLOCK.start);
  const now = $derived(todayAt(at));
  const through = $derived(Math.max(0, Math.min(100, Math.round(((at - CLASS.start) / (CLASS.end - CLASS.start)) * 100))));
  const span = (s: number) => ((s - CLOCK.from) / (CLOCK.to - CLOCK.from)) * 100;

  $effect(() => {
    if (!live) return;
    const id = setInterval(() => !document.hidden && (at = Math.min(CLOCK.to, at + 1)), 1000);
    return () => clearInterval(id);
  });
  let last = todayAt(CLOCK.start).phase;
  $effect(() => {
    if (now.phase === last) return;
    last = now.phase;
    buzz.tick();
    onreact?.();
  });
</script>

<div class="clockcard">
  <div class="tv" data-phase={now.phase} aria-live="polite">
    {#key now.phase}<span class="lab">{now.label}</span>{/key}
    <span class="code">{CLASS.code}</span>
    <span class="sub">{CLASS.title}, {CLASS.room}</span>
    <span class="left">
      <small>{now.sub}</small>
      {#if now.phase !== "over"}<b><PixelNum text={countdown(now.left)} size={3} /></b>{/if}
    </span>
    <span class="bar" aria-hidden="true"><i style:transform="scaleX({through / 100})"></i></span>
  </div>
  <label class="clock" for="talk-clock"><span>Sample time</span><b>{clock(at)}</b></label>
  <input id="talk-clock" class="slider" type="range" min={CLOCK.from} max={CLOCK.to} step="60" value={at} aria-valuetext={clock(at)}
    style:--a="{span(CLASS.start)}%" style:--b="{span(CLASS.end)}%" oninput={(e) => (at = +e.currentTarget.value)} />
</div>

<style>
  .clockcard {
    display: grid;
    gap: 6px;
    padding: 12px 12px 4px;
    border-radius: var(--radius);
    background: rgb(244 236 216 / 0.05);
    box-shadow: inset 0 0 0 1px rgb(244 236 216 / 0.12);
  }
  .tv {
    display: grid;
    grid-template-columns: minmax(0, 1fr) auto;
    column-gap: 10px;
    row-gap: 2px;
    align-items: end;
  }
  .lab {
    grid-column: 1 / -1;
    justify-self: start;
    font: 500 var(--text-label) var(--font-pixel);
    letter-spacing: 0.06em;
    color: var(--portal-accent);
    transform-origin: 0 50%;
    animation: pop var(--t-move) var(--ease) backwards;
  }
  .tv[data-phase="now"] .lab {
    color: var(--portal-gold);
  }
  @keyframes pop {
    from {
      opacity: 0;
      scale: 0.7;
    }
  }
  .code {
    font: 700 var(--text-headline) var(--font-display);
    color: var(--cream);
  }
  .sub {
    grid-column: 1;
    font: 400 var(--text-caption) / 1.35 var(--font-ui);
    color: rgb(244 236 216 / 0.7);
  }
  .left {
    grid-column: 2;
    grid-row: 2 / 4;
    display: grid;
    justify-items: end;
    gap: 4px;
    color: var(--cream);
  }
  .left small {
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
    white-space: nowrap;
  }
  .bar {
    grid-column: 1 / -1;
    height: 4px;
    margin-top: 8px;
    background: rgb(244 236 216 / 0.12);
  }
  .bar i {
    display: block;
    height: 100%;
    background: var(--portal-accent);
    transform-origin: 0 50%;
    transition: transform var(--t-move) var(--ease);
  }
  .clock {
    display: flex;
    align-items: baseline;
    justify-content: space-between;
    margin-top: 8px;
    font: 400 var(--text-caption) var(--font-ui);
    color: rgb(244 236 216 / 0.6);
  }
  .clock b {
    font: 600 var(--text-sub) var(--font-ui);
    font-variant-numeric: tabular-nums;
    color: var(--cream);
  }
  /* A clock to drag, the class's own stretch lit on its track. */
  .slider {
    width: 100%;
    height: 44px;
    margin: -6px 0 0;
    padding: 0;
    background: transparent;
    -webkit-appearance: none;
    appearance: none;
    touch-action: none;
  }
  .slider:focus-visible {
    outline: 2px solid var(--portal-gold);
    outline-offset: -2px;
  }
  .slider::-webkit-slider-runnable-track {
    height: 6px;
    background: linear-gradient(to right, rgb(244 236 216 / 0.16) var(--a), var(--portal-accent) var(--a) var(--b), rgb(244 236 216 / 0.16) var(--b));
  }
  .slider::-moz-range-track {
    height: 6px;
    background: linear-gradient(to right, rgb(244 236 216 / 0.16) var(--a), var(--portal-accent) var(--a) var(--b), rgb(244 236 216 / 0.16) var(--b));
  }
  .slider::-webkit-slider-thumb {
    width: 22px;
    height: 22px;
    margin-top: -8px;
    border: 0;
    background: var(--cream);
    box-shadow: inset 0 -3px 0 rgb(0 0 0 / 0.25);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    -webkit-appearance: none;
    appearance: none;
  }
  .slider::-moz-range-thumb {
    width: 22px;
    height: 22px;
    border: 0;
    border-radius: 0;
    background: var(--cream);
  }
</style>

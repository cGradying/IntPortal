<script lang="ts">
  // The chip (spec 046 C1b to C1d2): one floating button. A flat 3x3 grid of pixel squares on most
  // tabs, once IntAssis has been added; its four corners dither out into a + on Study. At rest it is
  // flat, in the room's own tokens, and draws nothing. Opening the chat grows it into LAR's window
  // (AssisWindow): the chip fades into it, sleeps while the window is open, and fades back in at its
  // spot as the window folds into it (`chip.at`).
  import { closable } from "../back";
  import { buzz } from "../haptics";
  import { rootPull } from "../fieldPulse";
  import { app } from "../state.svelte";
  import { assis, installed, open } from "./assis.svelte";
  import { chip } from "./AssisWindow.svelte";
  import { PX, crystalMode, drawChip, readTones } from "./crystal";

  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const mode = $derived(crystalMode(app.tab, installed(), !!app.editing));
  const thinking = $derived(assis.busy === "thinking" || assis.busy === "waking" || assis.busy === "cards");
  const items = $derived([...(installed() ? [{ label: "Ask LAR", run: open }] : []), ...assis.menu]);

  let canvas = $state<HTMLCanvasElement>();
  let button = $state<HTMLButtonElement>();
  let menuOpen = $state(false);
  let tones = readTones();

  // One stepped clock (about 12 fps) drives the dither swap and the thinking sweep. It only runs
  // while something moves, never while the page is hidden, and not at all under Reduce Motion.
  const moveMs = (() => {
    const v = getComputedStyle(document.documentElement).getPropertyValue("--t-move").trim();
    const n = parseFloat(v);
    return n > 0 ? (v.endsWith("ms") ? n : n * 1000) : 400;
  })();
  const fold = 1 / Math.max(1, Math.ceil(moveMs / 80));
  let p = 1;
  let alive = true;
  let step = 0;
  let pulseLeft = 0;
  let timer: ReturnType<typeof setInterval> | undefined;
  const paint = () => {
    const ctx = canvas?.getContext("2d");
    if (!ctx) return;
    const px = Math.round(48 * (devicePixelRatio || 1));
    if (canvas!.width !== px) canvas!.width = canvas!.height = px;
    drawChip(ctx, tones, p, step, menuOpen, px / PX);
  };
  const stop = () => {
    clearInterval(timer);
    timer = undefined;
  };
  const tick = () => {
    if (!canvas) return stop();
    const goal = mode === "plus" ? 0 : 1;
    p = Math.abs(goal - p) < fold * 0.99 ? goal : p + Math.sign(goal - p) * fold;
    pulseLeft = Math.max(0, pulseLeft - 1);
    const sweeping = thinking || pulseLeft > 0;
    step = sweeping ? step + 1 : 0;
    paint();
    if (p === goal && !sweeping) stop();
  };
  const wake = () => {
    if (!alive) return;
    if (reduce || document.hidden) {
      p = mode === "plus" ? 0 : 1;
      step = 0;
      return paint();
    }
    timer ??= setInterval(tick, 80);
  };
  $effect(() => {
    void [canvas, mode, thinking, menuOpen];
    wake();
  });
  $effect(() => {
    const seen = () => (document.hidden ? stop() : wake());
    document.addEventListener("visibilitychange", seen);
    return () => {
      alive = false;
      document.removeEventListener("visibilitychange", seen);
      stop();
    };
  });

  // It tucks aside while the page scrolls, and comes back when you stop (spec 045 C23).
  let tucked = $state(false);
  $effect(() => {
    let tuck: ReturnType<typeof setTimeout>;
    const scrolled = () => {
      tucked = true;
      clearTimeout(tuck);
      tuck = setTimeout(() => (tucked = false), 650);
    };
    addEventListener("scroll", scrolled, { passive: true });
    return () => {
      clearTimeout(tuck);
      removeEventListener("scroll", scrolled);
    };
  });

  // In the note editor the + floats above the keyboard (046 C11): the keyboard's height is what
  // the visual viewport has lost at the bottom.
  let kb = $state(0);
  $effect(() => {
    const vv = window.visualViewport;
    if (!app.editing || !vv) return;
    const measure = () => {
      const lost = window.innerHeight - vv.height - vv.offsetTop;
      kb = lost > 80 ? Math.round(lost) : 0;
    };
    measure();
    vv.addEventListener("resize", measure);
    vv.addEventListener("scroll", measure);
    return () => {
      vv.removeEventListener("resize", measure);
      vv.removeEventListener("scroll", measure);
      kb = 0;
    };
  });

  // A change of room or theme repaints the rest state.
  $effect(() => {
    const watch = new MutationObserver(() => {
      tones = readTones();
      paint();
    });
    watch.observe(document.documentElement, { attributes: true, attributeFilter: ["data-room", "data-theme", "style"] });
    return () => watch.disconnect();
  });

  $effect(() => {
    void app.tab;
    menuOpen = false;
  });
  // Android's back closes the menu, not the tab.
  $effect(() => {
    if (menuOpen) return closable(() => (menuOpen = false));
  });

  // Finishing grows roots behind the cards (C1b4).
  let wasThinking = false;
  $effect(() => {
    const now = thinking;
    if (wasThinking && !now && !assis.open && button)
      rootPull(button.getBoundingClientRect(), () => {
        pulseLeft = 12;
        wake();
      });
    wasThinking = now;
  });

  function press() {
    buzz.tick();
    if (mode === "plus" && assis.plus) assis.plus();
    else if (mode === "plus") menuOpen = !menuOpen;
    else open();
  }
  function choose(run: () => void) {
    menuOpen = false;
    buzz.tick();
    run();
  }
</script>

{#if mode}
  {#if menuOpen}
    <button class="scrim" aria-label="Close" onclick={() => (menuOpen = false)}></button>
    <div class="menu card notch" role="menu">
      {#each items as item (item.label)}
        <button role="menuitem" onclick={() => choose(item.run)}>{item.label}</button>
      {/each}
    </div>
  {/if}
  <button
    bind:this={button}
    class="orb card notch"
    class:open={menuOpen}
    data-orb
    class:away={chip.at !== "here"}
    class:tucked
    class:over={!!app.editing}
    style:--kb="{app.editing ? kb : 0}px"
    aria-label={mode === "plus" ? "Add" : "Ask LAR"}
    aria-expanded={mode === "plus" ? menuOpen : undefined}
    onclick={press}
  >
    <canvas bind:this={canvas} width={PX * 2} height={PX * 2} aria-hidden="true"></canvas>
  </button>
{/if}

<style>
  .orb {
    position: fixed;
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 84px);
    z-index: 22;
    width: 48px;
    height: 48px;
    display: grid;
    padding: 0;
    border: 0;
    overflow: hidden;
    box-shadow: inset 0 0 0 1px var(--edge-2);
    -webkit-tap-highlight-color: transparent;
    transition:
      opacity 0.2s var(--ease),
      transform 0.2s var(--ease),
      translate 0.22s var(--ease),
      scale 0.22s var(--ease);
  }
  /* Over the note editor, where there is no tab bar (046 C11). */
  .orb.over {
    z-index: 56;
    bottom: calc(var(--safe-bottom) + 16px + var(--kb, 0px));
  }

  .orb > * {
    grid-area: 1 / 1;
    width: 100%;
    height: 100%;
  }
  .orb canvas {
    image-rendering: pixelated;
  }
  .orb.tucked {
    translate: 22px 0;
    scale: 0.7;
    opacity: 0.7;
  }
  .orb:active {
    transform: scale(0.92);
  }
  .orb.away {
    opacity: 0;
    pointer-events: none;
  }
  .orb.open {
    z-index: 41;
  }
  .orb:focus-visible {
    outline: 2px solid var(--gold);
    outline-offset: -2px;
  }
  .scrim {
    position: fixed;
    inset: 0;
    z-index: 40;
    border: 0;
    border-radius: 0;
    background: rgb(0 0 0 / 0.45);
    animation: fadein 0.2s var(--ease) both;
  }
  .menu {
    position: fixed;
    right: var(--gutter);
    bottom: calc(var(--safe-bottom) + 140px);
    z-index: 41;
    min-width: 200px;
    display: grid;
    padding: 4px 0;
    background: var(--card);
    box-shadow: inset 0 0 0 1px var(--edge-2);
    animation: rise 0.3s var(--ease) both;
  }
  .menu button {
    min-height: 48px;
    padding: 0 16px;
    border: 0;
    border-radius: 0;
    background: none;
    box-shadow: none;
    color: var(--ink);
    font: inherit;
    font-weight: 600;
    text-align: left;
  }
  .menu button + button {
    border-top: 1px solid var(--edge);
  }
  .menu button:first-child {
    color: var(--gold);
  }
  @keyframes fadein {
    from {
      opacity: 0;
    }
  }
  @keyframes rise {
    from {
      opacity: 0;
      transform: translateY(10px);
    }
  }
  :global([data-glance="dock"]) .orb {
    bottom: calc(var(--safe-bottom) + 142px);
  }
  :global([data-glance="dock"]) .menu {
    bottom: calc(var(--safe-bottom) + 198px);
  }
  :global(html[data-keyboard="open"]) .orb:not(.over) {
    display: none;
  }
  @media (prefers-reduced-motion: reduce) {
    .scrim,
    .menu {
      animation: none;
    }
  }
</style>

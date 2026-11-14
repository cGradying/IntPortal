<script lang="ts">
  // The crystal (spec 046 C1b to C1d2): one floating button. A cube of data on most tabs, once
  // IntAssis has been added; it folds into a + on Study. At rest it is flat, in the room's own
  // tokens, and draws nothing. Opening the chat dithers LAR's window out of it (AssisWindow, spec 048
  // C1–C6): the chip hides as the dither starts, sleeps while the window is open, and comes back as
  // the window dithers back into it (`chip.at`).
  import { invoke } from "@tauri-apps/api/core";
  import { untrack } from "svelte";
  import { closable } from "../back";
  import { buzz } from "../haptics";
  import { api } from "../api";
  import { rootPull } from "../fieldPulse";
  import { FALLBACK_SIS } from "../portals";
  import { app } from "../state.svelte";
  import { assis, installed, open } from "./assis.svelte";
  import { chip } from "./AssisWindow.svelte";
  import { crystalMode, mountCrystal, readTones, restCube, useGlass, type Crystal } from "./crystal";

  const SIZE = 48;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  const webgl2 = "WebGL2RenderingContext" in window;
  /** False until the dive is over: compiling the shader on the main thread would hitch it. */
  let { settled = true }: { settled?: boolean } = $props();

  // The app's own tier, the one the AI keys on. Still image until it answers, and if it can't.
  let smallRam = $state(true);
  invoke<boolean>("ai_small_ram").then((small) => (smallRam = small)).catch(() => {});
  const glass = $derived(useGlass(reduce, smallRam, webgl2));

  const mode = $derived(crystalMode(app.tab, installed(), !!app.editing));
  const thinking = $derived(assis.busy === "thinking" || assis.busy === "waking" || assis.busy === "cards");
  const items = $derived([...(installed() ? [{ label: "Ask LAR", run: open }] : []), ...assis.menu]);

  let canvas = $state<HTMLCanvasElement>();
  let button = $state<HTMLButtonElement>();
  let crystal = $state<Crystal | null>(null);
  let menuOpen = $state(false);
  let remount = $state(0);
  let tones = $state(readTones());
  const faces = $derived(restCube(tones));
  let ramp = FALLBACK_SIS.theme.ramp;

  api.portals().then((list) => {
    const own = list.find((p) => p.id === (app.sisConnected ? "sis" : "mabini"));
    if (own) {
      ramp = own.theme.ramp;
      crystal?.look(ramp);
    }
  }).catch(() => {});

  // It tucks aside while the page scrolls, and comes back when you stop (spec 045 C23).
  let tucked = $state(false);
  $effect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const tapped = () => crystal?.wake();
    const scrolled = () => {
      tucked = true;
      crystal?.wake();
      clearTimeout(timer);
      timer = setTimeout(() => (tucked = false), 650);
    };
    addEventListener("scroll", scrolled, { passive: true });
    addEventListener("pointerdown", tapped, { passive: true });
    return () => {
      clearTimeout(timer);
      removeEventListener("scroll", scrolled);
      removeEventListener("pointerdown", tapped);
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

  // A change of room or theme repaints the rest state, whichever renderer is showing.
  $effect(() => {
    const watch = new MutationObserver(() => {
      tones = readTones();
      crystal?.wake();
    });
    watch.observe(document.documentElement, { attributes: true, attributeFilter: ["data-room", "data-theme", "style"] });
    return () => watch.disconnect();
  });

  // The shader compiles after the page has painted. The still image shows until it's ready,
  // and stays when glass can't start.
  $effect(() => {
    const cv = canvas;
    void remount;
    if (!cv || !glass || !settled) return;
    const timer = setTimeout(() => {
      crystal = mountCrystal(cv, { mode: untrack(() => mode) ?? "cube", size: SIZE, ramp, onlost: () => (crystal = null) });
    }, 400);
    // A context lost in the background comes back here, so the student keeps the glass.
    const restored = () => remount++;
    cv.addEventListener("webglcontextrestored", restored);
    return () => {
      clearTimeout(timer);
      cv.removeEventListener("webglcontextrestored", restored);
      untrack(() => crystal)?.dispose();
      crystal = null;
    };
  });

  $effect(() => {
    void app.tab;
    if (mode) crystal?.set(mode);
    menuOpen = false;
  });
  $effect(() => crystal?.menu(menuOpen));
  // Android's back closes the menu, not the tab.
  $effect(() => {
    if (menuOpen) return closable(() => (menuOpen = false));
  });
  $effect(() => crystal?.hide(chip.at === "hidden"));

  // Thinking maps something (C1b3). Finishing grows roots behind the cards (C1b4).
  let wasThinking = false;
  $effect(() => {
    const now = thinking;
    crystal?.think(now);
    if (wasThinking && !now && crystal && !assis.open && button) rootPull(button.getBoundingClientRect(), () => crystal?.pulse());
    wasThinking = now;
  });

  function press() {
    buzz.tick();
    crystal?.pulse();
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
    class:sweep={thinking && !crystal && !assis.open}
    data-orb
    class:away={chip.at !== "here"}
    class:tucked
    class:over={!!app.editing}
    style:--kb="{app.editing ? kb : 0}px"
    aria-label={mode === "plus" ? "Add" : "Ask LAR"}
    aria-expanded={mode === "plus" ? menuOpen : undefined}
    onclick={press}
  >
    {#if !crystal}
      <svg viewBox="-3.25 -3.25 6.5 6.5" aria-hidden="true">
        {#if mode === "plus"}
          <g fill={tones.gold}>
            <rect x="-1.77" y="-0.57" width="3.54" height="1.14" />
            <rect x="-0.57" y="-1.77" width="1.14" height="3.54" />
          </g>
        {:else}
          {#each faces as f, i (i)}
            <polygon points={f.points} fill={f.fill} stroke={tones.hair} stroke-width="0.07" />
            {#if f.dot}<polygon points={f.dot} fill={tones.gold} />{/if}
          {/each}
        {/if}
      </svg>
    {/if}
    {#if glass}<canvas bind:this={canvas} class:live={!!crystal} aria-hidden="true"></canvas>{/if}
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
    opacity: 0;
  }
  .orb canvas.live {
    opacity: 1;
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
  /* Phones without the glass: a cheap band across the still image while LAR thinks (C1d2). */
  .orb.sweep::after {
    content: "";
    grid-area: 1 / 1;
    width: 100%;
    height: 100%;
    background: linear-gradient(100deg, transparent 35%, var(--gold-soft) 50%, transparent 65%);
    animation: sweep 1.4s ease-in-out infinite;
  }
  @keyframes sweep {
    from {
      transform: translateX(-100%);
    }
    to {
      transform: translateX(100%);
    }
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
    .orb.sweep::after {
      animation: none;
    }
    .scrim,
    .menu {
      animation: none;
    }
  }
</style>

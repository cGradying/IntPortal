<script lang="ts">
  // Spec 057 C2–C8: the first screen. The still portal paints first; where the
  // device can run it, three.js loads after mount, takes over the same box,
  // and scrolling the hero dives through the mouth into the page.
  import { onMount, type Snippet } from "svelte";
  import Lar from "$app_lib/lar/Lar.svelte";
  import { talk } from "./talk";
  import PixelIcon from "$app_lib/PixelIcon.svelte";
  import Still from "./Still.svelte";
  import { canRun, readEnv } from "./gate";
  import type { Hero } from "./scene";

  let { children }: { children: Snippet } = $props();

  let section: HTMLElement;
  let box: HTMLElement;
  let canvas: HTMLCanvasElement;
  let live = $state(false);
  let shown = $state(false);
  let p = $state(0);
  let tx = $state(0);
  let ty = $state(0);
  let larSize = $state(5);
  // 058 C12 and 059 C1–C2: LAR says the app's own lines, and the portal sends out
  // a sculpture for each. He talks on his own every 7 s until he is tapped; only
  // lines the visitor asked for are announced.
  let said = $state(0);
  // He says this many lines on his own, then rests until tapped (059 C2).
  const OWN = 4;
  let tapped = $state(false);
  const line = $derived(talk[said % talk.length]);
  let heroApi = $state.raw<Hero | null>(null);
  $effect(() => heroApi?.form(line.form));
  let heard = $state("");
  function tap() {
    tapped = true;
    said++;
    heard = talk[said % talk.length].text;
  }

  onMount(() => {
    const wide = matchMedia("(min-width: 900px)");
    const huge = matchMedia("(min-width: 1800px) and (min-height: 1000px)");
    const size = () => (larSize = huge.matches ? 9 : wide.matches ? 7 : 5);
    size();
    wide.addEventListener("change", size);
    huge.addEventListener("change", size);

    let hero: Hero | null = null;
    let gone = false;
    let stillOnly = false;
    const env = readEnv();
    if (canRun(env)) {
      live = true;
      // 060 C20: fetch the scene in idle time, after the first paint.
      const idle = window.requestIdleCallback ?? ((f: () => void) => setTimeout(f, 200));
      idle(() => import("./scene").then(({ start }) => {
        if (gone || stillOnly) return;
        try {
          heroApi = hero = start(canvas, {
          box,
          onFirst: () => (shown = true),
          onSlow: () => {
            heroApi = null;
            shown = false;
            live = false;
            p = 0;
          },
          });
        } catch {
          live = false;
          return;
        }
        onScroll();
      }, () => (live = false)));
    }
    // Reduce Motion turned on while the scene runs: stop it and show the still.
    const rm = matchMedia("(prefers-reduced-motion: reduce)");
    const still = () => {
      if (!rm.matches) return;
      stillOnly = true;
      hero?.stop();
      hero = heroApi = null;
      live = false;
      shown = false;
      p = tx = ty = 0;
    };
    rm.addEventListener("change", still);

    function onScroll() {
      if (!live) return;
      const r = section.getBoundingClientRect();
      const run = r.height - innerHeight;
      // The dive runs past the sticky part, so its last phase (the field breaking into
      // dots) plays while the stage scrolls away and the next section arrives (C6).
      const span = run + innerHeight * 0.55;
      p = span > 0 ? Math.min(1, Math.max(0, -r.top / span)) : 0;
      hero?.scroll(p);
    }
    function onPointer(e: PointerEvent) {
      if (e.pointerType !== "mouse" || !live) return;
      // Against the canvas, which can be taller than the window or narrower by a scrollbar.
      const r = canvas.getBoundingClientRect();
      const x = ((e.clientX - r.left) / r.width) * 2 - 1;
      const y = ((e.clientY - r.top) / r.height) * 2 - 1;
      tx = x;
      ty = y;
      hero?.pointer(x, y);
    }
    // The mouse left the window: the tiles settle and the swirl calms (059 C6).
    function onLeave(e: PointerEvent) {
      if (e.pointerType !== "mouse" || e.relatedTarget || !live) return;
      tx = ty = 0;
      hero?.leave();
    }
    // 059 C2: while the scene runs and the hero is in view, he talks on his own.
    const chat = setInterval(() => {
      if (!tapped && heroApi && p < 0.02 && !document.hidden && said < OWN) said++;
    }, 7000);
    addEventListener("scroll", onScroll, { passive: true });
    addEventListener("pointermove", onPointer, { passive: true });
    document.addEventListener("pointerout", onLeave);
    return () => {
      clearInterval(chat);
      gone = true;
      hero?.stop();
      wide.removeEventListener("change", size);
      huge.removeEventListener("change", size);
      rm.removeEventListener("change", still);
      removeEventListener("scroll", onScroll);
      removeEventListener("pointermove", onPointer);
      document.removeEventListener("pointerout", onLeave);
    };
  });
</script>

<section class="hero" class:live bind:this={section} style="--p:{p}; --tx:{tx}; --ty:{ty}" aria-labelledby="hero-h">
  <div class="stage">
    <div class="box" bind:this={box}>
      <div class="still" class:gone={shown}><Still /></div>
    </div>
    <canvas class="scene" bind:this={canvas} class:on={shown} aria-hidden="true"></canvas>
    <div class="wrap copy">
      {@render children()}
      {#if live}<p class="hint pixel" aria-hidden="true">Scroll to step through <span><PixelIcon name="down" size={12} accent="var(--gold)" /></span></p>{/if}
    </div>
    <div class="box over">
      <button class="lar" aria-label="LAR, say something" onclick={tap}>
        <Lar size={larSize} gesture="wave" label="LAR, the Lakbay-Aral Robot, waving" />
        <span class="slab" aria-hidden="true"><span class="pixel who">LAR</span> {#key said}<span class="said">{line.text}</span>{/key}</span>
      </button>
      <!-- Only lines the visitor asked for are read out; this region is live from the start. -->
      <span class="sr" aria-live="polite">{heard}</span>
    </div>
  </div>
</section>

<style>
  /* The hero runs under the translucent header, so the scene fills the screen. */
  .hero {
    position: relative;
    height: max(640px, 100svh);
    margin-top: -64px;
  }
  /* With the dive, the hero is two screens tall and its stage stays put while
     the first one scrolls by (C6). */
  .hero.live {
    height: 200svh;
  }
  .stage {
    position: sticky;
    top: 0;
    height: max(640px, 100svh);
    overflow: hidden;
    background:
      radial-gradient(ellipse 60% 50% at 72% 46%, rgba(148, 28, 48, 0.22), transparent 70%),
      radial-gradient(rgba(245, 178, 39, 0.07) 1px, transparent 1.5px) 0 0 / 15px 15px,
      var(--void);
  }
  .scene {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    image-rendering: pixelated;
    opacity: 0;
    pointer-events: none;
  }
  .scene.on {
    opacity: 1;
    transition: opacity var(--t-hero) var(--ease);
  }
  .live .scene.on {
    transition: none;
  }
  /* The portal's box: right of the copy on a wide screen, above it on a phone.
     The 3D frame is fitted to this box, so the swap from the still never moves. */
  .box {
    position: absolute;
    left: 50%;
    top: max(72px, 8svh);
    height: min(clamp(190px, 100svh - 460px, 54svh), 92vw * 4 / 3);
    aspect-ratio: 12 / 16;
    translate: -50% 0;
  }
  .over {
    pointer-events: none;
  }
  .still {
    position: absolute;
    inset: 0;
    transition: opacity var(--t-hero) var(--ease);
  }
  .still.gone {
    opacity: 0;
  }
  .lar {
    position: absolute;
    left: 50%;
    bottom: -4%;
    display: block;
    padding: 0;
    border: 0;
    background: none;
    color: inherit;
    font: inherit;
    text-align: left;
    cursor: pointer;
    pointer-events: auto;
    translate: calc(-50% + var(--tx) * -10px) calc(var(--ty) * -6px);
    /* LAR steps through first: he shrinks into the mouth as the dive starts. */
    transform: translateY(calc(var(--p) * -160%)) scale(calc(1 - min(1, var(--p) * 2.2) * 0.85));
    transform-origin: 50% 100%;
    opacity: calc(1 - var(--p) * 3);
  }
  /* His line sits centred over his head and grows up over the portal, so it
     never runs off the screen or into the title, at any width. */
  .slab {
    position: absolute;
    left: 50%;
    bottom: calc(100% + 22px);
    translate: -50% 0;
    text-align: center;
    padding: 7px 12px;
    background: var(--void-3);
    box-shadow: inset 0 0 0 3px var(--slab-edge);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    width: max-content;
    max-width: min(300px, 100vw - 40px);
    color: var(--parch);
    font-weight: 600;
    line-height: 1.35;
    text-wrap: pretty;
  }
  .said {
    display: inline;
    animation: said 240ms steps(4) both;
  }
  @keyframes said {
    from {
      opacity: 0;
    }
  }
  .lar:hover .slab {
    box-shadow: inset 0 0 0 3px var(--gold);
  }
  .lar:focus-visible {
    outline: none;
  }
  .lar:focus-visible .slab {
    outline: 2px solid var(--gold);
    outline-offset: 3px;
  }
  .sr {
    position: absolute;
    width: 1px;
    height: 1px;
    overflow: hidden;
    clip-path: inset(50%);
    white-space: nowrap;
  }
  .who {
    color: var(--gold);
    margin-right: 6px;
  }
  /* The copy box spans the stage on a wide screen; only its children catch taps,
     so LAR stays tappable under it. */
  .copy {
    pointer-events: none;
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    padding-bottom: max(20px, 3svh);
    padding-top: 72px;
    background: linear-gradient(to top, var(--void) 40%, color-mix(in srgb, var(--void) 80%, transparent) 70%, transparent);
    opacity: calc(1 - var(--p) * 3);
    translate: 0 calc(var(--p) * -40px);
  }
  .copy > :global(*) {
    pointer-events: auto;
  }
  @media (max-width: 359px) {
    .slab {
      font-size: 0.88rem;
    }
  }
  .hint {
    display: none;
    margin-top: 22px;
    font-size: 0.85rem;
    color: var(--site-ink-2);
  }
  .hint span {
    display: inline-block;
    margin-left: 4px;
    animation: nudge 1.6s var(--ease) infinite;
  }
  @keyframes nudge {
    50% {
      transform: translateY(4px);
    }
  }
  @media (min-width: 900px) {
    /* Stars stay off the copy column until the dive fills the screen. */
    .scene {
      mask-image: linear-gradient(to right, rgb(0 0 0 / min(1, calc(var(--p) * 4))) 42%, #000 56%);
      -webkit-mask-image: linear-gradient(to right, rgb(0 0 0 / min(1, calc(var(--p) * 4))) 42%, #000 56%);
    }
    .box {
      left: auto;
      right: max(var(--site-gutter), (100% - var(--site-max)) / 2 + 24px);
      top: 50%;
      height: min(68svh, 640px);
      translate: 0 -54%;
    }
    .copy {
      top: 0;
      bottom: 0;
      display: flex;
      flex-direction: column;
      justify-content: center;
      padding: 64px 0 0;
      background: none;
    }
    .hint {
      display: block;
    }
    .copy > :global(*) {
      max-width: min(560px, 48%);
    }
  }
  @media (min-width: 1800px) and (min-height: 1000px) {
    .box {
      height: min(66svh, 900px);
    }
    .copy > :global(*) {
      max-width: min(720px, 48%);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .hint span,
    .said {
      animation: none;
    }
  }
</style>

<script lang="ts">
  // Spec 057 C2–C8: the first screen. The still portal paints first; where the
  // device can run it, three.js loads after mount, takes over the same box,
  // and scrolling the hero dives through the mouth into the page.
  import { onMount, type Snippet } from "svelte";
  import Lar from "$app_lib/lar/Lar.svelte";
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

  onMount(() => {
    const wide = matchMedia("(min-width: 900px)");
    const size = () => (larSize = wide.matches ? 7 : 5);
    size();
    wide.addEventListener("change", size);

    let hero: Hero | null = null;
    let gone = false;
    const env = readEnv();
    if (canRun(env)) {
      live = true;
      import("./scene").then(({ start }) => {
        if (gone) return;
        hero = start(canvas, {
          box,
          onFirst: () => (shown = true),
          onSlow: () => {
            shown = false;
            live = false;
            p = 0;
          },
        });
        onScroll();
      }, () => (live = false));
    }

    function onScroll() {
      if (!live) return;
      const r = section.getBoundingClientRect();
      const run = r.height - innerHeight;
      p = run > 0 ? Math.min(1, Math.max(0, -r.top / run)) : 0;
      hero?.scroll(p);
    }
    function onPointer(e: PointerEvent) {
      if (e.pointerType !== "mouse") return;
      const x = (e.clientX / innerWidth) * 2 - 1;
      const y = (e.clientY / innerHeight) * 2 - 1;
      tx = x;
      ty = y;
      hero?.pointer(x, y);
    }
    addEventListener("scroll", onScroll, { passive: true });
    addEventListener("pointermove", onPointer, { passive: true });
    return () => {
      gone = true;
      hero?.stop();
      wide.removeEventListener("change", size);
      removeEventListener("scroll", onScroll);
      removeEventListener("pointermove", onPointer);
    };
  });
</script>

<section class="hero" class:live bind:this={section} style="--p:{p}; --tx:{tx}; --ty:{ty}" aria-labelledby="hero-h">
  <div class="stage">
    <div class="box" bind:this={box}>
      <div class="still" class:gone={shown}><Still /></div>
    </div>
    <canvas class="scene" bind:this={canvas} class:on={shown} aria-hidden="true"></canvas>
    <div class="box over">
      <div class="lar">
        <p class="slab"><span class="pixel who">LAR</span> Tara, pasok!</p>
        <Lar size={larSize} gesture="wave" label="LAR, the Lakbay-Aral Robot, waving" />
      </div>
    </div>
    <div class="wrap copy">
      {@render children()}
      {#if live}<p class="hint pixel" aria-hidden="true">Scroll to step through <span><PixelIcon name="down" size={12} accent="var(--gold)" /></span></p>{/if}
    </div>
  </div>
</section>

<style>
  .hero {
    position: relative;
    height: max(640px, 100svh);
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
      radial-gradient(rgba(245, 178, 39, 0.07) 1px, transparent 1.5px) 0 0 / 14px 14px,
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
    opacity: calc(1 - max(0, (var(--p) - 0.9) * 10));
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
    top: max(72px, 9svh);
    height: min(46svh, 92vw * 4 / 3);
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
    display: grid;
    justify-items: center;
    gap: 4px;
    translate: calc(-50% + var(--tx) * -10px) calc(var(--ty) * -6px);
    /* LAR steps through first: he shrinks into the mouth as the dive starts. */
    transform: translateY(calc(var(--p) * -160%)) scale(calc(1 - min(1, var(--p) * 2.2) * 0.85));
    transform-origin: 50% 100%;
    opacity: calc(1 - var(--p) * 3);
  }
  .slab {
    padding: 7px 12px;
    background: var(--void-3);
    box-shadow: inset 0 0 0 3px var(--slab-edge);
    clip-path: polygon(0 3px, 3px 3px, 3px 0, calc(100% - 3px) 0, calc(100% - 3px) 3px, 100% 3px, 100% calc(100% - 3px), calc(100% - 3px) calc(100% - 3px), calc(100% - 3px) 100%, 3px 100%, 3px calc(100% - 3px), 0 calc(100% - 3px));
    color: var(--parch);
    font-weight: 600;
    white-space: nowrap;
  }
  .who {
    color: var(--gold);
    margin-right: 6px;
  }
  .copy {
    position: absolute;
    left: 0;
    right: 0;
    bottom: 0;
    padding-bottom: max(28px, 5svh);
    padding-top: 96px;
    background: linear-gradient(to top, var(--void) 40%, color-mix(in srgb, var(--void) 80%, transparent) 70%, transparent);
    opacity: calc(1 - var(--p) * 3);
    translate: 0 calc(var(--p) * -40px);
  }
  .hint {
    margin-top: 22px;
    font-size: 0.82rem;
    color: var(--site-ink-3);
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
    .copy > :global(*) {
      max-width: min(560px, 48%);
    }
  }
  @media (prefers-reduced-motion: reduce) {
    .hint span {
      animation: none;
    }
  }
</style>

<script lang="ts">
  // A screen from the app in a plain phone outline. Loops are muted, inline and
  // only play while on screen; Reduce Motion shows the still.
  import { onMount } from "svelte";
  let { src, alt, video = false, poster, spot }: { src: string; alt: string; video?: boolean; poster?: string; spot?: [number, number, number, number] } = $props();
  let el = $state<HTMLVideoElement>();
  onMount(() => {
    if (!el || matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const io = new IntersectionObserver(([e]) => (e.isIntersecting ? el!.play().catch(() => {}) : el!.pause()), { threshold: 0.3 });
    io.observe(el);
    return () => io.disconnect();
  });
</script>

<div class="phone">
  {#if video}
    <video bind:this={el} {src} {poster} muted loop playsinline preload="none" aria-label={alt}></video>
  {:else}
    <div class="screen"><img {src} {alt} loading="lazy" decoding="async" width="450" height="1000" />{#if spot}<i class="spot" style:left="{spot[0]}%" style:top="{spot[1]}%" style:width="{spot[2]}%" style:height="{spot[3]}%"></i>{/if}</div>
  {/if}
</div>

<style>
  .phone {
    width: min(264px, 70vw);
    aspect-ratio: 9 / 20;
    padding: 8px;
    border-radius: 36px;
    background: #050307;
    box-shadow: inset 0 0 0 1px rgba(244, 236, 216, 0.12), 0 30px 60px -30px rgba(0, 0, 0, 0.9), 0 0 0 1px #000;
  }
  .screen {
    position: relative;
    height: 100%;
    overflow: hidden;
    border-radius: 28px;
  }
  /* The part of the screen the story is about. */
  .spot {
    position: absolute;
    border-radius: 12px;
    box-shadow:
      0 0 0 1.5px rgba(245, 178, 39, 0.9),
      0 0 0 6px rgba(245, 178, 39, 0.14),
      0 0 0 999px rgba(5, 3, 7, 0.42);
    pointer-events: none;
  }
  img,
  video {
    display: block;
    width: 100%;
    height: 100%;
    object-fit: cover;
    border-radius: 28px;
    background: var(--void-2);
  }
</style>

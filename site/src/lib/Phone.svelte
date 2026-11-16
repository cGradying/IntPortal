<script lang="ts">
  // A screen from the app in a plain phone outline. Loops are muted, inline and
  // only play while on screen; Reduce Motion shows the still.
  import { onMount } from "svelte";
  let { src, alt, video = false, poster }: { src: string; alt: string; video?: boolean; poster?: string } = $props();
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
    <img {src} {alt} loading="lazy" decoding="async" width="450" height="1000" />
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

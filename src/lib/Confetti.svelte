<script lang="ts">
  // One burst of pixel confetti over its parent, in the room's own colours.
  // Skipped entirely under Reduce Motion.
  import { onMount } from "svelte";

  let cv: HTMLCanvasElement;

  onMount(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const g = cv.getContext("2d")!;
    const r = cv.getBoundingClientRect();
    const dpr = Math.min(3, devicePixelRatio || 1);
    cv.width = r.width * dpr;
    cv.height = r.height * dpr;
    g.scale(dpr, dpr);
    const css = getComputedStyle(cv);
    const colors = ["--gold", "--s1", "--s2", "--s3", "--s4", "--s5", "--s6"].map((v) => css.getPropertyValue(v).trim() || "#f5b227");
    const bits = Array.from({ length: 70 }, (_, i) => ({
      x: r.width * (0.25 + Math.random() * 0.5),
      y: r.height * 0.55,
      vx: (Math.random() - 0.5) * 7,
      vy: -4 - Math.random() * 6,
      s: Math.random() < 0.3 ? 5 : 3,
      c: colors[i % colors.length],
      spin: Math.random() < 0.5,
    }));
    let raf = 0;
    const t0 = performance.now();
    const step = (t: number) => {
      const age = (t - t0) / 1000;
      g.clearRect(0, 0, r.width, r.height);
      g.globalAlpha = Math.max(0, 1 - Math.max(0, age - 1.1) / 0.6);
      for (const b of bits) {
        b.vy += 0.28;
        b.vx *= 0.985;
        b.x += b.vx;
        b.y += b.vy;
        g.fillStyle = b.c;
        const w = b.spin && Math.floor(t / 90) % 2 ? 1 : b.s;
        g.fillRect(Math.round(b.x), Math.round(b.y), w, b.s);
      }
      if (age < 1.7) raf = requestAnimationFrame(step);
      else g.clearRect(0, 0, r.width, r.height);
    };
    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  });
</script>

<canvas bind:this={cv} aria-hidden="true"></canvas>

<style>
  canvas {
    position: absolute;
    inset: 0;
    width: 100%;
    height: 100%;
    pointer-events: none;
  }
</style>

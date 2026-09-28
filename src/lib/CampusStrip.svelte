<script lang="ts">
  // The living campus: PUP Sta. Mesa as a 192x80 pixel scene. The sky follows
  // the real hour (dithered bands, sun or moon on an arc, stars at night), the
  // next class is a lit window in the main building, and a jeepney passes now
  // and then. Drawn at a stepped 12 fps: pixel art's own cadence, and cheap.
  import { onMount } from "svelte";
  import { JEEP, JEEP_COLORS as JEEPC } from "./sprites";

  let { litKey = "", hour = $bindable<number | null>(null) }: { litKey?: string; hour?: number | null } = $props();

  const W = 192;
  const H = 80;
  let cv: HTMLCanvasElement;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  type RGB = [number, number, number];
  const hex = (h: string): RGB => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16)) as RGB;
  const mix = (a: RGB, b: RGB, t: number): RGB => a.map((v, i) => Math.round(v + (b[i] - v) * t)) as RGB;
  const css = (c: RGB) => `rgb(${c[0]},${c[1]},${c[2]})`;
  const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

  // Sky top and horizon through the day, eased between keyframes.
  const SKY: [number, string, string][] = [
    [0, "#0a0f2c", "#1d2757"],
    [4.5, "#0d1233", "#2a2d5c"],
    [5.75, "#2b2f5e", "#e39a7a"],
    [7, "#4a86cc", "#f3d2a2"],
    [9, "#4b92d6", "#bfe0f2"],
    [16, "#4a8ccf", "#cfe4ef"],
    [17.25, "#466aa8", "#f2a45e"],
    [18.3, "#2a2c64", "#b8587a"],
    [19.5, "#0e1336", "#26285a"],
    [24, "#0a0f2c", "#1d2757"],
  ];

  function skyAt(h: number): { top: RGB; bottom: RGB; light: number } {
    let i = 0;
    while (i < SKY.length - 2 && SKY[i + 1][0] <= h) i++;
    const [h0, t0, b0] = SKY[i];
    const [h1, t1, b1] = SKY[i + 1];
    const t = Math.min(1, Math.max(0, (h - h0) / (h1 - h0)));
    const e = t * t * (3 - 2 * t);
    const light = h < 5.5 || h > 19 ? 0 : h < 7 ? (h - 5.5) / 1.5 : h > 17.5 ? (19 - h) / 1.5 : 1;
    return { top: mix(hex(t0), hex(t1), e), bottom: mix(hex(b0), hex(b1), e), light: Math.max(0, Math.min(1, light)) };
  }

  let seed = 11;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const stars = Array.from({ length: 34 }, () => [Math.floor(rnd() * W), Math.floor(rnd() * 34), rnd()]);
  const skyline: [number, number, number][] = [];
  for (let x = 0; x < W; ) {
    const w = 5 + Math.floor(rnd() * 9);
    skyline.push([x, w, 5 + Math.floor(rnd() * 13)]);
    x += w + (rnd() < 0.3 ? 2 : 0);
  }
  const nightLit = Array.from({ length: 64 }, () => rnd() < 0.28);
  const clouds = [[20, 10, 16], [96, 16, 22], [150, 7, 14]];

  // Wing windows: 3 rows of 9 on each side; the central block has 3 tall ones.
  const WINDOWS: [number, number, number, number][] = [];
  for (let r = 0; r < 3; r++)
    for (let c = 0; c < 9; c++) {
      WINDOWS.push([36 + c * 5, 45 + r * 6, 2, 3]);
      WINDOWS.push([115 + c * 5, 45 + r * 6, 2, 3]);
    }
  const litIndex = $derived.by(() => {
    let s = 0;
    for (const ch of litKey) s += ch.charCodeAt(0);
    return litKey ? s % WINDOWS.length : -1;
  });

  let skyCache: HTMLCanvasElement | null = null;
  let skyKey = "";

  function paintSky(h: number) {
    const key = h.toFixed(2);
    if (skyCache && key === skyKey) return skyCache;
    skyKey = key;
    skyCache ??= document.createElement("canvas");
    skyCache.width = W;
    skyCache.height = 66;
    const g = skyCache.getContext("2d")!;
    const img = g.createImageData(W, 66);
    const { top, bottom } = skyAt(h);
    const bands = 7;
    for (let y = 0; y < 66; y++)
      for (let x = 0; x < W; x++) {
        const t = y / 65;
        const b = Math.min(bands - 1, Math.max(0, Math.floor(t * bands + BAYER[y & 3][x & 3] / 16 - 0.5)));
        const c = mix(top, bottom, b / (bands - 1));
        const i = (y * W + x) * 4;
        img.data[i] = c[0];
        img.data[i + 1] = c[1];
        img.data[i + 2] = c[2];
        img.data[i + 3] = 255;
      }
    g.putImageData(img, 0, 0);
    return skyCache;
  }

  function draw(g: CanvasRenderingContext2D, ms: number) {
    const now = new Date();
    const h = hour ?? now.getHours() + now.getMinutes() / 60;
    const frame = reduce ? 0 : Math.floor(ms / 83);
    const { bottom, light } = skyAt(h);
    const night = 1 - light;
    const R = (c: string | RGB, x: number, y: number, w: number, hh: number) => {
      g.fillStyle = typeof c === "string" ? c : css(c);
      g.fillRect(x, y, w, hh);
    };
    const shade = (c: string, k = 0.62) => mix(hex(c), [10, 12, 30], night * k);

    g.drawImage(paintSky(h), 0, 0);

    if (night > 0.3) {
      for (const [x, y, p] of stars) {
        if ((frame + Math.floor(p * 40)) % 37 > 2) R(p > 0.8 ? "#fff3c4" : "#c9cde8", x, y, 1, 1);
      }
    }

    // Sun by day, moon by night, each on its own arc.
    const arc = (t: number) => [Math.round(12 + t * (W - 24)), Math.round(40 - Math.sin(t * Math.PI) * 32)];
    if (h >= 5.8 && h <= 18.4) {
      const [sx, sy] = arc((h - 5.8) / 12.6);
      R("#fff1b8", sx - 2, sy - 1, 5, 3);
      R("#fff1b8", sx - 1, sy - 2, 3, 5);
      R("#ffd166", sx - 1, sy - 1, 3, 3);
    } else {
      const t = ((h < 12 ? h + 24 : h) - 18.4) / 11.4;
      const [mx, my] = arc(Math.min(1, Math.max(0, t)));
      R("#f4efd9", mx - 2, my - 1, 4, 3);
      R("#f4efd9", mx - 1, my - 2, 2, 5);
      R(css(bottom), mx, my - 1, 2, 2);
    }

    if (light > 0.2) {
      for (const [cx, cy, cw] of clouds) {
        const x = Math.round(((cx + ms / 900) % (W + 40)) - 20);
        g.globalAlpha = 0.85 * light;
        R("#ffffff", x + 2, cy, cw - 4, 2);
        R("#ffffff", x, cy + 2, cw, 2);
        R("#dfe8f2", x + 1, cy + 4, cw - 2, 1);
        g.globalAlpha = 1;
      }
    }

    // Far Manila skyline, sky-tinted.
    const far = mix(bottom, [20, 18, 32], 0.45 + night * 0.3);
    for (const [x, w, hh] of skyline) R(far, x, 64 - hh, w, hh);
    if (night > 0.4) for (const [x, w, hh] of skyline) if ((x * 7) % 5 === 0) R("#e8c46a", x + 2, 64 - hh + 3, 1, 1);

    // Trees either side.
    const leaf = shade("#2f6b3a"), leafHi = shade("#3f8a4a");
    for (const tx of [10, 22, 164, 178]) {
      R(shade("#4a3222"), tx + 3, 54, 2, 10);
      R(leaf, tx, 46, 8, 8);
      R(leaf, tx - 1, 48, 10, 4);
      R(leafHi, tx + 1, 46, 3, 2);
    }

    // Main building: wings, central block with a stepped pediment, gold trim.
    const wall = shade("#6d0e1f", 0.55), wallDk = shade("#560a19", 0.55), trim = shade("#c9a227", 0.35);
    R(wall, 32, 42, 128, 23);
    R(wallDk, 32, 62, 128, 3);
    R(trim, 32, 41, 128, 1);
    R(wall, 80, 32, 32, 33);
    R(trim, 80, 31, 32, 1);
    for (let s = 0; s < 4; s++) R(s === 3 ? trim : wall, 84 + s * 3, 27 - s * 1, 24 - s * 6, 4);
    R(trim, 94, 22, 4, 1);
    // Flag on the roof, two-frame wave.
    R(shade("#d9d2c0"), 104, 16, 1, 11);
    R("#7a1128", 105, 16 + (frame % 12 < 6 ? 0 : 1), 5, 2);
    R("#f2c14e", 105, 18 + (frame % 12 < 6 ? 0 : 1), 5, 1);

    // Windows. The next class's window burns gold.
    WINDOWS.forEach(([x, y, w, hh], i) => {
      let c: string | RGB = shade("#2a0a10", 0.3);
      if (night > 0.4 && nightLit[i % 64]) c = "#e8c46a";
      if (i === litIndex) c = frame % 16 < 12 ? "#ffd75e" : "#f2b233";
      R(c, x, y, w, hh);
    });
    for (let c = 0; c < 3; c++) R(night > 0.4 && c === 1 ? "#e8c46a" : shade("#2a0a10", 0.3), 86 + c * 8, 36, 4, 7);
    // Columns at the entrance.
    for (let c = 0; c < 5; c++) R(shade("#e9dcc4", 0.5), 84 + c * 6, 52, 2, 12);
    if (litIndex >= 0) {
      const [x, y] = WINDOWS[litIndex];
      g.globalAlpha = 0.25 + 0.15 * Math.sin(ms / 400);
      R("#ffd75e", x - 1, y - 1, 4, 5);
      g.globalAlpha = 1;
    }

    // The Obelisk, in front of the entrance.
    R(shade("#e8e1cf", 0.5), 94, 30, 4, 36);
    R(shade("#bdb49f", 0.5), 96, 30, 2, 36);
    R(shade("#e8e1cf", 0.5), 95, 27, 2, 3);
    R(shade("#8f877a", 0.5), 91, 64, 10, 3);

    // Plaza, grass, road.
    R(shade("#8a8074", 0.6), 0, 65, W, 3);
    R(shade("#3c6b3a"), 0, 68, W, 3);
    R(shade("#2e2e33", 0.3), 0, 71, W, 9);
    for (let x = 0; x < W; x += 12) R(shade("#b9a86a", 0.4), x + ((frame >> 1) % 12 === 0 ? 0 : 0), 75, 6, 1);

    // A jeepney every 16 seconds.
    const cycle = reduce ? -1 : (ms / 16000) % 1;
    if (cycle >= 0 && cycle < 0.55) {
      const jx = Math.round(-20 + (cycle / 0.55) * (W + 40));
      const bob = frame % 4 < 2 ? 0 : 1;
      JEEP.forEach((row, y) => {
        for (let x = 0; x < row.length; x++) {
          const c = JEEPC[row[x]];
          if (c) R(y === 6 ? c : shade(c, 0.35), jx + x, 71 + y - (y < 6 ? bob : 0), 1, 1);
        }
      });
      if (night > 0.4) R("#fff1b8", jx + 18, 74, 3, 1);
    }
  }

  onMount(() => {
    const g = cv.getContext("2d")!;
    g.imageSmoothingEnabled = false;
    let raf = 0;
    let last = 0;
    const loop = (ms: number) => {
      if (ms - last >= 83 || reduce) {
        draw(g, ms);
        last = ms;
      }
      if (!reduce) raf = requestAnimationFrame(loop);
    };
    raf = requestAnimationFrame(loop);
    const redraw = setInterval(() => reduce && draw(g, performance.now()), 60_000);
    return () => {
      cancelAnimationFrame(raf);
      clearInterval(redraw);
    };
  });
</script>

<div role="img" aria-label="PUP Sta. Mesa at this hour"><canvas bind:this={cv} width={W} height={H}></canvas></div>

<style>
  canvas {
    display: block;
    width: 100%;
    height: auto;
    aspect-ratio: 192 / 80;
    image-rendering: pixelated;
  }
</style>

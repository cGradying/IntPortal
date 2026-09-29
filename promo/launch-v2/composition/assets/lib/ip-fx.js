/* Pixel FX painters (2D canvas, pure functions of time). Everything draws on a low-res canvas that CSS upscales with image-rendering:pixelated. */
(function () {
  const IP = window.IP;
  const FX = (IP.fx = {});
  const CONF = ["#F5B227", "#FAEBB3", "#E0697E", "#941C30", "#7EA3E0", "#5FBF9C", "#F7ECEC"];

  // deterministic particle burst. tau = seconds since spawn. o: {n, seed, speed, spread, gravity, life, size, colors, angle0}
  FX.burst = function (g, cx, cy, tau, o = {}) {
    if (tau < 0) return;
    const n = o.n || 24, r = IP.rng(o.seed || 1), cols = o.colors || CONF, life = o.life || 1.4;
    for (let i = 0; i < n; i++) {
      const a = (o.angle0 == null ? -Math.PI / 2 : o.angle0) + (r() - 0.5) * (o.spread == null ? Math.PI * 2 : o.spread);
      const v = (o.speed || 90) * (0.35 + r() * 0.85), sz = o.size || (r() < 0.3 ? 2 : 1), col = cols[Math.floor(r() * cols.length)];
      const life_i = life * (0.6 + r() * 0.5);
      if (tau > life_i) continue;
      const x = cx + Math.cos(a) * v * tau, y = cy + Math.sin(a) * v * tau + 0.5 * (o.gravity == null ? 160 : o.gravity) * tau * tau;
      g.globalAlpha = tau > life_i * 0.7 ? Math.max(0, 1 - (tau - life_i * 0.7) / (life_i * 0.3)) : 1;
      g.fillStyle = col;
      g.fillRect(Math.round(x), Math.round(y), sz, sz);
    }
    g.globalAlpha = 1;
  };
  // pixel ring (stamp shockwave)
  FX.ring = function (g, cx, cy, tau, o = {}) {
    if (tau < 0 || tau > (o.dur || 0.5)) return;
    const u = tau / (o.dur || 0.5), rad = (o.r || 40) * (1 - Math.pow(1 - u, 3));
    const n = Math.max(12, Math.round(rad * 1.6));
    g.fillStyle = o.color || "#FAEBB3"; g.globalAlpha = 1 - u;
    for (let i = 0; i < n; i++) { const a = (i / n) * Math.PI * 2; g.fillRect(Math.round(cx + Math.cos(a) * rad), Math.round(cy + Math.sin(a) * rad * (o.squash || 1)), 1, 1); }
    g.globalAlpha = 1;
  };

  // Portal swirl wipe. p: 0..1 (0 nothing, .5 full cover, 1 gone). dir: r|l|u|d. Colours = the portal swirl ramp, Bayer-dithered.
  const RAMP = [[23, 5, 9], [84, 10, 28], [148, 28, 48], [204, 161, 40], [250, 235, 179]];
  FX.wipe = function (g, W, H, p, dir, img) {
    img = img || g.createImageData(W, H);
    const d = img.data, WD = 1.5, front = p * (1 + WD + 0.06) - 0.03;
    for (let y = 0; y < H; y++) for (let x = 0; x < W; x++) {
      const i = (y * W + x) * 4;
      const nx = x / W, ny = y / H;
      const u = dir === "r" ? nx : dir === "l" ? 1 - nx : dir === "u" ? 1 - ny : ny;
      const bay = IP.BAYER[y & 3][x & 3] / 16;
      const beh = front - (u + (bay - 0.5) * 0.045);
      if (beh < 0 || beh > WD) { d[i + 3] = 0; continue; }
      const r = beh / WD, v = Math.min(1, (1 - Math.abs(2 * r - 1)) * 4.5);   // ramp at both edges, flat core
      const lv = 1 + (1 - v) * 3.2 + (bay - 0.5) * 1.4;
      const k = Math.max(1, Math.min(4, Math.floor(lv)));
      d[i] = RAMP[k][0]; d[i + 1] = RAMP[k][1]; d[i + 2] = RAMP[k][2]; d[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    return img;
  };
})();

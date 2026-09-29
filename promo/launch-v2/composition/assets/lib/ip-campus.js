/* The living Sta. Mesa campus, sky and portal swirl as pure functions of (time, hour).
   Based on the app's 192x80 campus strip; generalised to any W x H so it can fill a 16:9 frame. */
(function () {
  const IP = window.IP;
  const hexRGB = IP.hex;
  const mixRGB = (a, b, t) => a.map((v, i) => Math.round(v + (b[i] - v) * t));
  const css = (c) => `rgb(${c[0]},${c[1]},${c[2]})`;
  const BAYER = IP.BAYER;

  const SKY = [
    [0, "#0a0f2c", "#1d2757"], [4.5, "#0d1233", "#2a2d5c"], [5.75, "#2b2f5e", "#e39a7a"], [7, "#4a86cc", "#f3d2a2"],
    [9, "#4b92d6", "#bfe0f2"], [16, "#4a8ccf", "#cfe4ef"], [17.25, "#466aa8", "#f2a45e"], [18.3, "#2a2c64", "#b8587a"],
    [19.5, "#0e1336", "#26285a"], [24, "#0a0f2c", "#1d2757"],
  ];
  IP.skyAt = function (h) {
    let i = 0;
    while (i < SKY.length - 2 && SKY[i + 1][0] <= h) i++;
    const [h0, t0, b0] = SKY[i], [h1, t1, b1] = SKY[i + 1];
    const t = Math.min(1, Math.max(0, (h - h0) / (h1 - h0)));
    const e = t * t * (3 - 2 * t);
    const light = h < 5.5 || h > 19 ? 0 : h < 7 ? (h - 5.5) / 1.5 : h > 17.5 ? (19 - h) / 1.5 : 1;
    return { top: mixRGB(hexRGB(t0), hexRGB(t1), e), bottom: mixRGB(hexRGB(b0), hexRGB(b1), e), light: Math.max(0, Math.min(1, light)) };
  };
  // video time -> hour of day (one school day in 32 s)
  IP.hourAt = function (t) {
    const K = [[0, 5.2], [3.2, 5.9], [6.4, 7.3], [12.8, 10.4], [16, 13.5], [19.2, 16.6], [22.4, 18.2], [25.6, 19.7], [32, 21.6]];
    for (let i = 0; i < K.length - 1; i++) {
      if (t <= K[i + 1][0]) { const u = (t - K[i][0]) / (K[i + 1][0] - K[i][0]); return K[i][1] + (K[i + 1][1] - K[i][1]) * Math.max(0, u); }
    }
    return K[K.length - 1][1];
  };

  const cache = {};
  function paintSky(W, skyH, h) {
    const key = `${W}x${skyH}@${h.toFixed(2)}`;
    if (cache.k === key) return cache.cv;
    const cv = cache.cv && cache.cv.width === W && cache.cv.height === skyH ? cache.cv : Object.assign(document.createElement("canvas"), { width: W, height: skyH });
    const g = cv.getContext("2d");
    const img = g.createImageData(W, skyH);
    const { top, bottom } = IP.skyAt(h);
    const bands = 7;
    for (let y = 0; y < skyH; y++) for (let x = 0; x < W; x++) {
      const t = y / (skyH - 1);
      const b = Math.min(bands - 1, Math.max(0, Math.floor(t * bands + BAYER[y & 3][x & 3] / 16 - 0.5)));
      const c = mixRGB(top, bottom, b / (bands - 1));
      const i = (y * W + x) * 4;
      img.data[i] = c[0]; img.data[i + 1] = c[1]; img.data[i + 2] = c[2]; img.data[i + 3] = 255;
    }
    g.putImageData(img, 0, 0);
    cache.k = key; cache.cv = cv;
    return cv;
  }

  // deterministic scenery, built once per (W,H)
  const scenery = {};
  function build(W, H) {
    const key = W + "x" + H;
    if (scenery[key]) return scenery[key];
    const rnd = IP.rng(11);
    const oy = H - 80;
    const stars = Array.from({ length: Math.round(34 * (W * (oy + 34)) / (192 * 34)) }, () => [Math.floor(rnd() * W), Math.floor(rnd() * (oy + 34)), rnd()]);
    const skyline = [];
    for (let x = 0; x < W;) { const w = 5 + Math.floor(rnd() * 9); skyline.push([x, w, 5 + Math.floor(rnd() * 13)]); x += w + (rnd() < 0.3 ? 2 : 0); }
    const nightLit = Array.from({ length: 64 }, () => rnd() < 0.28);
    const clouds = [[20, 10, 16], [96, 16, 22], [150, 7, 14], [230, 22, 18], [60, 30, 20], [190, 34, 24]].map(([x, y, w]) => [x, oy > 0 ? y + Math.floor(rnd() * oy * 0.6) : y, w]);
    scenery[key] = { stars, skyline, nightLit, clouds, oy };
    return scenery[key];
  }
  const WINDOWS = [];
  for (let r = 0; r < 3; r++) for (let c = 0; c < 9; c++) { WINDOWS.push([36 + c * 5, 45 + r * 6, 2, 3]); WINDOWS.push([115 + c * 5, 45 + r * 6, 2, 3]); }
  IP.WINDOWS = WINDOWS;
  IP.litIndexFor = (key) => { if (!key) return -1; let s = 0; for (const ch of key) s += ch.charCodeAt(0); return s % WINDOWS.length; };

  /* g: 2D context of a W x H canvas. ms: video time in ms. hour: 0-24. opts: {lit, jeepX, jeepOn, cloudsSpeed} */
  IP.drawCampus = function (g, W, H, ms, hour, opts = {}) {
    const S = build(W, H);
    const oy = S.oy, ox = Math.floor((W - 192) / 2);
    const frame = Math.floor(ms / 83);
    const { bottom, light } = IP.skyAt(hour);
    const night = 1 - light;
    const R = (c, x, y, w, h) => { g.fillStyle = typeof c === "string" ? c : css(c); g.fillRect(x, y, w, h); };
    const shade = (c, k = 0.62) => mixRGB(hexRGB(c), [10, 12, 30], night * k);
    const skyH = oy + 66;

    g.imageSmoothingEnabled = false;
    g.drawImage(paintSky(W, skyH, hour), 0, 0);
    if (night > 0.3) for (const [x, y, p] of S.stars) if ((frame + Math.floor(p * 40)) % 37 > 2) R(p > 0.8 ? "#fff3c4" : "#c9cde8", x, y, 1, 1);

    const arc = (t) => [Math.round(12 + t * (W - 24)), Math.round(oy + 40 - Math.sin(t * Math.PI) * (oy + 32))];
    if (hour >= 5.8 && hour <= 18.4) {
      const [sx, sy] = arc((hour - 5.8) / 12.6);
      R("#fff1b8", sx - 2, sy - 1, 5, 3); R("#fff1b8", sx - 1, sy - 2, 3, 5); R("#ffd166", sx - 1, sy - 1, 3, 3);
    } else {
      const t = ((hour < 12 ? hour + 24 : hour) - 18.4) / 11.4;
      const [mx, my] = arc(Math.min(1, Math.max(0, t)));
      R("#f4efd9", mx - 2, my - 1, 4, 3); R("#f4efd9", mx - 1, my - 2, 2, 5); R(css(bottom), mx, my - 1, 2, 2);
    }
    if (light > 0.2) {
      const sp = opts.cloudsSpeed == null ? 900 : opts.cloudsSpeed;
      for (const [cx, cy, cw] of S.clouds) {
        const x = Math.round(((cx + ms / sp) % (W + 40)) - 20);
        g.globalAlpha = 0.85 * light;
        R("#ffffff", x + 2, cy, cw - 4, 2); R("#ffffff", x, cy + 2, cw, 2); R("#dfe8f2", x + 1, cy + 4, cw - 2, 1);
        g.globalAlpha = 1;
      }
    }
    // far skyline
    const far = mixRGB(bottom, [20, 18, 32], 0.45 + night * 0.3);
    const baseY = oy + 64;
    for (const [x, w, hh] of S.skyline) R(far, x, baseY - hh, w, hh);
    if (night > 0.4) for (const [x, w, hh] of S.skyline) if ((x * 7) % 5 === 0) R("#e8c46a", x + 2, baseY - hh + 3, 1, 1);

    // trees
    const leaf = shade("#2f6b3a"), leafHi = shade("#3f8a4a");
    const treeXs = [10, 22, 164, 178];
    for (let k = 1; ox - 14 * k > -12; k++) { treeXs.push(10 - 14 * k, 22 - 14 * k - 3); }
    for (let k = 1; 192 + 14 * k < W - ox + 12; k++) { treeXs.push(164 + 14 * k + 8, 178 + 14 * k + 3); }
    for (const tx0 of treeXs) {
      const tx = tx0 + ox;
      R(shade("#4a3222"), tx + 3, oy + 54, 2, 10); R(leaf, tx, oy + 46, 8, 8); R(leaf, tx - 1, oy + 48, 10, 4); R(leafHi, tx + 1, oy + 46, 3, 2);
    }
    // main building
    const wall = shade("#6d0e1f", 0.55), wallDk = shade("#560a19", 0.55), trim = shade("#c9a227", 0.35);
    const X = (x) => x + ox, Y = (y) => y + oy;
    R(wall, X(32), Y(42), 128, 23); R(wallDk, X(32), Y(62), 128, 3); R(trim, X(32), Y(41), 128, 1);
    R(wall, X(80), Y(32), 32, 33); R(trim, X(80), Y(31), 32, 1);
    for (let s = 0; s < 4; s++) R(s === 3 ? trim : wall, X(84 + s * 3), Y(27 - s), 24 - s * 6, 4);
    R(trim, X(94), Y(22), 4, 1);
    R(shade("#d9d2c0"), X(104), Y(16), 1, 11);
    R("#7a1128", X(105), Y(16 + (frame % 12 < 6 ? 0 : 1)), 5, 2); R("#f2c14e", X(105), Y(18 + (frame % 12 < 6 ? 0 : 1)), 5, 1);
    const lit = opts.lit == null ? -1 : opts.lit;
    WINDOWS.forEach(([x, y, w, hh], i) => {
      let c = shade("#2a0a10", 0.3);
      if (night > 0.4 && S.nightLit[i % 64]) c = "#e8c46a";
      if (i === lit) c = frame % 16 < 12 ? "#ffd75e" : "#f2b233";
      R(c, X(x), Y(y), w, hh);
    });
    for (let c = 0; c < 3; c++) R(night > 0.4 && c === 1 ? "#e8c46a" : shade("#2a0a10", 0.3), X(86 + c * 8), Y(36), 4, 7);
    for (let c = 0; c < 5; c++) R(shade("#e9dcc4", 0.5), X(84 + c * 6), Y(52), 2, 12);
    if (lit >= 0) { const [x, y] = WINDOWS[lit]; g.globalAlpha = 0.25 + 0.15 * Math.sin(ms / 400); R("#ffd75e", X(x) - 1, Y(y) - 1, 4, 5); g.globalAlpha = 1; }
    // obelisk
    R(shade("#e8e1cf", 0.5), X(94), Y(30), 4, 36); R(shade("#bdb49f", 0.5), X(96), Y(30), 2, 36); R(shade("#e8e1cf", 0.5), X(95), Y(27), 2, 3); R(shade("#8f877a", 0.5), X(91), Y(64), 10, 3);
    // plaza, grass, road (full width)
    R(shade("#8a8074", 0.6), 0, Y(65), W, 3); R(shade("#3c6b3a"), 0, Y(68), W, 3); R(shade("#2e2e33", 0.3), 0, Y(71), W, 9);
    for (let x = 0; x < W; x += 12) R(shade("#b9a86a", 0.4), x, Y(75), 6, 1);
    // jeepney (explicit position, or the app's slow pass)
    let jx = null;
    if (opts.jeepX != null) jx = Math.round(opts.jeepX);
    else if (opts.jeepCycle !== false) { const cyc = (ms / 16000) % 1; if (cyc < 0.55) jx = Math.round(-20 + (cyc / 0.55) * (W + 40)); }
    if (jx != null) {
      const bob = frame % 4 < 2 ? 0 : 1;
      IP.JEEP.forEach((row, y) => { for (let x = 0; x < row.length; x++) { const c = IP.JEEP_COLORS[row[x]]; if (c) R(y === 6 ? c : css(mixRGB(hexRGB(c), [10, 12, 30], night * 0.35)), jx + x, Y(71 + y - (y < 6 ? bob : 0)), 1, 1); } });
      if (night > 0.4) R("#fff1b8", jx + 18, Y(74), 3, 1);
    }
  };

  // ---------- the dithered maroon->gold swirl (canvas) ----------
  IP.drawSwirl = function (cv, t, opts = {}) {
    const ctx = cv.getContext("2d");
    const w = cv.width, h = cv.height;
    const img = ctx.createImageData(w, h), d = img.data;
    const speed = opts.speed == null ? 1 : opts.speed, lit = opts.lit == null ? 1 : opts.lit, bias = opts.bias == null ? 0.35 : opts.bias;
    const tt = t * 1.15 * speed;
    const PALc = IP.C.swirl.map(hexRGB);
    for (let j = 0; j < h; j++) for (let i = 0; i < w; i++) {
      const x = i * 0.19, y = j * 0.135;
      const n = Math.sin(x * 1.3 + Math.sin(y * 1.1 + tt) * 1.8 + tt * 0.7) + Math.sin(y * 1.7 + Math.sin(x * 0.9 - tt * 0.8) * 1.6) + Math.sin((x + y) * 0.8 + tt * 0.5);
      let v = (n + 3) / 6;
      const u = i / w - 0.5;
      v += bias * Math.exp(-u * u * 9) * (0.35 + 0.4 * (j / h)) - 0.12;
      v = Math.max(0, Math.min(0.999, v)) * lit;
      const f = v * 4, base = Math.floor(f), frac = f - base;
      const idx = base + (frac > (BAYER[j & 3][i & 3] + 0.5) / 16 ? 1 : 0);
      const c = PALc[Math.min(4, idx)], o = (j * w + i) * 4;
      d[o] = c[0]; d[o + 1] = c[1]; d[o + 2] = c[2]; d[o + 3] = 255;
    }
    ctx.putImageData(img, 0, 0);
  };
})();

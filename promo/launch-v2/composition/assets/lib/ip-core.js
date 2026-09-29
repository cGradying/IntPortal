/* IntPortal trailer core: palette, rng, colour, pixel sprites (Isko, jeepney, icons), rooms.
   Deterministic: nothing here reads a clock or Math.random. */
(function () {
  const IP = (window.IP = window.IP || {});

  // ---------- rng / colour ----------
  IP.rng = function (seed) {
    let a = seed | 0;
    return function () {
      a = (a + 0x6d2b79f5) | 0;
      let t = Math.imul(a ^ (a >>> 15), 1 | a);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  };
  IP.hex = (h) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  IP.toHex = (c) => "#" + c.map((v) => Math.round(v).toString(16).padStart(2, "0")).join("");
  IP.mix = (a, b, t) => {
    const A = IP.hex(a), B = IP.hex(b);
    return IP.toHex(A.map((v, i) => v + (B[i] - v) * t));
  };
  IP.lerp = (a, b, t) => a + (b - a) * t;
  IP.clamp = (v, lo = 0, hi = 1) => Math.min(hi, Math.max(lo, v));
  IP.ease = {
    out3: (t) => 1 - Math.pow(1 - t, 3),
    in3: (t) => t * t * t,
    io: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  };

  // Pixelify Sans' "C" has a hairline aperture that extruded text-shadows fill in (CAMPUS -> OAMPUS). Wrap each C so CSS can re-open it.
  IP.cfix = (str) => str.split(/(<[^>]+>)/).map((p, i) => (i % 2 ? p : p.replace(/C/g, '<span class="cc">C</span>'))).join("");
  IP.cfixEl = (el) => { if (el) el.innerHTML = IP.cfix(el.innerHTML); return el; };

  // brand
  IP.C = {
    void: "#07050A", obs: "#170B1A", obsHi: "#34203F", obsFleck: "#4A2C58", obsLo: "#060307",
    maroon: "#6D0E1F", maroon2: "#560A19", gold: "#C9A227", goldBright: "#F5B227", cream: "#F7ECEC",
    swirl: ["#170509", "#540A1C", "#941C30", "#CCA128", "#FAEBB3"],
    night: "#19191c",
  };
  IP.BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];

  // ---------- sprites ----------
  IP.ISKO_COLORS = {
    h: "#1d1717", H: "#3a2f2c", f: "#e0a77c", F: "#c4865c", e: "#1d1717", m: "#9b4a3c", M: "#5a1f1f",
    w: "#f4f1ea", W: "#cfc8bb", r: "#7a1128", g: "#f2c14e", i: "#f2c14e", p: "#2c3346", P: "#1f2433", k: "#141414",
  };
  const BODY = [
    "..rrWwgwwWrr..", ".WwwwwgwwwwwW.", ".WwwwwgwwwwwW.", ".FWwwwiiwwwWF.", "..Wwwwiiwwww..",
    "..WwwwwwwwwW..", "..pppppppppp..", "..ppppP.pppp..", "..pppp..pppp..", "..Pppp..Pppp..", ".kkkkk..kkkkk.",
  ];
  const HEAD = [
    "....hhhhhh....", "...hHHhhhhh...", "..hhhhhhhhhh..", "..hhffffffhh..", "..hffeffefhh..",
    "...ffffffff...", "...ffffffff...", "....fffmff....", ".....FffF.....",
  ];
  const F = {};
  F.stand = HEAD.concat(BODY);
  F.wave = [
    "....hhhhhh..f.", "...hHHhhhhh.f.", "..hhhhhhhhhhf.", "..hhffffffhhW.", "..hffeffefhhW.",
    "...ffffffff.W.", "...ffffffffWW.", "....fffmff.W..", ".....FffF.W...",
    "..rrWwgwwWrr..", ".WwwwwgwwwwW..", ".WwwwwgwwwwW..", ".FWwwwiiwwwW..",
  ].concat(BODY.slice(4));
  // arms-up (jump / cheer): mirrored raised arm, legs tucked
  const UP = [
    ".f..hhhhhh..f.", ".f.hHHhhhhh.f.", ".fhhhhhhhhhhf.", ".WhhffffffhhW.", ".WhffeffefhhW.",
    ".W.ffffffff.W.", ".WWffffffffWW.", "..W.fffmff.W..", "...W.FffF.W...",
    "..rrWwgwwWrr..", "..WwwgwwwwwW..".replace("..WwwgwwwwwW..", "..WwwwgwwwwW.."), "..WwwwgwwwwW..", "..WwwwiiwwwW..",
    "..Wwwwiiwwww..", "..WwwwwwwwwW..", "..pppppppppp..", "..pppp..pppp..", "..Pppp..Pppp..", ".kkkkk..kkkkk.", "..............",
  ];
  F.jump = UP;
  F.cheer = UP.map((r, i) => (i === 7 ? "..W.ffMMff.W.." : r));
  // running: two-pose stride (art bob is applied by the caller)
  const RUN_A = ["..pppppppppp..", ".pppP...pppp..", ".pppp....pppp.", ".Pppp.....Pppp", "kkkkk.....kkkk"];
  const RUN_B = ["..pppppppppp..", "..ppppP.pppp..", "..pppp..pppp..", "..Pppp..kkkk..", ".kkkkk........"];
  F.runA = HEAD.concat(BODY.slice(0, 6), RUN_A);
  F.runB = HEAD.concat(BODY.slice(0, 6), RUN_B);
  // thinking: eyes look up
  F.think = F.stand.map((r, i) => (i === 3 ? "..hhfeffefhh.." : i === 4 ? "..hfffffffhh.." : r));
  // sleepy: heavy lids
  F.sleepy = F.stand.map((r, i) => (i === 3 ? "..hhfFffFfhh.." : r));
  // seen from behind (walks into the portal)
  F.back = F.stand.map((r, i) => {
    if (i === 3 || i === 4) return "..hhhhhhhhhh..";
    if (i === 5 || i === 6) return "...hhhhhhhh...";
    if (i === 7) return "....hhhhhh....";
    if (i === 9) return "..rrWwwwwWrr..";
    if (i === 10 || i === 11) return ".WwwwwwwwwwwW.";
    if (i === 12) return ".FWwwwwwwwwWF.";
    if (i === 13) return "..Wwwwwwwwww..";
    return r;
  });
  IP.ISKO = F;

  IP.JEEP = ["....gggggggggg....", "...wwwwwwwwwwwww..", "..wbbwbbwbbwbbrr..", "..rrrrrrrrrrrrrrss", "..yyyyyyyyyyyyyyss", "..rrrrrrrrrrrrrrrs", "...kk........kk..."];
  IP.JEEP[2] = "..wbbwbbwbbwbbrr..";
  IP.JEEP_COLORS = { g: "#c9a227", w: "#e9e4d6", b: "#2c3e57", r: "#b3202a", y: "#f2c14e", s: "#c7ccd3", k: "#141414" };

  IP.FLAME = ["...#...", "..##...", "..###..", ".####..", ".#####.", "###.##.", "##..###", "##...##", ".#####."];
  IP.CHECK = ["M0 2h1v1h1v1h1V3h1V2h1V1h1V0h1v1H6v1H5v1H4v1H3v1H2V4H1V3H0z"];

  IP.ICONS = {
    today: ["....#.#.....", "....##......".replace("....##......", ".....##....."), ".#...##...#.", "..#......#..", "....####....", "...#++++#...", "##.#++++#.##", "##.#++++#.##", "...#++++#...", "....####....", "..#......#..", ".#...##...#."],
    schedule: ["..#.....#...", "############", "############", "#..........#", "#.##.##.##.#", "#.##.##.##.#", "#..........#", "#.##.##.++.#", "#.##.##.++.#", "#..........#", "############", "............"],
    grades: [".....##.....", "...######...", ".##########.", "############", ".##########.", "...######.+.", "...######.+.", "....####..+.", "..........+.", ".........+++", ".........+++", "............"],
    you: ["....####....", "...######...", "...######...", "...######...", "....####....", "............", "..########..", ".##########.", ".####++####.", ".##########.", ".##########.", "............"],
    study: ["............", "...#########", "...#.......#", "#########..#", "#.......#..#", "#.+++++.#..#", "#.......#..#", "#.####..#..#", "#.......####", "#.###...#...", "#.......#...", "#########..."],
    sync: ["....####....", "..##....##..", ".#........#.", ".#......###.", "#........#..", "#...........", "...........#", "..#........#", ".###......#.", ".#........#.", "..##....##..", "....####...."],
  };
  // the sun icon the app uses for Today
  IP.ICONS.today = [".....##.....", ".#...##...#.", "..#......#..", "....####....", "...#++++#...", "##.#++++#.##", "##.#++++#.##", "...#++++#...", "....####....", "..#......#..", ".#...##...#.", ".....##....."];

  // sprite -> <canvas> (crisp). colors: map char -> css colour
  IP.spriteCanvas = function (rows, colors, scale = 1, flip = false) {
    const w = rows[0].length, h = rows.length;
    const cv = document.createElement("canvas");
    cv.width = w * scale; cv.height = h * scale;
    const g = cv.getContext("2d");
    IP.drawSprite(g, rows, colors, 0, 0, scale, flip);
    return cv;
  };
  IP.drawSprite = function (g, rows, colors, x, y, s = 1, flip = false, alpha = 1) {
    const w = rows[0].length;
    g.globalAlpha = alpha;
    for (let j = 0; j < rows.length; j++) {
      const row = rows[j];
      for (let i = 0; i < w; i++) {
        const ch = row[flip ? w - 1 - i : i];
        const c = colors[ch];
        if (!c) continue;
        g.fillStyle = c;
        g.fillRect(x + i * s, y + j * s, s, s);
      }
    }
    g.globalAlpha = 1;
  };
  // sprite -> inline SVG string (for DOM use, crisp at any size)
  IP.spriteSVG = function (rows, colors, opts = {}) {
    const w = rows[0].length, h = rows.length;
    let s = `<svg viewBox="0 0 ${w} ${h}" shape-rendering="crispEdges" xmlns="http://www.w3.org/2000/svg"${opts.cls ? ` class="${opts.cls}"` : ""}>`;
    for (let j = 0; j < h; j++) {
      let i = 0;
      while (i < w) {
        const ch = rows[j][i];
        const c = colors[ch];
        if (!c) { i++; continue; }
        let k = i + 1;
        while (k < w && rows[j][k] === ch) k++;
        s += `<rect x="${i}" y="${j}" width="${k - i}" height="1" fill="${c}"/>`;
        i = k;
      }
    }
    return s + "</svg>";
  };
  IP.iconSVG = function (name, size = 24, color = "currentColor", accent = "#f5b227") {
    const rows = IP.ICONS[name];
    let s = `<svg width="${size}" height="${size}" viewBox="0 0 12 12" shape-rendering="crispEdges">`;
    rows.forEach((row, y) => [...row].forEach((c, x) => {
      if (c === "#") s += `<rect x="${x}" y="${y}" width="1" height="1" fill="${color}"/>`;
      else if (c === "+") s += `<rect x="${x}" y="${y}" width="1" height="1" fill="${accent}"/>`;
    }));
    return s + "</svg>";
  };

  // ---------- rooms (themes): port of the app's rooms.ts ----------
  const lum = (h) => {
    const [r, g, b] = IP.hex(h).map((v) => { const s = v / 255; return s <= 0.03928 ? s / 12.92 : ((s + 0.055) / 1.055) ** 2.4; });
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  };
  const contrast = (a, b) => { const [x, y] = [lum(a), lum(b)].sort((p, q) => q - p); return (x + 0.05) / (y + 0.05); };
  const push = (fg, bg, ratio, toward) => { let c = fg; for (let i = 1; i <= 20 && contrast(c, bg) < ratio; i++) c = IP.mix(fg, toward, i / 20); return c; };
  const alpha = (h, a) => `${h}${Math.round(a * 255).toString(16).padStart(2, "0")}`;
  IP.ROOMS_HAND = {
    night: { name: "Night", "--ground": "#19191c", "--ground-2": "#202024", "--card": "#26262a", "--card-2": "#2d2d32", "--sunk": "#1f1f23", "--edge": "rgba(255,255,255,.07)", "--edge-2": "rgba(255,255,255,.13)", "--ink": "#efeff1", "--ink-2": "#a9a9b1", "--ink-3": "#7c7c85", "--gold": "#f5b227", "--gold-soft": "rgba(245,178,39,.14)", "--on-gold": "#1b1406", "--maroon": "#7a1128", "--good": "#58c792", "--bad": "#f07a6e", "--island": "#0e0e10", "--dot": "rgba(245,178,39,.07)", "--s1": "#e0697e", "--s2": "#e8866f", "--s3": "#e0b04a", "--s4": "#b58ad0", "--s5": "#5fbf9c", "--s6": "#7ea3e0", dark: true },
    day: { name: "Day", "--ground": "#f4f2ef", "--ground-2": "#ebe8e3", "--card": "#ffffff", "--card-2": "#f8f6f3", "--sunk": "#efece7", "--edge": "rgba(28,21,23,.08)", "--edge-2": "rgba(28,21,23,.16)", "--ink": "#1c1517", "--ink-2": "#554c4f", "--ink-3": "#766c6f", "--gold": "#b8860b", "--gold-soft": "rgba(201,162,39,.16)", "--on-gold": "#ffffff", "--maroon": "#6d0e1f", "--good": "#1e7249", "--bad": "#b42318", "--island": "#1c1517", "--dot": "rgba(122,17,40,.07)", "--s1": "#7a1128", "--s2": "#b13e34", "--s3": "#8f6410", "--s4": "#5c315f", "--s5": "#2e5a4f", "--s6": "#3f517a", dark: false },
    maroon: { name: "Maroon Night", "--ground": "#1a0a0e", "--ground-2": "#230d13", "--card": "#2a1016", "--card-2": "#34141c", "--sunk": "#200c11", "--edge": "rgba(255,220,200,.08)", "--edge-2": "rgba(255,220,200,.15)", "--ink": "#f7ecec", "--ink-2": "#ddb9be", "--ink-3": "#a98289", "--gold": "#f2c14e", "--gold-soft": "rgba(242,193,78,.14)", "--on-gold": "#2a0d06", "--maroon": "#6d0e1f", "--good": "#6fd3a0", "--bad": "#ff8a7a", "--island": "#0d0507", "--dot": "rgba(245,178,39,.08)", "--s1": "#ff8fa3", "--s2": "#ffa38a", "--s3": "#f2c14e", "--s4": "#d4a5f0", "--s5": "#7fe0bd", "--s6": "#9dbcf5", dark: true },
  };
  IP.PALETTES = {
    pupMaroon: { name: "PUP Maroon", accent: "#7a1128", canvasTop: "#fcfbfa", canvasBottom: "#f2edec", panel: "#140608", onPanel: "#fcfbfa", subjects: ["#7a1128", "#b13e34", "#a37314", "#5c315f", "#2e5a4f", "#3f517a"] },
    ivory: { name: "Ivory", accent: "#343c51", canvasTop: "#fdfbf6", canvasBottom: "#f6f2ea", panel: "#212125", onPanel: "#fdfbf6", subjects: ["#343c51", "#b46047", "#a37e32", "#734f6a", "#536d4f", "#3e7377"] },
    astraMoon: { name: "Astra Moon", accent: "#10b981", canvasTop: "#0e1525", canvasBottom: "#060c18", panel: "#060a13", onPanel: "#f1f6fa", subjects: ["#10b981", "#06969c", "#51a3ec", "#8b73ec", "#ec9d3e", "#e96983"] },
    sakura: { name: "Sakura", accent: "#e0417e", canvasTop: "#fff7fa", canvasBottom: "#fce9f0", panel: "#210816", onPanel: "#fff7fa", subjects: ["#e0417e", "#f16d66", "#8b51a2", "#c9a227", "#378b85", "#343c51"] },
    monochrome: { name: "Monochrome", accent: "#111111", canvasTop: "#ffffff", canvasBottom: "#f2f2f2", panel: "#111111", onPanel: "#ffffff", subjects: ["#1a1a1a", "#3d3d3d", "#5c5c5c", "#7a7a7a", "#999999", "#b8b8b8"] },
    matrix: { name: "Matrix", accent: "#00ff41", canvasTop: "#0d0f0d", canvasBottom: "#000000", panel: "#000000", onPanel: "#00ff41", subjects: ["#00ff41", "#00e5d4", "#ffb000", "#008f11", "#d3d3d3", "#28ad85"] },
    dracula: { name: "Dracula", accent: "#bd93f9", canvasTop: "#282a36", canvasBottom: "#1d1f28", panel: "#14151b", onPanel: "#f8f8f2", subjects: ["#bd93f9", "#ff79c6", "#8be9fd", "#50fa7b", "#ffb86c", "#ff5555"] },
    nord: { name: "Nord", accent: "#88c0d0", canvasTop: "#2e3440", canvasBottom: "#252933", panel: "#1b1e25", onPanel: "#eceff4", subjects: ["#88c0d0", "#81a1c1", "#5d81ac", "#a3be8c", "#ebcb8b", "#b48ead"] },
    gruvbox: { name: "Gruvbox", accent: "#fabd2f", canvasTop: "#282828", canvasBottom: "#1d2021", panel: "#191919", onPanel: "#ebdbb2", subjects: ["#fabd2f", "#b8bb26", "#83a598", "#d3869b", "#fb4934", "#af80ca"] },
    solarizedDark: { name: "Solarized Dark", accent: "#268bd2", canvasTop: "#073642", canvasBottom: "#002b36", panel: "#052932", onPanel: "#eee8d5", subjects: ["#268bd2", "#849900", "#d53682", "#b58900", "#2aa198", "#6d71c4"] },
    solarizedLight: { name: "Solarized Light", accent: "#268bd2", canvasTop: "#fdf6e3", canvasBottom: "#eee8d5", panel: "#073642", onPanel: "#eee8d5", subjects: ["#268bd2", "#849900", "#d53682", "#b58900", "#2aa198", "#6d71c4"] },
    tokyoNight: { name: "Tokyo Night", accent: "#7aa2f7", canvasTop: "#1a1b26", canvasBottom: "#12131b", panel: "#0e0f16", onPanel: "#c5cae6", subjects: ["#7aa2f7", "#bd92f9", "#6ad8ef", "#9dcd6d", "#e09860", "#f7768e"] },
    catppuccin: { name: "Catppuccin", accent: "#cba6f7", canvasTop: "#2e2f40", canvasBottom: "#1e1e2e", panel: "#171825", onPanel: "#cdd6f4", subjects: ["#cba6f7", "#f4c2d8", "#92e1fa", "#a6e3a1", "#fab387", "#f38ba8"] },
    oneDark: { name: "One Dark", accent: "#61afef", canvasTop: "#2c2e34", canvasBottom: "#212227", panel: "#1b1c20", onPanel: "#abb2bf", subjects: ["#61afef", "#c678dd", "#56b6c2", "#98c379", "#d19a66", "#e06c75"] },
  };
  IP.derive = function (p) {
    const dark = lum(p.canvasBottom) < 0.3;
    const ground = p.canvasBottom;
    const card = dark ? IP.mix(p.canvasTop, "#ffffff", 0.05) : IP.mix(p.canvasTop, "#ffffff", 0.7);
    const card2 = dark ? IP.mix(p.canvasTop, "#ffffff", 0.09) : IP.mix(p.canvasTop, "#ffffff", 0.9);
    const inkBase = dark ? (lum(p.onPanel) > 0.3 ? p.onPanel : "#f2f2f2") : p.panel;
    const far = dark ? "#ffffff" : "#000000";
    const ink = push(inkBase, card, 7, far);
    const gold = push(p.accent, card, 3, far);
    const onGold = contrast("#ffffff", gold) >= contrast("#111111", gold) ? "#ffffff" : "#111111";
    const r = {
      name: p.name, dark,
      "--ground": ground, "--ground-2": p.canvasTop, "--dot": alpha(p.accent, 0.09), "--card": card, "--card-2": card2,
      "--sunk": IP.mix(ground, dark ? "#000000" : p.panel, 0.06), "--edge": alpha(ink, 0.08), "--edge-2": alpha(ink, 0.16), "--ink": ink,
      "--ink-2": push(IP.mix(ink, card, 0.3), card, 4.5, ink), "--ink-3": push(IP.mix(ink, card, 0.48), card, 3, ink),
      "--gold": gold, "--gold-soft": alpha(gold, 0.16), "--on-gold": onGold, "--maroon": p.accent, "--maroon-2": IP.mix(p.accent, far, 0.15),
      "--good": dark ? "#58c792" : "#1e7249", "--bad": dark ? "#f07a6e" : "#b42318", "--island": dark ? IP.mix(p.panel, "#000000", 0.3) : p.panel,
    };
    p.subjects.forEach((s, i) => (r[`--s${i + 1}`] = push(s, card, 3, far)));
    return r;
  };
  IP.room = function (id) {
    if (IP.ROOMS_HAND[id]) return IP.ROOMS_HAND[id];
    return IP.derive(IP.PALETTES[id]);
  };
  IP.applyRoom = function (el, id) {
    const r = IP.room(id);
    for (const k in r) if (k.startsWith("--")) el.style.setProperty(k, r[k]);
    el.dataset.dark = r.dark ? "1" : "0";
    return r;
  };
})();

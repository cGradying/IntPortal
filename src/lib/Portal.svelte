<script lang="ts">
  // The landing scene, ported from docs/legacy/specs/prototypes/intportal-v3.html
  // (drawScene, frame, block, platform, figure, the WebGL swirl, warp) and
  // re-framed for a portrait phone. The student stands before an obsidian
  // frame that builds block by block, then ignites into a dithered
  // maroon-to-gold swirl. Stepping through warps into the app.
  import { onMount } from "svelte";

  let {
    rest = "signin",
    busy = false,
    onwarped,
    warp = $bindable(),
  }: {
    rest?: "signin" | "hub";
    busy?: boolean;
    onwarped?: () => void;
    warp?: () => void;
  } = $props();

  let host: HTMLDivElement;
  let cv: HTMLCanvasElement;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;

  const clamp = (v: number, a = 0, b = 1) => Math.min(b, Math.max(a, v));
  const PERIM: [number, number][] = (() => {
    const p: [number, number][] = [];
    for (let c = 0; c < 6; c++) p.push([c, 7]);
    for (let r = 6; r >= 0; r--) p.push([5, r]);
    for (let c = 4; c >= 0; c--) p.push([c, 0]);
    for (let r = 1; r <= 6; r++) p.push([0, r]);
    return p;
  })();
  const FIG = ["..hhhh..", "..hhhh..", "..hhhh..", "...ss...", ".mmmmmm.", "mmmmmmmm", "m.mmmm.m", "s.mmmm.s", "..pppp..", "..p..p..", "..p..p..", "..k..k.."];
  const FIGC: Record<string, string> = { h: "#1A1012", s: "#B9805F", m: "#7A1128", p: "#222840", k: "#0D090B" };

  // Deterministic seeds, so the frame's speckle never shimmers between frames.
  let seed = 7;
  const rnd = () => ((seed = (seed * 16807) % 2147483647) / 2147483647);
  const seeds = Array.from({ length: 200 }, rnd);
  const motes = Array.from({ length: 60 }, () => ({ x: rnd(), y: rnd(), v: 0.01 + rnd() * 0.03, s: rnd() < 0.3 ? 2 : 1, g: rnd() < 0.35 }));

  const S = { state: "intro" as "intro" | "rest" | "warp" | "off", t0: 0, formed: 0, lit: 0, zoom: 1, speed: 1, glScale: 3, shift: 0, flash: 0 };
  let flash = $state(0);

  warp = () => {
    if (S.state !== "rest") return;
    S.state = "warp";
    S.t0 = performance.now();
  };

  onMount(() => {
    const ctx = cv.getContext("2d")!;
    let W = 0, H = 0, dpr = 1, raf = 0;

    const glc = document.createElement("canvas");
    const gl = glc.getContext("webgl", { antialias: false, preserveDrawingBuffer: true });
    let prog: WebGLProgram | null = null;
    let uR: WebGLUniformLocation | null = null, uT: WebGLUniformLocation | null = null, uS: WebGLUniformLocation | null = null, uL: WebGLUniformLocation | null = null;
    if (gl) {
      const vs = "attribute vec2 p;void main(){gl_Position=vec4(p,0.,1.);}";
      const fs = `precision mediump float;uniform vec2 r;uniform float t,s,l;
      float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
      float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
      float fbm(vec2 p){float v=0.,a=.5;for(int k=0;k<4;k++){v+=a*n(p);p*=2.03;a*=.5;}return v;}
      float b2(vec2 a){a=floor(a);return fract(a.x/2.+a.y*a.y*.75);}
      float bay(vec2 a){return b2(.5*a)*.25+b2(a);}
      void main(){
        vec2 uv=(gl_FragCoord.xy-.5*r)/r.y;float d=length(uv*vec2(1.25,.8));
        float a=atan(uv.y,uv.x)+t*.28*s+d*3.2;
        vec2 q=vec2(cos(a),sin(a))*d*2.4;
        float v=fbm(q*2.2+vec2(0.,-t*.5*s));
        v+=.22*sin(uv.x*16.+fbm(uv*3.+t*.25*s)*7.+t*1.6*s);
        v=v*.95+(.55-d)*.55;
        v=clamp(v,0.,1.)*l;
        float lv=v*4.+bay(gl_FragCoord.xy)-.5;float k=clamp(floor(lv),0.,4.);
        vec3 c=k<.5?vec3(.09,.02,.05):k<1.5?vec3(.33,.04,.11):k<2.5?vec3(.58,.11,.19):k<3.5?vec3(.80,.63,.16):vec3(.98,.92,.70);
        gl_FragColor=vec4(c,1.);}`;
      const sh = (type: number, src: string) => {
        const o = gl.createShader(type)!;
        gl.shaderSource(o, src);
        gl.compileShader(o);
        return o;
      };
      prog = gl.createProgram()!;
      gl.attachShader(prog, sh(gl.VERTEX_SHADER, vs));
      gl.attachShader(prog, sh(gl.FRAGMENT_SHADER, fs));
      gl.linkProgram(prog);
      if (!gl.getProgramParameter(prog, gl.LINK_STATUS)) prog = null;
      else {
        gl.useProgram(prog);
        const b = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, b);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
        const loc = gl.getAttribLocation(prog, "p");
        gl.enableVertexAttribArray(loc);
        gl.vertexAttribPointer(loc, 2, gl.FLOAT, false, 0, 0);
        uR = gl.getUniformLocation(prog, "r");
        uT = gl.getUniformLocation(prog, "t");
        uS = gl.getUniformLocation(prog, "s");
        uL = gl.getUniformLocation(prog, "l");
      }
    }

    // Plain 2D swirl for a webview without WebGL.
    const fb = document.createElement("canvas");
    const pal = ["#170509", "#540A1C", "#941C30", "#CCA128", "#FAEBB3"];
    const BAYER = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]];
    function swirl(w: number, h: number, t: number, s: number, lit: number): HTMLCanvasElement {
      if (gl && prog) {
        if (glc.width !== w || glc.height !== h) {
          glc.width = w;
          glc.height = h;
          gl.viewport(0, 0, w, h);
        }
        gl.uniform2f(uR, w, h);
        gl.uniform1f(uT, t);
        gl.uniform1f(uS, s);
        gl.uniform1f(uL, lit);
        gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
        return glc;
      }
      fb.width = w;
      fb.height = h;
      const g = fb.getContext("2d")!;
      for (let y = 0; y < h; y++)
        for (let x = 0; x < w; x++) {
          const u = x / w - 0.5, v = y / h - 0.5, d = Math.hypot(u * 1.2, v * 0.8);
          const val = clamp(0.5 + 0.3 * Math.sin(Math.atan2(v, u) * 3 + d * 12 - t * s) + (0.5 - d) * 0.6) * lit;
          g.fillStyle = pal[clamp(Math.floor(val * 4 + BAYER[y & 3][x & 3] / 16 - 0.5), 0, 4)];
          g.fillRect(x, y, 1, 1);
        }
      return fb;
    }

    function size() {
      const r = host.getBoundingClientRect();
      dpr = Math.min(3, devicePixelRatio || 1);
      W = r.width;
      H = r.height;
      cv.width = Math.round(W * dpr);
      cv.height = Math.round(H * dpr);
    }

    function geom() {
      // Hub: a big portal low on the screen. Sign-in: smaller and higher,
      // between the wordmark and the sheet.
      const hub = Math.min(W / 10.5, H / 22);
      const signin = Math.min(W / 15, H / 33);
      const B = Math.max(10, Math.round(hub + (signin - hub) * S.shift));
      const baseY = Math.round(H * (0.64 - 0.2 * S.shift));
      return { B, cx: Math.round(W / 2), baseY, top: baseY - 8 * B };
    }

    function block(x: number, y: number, B: number, i: number) {
      ctx.fillStyle = "#170B1A";
      ctx.fillRect(x, y, B, B);
      const u = Math.max(2, Math.round(B / 8));
      ctx.fillStyle = "#34203F";
      ctx.fillRect(x, y, B, u);
      ctx.fillRect(x, y, u, B);
      ctx.fillStyle = "#060307";
      ctx.fillRect(x, y + B - u, B, u);
      ctx.fillRect(x + B - u, y, u, B);
      ctx.fillStyle = "#4A2C58";
      for (let k = 0; k < 3; k++) {
        const a = seeds[(i * 7 + k * 13) % 200], b = seeds[(i * 11 + k * 17) % 200];
        ctx.fillRect(x + u + Math.floor(a * (B - 3 * u)), y + u + Math.floor(b * (B - 3 * u)), u, u);
      }
    }

    function frame(g: ReturnType<typeof geom>, t: number) {
      const { B } = g, fx = g.cx - 3 * B;
      const full = Math.floor(S.formed), frac = S.formed - full;
      for (let i = 0; i < Math.min(PERIM.length, Math.ceil(S.formed)); i++) {
        const [c, r] = PERIM[i];
        let y = g.top + r * B;
        if (i === full) {
          ctx.globalAlpha = frac;
          y -= (1 - frac) * B * 1.6;
        }
        block(fx + c * B, y, B, i);
        ctx.globalAlpha = 1;
      }
      if (S.lit > 0) {
        const iw = 4 * B, ih = 6 * B, ix = g.cx - 2 * B, iy = g.top + B;
        const glow = ctx.createRadialGradient(g.cx, iy + ih / 2, B, g.cx, iy + ih / 2, B * 7);
        glow.addColorStop(0, `rgba(201,162,39,${0.22 * S.lit})`);
        glow.addColorStop(1, "rgba(201,162,39,0)");
        ctx.globalCompositeOperation = "lighter";
        ctx.fillStyle = glow;
        ctx.fillRect(g.cx - B * 7, iy + ih / 2 - B * 7, B * 14, B * 14);
        ctx.globalCompositeOperation = "source-over";
        const src = swirl(Math.max(8, Math.round(iw / S.glScale)), Math.max(12, Math.round(ih / S.glScale)), t, S.speed, S.lit);
        ctx.imageSmoothingEnabled = false;
        ctx.drawImage(src, ix, iy, iw, ih);
      }
    }

    function platform(g: ReturnType<typeof geom>) {
      const a = Math.round(g.B * 0.95), d = Math.round(g.B * 0.7), n = 5;
      const ox = g.cx, oy = g.baseY - a * 2;
      for (let s = 0; s <= 2 * (n - 1); s++)
        for (let i = 0; i < n; i++) {
          const j = s - i;
          if (j < 0 || j >= n) continue;
          const x = ox + (i - j) * a, y = oy + ((i + j) * a) / 2, k = seeds[(i * 5 + j) % 200];
          const glow = S.lit * clamp(1 - Math.hypot(i - 1.5, j - 1.5) / 3.2);
          ctx.fillStyle = `rgb(${38 + k * 10 + glow * 70},${26 + k * 6 + glow * 40},${34 + k * 8 + glow * 8})`;
          ctx.beginPath();
          ctx.moveTo(x, y);
          ctx.lineTo(x + a, y + a / 2);
          ctx.lineTo(x, y + a);
          ctx.lineTo(x - a, y + a / 2);
          ctx.closePath();
          ctx.fill();
          if (i === n - 1) {
            ctx.fillStyle = "#1D1217";
            ctx.beginPath();
            ctx.moveTo(x + a, y + a / 2);
            ctx.lineTo(x, y + a);
            ctx.lineTo(x, y + a + d);
            ctx.lineTo(x + a, y + a / 2 + d);
            ctx.fill();
          }
          if (j === n - 1) {
            ctx.fillStyle = "#291921";
            ctx.beginPath();
            ctx.moveTo(x - a, y + a / 2);
            ctx.lineTo(x, y + a);
            ctx.lineTo(x, y + a + d);
            ctx.lineTo(x - a, y + a / 2 + d);
            ctx.fill();
          }
        }
    }

    function figure(g: ReturnType<typeof geom>) {
      const u = Math.max(2, Math.round(g.B / 5));
      const x0 = Math.round(g.cx - 4 * u), y0 = g.baseY + Math.round(g.B * 0.55) - 12 * u;
      FIG.forEach((row, y) => {
        for (let x = 0; x < 8; x++) {
          const c = FIGC[row[x]];
          if (c) {
            ctx.fillStyle = c;
            ctx.fillRect(x0 + x * u, y0 + y * u, u, u);
          }
        }
      });
    }

    function draw(now: number) {
      const t = reduce ? 1.5 : now / 1000;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      const bg = ctx.createLinearGradient(0, 0, 0, H);
      bg.addColorStop(0, "#07050A");
      bg.addColorStop(1, "#12070E");
      ctx.fillStyle = bg;
      ctx.fillRect(0, 0, W, H);
      const g = geom();
      const ix = g.cx, iy = g.top + g.B + 3 * g.B;
      ctx.setTransform(dpr * S.zoom, 0, 0, dpr * S.zoom, dpr * (ix - ix * S.zoom), dpr * (iy - iy * S.zoom));
      for (const m of motes) {
        if (!reduce) {
          m.y -= (m.v * (S.state === "warp" ? 6 : 1)) / 60;
          if (m.y < 0) {
            m.y = 1;
            m.x = rnd();
          }
        }
        let x = m.x * W;
        const y = m.y * H;
        if (m.g && S.lit > 0) x += (ix - x) * 0.08 * S.lit;
        ctx.fillStyle = m.g ? `rgba(230,196,90,${0.25 + 0.5 * S.lit})` : "rgba(170,150,170,.35)";
        ctx.fillRect(Math.round(x), Math.round(y), m.s * 2, m.s * 2);
      }
      platform(g);
      frame(g, t);
      figure(g);
    }

    function tick(now: number) {
      if (S.state === "off") return;
      const e = now - S.t0;
      if (S.state === "intro") {
        S.formed = reduce ? PERIM.length : clamp((e - 400) / 1200) * PERIM.length;
        S.lit = reduce ? 1 : clamp((e - 1700) / 500);
        if (e > (reduce ? 0 : 2300)) {
          S.state = "rest";
          S.formed = PERIM.length;
          S.lit = 1;
        }
      }
      const wantShift = rest === "signin" && S.state !== "warp" ? 1 : 0;
      S.shift += (wantShift - S.shift) * (reduce ? 1 : 0.1);
      if (S.state !== "warp") S.speed += ((busy ? 2.4 : 1) - S.speed) * 0.05;
      if (S.state === "warp") {
        const p = clamp(e / 950);
        S.zoom = reduce ? 1 : 1 + Math.pow(p, 2.6) * 11;
        S.speed = 1 + p * 8;
        S.glScale = 3 + p * 10;
        flash = reduce ? 1 : clamp((p - 0.82) / 0.1);
        if (e > (reduce ? 220 : 1080)) {
          S.state = "off";
          draw(now);
          onwarped?.();
          return;
        }
      }
      draw(now);
      raf = requestAnimationFrame(tick);
    }

    S.shift = rest === "signin" ? 1 : 0;
    size();
    const ro = new ResizeObserver(size);
    ro.observe(host);
    S.t0 = performance.now();
    raf = requestAnimationFrame(tick);
    const skip = () => {
      if (S.state === "intro") S.t0 -= 5000;
    };
    host.addEventListener("pointerdown", skip);
    const vis = () => {
      cancelAnimationFrame(raf);
      if (!document.hidden && S.state !== "off") raf = requestAnimationFrame(tick);
    };
    document.addEventListener("visibilitychange", vis);
    return () => {
      cancelAnimationFrame(raf);
      ro.disconnect();
      host.removeEventListener("pointerdown", skip);
      document.removeEventListener("visibilitychange", vis);
    };
  });
</script>

<div class="portal" bind:this={host}>
  <canvas bind:this={cv}></canvas>
  <div class="flash" style:opacity={flash}></div>
</div>

<style>
  .portal {
    position: absolute;
    inset: 0;
    overflow: hidden;
    background: #07050a;
  }
  canvas {
    width: 100%;
    height: 100%;
    display: block;
  }
  .flash {
    position: absolute;
    inset: 0;
    pointer-events: none;
    background: radial-gradient(circle at 50% 45%, #fffbe8, #f5d98a 45%, #c9a227);
  }
</style>

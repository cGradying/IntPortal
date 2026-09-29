/* IntPortal 3D voxel world (Three.js r158, low-res render, flat pixel-art shading).
   Deterministic: every transform is a pure function of time passed in by the scene. */
(function () {
  const IP = window.IP;
  const T = window.THREE;
  T.ColorManagement.enabled = false;   // keep sprite hex colours exactly as authored

  const V3 = (x, y, z) => new T.Vector3(x, y, z);

  IP.createWorld = function (canvas, W, H, opts = {}) {
    const renderer = new T.WebGLRenderer({ canvas, antialias: false, alpha: true, preserveDrawingBuffer: true });
    renderer.outputColorSpace = T.LinearSRGBColorSpace;
    renderer.useLegacyLights = true;      // classic light units: ambient+key ~ 1.0 keeps sprite colours true
    renderer.setPixelRatio(1);
    renderer.setSize(W, H, false);
    renderer.setClearColor(opts.clear == null ? 0x07050a : opts.clear, opts.transparent ? 0 : 1);
    const scene = new T.Scene();
    const camera = new T.PerspectiveCamera(opts.fov || 32, W / H, 0.1, 400);
    const key = new T.DirectionalLight(0xffffff, 0.55);
    key.position.set(4, 8, 6);
    scene.add(key, new T.AmbientLight(0xffffff, 0.72));
    const world = { renderer, scene, camera, W, H, key, res: [W, H], update: null };
    world.setRes = function (w, h) {
      w = Math.max(8, Math.round(w)); h = Math.max(8, Math.round(h));
      if (w === world.res[0] && h === world.res[1]) return;
      world.res = [w, h];
      renderer.setSize(w, h, false);
      camera.aspect = w / h;
      camera.updateProjectionMatrix();
    };
    world.render = function (t) {
      if (world.update) world.update(t);
      renderer.render(scene, camera);
    };
    return world;
  };

  // ---------- materials ----------
  IP.lambert = (color, extra) => new T.MeshLambertMaterial(Object.assign({ color, flatShading: true }, extra || {}));
  const BOX = new T.BoxGeometry(1, 1, 1);
  const _m = new T.Matrix4(), _c = new T.Color(), _q = new T.Quaternion(), _s = new T.Vector3(1, 1, 1), _p = new T.Vector3();

  // Instanced cubes from a list of {x,y,z,c,s?}
  IP.cubes = function (list, mat) {
    const mesh = new T.InstancedMesh(BOX, mat || IP.lambert(0xffffff), list.length);
    list.forEach((v, i) => {
      _p.set(v.x, v.y, v.z);
      const s = v.s == null ? 1 : v.s;
      _s.set(v.sx || s, v.sy || s, v.sz || s);
      _m.compose(_p, _q, _s);
      mesh.setMatrixAt(i, _m);
      _c.set(v.c);
      mesh.setColorAt(i, _c);
    });
    mesh.instanceMatrix.needsUpdate = true;
    if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    return mesh;
  };

  // ---------- extrude a sprite grid into voxels ----------
  // rows: sprite rows; colors: char->hex; opts: {depth, x0,x1,y0,y1, back:(ch)=>ch, zc}
  IP.extrude = function (rows, colors, o = {}) {
    const d = o.depth || 5;
    const x0 = o.x0 || 0, x1 = o.x1 == null ? rows[0].length - 1 : o.x1, y0 = o.y0 || 0, y1 = o.y1 == null ? rows.length - 1 : o.y1;
    const w = rows[0].length, h = rows.length;
    const list = [];
    for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) {
      const ch = rows[y][x];
      if (!colors[ch]) continue;
      for (let k = 0; k < d; k++) {
        const front = k === d - 1;
        let c = colors[ch];
        if (!front && o.back) { const bc = o.back(ch, k, d); c = colors[bc] || c; }
        list.push({ x: x - w / 2 + 0.5, y: h - y - 0.5, z: k - d / 2 + 0.5, c });
      }
    }
    return IP.cubes(list);
  };

  // ---------- Isko, a voxel figurine extruded from the app's 14x20 sprite ----------
  IP.makeIsko = function () {
    const S = IP.ISKO.stand, C = IP.ISKO_COLORS;
    const root = new T.Group();
    const parts = {};
    const skin = { f: 1, F: 1, e: 1, m: 1, M: 1 };
    // head (rows 0-8), hair wraps the back and sides
    const head = IP.extrude(S, C, { depth: 8, y0: 0, y1: 8, x0: 2, x1: 11, back: (ch, k, d) => (skin[ch] && k < d - 2 ? "h" : ch) });
    const headG = new T.Group(); headG.add(head); headG.position.set(0, 0, 0); parts.head = headG;
    // torso (rows 9-14, cols 2-11): polo, collar, lanyard + ID on the front only
    const torso = IP.extrude(S, C, { depth: 5, y0: 9, y1: 14, x0: 2, x1: 11, back: (ch, k, d) => (ch === "g" || ch === "i" ? "w" : ch) });
    const torsoG = new T.Group(); torsoG.add(torso); parts.torso = torsoG;
    // legs (rows 15-19), two independent legs
    const legs = {};
    [[2, 5, "L"], [8, 11, "R"]].forEach(([a, b, k]) => {
      const leg = IP.extrude(S, C, { depth: 4, y0: 15, y1: 19, x0: a, x1: b });
      const g = new T.Group(); g.add(leg);
      // pivot at the hip
      leg.position.set(0, 0, 0);
      legs[k] = g; parts["leg" + k] = g;
    });
    // arms: 2x6 sleeve + hand, pivot at the shoulder
    const arm = (sx) => {
      const g = new T.Group();
      const list = [];
      for (let j = 0; j < 4; j++) for (let i = 0; i < 2; i++) for (let k = 0; k < 2; k++) list.push({ x: i, y: -j, z: k, c: C.w });
      list.push({ x: 0, y: -4, z: 0, c: C.f }, { x: 1, y: -4, z: 0, c: C.f }, { x: 0, y: -4, z: 1, c: C.F }, { x: 1, y: -4, z: 1, c: C.F });
      const m = IP.cubes(list);
      m.position.set(sx > 0 ? 0.5 : -1.5, 0, -0.5);
      g.add(m);
      return g;
    };
    const armL = arm(-1), armR = arm(1); parts.armL = armL; parts.armR = armR;
    // backpack with a tiny portal on it (Isko carries his portal)
    const bp = new T.Group();
    const bl = [];
    for (let y = 0; y < 8; y++) for (let x = 0; x < 6; x++) {
      const ring = x === 0 || x === 5 || y === 0 || y === 7;
      bl.push({ x: x - 2.5, y: y - 3.5, z: 0, c: ring ? "#34203f" : ["#941c30", "#cca128", "#540a1c", "#faebb3"][(x * 3 + y * 5) % 4] });
    }
    const bpm = IP.cubes(bl); bp.add(bpm); parts.pack = bp;
    // assemble (units: 1 voxel = 1 unit; sprite is 14 wide x 20 tall)
    const H = 20;
    headG.position.set(0, 0, 0);
    torsoG.position.set(0, 0, 0);
    // sprite space -> figure space: each part keeps sprite-y so we only need pivots
    legs.L.position.set(0, 0, 0); legs.R.position.set(0, 0, 0);
    armL.position.set(-5.5, H - 10.5, 0); armR.position.set(5.5, H - 10.5, 0);
    bp.position.set(0, H - 12.5, -3.4); bp.scale.setScalar(0.62);
    // hip/neck pivots by wrapping in groups
    const wrap = (g, px, py) => { const w = new T.Group(); w.position.set(px, py, 0); g.position.set(-px, -py, 0); w.add(g); return w; };
    const figure = new T.Group();
    const hipY = H - 15;      // y of the hip line (sprite row 15 -> y = 5)
    const legLw = wrap(legs.L, -2.2, hipY), legRw = wrap(legs.R, 2.2, hipY);
    const headW = wrap(headG, 0, H - 9);
    figure.add(torsoG, headW, legLw, legRw, armL, armR, bp);
    figure.position.y = -H / 2;
    root.add(figure);
    root.userData = { figure, headW, legLw, legRw, armL, armR, torsoG, bp };
    // pose: t (seconds), mode, params -> transforms. All pure.
    root.pose = function (mode, t, p = {}) {
      const u = root.userData;
      const bob = Math.sin(t * 6.3) * 0.25;
      u.figure.position.y = -H / 2;
      u.figure.rotation.set(0, 0, 0);
      u.headW.rotation.set(0, 0, 0);
      u.legLw.rotation.set(0, 0, 0); u.legRw.rotation.set(0, 0, 0);
      u.armL.rotation.set(0, 0, 0); u.armR.rotation.set(0, 0, 0);
      u.armL.position.y = u.armR.position.y = H - 10.5;
      if (mode === "idle") {
        u.figure.position.y += bob * 0.5;
        u.headW.rotation.y = Math.sin(t * 1.7) * 0.15;
        u.armL.rotation.z = -0.05 + Math.sin(t * 2) * 0.03; u.armR.rotation.z = 0.05 - Math.sin(t * 2) * 0.03;
      } else if (mode === "run") {
        const ph = t * (p.rate || 11);
        const s = Math.sin(ph);
        u.legLw.rotation.x = s * 0.85; u.legRw.rotation.x = -s * 0.85;
        u.armL.rotation.x = -s * 0.9; u.armR.rotation.x = s * 0.9;
        u.figure.position.y += Math.abs(Math.sin(ph)) * 0.9;
        u.figure.rotation.z = Math.sin(ph) * 0.05;
        u.figure.rotation.x = 0.08;
      } else if (mode === "wave") {
        u.figure.position.y += bob * 0.4;
        u.armR.rotation.z = 2.55 + Math.sin(t * 13) * 0.35;       // right arm up, waving
        u.armR.rotation.x = 0;
        u.headW.rotation.y = Math.sin(t * 2.2) * 0.1;
        u.headW.rotation.z = -0.05;
      } else if (mode === "jump") {
        const q = p.q == null ? 0.5 : p.q;                          // 0..1 through the jump
        const up = Math.sin(Math.PI * q);
        u.figure.position.y += up * (p.h || 5);
        const squash = q < 0.15 ? 1 - (0.15 - q) * 2.4 : q > 0.9 ? 1 - (q - 0.9) * 2.4 : 1 + up * 0.12;
        u.figure.scale.set(1 / Math.sqrt(squash), squash, 1 / Math.sqrt(squash));
        u.armL.rotation.z = -2.6 * up; u.armR.rotation.z = 2.6 * up;
        u.legLw.rotation.x = -0.5 * up; u.legRw.rotation.x = -0.5 * up;
      } else if (mode === "cheer") {
        const up = Math.abs(Math.sin(t * 9));
        u.figure.position.y += up * 1.6;
        u.armL.rotation.z = -2.7 + Math.sin(t * 18) * 0.25; u.armR.rotation.z = 2.7 - Math.sin(t * 18) * 0.25;
      } else if (mode === "sleepy") {
        u.figure.position.y += Math.sin(t * 1.3) * 0.2;
        u.headW.rotation.x = 0.22 + Math.sin(t * 1.3) * 0.05;
        u.headW.rotation.z = 0.08;
      }
      if (mode !== "jump") u.figure.scale.set(1, 1, 1);
    };
    return root;
  };

  // ---------- jeepney (extruded from the 18x7 sprite) with spinning wheels ----------
  IP.makeJeep = function () {
    const root = new T.Group();
    const body = IP.extrude(IP.JEEP, Object.assign({}, IP.JEEP_COLORS, { k: null }), { depth: 8, y0: 0, y1: 6, back: (ch, k, d) => (ch === "b" ? "w" : ch) });
    root.add(body);
    const wheels = [];
    const wm = IP.lambert(0x141414);
    const cyl = new T.CylinderGeometry(1.35, 1.35, 1.1, 8);
    [-5.0, 5.0].forEach((x) => {
      [1, -1].forEach((side) => {
        const w = new T.Mesh(cyl, wm);
        w.rotation.z = Math.PI / 2;
        w.position.set(x, 1.0, side * 4.05);
        root.add(w); wheels.push(w);
      });
    });
    root.wheels = wheels;
    root.spin = (t) => wheels.forEach((w) => (w.rotation.x = -t * 14));
    return root;
  };


  // ---------- IntAssis "thinking cube": 3x3x3 gold voxels that breathe + orbiting satellites ----------
  IP.makeCube = function (o = {}) {
    const root = new T.Group();
    const mat = IP.lambert(0xffffff);
    const vox = [];
    const N = 3, gap = o.gap == null ? 1.08 : o.gap;
    for (let x = 0; x < N; x++) for (let y = 0; y < N; y++) for (let z = 0; z < N; z++) {
      const cx = x - 1, cy = y - 1, cz = z - 1;
      const core = cx === 0 && cy === 0 && cz === 0;
      const edge = Math.abs(cx) + Math.abs(cy) + Math.abs(cz);
      const hi = (-cx * 0.4 + cy * 0.7 + cz * 0.55);
      const c = core ? "#faebb3" : IP.mix("#cca128", "#faebb3", IP.clamp(0.35 + hi * 0.28 - (edge - 1) * 0.06));
      const m = IP.cubes([{ x: 0, y: 0, z: 0, c, s: 0.94 }], mat);
      m.position.set(cx * gap, cy * gap, cz * gap);
      root.add(m); vox.push({ m, cx, cy, cz, core });
    }
    const sats = [];
    for (let i = 0; i < 4; i++) { const m = IP.cubes([{ x: 0, y: 0, z: 0, c: i % 2 ? "#faebb3" : "#f5b227", s: 0.42 }], mat); root.add(m); sats.push(m); }
    root.vox = vox; root.sats = sats;
    // t: seconds; think: 0..1 how hard it is "thinking"; pop: 0..1 kick scale
    root.pose = function (t, think = 0, pop = 0) {
      root.rotation.set(0.5 + Math.sin(t * 1.3) * 0.15 + think * t * 1.7, t * (0.9 + think * 2.6), 0.18);
      const s = 1 + pop * 0.5;
      root.scale.setScalar(s);
      vox.forEach((v, i) => {
        const k = 1 + Math.sin(t * (3 + think * 6) + i * 0.9) * (0.07 + think * 0.16);
        v.m.scale.setScalar(v.core ? 0.9 + 0.3 * Math.sin(t * 6 + 1) * think : k);
      });
      sats.forEach((m, i) => {
        const a = t * (1.4 + think * 2.2) + i * Math.PI / 2, r = 3.2 + Math.sin(t * 2 + i) * 0.25;
        m.position.set(Math.cos(a) * r, Math.sin(a * 0.7 + i) * 1.1, Math.sin(a) * r);
        m.rotation.set(t * 3 + i, t * 2, 0);
      });
    };
    return root;
  };

  // ---------- portal frame: 24 obsidian blocks + swirl plane ----------
  const SWIRL_FRAG = `precision mediump float;varying vec2 vUv;uniform float t,lit,cell;uniform vec2 res;
  float h(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
  float n(vec2 p){vec2 i=floor(p),f=fract(p);f=f*f*(3.-2.*f);return mix(mix(h(i),h(i+vec2(1,0)),f.x),mix(h(i+vec2(0,1)),h(i+vec2(1,1)),f.x),f.y);}
  float fbm(vec2 p){float v=0.,a=.5;for(int k=0;k<4;k++){v+=a*n(p);p*=2.03;a*=.5;}return v;}
  float b2(vec2 a){a=floor(a);return fract(a.x/2.+a.y*a.y*.75);}
  float bay(vec2 a){return b2(.5*a)*.25+b2(a);}
  void main(){
    vec2 uv=vUv-.5; float d=length(uv*vec2(1.25,.8));
    float a=atan(uv.y,uv.x)+t*.28+d*3.2; vec2 q=vec2(cos(a),sin(a))*d*2.4;
    float v=fbm(q*2.2+vec2(0.,-t*.5));
    v+=.22*sin(uv.x*16.+fbm(uv*3.+t*.25)*7.+t*1.6);
    v=v*.95+(.55-d)*.55; v=clamp(v,0.,1.)*lit;
    float lv=v*4.+bay(floor(gl_FragCoord.xy/cell))-.5; float k=clamp(floor(lv),0.,4.);
    vec3 c=k<.5?vec3(.09,.02,.05):k<1.5?vec3(.33,.04,.11):k<2.5?vec3(.58,.11,.19):k<3.5?vec3(.80,.63,.16):vec3(.98,.92,.70);
    gl_FragColor=vec4(c,1.);}`;
  IP.makePortal = function (o = {}) {
    const root = new T.Group();
    const r = IP.rng(o.seed || 5);
    const blocks = [];
    const order = [];
    // DESIGN order: bottom row, right column up, top row left, left column down
    for (let c = 0; c < 6; c++) order.push([c, 7]);
    for (let rr = 6; rr >= 1; rr--) order.push([5, rr]);
    for (let c = 5; c >= 0; c--) order.push([c, 0]);
    for (let rr = 1; rr <= 6; rr++) order.push([0, rr]);
    const mat = IP.lambert(0xffffff);
    order.forEach(([c, rr], i) => {
      const g = new T.Group();
      const jit = 0.94 + r() * 0.06;
      const base = IP.mix("#34203f", "#170b1a", 0.25 + r() * 0.35);
      const list = [{ x: 0, y: 0, z: 0, c: base, s: 0.98 }];
      // bevel: lighter top-left edge strip, darker bottom-right, flecks
      list.push({ x: 0, y: 0.44, z: 0.5, c: "#4d2f5a", sx: 0.98, sy: 0.12, sz: 0.06 });
      list.push({ x: -0.44, y: 0, z: 0.5, c: "#4d2f5a", sx: 0.12, sy: 0.98, sz: 0.06 });
      list.push({ x: 0, y: -0.44, z: 0.5, c: "#120912", sx: 0.98, sy: 0.12, sz: 0.06 });
      list.push({ x: 0.44, y: 0, z: 0.5, c: "#120912", sx: 0.12, sy: 0.98, sz: 0.06 });
      for (let k = 0; k < 3; k++) list.push({ x: (r() - 0.5) * 0.6, y: (r() - 0.5) * 0.6, z: 0.5, c: r() < 0.4 ? "#5f3c6d" : "#170b1a", s: 0.14, sz: 0.08 });
      g.add(IP.cubes(list, mat));
      g.position.set(c - 2.5, 3.5 - rr, 0);
      root.add(g); blocks.push({ g, home: g.position.clone(), c, rr, i });
    });
    const uni = { t: { value: 0 }, lit: { value: 1 }, cell: { value: 1 }, res: { value: new T.Vector2(1, 1) } };
    const sm = new T.ShaderMaterial({ uniforms: uni, vertexShader: "varying vec2 vUv;void main(){vUv=uv;gl_Position=projectionMatrix*modelViewMatrix*vec4(position,1.);}", fragmentShader: SWIRL_FRAG });
    const swirl = new T.Mesh(new T.PlaneGeometry(4, 6), sm);
    swirl.position.z = -0.1;
    root.add(swirl);
    root.blocks = blocks; root.swirl = swirl; root.uni = uni;
    return root;
  };

  // ---------- isometric platform ----------
  IP.makePlatform = function (n = 5, tile = 1.9) {
    const g = new T.Group();
    const r = IP.rng(3);
    const list = [];
    for (let i = 0; i < n; i++) for (let j = 0; j < n; j++) {
      const k = r();
      const glow = Math.max(0, 1 - Math.hypot(i - (n - 1) / 2, j - (n - 1) / 2) / 3.2);
      const col = IP.toHex([38 + k * 10 + glow * 70, 26 + k * 6 + glow * 40, 34 + k * 8 + glow * 8]);
      list.push({ x: (i - (n - 1) / 2) * tile, y: -0.35, z: (j - (n - 1) / 2) * tile, c: col, sx: tile * 0.97, sy: 0.7, sz: tile * 0.97 });
    }
    g.add(IP.cubes(list));
    return g;
  };

  // ---------- motes (square points) ----------
  IP.makeMotes = function (count, spread, seed = 7) {
    const r = IP.rng(seed);
    const pos = new Float32Array(count * 3), col = new Float32Array(count * 3);
    const base = [];
    for (let i = 0; i < count; i++) {
      base.push([(r() - 0.5) * spread[0], (r() - 0.5) * spread[1], (r() - 0.5) * spread[2], 0.2 + r() * 0.8, r() * 6.28]);
      const gold = r() < 0.6;
      const c = new T.Color(gold ? "#e6c45a" : r() < 0.5 ? "#941c30" : "#c9cde8");
      col.set([c.r, c.g, c.b], i * 3);
    }
    const geo = new T.BufferGeometry();
    geo.setAttribute("position", new T.BufferAttribute(pos, 3));
    geo.setAttribute("color", new T.BufferAttribute(col, 3));
    const pts = new T.Points(geo, new T.PointsMaterial({ size: 2, sizeAttenuation: false, vertexColors: true }));
    pts.userData.step = (t) => {
      for (let i = 0; i < count; i++) {
        const b = base[i];
        pos[i * 3] = b[0] + Math.sin(t * 0.4 + b[4]) * 0.6;
        pos[i * 3 + 1] = ((b[1] + spread[1] / 2 + t * b[3] * 0.5) % spread[1]) - spread[1] / 2;
        pos[i * 3 + 2] = b[2];
      }
      geo.attributes.position.needsUpdate = true;
    };
    pts.userData.step(0);
    return pts;
  };

  // pixel bitmap (array of strings, '#' = on) -> voxels
  IP.bitmapVoxels = function (rows, colorAt, depth = 3) {
    const list = [];
    const h = rows.length, w = rows[0].length;
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      if (rows[y][x] !== "#") continue;
      for (let k = 0; k < depth; k++) list.push({ x: x - w / 2 + 0.5, y: h / 2 - y - 0.5, z: k - depth / 2 + 0.5, c: colorAt(x, y, k) });
    }
    return list;
  };
})();

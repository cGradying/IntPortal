// Square sparks in the room's colours, with gravity (spec 045 C17). One canvas
// over the app, freed when the last spark is gone. Nothing under Reduce Motion.
interface Spark {
  x: number;
  y: number;
  vx: number;
  vy: number;
  c: string;
  s: number;
  age: number;
  life: number;
}

let cv: HTMLCanvasElement | null = null;
let sparks: Spark[] = [];

export function burst(x: number, y: number, n: number, power = 1) {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
  const vars = getComputedStyle(document.documentElement);
  const colors = ["--gold", "--s3", "--s1", "--ink", "--good"].map((v) => vars.getPropertyValue(v).trim() || "#f5b227");
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2 + Math.random() * 0.5;
    const v = (70 + Math.random() * 80) * power;
    sparks.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v - 50 * power, c: colors[i % colors.length], s: i % 3 ? 2 : 3, age: 0, life: 0.45 + 0.25 * power + Math.random() * 0.2 });
  }
  if (cv) return;
  const c = (cv = document.createElement("canvas"));
  const dpr = Math.min(devicePixelRatio, 3);
  const [w, h] = [innerWidth, innerHeight];
  c.width = Math.round(w * dpr);
  c.height = Math.round(h * dpr);
  c.setAttribute("aria-hidden", "true");
  c.style.cssText = "position:fixed;inset:0;width:100%;height:100%;z-index:75;pointer-events:none";
  document.body.append(c);
  const g = c.getContext("2d");
  if (!g) return c.remove();
  let last = performance.now();
  const tick = (now: number) => {
    const dt = Math.min(0.033, (now - last) / 1000);
    last = now;
    g.setTransform(dpr, 0, 0, dpr, 0, 0);
    g.clearRect(0, 0, w, h);
    sparks = sparks.filter((q) => (q.age += dt) < q.life);
    for (const q of sparks) {
      q.vy += 320 * dt;
      q.vx *= 0.97;
      q.x += q.vx * dt;
      q.y += q.vy * dt;
      g.globalAlpha = Math.max(0, 1 - q.age / q.life);
      g.fillStyle = q.c;
      g.fillRect(Math.round(q.x), Math.round(q.y), q.s, q.s);
    }
    if (sparks.length) requestAnimationFrame(tick);
    else {
      c.remove();
      cv = null;
    }
  };
  requestAnimationFrame(tick);
}

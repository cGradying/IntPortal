// Dev only. Renders every scene into the page, and exposes timing for the perf budget.
import { build, type SceneDef } from "../../src/lib/campus/paint";
import { startStrip } from "../../src/lib/campus/render";
import { PUP_CAMPUSES, loadScene } from "../../src/lib/campus/scenes";
import { school } from "../../src/lib/campus/scenes/school";
import { litWindow } from "../../src/lib/campus/sky";

export const HOURS = [6, 12, 18.5, 22];
const label = (h: number) => `${String(Math.floor(h)).padStart(2, "0")}:${String(Math.round((h % 1) * 60)).padStart(2, "0")}`;

async function scenes(): Promise<SceneDef[]> {
  const pup = await Promise.all(PUP_CAMPUSES.map((n) => loadScene(n)));
  return [...pup, school({ id: "earist", name: "EARIST", accent: "#f0a33a", ramp: ["#3a0f0f", "#7a1c1c"], motif: "bloom" }), school({ id: "rtu", name: "RTU", accent: "#5aa0e6", ramp: ["#0d2240"], motif: "lattice" })];
}

declare global {
  interface Window {
    sheet(force?: "webgl2" | "webgl" | "2d"): Promise<{ id: string; urls: string[] }[]>;
    perf(force?: "webgl2" | "webgl"): Promise<{ buildMs: number; firstFrameMs: number; mode: string }>;
  }
}

window.sheet = async (force) => {
  const root = document.getElementById("sheet")!;
  root.innerHTML = `<div class="row head"><span></span>${HOURS.map((h) => `<span>${label(h)}</span>`).join("")}</div>`;
  const out = [];
  // One canvas, one context: Chromium keeps only so many alive.
  const cv = document.createElement("canvas");
  for (const def of await scenes()) {
    const b = build(def);
    const row = document.createElement("div");
    row.className = "row";
    row.innerHTML = `<span>${def.label}</span>`;
    root.append(row);
    const urls = [];
    for (const h of HOURS) {
      // 5 s into the loop puts the jeepney mid-street.
      const s = startStrip(cv, b, { lit: litWindow("COMP 20073", b.windows), hour: () => h, keep: true, force });
      s.draw(5000);
      s.stop();
      const img = new Image();
      img.src = cv.toDataURL("image/png");
      row.append(img);
      urls.push(img.src);
    }
    out.push({ id: def.id, urls });
  }
  return out;
};

window.perf = async (force) => {
  const def = await loadScene("Sta. Mesa");
  const t0 = performance.now();
  const b = build(def);
  const t1 = performance.now();
  const cv = document.createElement("canvas");
  document.body.append(cv);
  const s = startStrip(cv, b, { lit: 3, hour: () => 12, force });
  // Read one pixel back so the GPU has really finished the first frame.
  const gl = (cv.getContext(s.mode === "webgl2" ? "webgl2" : "webgl") as WebGLRenderingContext | null);
  gl?.readPixels(0, 0, 1, 1, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array(4));
  const t2 = performance.now();
  s.stop();
  return { buildMs: t1 - t0, firstFrameMs: t2 - t1, mode: s.mode };
};

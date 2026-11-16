// Dev only. Draws the README banner and campus frames with the app's own renderer.
import "../../src/lib/app.css";
import { build } from "../../src/lib/campus/paint";
import { startStrip } from "../../src/lib/campus/render";
import { loadScene } from "../../src/lib/campus/scenes";
import { litWindow } from "../../src/lib/campus/sky";

declare global {
  interface Window {
    banner(ms?: number): Promise<void>;
    frames(name: string, shots: { hour: number; ms: number }[]): Promise<string[]>;
  }
}

let built: ReturnType<typeof build> | null = null;
window.banner = async (ms = 5000) => {
  await document.fonts.ready;
  const cv = document.getElementById("scene") as HTMLCanvasElement;
  built ??= build(await loadScene("Sta. Mesa"));
  const s = startStrip(cv, built, { lit: litWindow("COMP 20073", built.windows), hour: () => 19.5, keep: true });
  s.draw(ms);
  s.stop();
};

window.frames = async (name, shots) => {
  const b = build(await loadScene(name));
  const cv = document.createElement("canvas");
  const out: string[] = [];
  for (const { hour, ms } of shots) {
    const s = startStrip(cv, b, { lit: litWindow("COMP 20073", b.windows), hour: () => hour, keep: true });
    s.draw(ms);
    s.stop();
    out.push(cv.toDataURL("image/png"));
  }
  return out;
};

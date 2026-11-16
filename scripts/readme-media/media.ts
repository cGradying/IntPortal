// Dev only. Draws the README banner and campus frames with the app's own renderer.
import "../../src/lib/app.css";
import { build } from "../../src/lib/campus/paint";
import { startStrip } from "../../src/lib/campus/render";
import { loadScene } from "../../src/lib/campus/scenes";
import { litWindow } from "../../src/lib/campus/sky";

declare global {
  interface Window {
    banner(): Promise<void>;
    frames(name: string, shots: { hour: number; ms: number }[]): Promise<string[]>;
  }
}

async function paint(cv: HTMLCanvasElement, name: string, hour: number, ms: number) {
  const b = build(await loadScene(name));
  const s = startStrip(cv, b, { lit: litWindow("COMP 20073", b.windows), hour: () => hour, keep: true });
  s.draw(ms);
  s.stop();
}

window.banner = async () => {
  await document.fonts.ready;
  await paint(document.getElementById("scene") as HTMLCanvasElement, "Sta. Mesa", 19.5, 5000);
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

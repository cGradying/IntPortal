// Film entry: window.seek(t) paints frame t. Scenes are listed in paint
// order; each has a beat window [from, to) on the measured grid and a
// stateless render().
import { bt, loadBeats, tb } from "./lib/core.js";
import { beginFrame, initGL } from "./art/gl.js";
import { initCampus } from "./art/campus.js";
import open from "./scenes/open.js";
import magnet from "./scenes/magnet.js";
import ios from "./scenes/ios.js";
import editrooms from "./scenes/editrooms.js";
import platforms from "./scenes/platforms.js";
import sync from "./scenes/sync.js";
import drop from "./scenes/drop.js";
import ai from "./scenes/ai.js";
import hub from "./scenes/hub.js";
import faceid from "./scenes/faceid.js";
import flash from "./scenes/flash.js";

const SCENES = [magnet, hub, open, ios, editrooms, platforms, sync, drop, ai, faceid, flash];

async function init() {
  await loadBeats();
  await document.fonts.load("800 40px Montserrat");
  await document.fonts.load("400 20px 'Source Sans 3'");
  await document.fonts.load("600 20px 'Source Sans 3'");
  await document.fonts.load("700 20px 'Source Sans 3'");
  await document.fonts.load("500 20px 'Pixelify Sans'");
  await document.fonts.load("700 20px 'Pixelify Sans'");
  await document.fonts.ready;
  initGL();
  initCampus();
  const dom = document.getElementById("dom");
  const fx = document.getElementById("fx");
  for (const s of SCENES) {
    s.layer = document.createElement("div");
    s.layer.className = "layer";
    s.layer.dataset.scene = s.id;
    (s.top ? fx : dom).appendChild(s.layer);
    await s.init(s.layer);
  }
  window.DURATION = tb(244) + 1.6;
  window.seek = seek;
  seek(0);
  window.__ready = true;
}

function seek(t) {
  const b = bt(t);
  let cell = 1;
  for (const s of SCENES) if (b >= s.from && b < s.to && s.cell) cell = Math.max(cell, s.cell(b));
  beginFrame(cell);
  for (const s of SCENES) {
    const on = b >= s.from && b < s.to;
    s.layer.style.display = on ? "block" : "none";
    if (on) s.render(b, t);
  }
}

init();

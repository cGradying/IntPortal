// The sound kit (spec 045 C19): synthesised, so it adds nothing to the app.
// Off by default, a switch in You. Each note is detuned a little at random, so
// the hundredth tap doesn't sound like the first.
import { noteHz } from "./doneRun";

function stored(): boolean {
  try {
    return localStorage.getItem("sound") === "1";
  } catch {
    return false;
  }
}

export const sound = { on: stored() };

export function setSound(on: boolean) {
  sound.on = on;
  try {
    localStorage.setItem("sound", on ? "1" : "0");
  } catch {
    // Remembered for this session only.
  }
}

let ctx: AudioContext | null = null;
function audio(): AudioContext | null {
  if (!sound.on || matchMedia("(prefers-reduced-motion: reduce)").matches) return null;
  try {
    ctx ??= new AudioContext();
    if (ctx.state === "suspended") void ctx.resume();
    return ctx;
  } catch {
    return null;
  }
}

const detune = () => 2 ** ((Math.random() - 0.5) * 0.02);

function pluck(a: AudioContext, hz: number, at: number, dur: number, type: OscillatorType = "triangle", vol = 0.07) {
  const o = a.createOscillator();
  const g = a.createGain();
  o.type = type;
  o.frequency.value = hz * detune();
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(vol, at + 0.004);
  g.gain.exponentialRampToValueAtTime(0.0001, at + dur);
  o.connect(g).connect(a.destination);
  o.start(at);
  o.stop(at + dur + 0.02);
}

function click(a: AudioContext, at: number, hz = 3200, vol = 0.22) {
  const n = a.createBuffer(1, Math.round(a.sampleRate * 0.012), a.sampleRate);
  const d = n.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = (Math.random() * 2 - 1) * (1 - i / d.length) ** 3;
  const s = a.createBufferSource();
  const bp = a.createBiquadFilter();
  const g = a.createGain();
  bp.type = "bandpass";
  bp.frequency.value = hz * detune();
  bp.Q.value = 1.4;
  g.gain.value = vol;
  s.buffer = n;
  s.connect(bp).connect(g).connect(a.destination);
  s.start(at);
}

function thump(a: AudioContext, at: number) {
  const o = a.createOscillator();
  const g = a.createGain();
  o.type = "sine";
  o.frequency.setValueAtTime(150, at);
  o.frequency.exponentialRampToValueAtTime(55, at + 0.12);
  g.gain.setValueAtTime(0.0001, at);
  g.gain.exponentialRampToValueAtTime(0.16, at + 0.006);
  g.gain.exponentialRampToValueAtTime(0.0001, at + 0.16);
  o.connect(g).connect(a.destination);
  o.start(at);
  o.stop(at + 0.2);
}

export const sfx = {
  press() {
    const a = audio();
    if (a) click(a, a.currentTime);
  },
  /** A deadline done: the pluck, a fifth above for the strike, a thump under the stamp. */
  done(step: number) {
    const a = audio();
    if (!a) return;
    const t = a.currentTime;
    const f = noteHz(step);
    pluck(a, f, t, 0.22);
    pluck(a, f * 2, t, 0.12, "sine", 0.025);
    pluck(a, f * 1.5, t + 0.07, 0.2, "triangle", 0.05);
    if (step >= 3) pluck(a, f * 2, t + 0.14, 0.18, "square", 0.012);
    thump(a, t + 0.24);
  },
  /** A card landing in Done. */
  land() {
    const a = audio();
    if (!a) return;
    click(a, a.currentTime, 1400, 0.14);
    pluck(a, 196, a.currentTime, 0.09, "triangle", 0.03);
  },
  /** The list cleared: a rising run. */
  clear() {
    const a = audio();
    if (!a) return;
    const t = a.currentTime + 0.05;
    [0, 4, 7, 12, 16, 19].forEach((n, i) => pluck(a, noteHz(0) * 2 ** (n / 12), t + i * 0.06, 0.32, "triangle", 0.06));
    pluck(a, noteHz(0) * 2, t + 0.36, 0.7, "sine", 0.03);
    thump(a, t + 0.36);
  },
};

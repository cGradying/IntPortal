// The reel's score (spec 054 C5), made in code: 112 BPM, A minor (i, VI, III, VII),
// cut to the timeline's acts. Writes reel/out/score.wav, 48 kHz stereo.
//   node reel/score.mjs
import { mkdirSync, writeFileSync } from "node:fs";
import { fileURLToPath } from "node:url";

const SR = 48000;
const DUR = 46;
const BPM = 112;
const BEAT = 60 / BPM;
const N = SR * DUR;
const L = new Float32Array(N);
const R = new Float32Array(N);

// Acts, in seconds (timeline.ts).
const DROP = 5; // the dive
const PROMISE = 34.5;
const END = 40.6;

const hz = (midi) => 440 * 2 ** ((midi - 69) / 12);
// Am, F, C, G as MIDI chords; one per bar.
const CHORDS = [
  [57, 60, 64],
  [53, 57, 60],
  [48, 52, 55],
  [55, 59, 62],
];
const chordAt = (t) => CHORDS[Math.floor(t / (BEAT * 4)) % 4];

let seed = 7;
const noise = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x3fffffff) - 1;

function add(t0, dur, gain, pan, voice) {
  const s0 = Math.max(0, Math.floor(t0 * SR));
  const s1 = Math.min(N, Math.floor((t0 + dur) * SR));
  const gl = gain * Math.cos(((pan + 1) * Math.PI) / 4);
  const gr = gain * Math.sin(((pan + 1) * Math.PI) / 4);
  for (let i = s0; i < s1; i++) {
    const v = voice((i - s0) / SR);
    L[i] += v * gl;
    R[i] += v * gr;
  }
}

const env = (t, a, d) => (t < a ? t / a : Math.exp(-(t - a) / d));
const square = (f, t, w = 0.5) => ((t * f) % 1 < w ? 1 : -1);
const saw = (f, t) => 2 * ((t * f) % 1) - 1;

const kick = (t) => Math.sin(2 * Math.PI * (45 * t + (75 / 18) * (1 - Math.exp(-18 * t)))) * Math.exp(-t / 0.22);
const hat = () => {
  let lp = 0;
  return (t) => {
    const n = noise();
    lp += 0.6 * (n - lp);
    return (n - lp) * Math.exp(-t / 0.03);
  };
};
const clap = (t) => noise() * Math.exp(-t / 0.09) * (t < 0.01 ? 0.6 : 1);
const pluck = (f) => (t) => square(f, t, 0.25) * env(t, 0.004, 0.12) * 0.5;
const bass = (f) => {
  let lp = 0;
  return (t) => {
    lp += 0.08 * (saw(f, t) - lp);
    return lp * env(t, 0.01, 0.35);
  };
};
const pad = (fs, len) => {
  const lps = fs.map(() => 0);
  return (t) => {
    const a = Math.min(1, t / 0.6) * Math.min(1, (len - t) / 0.8);
    let v = 0;
    fs.forEach((f, i) => {
      const s = saw(f, t) * 0.5 + saw(f * 1.004, t) * 0.5;
      lps[i] += 0.03 * (s - lps[i]);
      v += lps[i];
    });
    return (v / fs.length) * a;
  };
};
const bell = (f) => (t) => (Math.sin(2 * Math.PI * f * t) + 0.4 * Math.sin(2 * Math.PI * f * 2.76 * t)) * env(t, 0.003, 0.9);

const bars = Math.ceil(DUR / (BEAT * 4));

// Act one: the questions. A held pad and a pluck per question.
add(0, DROP, 0.18, 0, pad([57, 64, 72].map(hz), DROP));
[0.4, 1.5, 2.6].forEach((t, i) => add(t, 0.6, 0.22, -0.3 + i * 0.3, pluck(hz([76, 79, 81][i]))));
// The riser into the dive.
add(3.6, DROP - 3.6, 0.22, 0, (t) => noise() * (t / (DROP - 3.6)) ** 2 * 0.6 + square(220 + 880 * (t / (DROP - 3.6)) ** 2, t, 0.5) * 0.08 * (t / 1.4));

for (let b = 0; b < bars; b++) {
  const bar = b * BEAT * 4;
  const chord = chordAt(bar + 0.01);
  // Pad under everything, quieter in the groove.
  if (bar >= DROP - 0.01 && bar < END) add(bar, BEAT * 4, bar >= PROMISE ? 0.2 : 0.1, 0, pad(chord.map(hz), BEAT * 4));
  for (let k = 0; k < 4; k++) {
    const t = bar + k * BEAT;
    if (t < DROP || t >= END) continue;
    const half = t >= PROMISE; // the promise is half time
    if (!half || k % 2 === 0) add(t, 0.4, 0.95, 0, kick);
    if (!half && (k === 1 || k === 3)) add(t, 0.25, 0.25, 0.1, clap);
    add(t, BEAT * 0.9, 0.32, 0, bass(hz(chord[0] - 12)));
    for (let e = 0; e < 2; e++) add(t + (e * BEAT) / 2, 0.08, half ? 0.08 : 0.14, e ? 0.5 : -0.5, hat());
    if (!half && t >= 12.5) {
      // The arp comes in with the app tour, a sixteenth at a time.
      for (let s = 0; s < 4; s++) add(t + (s * BEAT) / 4, BEAT / 4, 0.08, s % 2 ? 0.35 : -0.35, pluck(hz(chord[(k * 4 + s) % 3] + 12)));
    }
  }
}

// The end card: the home chord rings, and two gold bells.
add(END, DUR - END, 0.32, 0, pad([45, 57, 60, 64].map(hz), DUR - END));
add(END, 0.5, 1, 0, kick);
add(END + 0.6, 3, 0.25, -0.2, bell(hz(81)));
add(END + 1.3, 3, 0.2, 0.2, bell(hz(88)));

// Soft clip, then 16-bit WAV.
const out = Buffer.alloc(44 + N * 4);
out.write("RIFF", 0);
out.writeUInt32LE(36 + N * 4, 4);
out.write("WAVEfmt ", 8);
out.writeUInt32LE(16, 16);
out.writeUInt16LE(1, 20);
out.writeUInt16LE(2, 22);
out.writeUInt32LE(SR, 24);
out.writeUInt32LE(SR * 4, 28);
out.writeUInt16LE(4, 32);
out.writeUInt16LE(16, 34);
out.write("data", 36);
out.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  out.writeInt16LE(Math.round(Math.tanh(L[i] * 0.8) * 30000), 44 + i * 4);
  out.writeInt16LE(Math.round(Math.tanh(R[i] * 0.8) * 30000), 46 + i * 4);
}
const dir = fileURLToPath(new URL("./out/", import.meta.url));
mkdirSync(dir, { recursive: true });
writeFileSync(dir + "score.wav", out);
console.log("wrote reel/out/score.wav");

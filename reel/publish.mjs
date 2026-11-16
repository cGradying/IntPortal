// Puts the rendered reel on the website (spec 054 C4, C7, C8): muxes the score,
// encodes each cut for the web (at most 25 MB), makes posters and the WebVTT
// captions, and writes them to site/static/reel.
//   node reel/score.mjs && node reel/render.mjs --w 1080 --h 1920 && node reel/render.mjs --w 1920 --h 1080 && node reel/publish.mjs
import { execFileSync } from "node:child_process";
import { mkdirSync, statSync, writeFileSync } from "node:fs";
import { LINES } from "./timeline.ts";

const site = "site/static/reel";
mkdirSync(site, { recursive: true });
const ff = (...a) => execFileSync("ffmpeg", ["-v", "error", "-y", ...a]);

for (const cut of ["9x16", "16x9"]) {
  const file = `${site}/intportal-${cut}.mp4`;
  ff("-i", `reel/out/silent-${cut}.mp4`, "-i", "reel/out/mix.wav", "-map", "0:v", "-map", "1:a", "-c:v", "libx264", "-preset", "slow", "-crf", "22", "-maxrate", "4M", "-bufsize", "8M", "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart", "-shortest", file);
  const mb = statSync(file).size / 1e6;
  if (mb > 25) throw new Error(`${file} is ${mb.toFixed(1)} MB, over 25`);
  ff("-ss", "44", "-i", `reel/out/silent-${cut}.mp4`, "-frames:v", "1", `reel/out/poster-${cut}.png`);
  execFileSync("cwebp", ["-quiet", "-q", "82", `reel/out/poster-${cut}.png`, "-o", `${site}/poster-${cut}.webp`]);
  console.log(`${file}: ${mb.toFixed(1)} MB`);
}

const stamp = (s) => new Date(s * 1000).toISOString().slice(11, 23);
writeFileSync(`${site}/captions.vtt`, "WEBVTT\n\n" + LINES.map((l, i) => `${i + 1}\n${stamp(l.at)} --> ${stamp(l.end)}\n${l.text}\n`).join("\n"));
console.log(`${site}/captions.vtt: ${LINES.length} cues`);

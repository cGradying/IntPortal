// Dumps the timeline's beat events, clicks and drags to audio/cues.json
// (the SFX cue list) and asserts that no beat is dead.
import { writeFileSync } from "node:fs";
import { PHRASES } from "../src/phrases";
import { B, BEATS_TOTAL } from "../src/lib/motion";

const events = PHRASES.flatMap((p) => p.events.map(([b, e]) => ({ b, t: B(b), e, phrase: p.name })));
const clicks = PHRASES.flatMap((p) => p.clicks).map((b) => ({ b, t: B(b) }));
const holds = PHRASES.flatMap((p) => p.holds ?? []).map(([a, z]) => ({ a, z, ta: B(a), tz: B(z) }));
const dead = [];
for (let b = 0; b < BEATS_TOTAL; b++) if (!events.some((e) => Math.floor(e.b) === b)) dead.push(b);
writeFileSync("audio/cues.json", JSON.stringify({ events, clicks, holds, beats: Array.from({ length: BEATS_TOTAL + 1 }, (_, i) => B(i)) }, null, 1));
console.log(`events ${events.length}, clicks ${clicks.length}, holds ${holds.length}, dead beats: ${dead.length ? dead.join(",") : "none"}`);
if (dead.length) process.exit(1);

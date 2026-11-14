// Fails when the UI invokes a command the shell doesn't register, or the shell registers one nothing invokes.
// The stand-in for generated bindings (#61): the two lists are typed by hand, so CI compares them.
// Run: node scripts/commands-check.mjs
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

const walk = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((e) => (e.isDirectory() ? walk(join(dir, e.name)) : [join(dir, e.name)]));
const handler = /generate_handler!\[([\s\S]*?)\]\)/.exec(readFileSync("src-tauri/src/lib.rs", "utf8"))[1];
const registered = new Set(handler.split(",").map((s) => s.trim().split("::").pop()).filter(Boolean));
const invoked = new Set();
for (const f of walk("src").filter((f) => /\.(ts|svelte)$/.test(f) && !f.endsWith(".test.ts"))) {
  for (const m of readFileSync(f, "utf8").matchAll(/invoke(?:<[^(]*>)?\(\s*"([a-z_0-9]+)"/g)) invoked.add(m[1]);
}
const unknown = [...invoked].filter((c) => !registered.has(c)).sort();
// Built in the shell, waiting on their screens (#92: syllabus from text or a course title).
const PENDING = new Set(["ai_guide", "ai_outline_text"]);
const unused = [...registered].filter((c) => !invoked.has(c) && !PENDING.has(c)).sort();
if (unknown.length) console.error("Invoked by the UI but not registered in lib.rs:", unknown.join(", "));
if (unused.length) console.error("Registered in lib.rs but never invoked by the UI:", unused.join(", "));
if (unknown.length || unused.length) process.exit(1);
console.log(`${registered.size} commands, registered and invoked.`);

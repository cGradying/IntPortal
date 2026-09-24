#!/usr/bin/env node
// Prints the inline <script> blocks of an HTML file so `node --check` can parse them.
import fs from "node:fs";

const file = process.argv[2];
if (!file) {
	console.error("Usage: node Scripts/extract-js.mjs <page.html>");
	process.exit(2);
}
const html = fs.readFileSync(file, "utf8");
const blocks = [...html.matchAll(/<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
if (blocks.length === 0) {
	console.error(`${file}: no inline script`);
	process.exit(1);
}
process.stdout.write(blocks.join("\n;\n"));

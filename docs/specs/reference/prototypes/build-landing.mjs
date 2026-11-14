// Builds landing-v9.html from landing-v9.src.html: inlines a JS copy of src/lib/lar/sprite.ts and the
// app's own tile renderer (static/tiles.wasm, from scripts/tiles.sh), so the mockup cannot drift from the app.
// Run from the repo root: node docs/specs/reference/prototypes/build-landing.mjs
import { readFileSync, writeFileSync } from "node:fs";
import ts from "typescript";

const dir = "docs/specs/reference/prototypes/";
const js = ts.transpileModule(readFileSync("src/lib/lar/sprite.ts", "utf8"), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
}).outputText;
const names = [...js.matchAll(/^export (?:const|function) (\w+)/gm)].map((m) => m[1]);
const sprite = `const { ${names.join(", ")} } = (() => {\n${js.replace(/^export /gm, "")}\nreturn { ${names.join(", ")} };\n})();`;
const wasm = readFileSync("static/tiles.wasm").toString("base64");
const html = readFileSync(dir + "landing-v9.src.html", "utf8").replace("/*SPRITE*/", () => sprite).replace("/*WASM*/", () => wasm);
writeFileSync(dir + "landing-v9.html", "<!doctype html>\n" + html);
console.log("landing-v9.html", html.length, "bytes");

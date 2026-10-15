// Builds lar-sheet.html: the sheet's script gets a JS copy of src/lib/lar/sprite.ts,
// so grids, pose() and tint() can never drift from the app.
// Run from the repo root: node docs/specs/reference/prototypes/build-lar-sheet.mjs
import { readFileSync, writeFileSync } from "node:fs";
import ts from "typescript";

const dir = "docs/specs/reference/prototypes/";
const js = ts.transpileModule(readFileSync("src/lib/lar/sprite.ts", "utf8"), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
}).outputText;
const names = [...js.matchAll(/^export (?:const|function) (\w+)/gm)].map((m) => m[1]);
const sprite = `const { ${names.join(", ")} } = (() => {\n${js.replace(/^export /gm, "")}\nreturn { ${names.join(", ")} };\n})();`;
const html = readFileSync(dir + "lar-sheet.src.html", "utf8").replace("/*SPRITE*/", () => sprite);
writeFileSync(dir + "lar-sheet.html", html);
console.log("lar-sheet.html", html.length, "bytes,", names.length, "exports");

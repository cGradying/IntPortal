// Builds lar-sheet.html and mockups.html: each page's script gets a JS copy of src/lib/lar/sprite.ts,
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
for (const page of ["lar-sheet", "mockups"]) {
  const html = readFileSync(dir + page + ".src.html", "utf8").replace("/*SPRITE*/", () => sprite);
  writeFileSync(dir + page + ".html", html);
  console.log(page + ".html", html.length, "bytes,", names.length, "exports");
}

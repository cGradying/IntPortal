// Builds lar-window.html from lar-window.src.html and one fragment per row in lar-window/.
// A fragment is <style>…</style>, the row's <section>, then <script>…</script>; its script runs
// inside the page's closure, so it can use $, shell, mountCrystal, startLar, rootPull and the rest.
// Run from the repo root: node docs/specs/reference/prototypes/build-lar-window.mjs [out.html]
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import ts from "typescript";

const dir = "docs/specs/reference/prototypes/";
const out = process.argv[2] ?? dir + "lar-window.html";
const js = ts.transpileModule(readFileSync("src/lib/lar/sprite.ts", "utf8"), {
  compilerOptions: { target: ts.ScriptTarget.ES2022, module: ts.ModuleKind.ESNext },
}).outputText;
const names = [...js.matchAll(/^export (?:const|function) (\w+)/gm)].map((m) => m[1]);
const sprite = `const { ${names.join(", ")} } = (() => {\n${js.replace(/^export /gm, "")}\nreturn { ${names.join(", ")} };\n})();`;
const icons = /SPRITES = (\{[\s\S]*?\n  \}) as const/.exec(readFileSync("src/lib/PixelIcon.svelte", "utf8"))[1];

const css = [], rows = [], code = [];
for (const row of ["greet", "window", "due", "study", "isko"]) {
  const f = `${dir}lar-window/${row}.html`;
  if (!existsSync(f)) continue;
  let s = readFileSync(f, "utf8");
  s = s.replace(/<style>([\s\S]*?)<\/style>/g, (_, c) => (css.push(`/* ${row} */\n${c}`), ""));
  s = s.replace(/<script>([\s\S]*?)<\/script>/g, (_, c) => (code.push(`/* ---------------- row: ${row} ---------------- */\n{\n${c}\n}`), ""));
  rows.push(s.trim());
}
const html = readFileSync(dir + "lar-window.src.html", "utf8")
  .replace("/*SPRITE*/", () => sprite)
  .replace("/*ICONS*/", () => icons)
  .replace("/*ROWCSS*/", () => css.join("\n"))
  .replace("<!--ROWS-->", () => rows.join("\n\n"))
  .replace("/*ROWJS*/", () => code.join("\n"));
writeFileSync(out, html);
console.log(out, html.length, "bytes,", rows.length, "rows");

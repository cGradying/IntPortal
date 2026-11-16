// The browser demo starts its WebAssembly shell before the app runs (spec 052).
export async function init() {
  if (__WEB__) await (await import("$lib/web")).install();
}

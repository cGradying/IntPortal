import { describe, expect, it } from "vitest";
import { resource } from "./load.svelte";

const settle = () => new Promise((r) => setTimeout(r, 0));
function deferred<T>() {
  let resolve!: (v: T) => void, reject!: (e: unknown) => void;
  const promise = new Promise<T>((a, b) => ((resolve = a), (reject = b)));
  return { promise, resolve, reject };
}

describe("resource", () => {
  it("is loading until the fetch lands, then ready with the value", async () => {
    const d = deferred<number>();
    const r = resource(() => d.promise);
    expect(r.current).toEqual({ state: "loading" });
    d.resolve(42);
    await settle();
    expect(r.current).toEqual({ state: "ready", value: 42 });
  });

  it("fails with the error, and a reload tries again from loading", async () => {
    let n = 0;
    const r = resource(() => (n++ === 0 ? Promise.reject("SIS is down") : Promise.resolve("ok")));
    await settle();
    expect(r.current).toEqual({ state: "failed", error: "SIS is down" });
    r.reload();
    expect(r.current).toEqual({ state: "loading" });
    await settle();
    expect(r.current).toEqual({ state: "ready", value: "ok" });
  });

  it("keeps showing the old value while a reload is on its way", async () => {
    const calls = [deferred<string>(), deferred<string>()];
    let n = 0;
    const r = resource(() => calls[n++].promise);
    calls[0].resolve("monday");
    await settle();
    r.reload();
    expect(r.current).toEqual({ state: "ready", value: "monday" });
    calls[1].resolve("tuesday");
    await settle();
    expect(r.current).toEqual({ state: "ready", value: "tuesday" });
  });

  it("ignores an answer that arrives after a newer one", async () => {
    const calls = [deferred<string>(), deferred<string>()];
    let n = 0;
    const r = resource(() => calls[n++].promise);
    r.reload();
    calls[1].resolve("new");
    await settle();
    calls[0].resolve("old");
    await settle();
    expect(r.current).toEqual({ state: "ready", value: "new" });
  });
});

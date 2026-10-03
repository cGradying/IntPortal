// One shape for every screen's data: loading, ready or failed, with a way
// to load again. A reload keeps the old value on screen until the new one
// lands, so swiping a day doesn't flash a skeleton.
export type Load<T> = { state: "loading" } | { state: "ready"; value: T } | { state: "failed"; error: string };

export function resource<T>(fetch: () => Promise<T>) {
  let current = $state<Load<T>>({ state: "loading" });
  let latest = 0;

  function reload() {
    const run = ++latest;
    if (current.state !== "ready") current = { state: "loading" };
    fetch().then(
      (value) => run === latest && (current = { state: "ready", value }),
      (e) => run === latest && (current = { state: "failed", error: typeof e === "string" ? e : e instanceof Error ? e.message : String(e) }),
    );
  }

  reload();
  return {
    get current() {
      return current;
    },
    reload,
  };
}

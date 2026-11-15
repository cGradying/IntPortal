// The launch hello (spec 010 C35): what it says and how long it takes.

/** "Good morning", or "Good morning, Jan" with the name the intro asked for (spec 049 C8). */
export function greeting(now: Date, name = ""): string {
  const h = now.getHours();
  const part = h < 5 ? "Up late" : h < 12 ? "Good morning" : h < 18 ? "Good afternoon" : "Good evening";
  return name ? `${part}, ${name}` : part;
}

export function dateLine(now: Date): string {
  return now.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
}

/** When each line of the hello starts, how long it holds and how long it takes to leave, in ms. */
export function helloTimes(reduce: boolean) {
  if (reduce) return { in: [0, 0], hold: 1400, out: 300 };
  return { in: [0, 450], hold: 1500, out: 500 };
}

/** The hello never waits on loading for longer than this; Today then shows what is cached (as C26). */
export const HELLO_CAP_MS = 3000;

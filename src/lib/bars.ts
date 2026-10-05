// Android draws the status and navigation bars over the page (edge to edge)
// and can't see what is under them. This tells it which bars sit on a dark
// background, so their icons stay readable, and takes the bars' heights for
// --safe-top and --safe-bottom, which older WebViews leave at 0. iOS needs
// neither.

declare global {
  interface Window {
    /** Added by MainActivity.kt on Android only. */
    IntPortalAndroid?: { bars(topDark: boolean, bottomDark: boolean): void; insets(): string; leave(): void };
  }
}

/** Whether the first opaque background under the point is dark. */
function darkAt(y: number): boolean {
  for (let el = document.elementFromPoint(innerWidth / 2, y); el; el = el.parentElement) {
    const [r, g, b, a = 1] = (getComputedStyle(el).backgroundColor.match(/[\d.]+/g) ?? []).map(Number);
    if (r !== undefined && a > 0.5) return 0.2126 * r + 0.7152 * g + 0.0722 * b < 128;
  }
  return getComputedStyle(document.documentElement).colorScheme === "dark";
}

export function watchBars() {
  const bridge = window.IntPortalAndroid;
  if (!bridge) return;
  // On body: rooms clear every custom property on the root element.
  const safe = () => {
    const [top, bottom] = bridge.insets().split(" ");
    document.body.style.setProperty("--safe-top", `${top}px`);
    document.body.style.setProperty("--safe-bottom", `${bottom}px`);
  };
  addEventListener("insets", safe);
  safe();
  let last = "";
  let timer = 0;
  const read = () => {
    timer = 0;
    const top = darkAt(1);
    const bottom = darkAt(innerHeight - 2);
    if (`${top}${bottom}` !== last) bridge.bars(top, bottom);
    last = `${top}${bottom}`;
  };
  // Screens, rooms and the landing all change the DOM; look again shortly after.
  new MutationObserver(() => (timer ||= window.setTimeout(read, 250))).observe(document.documentElement, {
    attributes: true,
    childList: true,
    subtree: true,
  });
  addEventListener("scroll", () => (timer ||= window.setTimeout(read, 250)), { passive: true });
  read();
}

// The visual viewport while a sheet is open. With the keyboard up, iOS
// shrinks it and scrolls the page, so a bottom-pinned sheet would slide its
// top off screen; a frame that follows it keeps the sheet whole.
export function visualViewport() {
  const vv = $state({ h: innerHeight, top: 0 });
  $effect(() => {
    const v = window.visualViewport;
    if (!v) return;
    const sync = () => ((vv.h = v.height), (vv.top = v.offsetTop));
    sync();
    v.addEventListener("resize", sync);
    v.addEventListener("scroll", sync);
    return () => {
      v.removeEventListener("resize", sync);
      v.removeEventListener("scroll", sync);
    };
  });
  return {
    get h() {
      return vv.h;
    },
    get top() {
      return vv.top;
    },
    /** The keyboard is up. */
    get keyboard() {
      return vv.h < innerHeight - 120;
    },
  };
}

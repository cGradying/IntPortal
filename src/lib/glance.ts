// What the glance shows, as data. `Glance.svelte` draws it as the Dynamic
// Island capsule or the dock above the tab bar.
import type { Glance } from "./api";

export type Trip = "drive" | "arrived" | "stalled";
export type Tone = "calm" | "live" | "trouble";

export interface GlanceView {
  /** The jeepney's state; none means the portal glyph. */
  trip: Trip | null;
  tone: Tone;
  /** The full sentence. */
  line: string;
  /** A few characters after it: the countdown. */
  short: string;
}

export function glanceView(g: Glance | undefined, line: string | undefined, syncing: boolean, arrived: boolean, failed: boolean): GlanceView {
  if (syncing) return { trip: "drive", tone: "calm", line: "On the way to SIS…", short: "" };
  if (arrived) return { trip: "arrived", tone: "calm", line: "Synced · everything's fresh", short: "" };
  const view: GlanceView = { trip: failed ? "stalled" : null, tone: "calm", line: line ?? "IntPortal", short: "" };
  if (!g) return view;
  switch (g.kind) {
    case "in_session":
      return { ...view, tone: "live", short: g.until };
    case "next_today":
      return { ...view, short: g.when.replace(/^(in|at) /, "") };
    case "sync_trouble":
      return { ...view, tone: "trouble", short: "Retry" };
    case "thinking":
      return { ...view, short: "…" };
    case "day_done":
      return { ...view };
  }
}

export function ago(secs: string | null | undefined, now = Date.now()): string {
  if (!secs) return "never";
  const m = Math.round((now / 1000 - Number(secs)) / 60);
  return m < 1 ? "just now" : m < 60 ? `${m} min ago` : m < 1440 ? `${Math.round(m / 60)} h ago` : `${Math.round(m / 1440)} d ago`;
}

/** Calls back with whether the phone has a Dynamic Island, now and whenever
 *  the top safe area changes: it can read 0 until iOS lays the page out.
 *  Dynamic Island iPhones have a top safe area of 59 pt or more, notched
 *  ones 44 to 50, home-button ones 20. */
export function watchDynamicIsland(onchange: (island: boolean) => void): () => void {
  const android = /Android/i.test(navigator.userAgent);
  const probe = document.createElement("div");
  probe.style.cssText = "position:fixed;top:0;left:0;width:1px;height:env(safe-area-inset-top);visibility:hidden;pointer-events:none";
  document.body.append(probe);
  const read = () => onchange(!android && probe.getBoundingClientRect().height >= 55);
  const observer = new ResizeObserver(read);
  observer.observe(probe);
  read();
  return () => {
    observer.disconnect();
    probe.remove();
  };
}

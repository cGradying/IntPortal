// How every note's page looks (spec 046 C11a). Kept on the phone; never in the Markdown.
import type { Template } from "./md";

export interface PageLook {
  size: "S" | "M" | "L";
  font: "phone" | "classic" | "mono";
  spacing: "Tight" | "Normal" | "Roomy";
  paper: "plain" | "lines" | "dots" | "grid";
  /** What a new note starts as: ask with the templates, blank, or the last one used. */
  start: "Ask" | "Blank" | "Last used";
  count: boolean;
  awake: boolean;
  last: Template;
}

export const DEFAULT_LOOK: PageLook = { size: "M", font: "phone", spacing: "Normal", paper: "plain", start: "Ask", count: true, awake: false, last: "blank" };

export function readLook(): PageLook {
  try {
    return { ...DEFAULT_LOOK, ...JSON.parse(localStorage.getItem("notePage") ?? "{}") };
  } catch {
    return { ...DEFAULT_LOOK };
  }
}

export function writeLook(l: PageLook) {
  try {
    localStorage.setItem("notePage", JSON.stringify(l));
  } catch {
    // Then the look lasts this launch.
  }
}

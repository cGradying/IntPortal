// LAR's steps, as the trace under a question shows them (spec 048 C12–C14). Pure, so it is tested
// without a phone. A step is done once the next one arrives; the last is done once the reply lands, so a
// rule answer's read step never blinks on.
import { foundLine } from "./apply";
import type { Intent, Source, Step } from "./assis.svelte";

export interface Row {
  text: string;
  done: boolean;
  found?: Source[];
  quote?: string;
}

const read = (intent?: Intent) => (intent === "due" ? "Read your dues and timetable" : "Read your timetable");

/** The rows of a trace. `live`: the reply has not landed yet. A search and its result are one row. */
export function rows(steps: Step[], intent: Intent | undefined, live: boolean): Row[] {
  const out: Row[] = [];
  for (const s of steps) {
    const prev = out[out.length - 1];
    if (prev) prev.done = true;
    switch (s.step) {
      case "wake":
        out.push({ text: "Waking up", done: false });
        break;
      case "read":
        out.push({ text: read(intent), done: false });
        break;
      case "search":
        out.push({ text: "Searching your notes and decks…", done: false });
        break;
      case "found":
      case "nothing":
      case "search_off": {
        if (prev?.text.startsWith("Searching")) out.pop(); // the search and its result are one row
        out.push(
          s.step === "found"
            ? { text: `Found ${foundLine(s.found)}`, done: true, found: s.found.slice(0, 3), quote: s.quote || undefined }
            : { text: s.step === "nothing" ? "Nothing close in your notes or decks" : "Note search is off", done: true },
        );
        break;
      }
      case "write":
        out.push({ text: "Writing", done: false });
        break;
    }
  }
  const last = out[out.length - 1];
  if (last && !live) last.done = true;
  for (const r of out) if (r.text === "Waking up" && r.done) r.text = "Woke up";
  return out;
}

/** The one line a trace folds into once the answer is in. */
export function summary(steps: Step[], intent?: Intent): string {
  const found = steps.find((s) => s.step === "found");
  if (found?.step === "found") return `Looked at ${foundLine(found.found)}`;
  if (steps.some((s) => s.step === "nothing")) return "Searched, nothing close";
  if (steps.some((s) => s.step === "search_off")) return "Note search was off";
  return intent === "due" ? "Read your dues" : "Read your timetable";
}

/** What the header's status says while he works: the running step, as a present-tense line. */
export function doing(steps: Step[], intent?: Intent): string {
  const last = steps[steps.length - 1];
  if (!last) return "Thinking";
  if (last.step === "wake") return "Waking up";
  if (last.step === "read") return intent === "due" ? "Reading your dues…" : "Reading your timetable…";
  if (last.step === "search") return "Searching your notes and decks…";
  return "Writing";
}

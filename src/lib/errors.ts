// Spec 040 C4: what the core says, in words a student reads. The core's own
// messages start lowercase ("couldn't reach the SIS: …") and map through the
// table. The app's own sentences are listed in OWN and pass through; any other
// text, a portal's page message included, becomes FALLBACK.

const TABLE: [RegExp, string | ((m: RegExpMatchArray) => string)][] = [
  [/^couldn't reach the SIS/i, "Can't reach the SIS right now. Showing what was saved."],
  [/^the SIS session expired/i, "Your session ended. Pull to sync."],
  [/no SIS server had your schedule/i, "The SIS has no classes for you this term yet."],
  [/^too many sign-in tries(?:.*try again at (\d+))?/i, (m) => (m[1] ? `Too many tries. You can try again at ${new Date(Number(m[1]) * 1000).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })}.` : "Too many tries. Wait a few minutes, then try again.")],
  [/not a PUP SIS host/i, "That address isn't a PUP server, so IntPortal won't use it."],
  [/eMabini|error sending request|timed out|dns error|connection/i, "Can't reach eMabini right now."],
];

/** The app's own sentences (Rust commands, the core's store and backup, the UI). A string starts with one of these, or is it. */
const OWN = [
  "Give the deck a name.", "Give it a name first.", "No such card.", "Unknown note", "Type a question first.", "Select the words to explain first.",
  "The note is empty.", "This note is too long for me to take in at once.", "A target GPA runs from", "Program units look off",
  "This PDF", "This file could not be read as a PDF", "Send the PDF as raw bytes", "This store can't be opened", "That note isn't saved yet.",
  "Only a freeform note can change subject.", "A note holds up to 20 photos.", "That file isn't a readable IntPortal backup.",
  "That file is too big", "That backup", "Sign in first, then restore.", "Saving your login isn't supported", "The data is locked.",
  "IntAssis", "That isn't the student number", "Couldn't make the backup.", "Couldn't restore that backup", "Your photos make this backup",
  "A class has to end after it starts", "That photo isn't where it should be.", "The last day of classes has to be after today.",
  "Weights and scores are percents", "I couldn't", "This phone can't share files", "The SIS turned your login down.", "Sign-in didn't go through.",
];

export const FALLBACK = "Something went wrong. Try again in a bit.";

export function friendly(raw: unknown): string {
  const text = (typeof raw === "string" ? raw : ((raw as { message?: string })?.message ?? String(raw))).replace(/^Error:\s*/, "").trim();
  for (const [re, copy] of TABLE) {
    const m = text.match(re);
    if (m) return typeof copy === "string" ? copy : copy(m);
  }
  if (OWN.some((s) => text.startsWith(s))) return text;
  console.warn("unmapped error:", text);
  return FALLBACK;
}

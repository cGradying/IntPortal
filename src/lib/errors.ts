// Spec 040 C4: what the core says, in words a student reads. The core's own
// messages start lowercase ("couldn't reach the SIS: …") and map through the
// table. The app's own sentences are listed in OWN, checked first, and pass through; any other
// text, a portal's page message included, becomes FALLBACK.

const TABLE: [RegExp, string | ((m: RegExpMatchArray) => string)][] = [
  [/^couldn't reach the SIS/i, "Can't reach the SIS right now. Showing what was saved."],
  [/^the SIS session expired/i, "Your session ended. Pull to sync."],
  [/no SIS server had your schedule/i, "The SIS has no classes for you this term yet."],
  [/^too many sign-in tries(?:.*try again at (\d+))?/i, (m) => (m[1] ? `Too many tries. You can try again at ${new Date(Number(m[1]) * 1000).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" })}.` : "Too many tries. Wait a few minutes, then try again.")],
  [/not a PUP SIS host/i, "That address isn't a PUP server, so IntPortal won't use it."],
  [/eMabini|error sending request|timed out|dns error|connection/i, "Can't reach eMabini right now."],
];

/** The app's own sentences (Rust commands, the core's store and backup, the UI). A string starts with one of these. */
const OWN = [
  // src-tauri commands
  "Give the deck a name.", "Give it a name first.", "No such card.", "Unknown note", "Unknown model", "Unknown action", "Sync first", "Not signed in",
  "Turn IntAssis on first", "Send the PDF as raw bytes", "Saving your login isn't supported on this device yet.", "The data is locked. Restart the app.",
  "The store key in the keychain is damaged.", "IntAssis is busy", "IntAssis stopped. Try again.", "Couldn't make the backup.", "Couldn't restore that backup, so nothing changed.",
  "Sign in first, then back up.", "That deck is gone.", "That card is gone.", "That photo isn't where it should be.", "A class has to end after it starts, before midnight.",
  "A target GPA runs from 1.00 to 5.00.", "Program units look off; check your curriculum.", "The last day of classes has to be after today.", "Weights and scores are percents, 0 to 100.",
  "That isn't the student number signed in to the SIS on this phone.", "Your photos make this backup too big to restore here;",
  // the AI crate and the core
  "Type a question first.", "Select the words to explain first.", "The note is empty.", "This note is too long for me to take in at once. Select part of it.",
  "This PDF has no text to read", "This PDF is over 20 MB", "This PDF has ", "This file could not be read as a PDF",
  "This store can't be opened with this phone's key.", "That note isn't saved yet.", "Only a freeform note can change subject.", "A note holds up to 20 photos.",
  "That file isn't a readable IntPortal backup.", "That file is too big to be an IntPortal backup.", "That backup is from a newer IntPortal. Update the app, then try again.",
  "That backup belongs to another student.", "Sign in first, then restore.", "Use a link that starts with https://",
  // the UI
  "I couldn't find new cards in that", "I couldn't wake up. Try again.", "I couldn't make cards for that. Try a note's own text instead.", "This phone can't share files from IntPortal yet.",
  "The photo couldn't be added.", "IntPortal can't use the camera.", "This phone has no camera.", "There isn't room on this phone for the photo.", "A note holds up to 20 photos. Remove one",
  // the SIS and eMabini pages
  "The SIS turned your login down.", "Sign-in didn't go through.",
];

export const FALLBACK = "Something went wrong. Try again in a bit.";

export function friendly(raw: unknown): string {
  const text = (typeof raw === "string" ? raw : ((raw as { message?: string })?.message ?? String(raw))).replace(/^Error:\s*/, "").trim();
  if (OWN.some((s) => text.startsWith(s))) return text;
  for (const [re, copy] of TABLE) {
    const m = text.match(re);
    if (m) return typeof copy === "string" ? copy : copy(m);
  }
  console.warn("unmapped error:", text);
  return FALLBACK;
}

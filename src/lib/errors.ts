// Spec 040 C4: what the core says, in words a student reads. The core's own
// messages start lowercase ("couldn't reach the SIS: …"); a portal's or the
// app's own sentences are already for the student and pass through.

const TABLE: [RegExp, string][] = [
  [/^couldn't reach the SIS/i, "Can't reach the SIS right now."],
  [/^the SIS session expired/i, "Your session ended. Pull to sync."],
  [/no SIS server had your schedule/i, "The SIS has no classes for you this term yet."],
  [/^too many sign-in tries/i, "Too many tries. Wait a few minutes, then try again."],
  [/not a PUP SIS host/i, "That address isn't a PUP server, so IntPortal won't use it."],
  [/eMabini|error sending request|timed out|dns error|connection/i, "Can't reach eMabini right now."],
];

export const FALLBACK = "Something went wrong. Try again in a bit.";

export function friendly(raw: unknown): string {
  const text = (typeof raw === "string" ? raw : ((raw as { message?: string })?.message ?? String(raw))).replace(/^Error:\s*/, "").trim();
  const hit = TABLE.find(([re]) => re.test(text));
  if (hit) return hit[1];
  if (/^[A-Z"'“]/.test(text)) return text;
  console.warn("unmapped error:", text);
  return FALLBACK;
}

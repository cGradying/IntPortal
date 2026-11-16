// What the talk with LAR (spec 049) learns about the student before sign-in: what to call them,
// where they study and what they care about most. Kept on the phone only. Other parts read the
// keys directly, so they are a contract: `intportal.name`; `intportal.campus` holding a campus
// `name` exactly as in crates/intportal-core/src/campus.rs (e.g. "Sta. Mesa"), or
// `school:<portal id>`; and `intportal.focus`, the student's picks from FOCI, comma-joined in the
// order they picked them (e.g. "deadlines,classes").

export const NAME_KEY = "intportal.name";
export const CAMPUS_KEY = "intportal.campus";
export const FOCUS_KEY = "intportal.focus";
export const MAX_NAME = 20;

/** What a student can say they care about most. */
export const FOCI = ["classes", "deadlines", "grades", "study"] as const;
export type Focus = (typeof FOCI)[number];
/** Picks as kept: known ones only, each once, in the order given. */
export const cleanFocus = (raw: readonly string[]): Focus[] => [...new Set(raw)].filter((f): f is Focus => (FOCI as readonly string[]).includes(f));

/** PUP's campuses, in campus.rs order (profile.test.ts keeps the two in step). */
export const CAMPUSES = [
  "Sta. Mesa", "San Juan", "Parañaque", "Taguig", "Quezon City", "Caloocan", "Mariveles", "Pulilan", "Sta. Maria",
  "Cabiao", "Maragondon", "Alfonso", "Biñan", "Calauan", "San Pedro", "Sta. Rosa", "Sto. Tomas", "Talisay",
  "Mulanay", "Lopez", "Unisan", "Ragay", "Bansud", "Sablayan", "Leyte",
] as const;

/** A name as kept: single spaces, no ends, at most 20 characters. */
export const cleanName = (raw: string) => raw.replace(/\s+/g, " ").trim().slice(0, MAX_NAME).trim();

function read(key: string): string | null {
  try {
    return localStorage.getItem(key);
  } catch {
    return null;
  }
}
function write(key: string, value: string | null) {
  try {
    if (value) localStorage.setItem(key, value);
    else localStorage.removeItem(key);
  } catch {
    // Private mode: it lasts this launch.
  }
}

export const getName = () => read(NAME_KEY) ?? "";
export const setName = (raw: string) => write(NAME_KEY, cleanName(raw) || null);
export const getCampus = () => read(CAMPUS_KEY);
/** A campus name from CAMPUSES, `school:<portal id>`, or null to forget it. */
export const setCampus = (value: string | null) => write(CAMPUS_KEY, value);
export const getFocus = () => cleanFocus((read(FOCUS_KEY) ?? "").split(","));
/** The picks, most wanted first; none forgets them. */
export const setFocus = (picks: readonly string[]) => write(FOCUS_KEY, cleanFocus(picks).join(",") || null);

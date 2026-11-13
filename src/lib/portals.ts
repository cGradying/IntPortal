// What the landing and the You screen need to treat each portal alike: which
// fields it asks for, whether they are filled in, what to say. Pure, so
// components never branch on a portal id.
import type { Portal, Tries } from "./api";

export interface FormValues {
  student_number: string;
  birthdate: string;
  password: string;
}

const STUDENT_NUMBER = /^\d{4}-?\d{5}-?[A-Za-z]{2}-?\d$/;

/** The first thing missing or wrong for this portal's fields, or "". */
export function validate(portal: Portal, v: FormValues): string {
  for (const field of portal.fields) {
    if (field === "student_number") {
      if (!v.student_number.trim()) return "Add your student number.";
      if (!STUDENT_NUMBER.test(v.student_number.trim())) return "Student number looks like 2026-00000-MN-0.";
    }
    if (field === "birthdate" && !v.birthdate) return "Add your birthdate.";
    if (field === "password" && !v.password) return "Add your password.";
  }
  return "";
}

/** What goes to the core: a trimmed, upper-cased student number. */
export const fieldValues = (v: FormValues): FormValues => ({ ...v, student_number: v.student_number.trim().toUpperCase() });

/** "2 tries left" once a try is used; when it unlocks once none are left. */
export function triesLine(t: Tries, portal: Portal, now: number): string {
  if (t.left <= 0) {
    const at = new Date((t.retry_at ?? now) * 1000).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit" });
    return `Too many tries. You can try again at ${at}.`;
  }
  return t.left >= portal.limits.attempts ? "" : `${t.left} ${t.left === 1 ? "try" : "tries"} left`;
}

export interface PortalCopy {
  /** LAR's line above the form. */
  lar: string;
  keychainNote: string;
  /** Label of the field that names the student. */
  hint: string;
  /** One line under the wordmark: what IntPortal does with this portal (spec 010 C38). */
  pitch: string;
}

const COPY: Record<string, PortalCopy> = {
  sis: {
    lar: "Hi, I'm LAR. Sign in with your SIS login and I'll bring everything over.",
    keychainNote: "Your login stays in this phone's keychain. IntPortal only talks to PUP SIS.",
    hint: "PUP SIS",
    pitch: "Your SIS schedule, grades and deadlines on your phone. Works offline.",
  },
  mabini: {
    lar: "Hi, I'm LAR. Sign in to eMabini and I'll bring your courses and deadlines.",
    keychainNote: "Your login stays in this phone's keychain. IntPortal only talks to PUP eMabini.",
    hint: "PUP eMabini",
    pitch: "Your eMabini courses and deadlines, next to your classes. Works offline.",
  },
};

export const portalCopy = (id: string): PortalCopy => COPY[id] ?? COPY.sis;

/** Drawn until the core's list arrives, so the form is never empty. */
export const FALLBACK_SIS: Portal = {
  id: "sis",
  name: "SIS",
  school: "Polytechnic University of the Philippines",
  region: "NCR",
  status: "ready",
  theme: { ramp: ["#3b1220", "#7a1c2c", "#b5412a", "#e08a35", "#f3cf6a"], accent: "#e8b04a" },
  shape: { cols: 6, rows: 8, corner: "square" },
  motif: "swirl",
  fields: ["student_number", "birthdate", "password"],
  limits: { attempts: 3, window_secs: 900 },
  keychain_service: "ph.intportal.app",
};

/** The student number as it is typed or pasted, shaped as `YYYY-NNNNN-CC-N` (011 C4). */
export function maskStudentNumber(raw: string): string {
  const s = raw.toUpperCase().replace(/[^0-9A-Z]/g, "");
  const parts: string[] = [];
  let i = 0;
  const take = (n: number, ok: RegExp) => {
    let out = "";
    while (out.length < n && i < s.length && ok.test(s[i])) out += s[i++];
    return out;
  };
  for (const [n, ok] of [[4, /\d/], [5, /\d/], [2, /[A-Z]/], [1, /\d/]] as const) {
    const p = take(n, ok);
    if (!p) break;
    parts.push(p);
    if (p.length < n) break;
  }
  return parts.join("-");
}

/** Years the birthdate wheel offers, newest first: 14 to 70 years ago (011 C2). */
export const birthYears = (now: Date) => Array.from({ length: 57 }, (_, k) => now.getFullYear() - 14 - k);

/** Days in a month (1–12) of a year: the day wheel never offers more (011 C3). */
export const daysIn = (month: number, year: number) => new Date(year, month, 0).getDate();

/** The SIS turned a login down: its own words, or ours when it gave none (011 C8). */
export const REJECTED = "Sign-in didn't go through. Check your student number, birthdate and password.";
/** No SIS host answered (011 C9). */
export const DOWN = "SIS is down right now. Your data is safe. Try again in a bit.";

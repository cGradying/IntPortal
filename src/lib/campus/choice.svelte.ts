// Which campus Today draws, live: the one the student number resolves to, else
// the student's pick (stored by the intro or You), else Sta. Mesa.
import { api } from "../api";
import { pickScene } from "./scenes";

/** Holds a campus name as `campus.rs` writes it ("Sta. Mesa"), or `school:<portal id>`. */
export const CAMPUS_KEY = "intportal.campus";

function read(): string | null {
  try {
    return localStorage.getItem(CAMPUS_KEY);
  } catch {
    return null;
  }
}

export const campus = $state({ stored: read(), resolved: null as string | null });

/** Picks up a choice written straight to storage (the intro writes it before Today mounts). */
export const refreshCampus = () => void (campus.stored = read());

/** The scene key to draw now. */
export const sceneKey = () => pickScene(campus.resolved, campus.stored);

export function setCampus(key: string) {
  campus.stored = key;
  try {
    localStorage.setItem(CAMPUS_KEY, key);
  } catch {
    // Storage off: the pick lasts until the app closes.
  }
}

let asked = false;
/** Looks up the saved SIS student number's campus once. */
export function resolveCampus() {
  if (asked) return;
  asked = true;
  api
    .loginHint("sis")
    .then((n) => (n ? api.campus(n) : null))
    .then((r) => {
      if (r?.kind === "known") campus.resolved = r.campus.name;
    })
    .catch(() => {});
}

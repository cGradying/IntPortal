// Which campus Today draws, live: the one the student number resolves to, else
// the student's pick (stored by the intro or You through profile.ts), else Sta. Mesa.
import { api } from "../api";
import { getCampus, setCampus as keep } from "../profile";
import { pickScene } from "./scenes";

export const campus = $state({ stored: getCampus(), resolved: null as string | null });

/** Picks up a choice the intro wrote before Today mounted. */
export const refreshCampus = () => void (campus.stored = getCampus());

/** The scene key to draw now. */
export const sceneKey = () => pickScene(campus.resolved, campus.stored);

/** A campus name or `school:<portal id>`; Today's strip follows at once. */
export function setCampus(key: string) {
  campus.stored = key;
  keep(key);
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

// Which scene a key names, and the loaders. Each scene is its own chunk, so a
// student downloads and parses only their own campus.
import type { SceneDef } from "../paint";
import type { SchoolLook } from "./school";

/** PUP's campuses, named exactly as `crates/intportal-core/src/campus.rs` names them. */
export const PUP_CAMPUSES = [
  "Sta. Mesa", "San Juan", "Parañaque", "Taguig", "Quezon City", "Caloocan", "Mariveles", "Pulilan", "Sta. Maria",
  "Cabiao", "Maragondon", "Alfonso", "Biñan", "Calauan", "San Pedro", "Sta. Rosa", "Sto. Tomas", "Talisay", "Mulanay",
  "Lopez", "Unisan", "Ragay", "Bansud", "Sablayan", "Leyte",
] as const;

export const DEFAULT_SCENE = "Sta. Mesa";

const own = (m: Promise<{ default: SceneDef }>) => m.then((x) => x.default);

/** The hand-drawn ones; every other PUP campus gets the shared branch scene. */
export const HAND_DRAWN: Record<string, () => Promise<SceneDef>> = {
  "Sta. Mesa": () => own(import("./staMesa")),
  "San Juan": () => own(import("./sanJuan")),
  "Parañaque": () => own(import("./paranaque")),
  Taguig: () => own(import("./taguig")),
  "Quezon City": () => own(import("./quezonCity")),
  Caloocan: () => own(import("./caloocan")),
  "Sto. Tomas": () => own(import("./stoTomas")),
  Ragay: () => own(import("./ragay")),
  Mariveles: () => own(import("./mariveles")),
};

const isPup = (k: string) => (PUP_CAMPUSES as readonly string[]).includes(k);
/** A key a scene can be drawn for: a PUP campus name, or `school:<portal id>`. */
export const isSceneKey = (k: string | null | undefined): k is string => !!k && (isPup(k) || /^school:[a-z0-9-]+$/.test(k));

/** The scene to draw: the campus the student number resolves to, else the stored pick, else Sta. Mesa. */
export function pickScene(resolved: string | null | undefined, stored: string | null | undefined): string {
  if (resolved && isPup(resolved)) return resolved;
  if (isSceneKey(stored)) return stored;
  return DEFAULT_SCENE;
}

/** Loads the scene for a key. A school needs its look (accent, motif) from the portal list. */
export function loadScene(key: string, look?: SchoolLook): Promise<SceneDef> {
  if (key.startsWith("school:")) {
    const id = key.slice(7);
    return import("./school").then((m) => m.school(look ?? { id, name: id.toUpperCase(), accent: "#e8b04a", ramp: [], motif: "swirl" }));
  }
  return HAND_DRAWN[key]?.() ?? import("./branch").then((m) => m.branch(key));
}

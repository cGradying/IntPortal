// Spec 057 C2 and 059 C8: the 3D hero runs only where it can run well.
export type Env = { webgl2: boolean; reduced: boolean; saveData: boolean; cores: number; /** GB, where the browser says. */ memory?: number };

export const canRun = (e: Env) => e.webgl2 && !e.reduced && !e.saveData && e.cores >= 4 && (e.memory ?? 4) >= 4;

export function readEnv(): Env {
  let webgl2 = false;
  try {
    webgl2 = !!document.createElement("canvas").getContext("webgl2");
  } catch {
    webgl2 = false;
  }
  const nav = navigator as Navigator & { connection?: { saveData?: boolean }; deviceMemory?: number };
  return {
    webgl2,
    reduced: matchMedia("(prefers-reduced-motion: reduce)").matches,
    saveData: !!nav.connection?.saveData,
    cores: navigator.hardwareConcurrency ?? 4,
    memory: nav.deviceMemory,
  };
}

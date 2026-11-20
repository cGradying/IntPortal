// Spec 057 C2, 059 C8 and 060 C20: the 3D hero runs only where it can run well.
export type Env = {
  webgl2: boolean;
  reduced: boolean;
  saveData: boolean;
  cores: number;
  /** GB, where the browser says. */
  memory?: number;
  /** navigator.connection, where the browser has it: effectiveType and Mbit/s. */
  net?: { type?: string; downlink?: number };
};

export const canRun = (e: Env) =>
  e.webgl2 && !e.reduced && !e.saveData && e.cores >= 4 && (e.memory ?? 4) >= 4 && (e.net?.type ?? "4g") === "4g" && (e.net?.downlink ?? 1.5) >= 1.5;

export function readEnv(): Env {
  let webgl2 = false;
  try {
    webgl2 = !!document.createElement("canvas").getContext("webgl2");
  } catch {
    webgl2 = false;
  }
  const nav = navigator as Navigator & { connection?: { saveData?: boolean; effectiveType?: string; downlink?: number }; deviceMemory?: number };
  return {
    webgl2,
    reduced: matchMedia("(prefers-reduced-motion: reduce)").matches,
    saveData: !!nav.connection?.saveData,
    cores: navigator.hardwareConcurrency ?? 4,
    memory: nav.deviceMemory,
    net: nav.connection && { type: nav.connection.effectiveType, downlink: nav.connection.downlink },
  };
}

// The one camera plugin: a photo from the camera or the library, read on the
// phone (text, QR) and kept only when `saveTo` names a folder. Without it the
// photo is gone once read (spec 041 C16).
import { addPluginListener, invoke } from "@tauri-apps/api/core";

export interface CaptureOptions {
  source: "camera" | "library";
  read?: { text?: boolean; qr?: boolean };
  /** An absolute folder in the app's data. The plugin names the file. */
  saveTo?: string;
}

export interface Capture {
  cancelled: boolean;
  path?: string;
  width?: number;
  height?: number;
  text?: string;
  /** Each line read and where it sits, 0 to 1 of the photo, top-left origin (spec 060 C10). */
  lines?: ScanLine[];
  qr?: string[];
}

export interface ScanLine {
  text: string;
  x: number;
  y: number;
  w: number;
  h: number;
}

/**
 * `downloading` runs when Android fetches the scanner's models first (Play
 * normally installs them with the app); iOS reads with Vision, nothing to fetch.
 */
export async function capture(options: CaptureOptions, downloading?: () => void): Promise<Capture> {
  const heard = downloading ? await addPluginListener("camera", "scanner", downloading).catch(() => null) : null;
  try {
    return await invoke<Capture>("plugin:camera|capture", { ...options });
  } finally {
    void heard?.unregister();
  }
}

/** What a scan says while the scanner downloads, and when it couldn't. */
export const scannerDownloading = "Downloading the scanner…";
export const noScanner = "The scanner needs a one-time download. Connect to the internet and try again.";

export type CameraProblem = "camera_denied" | "no_camera" | "no_space" | "no_scanner" | "other";
const CODES = new Set<string>(["camera_denied", "no_camera", "no_space", "no_scanner"]);

/** A plugin's rejection is an object with a message, which here is one of these codes. */
export function cameraProblem(e: unknown): CameraProblem {
  const code = typeof e === "string" ? e : (e as { message?: string })?.message;
  return code && CODES.has(code) ? (code as CameraProblem) : "other";
}

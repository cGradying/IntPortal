// The one camera plugin: a photo from the camera or the library, read on the
// phone (text, QR) and kept only when `saveTo` names a folder. Without it the
// photo is gone once read (spec 041 C16).
import { invoke } from "@tauri-apps/api/core";

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
  qr?: string[];
}

export const capture = (options: CaptureOptions) => invoke<Capture>("plugin:camera|capture", { ...options });

/** A plugin's rejection is an object with a message, which here is one of these codes. */
export function cameraProblem(e: unknown): "camera_denied" | "no_camera" | "no_space" | "other" {
  const code = typeof e === "string" ? e : (e as { message?: string })?.message;
  return code === "camera_denied" || code === "no_camera" || code === "no_space" ? code : "other";
}

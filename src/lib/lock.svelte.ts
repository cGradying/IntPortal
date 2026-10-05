// The optional app lock: Face ID / Touch ID, falling back to the phone's
// passcode. It locks at launch and after the app has been away a minute,
// and a cover hides the screen whenever the app is in the background.
import { authenticate, checkStatus } from "@tauri-apps/plugin-biometric";
import { buzz } from "./haptics";

const AWAY_MS = 60_000;

const android = typeof navigator !== "undefined" && /Android/i.test(navigator.userAgent);
/** What unlocks the app, in the phone's own words. */
export const unlockWith = android ? "fingerprint or screen lock" : "Face ID or passcode";

function read(): boolean {
  try {
    return localStorage.getItem("appLock") === "1";
  } catch {
    return false;
  }
}

export const lock = $state({ enabled: read(), locked: read(), hidden: false, error: "" });

let hiddenAt = 0;

export function watchLock() {
  document.addEventListener("visibilitychange", () => {
    lock.hidden = document.hidden;
    if (document.hidden) hiddenAt = Date.now();
    else if (lock.enabled && Date.now() - hiddenAt >= AWAY_MS) lock.locked = true;
  });
}

export async function unlock(): Promise<boolean> {
  try {
    await authenticate("Unlock IntPortal", { allowDeviceCredential: true, cancelTitle: "Cancel" });
    lock.locked = false;
    buzz.done();
    lock.error = "";
    return true;
  } catch (e) {
    lock.error = typeof e === "string" ? e : "Couldn't confirm it's you.";
    return false;
  }
}

/** Turning the lock on proves Face ID works first, so nobody locks
 *  themselves out. */
export async function setLock(on: boolean) {
  if (on) {
    const status = await checkStatus().catch(() => null);
    if (!status?.isAvailable) {
      lock.error = android
        ? "This phone has no fingerprint, face unlock or screen lock set up."
        : "This phone has no Face ID, Touch ID or passcode set up.";
      return;
    }
    if (!(await unlock())) return;
  }
  lock.enabled = on;
  lock.error = "";
  try {
    localStorage.setItem("appLock", on ? "1" : "0");
  } catch {
    // The lock lasts this session only.
  }
}

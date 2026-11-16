import { openUrl } from "@tauri-apps/plugin-opener";

/** Opens a web page outside the app. Only http(s) links, only on a tap; `httpsOnly` for a link the student typed (class meetings). */
export async function openLink(url: string, httpsOnly = false): Promise<void> {
  if (!(httpsOnly ? /^https:\/\//i : /^https?:\/\//i).test(url)) return;
  try {
    await openUrl(url);
  } catch {
    // No browser to hand it to; nothing to show.
  }
}

/** A link that came from a portal's data (an eMabini course or deadline, a plan step): https on PUP's own hosts only (050 C6). */
export function isPortalUrl(url: string): boolean {
  try {
    const u = new URL(url);
    return u.protocol === "https:" && (u.hostname === "pup.edu.ph" || u.hostname.endsWith(".pup.edu.ph"));
  } catch {
    return false;
  }
}

/** Opens a link from portal data, or nothing if it points anywhere but PUP. */
export function openPortalLink(url: string): Promise<void> {
  return isPortalUrl(url) ? openLink(url, true) : Promise.resolve();
}

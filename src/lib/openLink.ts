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

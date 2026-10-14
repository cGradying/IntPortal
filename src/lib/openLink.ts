import { openUrl } from "@tauri-apps/plugin-opener";

/** Opens a web page outside the app. Only http(s) links, only on a tap. */
export async function openLink(url: string): Promise<void> {
  if (!/^https?:\/\//i.test(url)) return;
  try {
    await openUrl(url);
  } catch {
    // No browser to hand it to; nothing to show.
  }
}

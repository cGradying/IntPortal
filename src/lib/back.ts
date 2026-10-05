// Android's back gesture closes whatever is on top (a sheet, the editor, a
// page), then returns to Today, then leaves the app the way Home does. iOS
// has no back button, so nothing here runs there.
import { onBackButtonPress } from "@tauri-apps/api/app";

const stack: (() => void)[] = [];

/** Registers how to close something while it's open. Call it in an
 *  `$effect` so it unregisters when the thing closes. */
export function closable(close: () => void): () => void {
  stack.push(close);
  return () => {
    const i = stack.lastIndexOf(close);
    if (i >= 0) stack.splice(i, 1);
  };
}

/** `home` goes back to the first tab, false when already there. */
export function watchBack(home: () => boolean) {
  const bridge = window.IntPortalAndroid;
  if (!bridge) return;
  onBackButtonPress(() => {
    const top = stack.at(-1);
    if (top) top();
    else if (!home()) bridge.leave();
  }).catch(() => {});
}

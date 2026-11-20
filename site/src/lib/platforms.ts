// What each platform needs and how to install it (051 C9, C10). Plain data, so
// the download list, the first screen and the install help read one place.
import type { Device } from "./device";
import type { Platform } from "./releases";

export interface PlatformInfo {
  id: Platform;
  name: string;
  button: string;
  needs: string;
  /** Short numbered steps for the install help. */
  steps: string[];
  /** Shown when the release has no file for it yet. */
  later?: string;
}

export const PLATFORMS: PlatformInfo[] = [
  {
    id: "android",
    name: "Android",
    button: "Download for Android",
    needs: "Android 7 or newer, 64-bit",
    steps: [
      "Tap Download for Android. Your browser saves IntPortal.apk.",
      "Open it from the notification or your Downloads.",
      "Android asks to allow installs from your browser the first time. Allow it, then tap Install.",
      "Updates install the same way, over the old version, and keep your data.",
    ],
  },
  {
    id: "ios",
    name: "iPhone and iPad",
    button: "Download for iPhone",
    needs: "iOS 16 or newer, through AltStore or SideStore",
    steps: [
      "There is no App Store build yet: that needs a paid Apple developer account.",
      "Install AltStore or SideStore on your iPhone, with your own Apple ID.",
      "Download IntPortal-unsigned.ipa on the iPhone and open it with AltStore or SideStore. It signs the app with your Apple ID.",
      "A free Apple ID's apps stop opening after 7 days. Open AltStore or SideStore to refresh it.",
    ],
  },
  {
    id: "mac",
    name: "Mac",
    button: "Download for Mac",
    needs: "macOS 12 or newer",
    later: "The Mac app comes with 0.4.",
    steps: [
      "Open IntPortal-mac.dmg and drag IntPortal to Applications.",
      "The first time, Control-click IntPortal in Applications and choose Open. macOS asks once because the app isn't notarised.",
    ],
  },
  {
    id: "windows",
    name: "Windows",
    button: "Download for Windows",
    needs: "Windows 10 or newer, 64-bit",
    later: "The Windows app comes with 0.4.",
    steps: [
      "Open IntPortal-windows.msi.",
      "If SmartScreen stops it, choose More info, then Run anyway. The app isn't signed with a paid certificate.",
    ],
  },
  {
    id: "linux",
    name: "Linux",
    button: "Download for Linux",
    needs: "64-bit, with GNOME Keyring or KWallet",
    later: "The Linux app comes with 0.4.",
    steps: [
      "On Debian or Ubuntu, install IntPortal-linux.deb. Anywhere else, make IntPortal-linux.AppImage executable and run it.",
      "Your login goes to the system keychain, so GNOME Keyring or KWallet must be running.",
    ],
  },
];

/** The platform to put first for a device; iPhones and unknown devices get the browser demo first. */
export const firstFor = (d: Device): Platform | "try" => (d === "ios" || d === "other" ? "try" : d);

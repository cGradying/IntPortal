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
  /** Sites the steps name, linked beside them. Link targets, not loads (051 C3). */
  links?: { name: string; href: string }[];
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
      "Play Protect may warn that it's an unknown app. Tap More details, then Install anyway. It says this for every app from outside the Play Store.",
      "Updates install the same way, over the old version, and keep your data.",
    ],
  },
  {
    id: "ios",
    name: "iPhone and iPad",
    button: "Get the iPhone file (.ipa)",
    needs: "iOS 16 or newer, sideloaded. Needs a computer once.",
    steps: [
      "There's no App Store build yet: that needs a paid Apple developer account. So you sideload it.",
      "You need a Mac or Windows computer once, to set up AltStore or SideStore on your iPhone with your own Apple ID.",
      "Download IntPortal-unsigned.ipa on the iPhone and open it with AltStore or SideStore. It signs the app with your Apple ID.",
      "A free Apple ID runs at most 3 sideloaded apps at a time, and AltStore or SideStore counts as one.",
      "Refresh it every 7 days or it stops opening. AltStore refreshes when your computer is on the same Wi-Fi; SideStore refreshes on the phone itself.",
    ],
    links: [
      { name: "AltStore", href: "https://altstore.io" },
      { name: "SideStore", href: "https://sidestore.io" },
    ],
  },
  {
    id: "mac",
    name: "Mac",
    button: "Download for Mac",
    needs: "macOS 12 or newer",
    later: "Coming in a later release.",
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
    later: "Coming in a later release.",
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
    later: "Coming in a later release.",
    steps: [
      "On Debian or Ubuntu, install IntPortal-linux.deb. Anywhere else, make IntPortal-linux.AppImage executable and run it.",
      "Your login goes to the system keychain, so GNOME Keyring or KWallet must be running.",
    ],
  },
];

/** The platform to put first for a device; iPhones and unknown devices get the browser demo first. */
export const firstFor = (d: Device): Platform | "try" => (d === "ios" || d === "other" ? "try" : d);

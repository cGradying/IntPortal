// The downloads, from GitHub Releases (spec 051 C9). Links point at
// releases/latest/download/<stable name> when the newest release is a full one,
// so they never go stale; a pre-release links its own files.

export type Platform = "android" | "ios" | "mac" | "windows" | "linux";

export interface Asset {
  platform: Platform;
  file: string;
  url: string;
  size: number;
}

export interface Release {
  version: string;
  date: string;
  prerelease: boolean;
  page: string;
  assets: Asset[];
}

export interface GhAsset {
  name: string;
  size: number;
  browser_download_url: string;
}

export interface GhRelease {
  tag_name: string;
  draft: boolean;
  prerelease: boolean;
  published_at: string | null;
  html_url: string;
  assets: GhAsset[];
}

export const REPO = "cGradying/IntPortal";
export const REPO_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${REPO_URL}/releases`;
export const API_URL = `https://api.github.com/repos/${REPO}/releases?per_page=12`;

/** A file's platform, from its name. `stable` names carry no version (050 C16, 053 C6). */
const KINDS: { platform: Platform; match: RegExp; stable: RegExp }[] = [
  { platform: "android", match: /^IntPortal(-[\d.]+)?\.apk$/, stable: /^IntPortal\.apk$/ },
  { platform: "ios", match: /^IntPortal(-[\d.]+)?-unsigned\.ipa$/, stable: /^IntPortal-unsigned\.ipa$/ },
  { platform: "mac", match: /^IntPortal(-[\d.]+)?-mac\.dmg$/, stable: /^IntPortal-mac\.dmg$/ },
  { platform: "windows", match: /^IntPortal(-[\d.]+)?-windows\.msi$/, stable: /^IntPortal-windows\.msi$/ },
  { platform: "linux", match: /^IntPortal(-[\d.]+)?-linux\.(AppImage|deb)$/, stable: /^IntPortal-linux\.(AppImage|deb)$/ },
];

/** "android-v0.3.0" or "v0.4.0-rc.1" to "0.3.0" / "0.4.0-rc.1". */
export const versionOf = (tag: string) => tag.match(/v?(\d+\.\d+\.\d+(?:-[\w.]+)?)$/)?.[1] ?? tag;

/** One release's files by platform. Each platform keeps its stable-named file when there is
 *  one; Linux keeps one AppImage and one .deb. `latest` links the stable names through /latest/. */
export function toRelease(r: GhRelease, latest: boolean): Release {
  const assets: Asset[] = [];
  for (const k of KINDS) {
    const files = r.assets.filter((a) => k.match.test(a.name));
    const formats = new Map<string, GhAsset>();
    for (const a of files) {
      const ext = a.name.split(".").pop()!;
      const kept = formats.get(ext);
      if (!kept || (k.stable.test(a.name) && !k.stable.test(kept.name))) formats.set(ext, a);
    }
    for (const a of formats.values()) {
      const url = latest && k.stable.test(a.name) ? `${RELEASES_URL}/latest/download/${a.name}` : a.browser_download_url;
      assets.push({ platform: k.platform, file: a.name, url, size: a.size });
    }
  }
  return { version: versionOf(r.tag_name), date: (r.published_at ?? "").slice(0, 10), prerelease: r.prerelease, page: r.html_url, assets };
}

/** The newest full release, else the newest pre-release. Drafts never show. */
export function pick(list: GhRelease[]): Release | null {
  const live = list.filter((r) => !r.draft && r.published_at).sort((a, b) => b.published_at!.localeCompare(a.published_at!));
  const full = live.find((r) => !r.prerelease);
  if (full) return toRelease(full, true);
  return live[0] ? toRelease(live[0], false) : null;
}

/** Asks GitHub for the releases; null when it doesn't answer. */
export async function fetchRelease(get: typeof fetch = fetch): Promise<Release | null> {
  try {
    const res = await get(API_URL, { headers: { Accept: "application/vnd.github+json" } });
    return res.ok ? pick((await res.json()) as GhRelease[]) : null;
  } catch {
    return null;
  }
}

/** "67 MB". */
export const megabytes = (bytes: number) => `${Math.max(1, Math.round(bytes / 1_000_000))} MB`;

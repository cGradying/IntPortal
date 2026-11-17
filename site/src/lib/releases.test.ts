import { describe, expect, it } from "vitest";
import recorded from "./fallback.json";
import { megabytes, pick, toRelease, versionOf, type GhRelease } from "./releases";

const rel = (over: Partial<GhRelease>): GhRelease => ({ tag_name: "android-v0.4.0", draft: false, prerelease: false, published_at: "2026-11-20T00:00:00Z", html_url: "https://github.com/x/y/releases/tag/android-v0.4.0", assets: [], ...over });
const asset = (name: string, size = 70_000_000) => ({ name, size, browser_download_url: `https://github.com/cGradying/IntPortal/releases/download/android-v0.4.0/${name}` });

describe("051 C9 every download, listed", () => {
  it("reads the version from a tag", () => {
    expect(versionOf("android-v0.3.0")).toBe("0.3.0");
    expect(versionOf("android-v0.2.0-rc.1")).toBe("0.2.0-rc.1");
  });
  it("takes the newest pre-release from GitHub's real answer when no full release exists", () => {
    const r = pick(recorded as GhRelease[])!;
    expect(r.version).toBe("0.2.0-rc.1");
    expect(r.prerelease).toBe(true);
    expect(r.assets).toEqual([{ platform: "android", file: "IntPortal-0.2.0.apk", size: expect.any(Number), url: expect.stringContaining("/download/android-v0.2.0-rc.1/IntPortal-0.2.0.apk") }]);
  });
  it("links a full release's stable names through /latest/, so links never go stale", () => {
    const r = toRelease(rel({ assets: [asset("IntPortal-0.4.0.apk"), asset("IntPortal.apk"), asset("IntPortal-0.4.0.aab"), asset("IntPortal-unsigned.ipa"), asset("IntPortal-linux.AppImage"), asset("IntPortal-linux.deb"), asset("IntPortal-mac.dmg"), asset("IntPortal-windows.msi")] }), true);
    expect(r.assets.map((a) => [a.platform, a.url.replace("https://github.com/cGradying/IntPortal/releases", "")])).toEqual([
      ["android", "/latest/download/IntPortal.apk"],
      ["ios", "/latest/download/IntPortal-unsigned.ipa"],
      ["mac", "/latest/download/IntPortal-mac.dmg"],
      ["windows", "/latest/download/IntPortal-windows.msi"],
      ["linux", "/latest/download/IntPortal-linux.AppImage"],
      ["linux", "/latest/download/IntPortal-linux.deb"],
    ]);
  });
  it("prefers a full release over a newer pre-release and never shows a draft", () => {
    const list = [rel({ tag_name: "android-v0.5.0", draft: true }), rel({ tag_name: "android-v0.4.1-rc.1", prerelease: true, published_at: "2026-11-25T00:00:00Z" }), rel({})];
    expect(pick(list)?.version).toBe("0.4.0");
    expect(pick([])).toBeNull();
  });
  it("rounds sizes to megabytes", () => {
    expect(megabytes(70_123_456)).toBe("70 MB");
    expect(megabytes(10)).toBe("1 MB");
  });
});

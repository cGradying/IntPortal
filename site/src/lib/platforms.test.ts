import { describe, expect, it } from "vitest";
import { FAQ } from "./content/help";
import { PLATFORMS } from "./platforms";

const get = (id: string) => PLATFORMS.find((p) => p.id === id)!;

describe("060 install copy", () => {
  it("c2_iphone_says_the_awkward_parts_first", () => {
    const ios = get("ios");
    const all = ios.steps.join(" ");
    expect(ios.button).toBe("Get the iPhone file (.ipa)");
    expect(ios.needs).toBe("iOS 16 or newer, sideloaded. Needs a computer once.");
    expect(all).toMatch(/Mac or Windows computer once/);
    expect(all).toMatch(/at most 3 sideloaded apps/);
    expect(all).toMatch(/every 7 days/);
    expect(ios.links?.map((l) => l.href)).toEqual(["https://altstore.io", "https://sidestore.io"]);
    expect(FAQ.find((q) => q.id === "q-why-isnt-it-on-the-app-store")!.a).toMatch(/computer once.*3 sideloaded apps.*7 days/);
  });
  it("c3_android_names_play_protect", () => {
    expect(get("android").steps.join(" ")).toMatch(/Play Protect.*More details, then Install anyway/);
  });
  it("c6_no_release_number_promises", () => {
    for (const p of PLATFORMS) if (p.later) expect(p.later, p.id).toBe("Coming in a later release.");
  });
});

import { describe, expect, it, vi } from "vitest";
import { FALLBACK, friendly } from "./errors";

describe("spec 040 C4: friendly", () => {
  it("c4_friendly_maps_known_errors_and_falls_back", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(friendly("couldn't reach the SIS: error sending request")).toBe("Can't reach the SIS right now. Showing what was saved.");
    expect(friendly("the SIS session expired")).toBe("Your session ended. Pull to sync.");
    expect(friendly("signed in, but no SIS server had your schedule")).toBe("The SIS has no classes for you this term yet.");
    expect(friendly("refusing to talk to x.com: not a PUP SIS host")).toBe("That address isn't a PUP server, so IntPortal won't use it.");
    expect(friendly({ message: "no login form on the eMabini page" })).toBe("Can't reach eMabini right now.");
    const at = 1_800_000_000;
    expect(friendly(`too many sign-in tries; try again at ${at}`)).toMatch(/^Too many tries\. You can try again at \d{1,2}:\d{2}/);
    expect(friendly("too many sign-in tries; try again later")).toBe("Too many tries. Wait a few minutes, then try again.");
    expect(friendly("store is locked: SQLITE_BUSY")).toBe(FALLBACK);
    expect(warn).toHaveBeenCalled();
  });
  it("keeps the app's own sentences, not any capitalised text", () => {
    expect(friendly("Error: Give it a name first.")).toBe("Give it a name first.");
    expect(friendly("A note holds up to 20 photos.")).toBe("A note holds up to 20 photos.");
    vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(friendly("Invalid login, please try again")).toBe(FALLBACK);
    expect(friendly("Database exploded")).toBe(FALLBACK);
  });
  it("every sentence the app writes passes through unchanged, even ones a table regex would catch", () => {
    const sentences = [
      "That isn't the student number signed in to the SIS on this phone. Use your own eMabini login, or sign out of the SIS first.",
      "Sign in first, then back up.", "That deck is gone.", "That card is gone.", "Turn IntAssis on first", "Sync first", "Not signed in", "Not signed in to Mabini",
      "The store key in the keychain is damaged.", "Couldn't restore that backup, so nothing changed.", "Couldn't make the backup.", "IntAssis is busy, try again in a moment.",
      "Your photos make this backup too big to restore here; it's 40 MB. Remove some photos and try again.", "Use a link that starts with https://",
      "IntPortal can't use the camera. Turn it on in Settings, or add a photo from your library.", "This phone has no camera. Add a photo from your library instead.",
      "There isn't room on this phone for the photo. Free some space and try again.", "The photo couldn't be added. Try again.",
      "A note holds up to 20 photos. Remove one to add another.", "I couldn't wake up. Try again.", "Unknown note", "Sign in first, then restore.",
    ];
    for (const t of sentences) expect(friendly(t)).toBe(t);
  });
});

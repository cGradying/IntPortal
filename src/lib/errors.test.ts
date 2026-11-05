import { describe, expect, it, vi } from "vitest";
import { FALLBACK, friendly } from "./errors";

describe("spec 040 C4: friendly", () => {
  it("maps the core's own errors to plain copy", () => {
    expect(friendly("couldn't reach the SIS: error sending request")).toBe("Can't reach the SIS right now.");
    expect(friendly("the SIS session expired")).toBe("Your session ended. Pull to sync.");
    expect(friendly("signed in, but no SIS server had your schedule")).toBe("The SIS has no classes for you this term yet.");
    expect(friendly("too many sign-in tries; try again later")).toBe("Too many tries. Wait a few minutes, then try again.");
    expect(friendly({ message: "no login form on the eMabini page" })).toBe("Can't reach eMabini right now.");
  });
  it("keeps a portal's or the app's own sentence", () => {
    expect(friendly("Invalid login, please try again")).toBe("Invalid login, please try again");
    expect(friendly("Error: Give it a name first.")).toBe("Give it a name first.");
  });
  it("hides anything else behind one line", () => {
    const warn = vi.spyOn(console, "warn").mockImplementation(() => {});
    expect(friendly("store is locked: SQLITE_BUSY")).toBe(FALLBACK);
    expect(warn).toHaveBeenCalled();
  });
});

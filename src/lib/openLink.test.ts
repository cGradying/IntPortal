import { describe, expect, it } from "vitest";
import { isPortalUrl } from "./openLink";

describe("050 C6 links from portal data", () => {
  it("opens PUP's own https hosts", () => {
    expect(isPortalUrl("https://emabini.pup.edu.ph/mod/assign/view.php?id=1")).toBe(true);
    expect(isPortalUrl("https://sis8.pup.edu.ph/student")).toBe(true);
  });
  it("refuses plain http, lookalikes and other sites", () => {
    expect(isPortalUrl("http://emabini.pup.edu.ph/")).toBe(false);
    expect(isPortalUrl("https://emabini.pup.edu.ph.evil.com/")).toBe(false);
    expect(isPortalUrl("https://evilpup.edu.ph/")).toBe(false);
    expect(isPortalUrl("javascript:alert(1)")).toBe(false);
    expect(isPortalUrl("not a url")).toBe(false);
  });
});

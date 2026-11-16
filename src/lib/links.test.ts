import { describe, expect, it } from "vitest";
import { ISSUES, PRIVACY, SITE, UPDATES } from "./links";

describe("050 C15 the app's outside links", () => {
  it("send Updates to the download page, or GitHub before the site is live", () => {
    expect(UPDATES).toBe(SITE ? `${SITE}/download` : "https://github.com/cGradying/intportal-app/releases");
    expect(PRIVACY.startsWith("https://")).toBe(true);
    expect(ISSUES).toBe("https://github.com/cGradying/intportal-app/issues");
  });
});

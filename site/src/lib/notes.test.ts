import { describe, expect, it } from "vitest";
import { notes } from "./notes";

describe("057 C12 changelog lines", () => {
  it("links a pull request number", () => {
    expect(notes("Faster sync (#317)")).toContain('href="https://github.com/cGradying/IntPortal/pull/317"');
  });
  it("leaves apostrophes and links alone", () => {
    const html = notes("you're set, see [#9](https://x.y/#9)");
    expect(html).toContain("you&#39;re");
    expect(html).not.toContain("pull/39");
    expect(html).not.toContain("pull/9");
  });
});

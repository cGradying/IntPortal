import { describe, expect, it } from "vitest";
import { inline, markdown } from "./markdown";

describe("051 C5 PRIVACY.md on the site", () => {
  it("renders the parts PRIVACY.md uses and escapes the rest", () => {
    expect(markdown("# Privacy\n\n- **Your login** stays\n- `sis8`\n\nSee <https://x.y/z> <b>")).toBe(
      '<h1>Privacy</h1>\n<ul><li><strong>Your login</strong> stays</li><li><code>sis8</code></li></ul>\n<p>See <a href="https://x.y/z" rel="noopener">https://x.y/z</a> &lt;b&gt;</p>',
    );
  });
  it("renders a table", () => {
    expect(markdown("| A | B |\n|---|---|\n| 1 | 2 |")).toContain("<th>A</th><th>B</th></tr></thead><tbody><tr><td>1</td><td>2</td></tr>");
  });
});

describe("inline", () => {
  it("keeps a link's URL inside its href", () => {
    const html = inline('[x](https://a.b/"onmouseover="alert(1))');
    expect(html).not.toContain('"onmouseover="');
    expect(html).toContain("&quot;");
  });
});

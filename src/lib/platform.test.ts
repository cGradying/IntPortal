import { describe, expect, it } from "vitest";
import { isPhone } from "./platform";

describe("053 C5 phone-only settings", () => {
  it("knows a phone's webview from a desktop's", () => {
    expect(isPhone("Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148")).toBe(true);
    expect(isPhone("Mozilla/5.0 (Linux; Android 14; wv) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36")).toBe(true);
    expect(isPhone("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15")).toBe(false);
    expect(isPhone("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Edg/131.0")).toBe(false);
  });
});

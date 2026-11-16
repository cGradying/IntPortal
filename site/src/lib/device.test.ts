import { describe, expect, it } from "vitest";
import { device } from "./device";

describe("051 C8 the right download first", () => {
  it("reads phones", () => {
    expect(device("Mozilla/5.0 (Linux; Android 14; SM-A155F) AppleWebKit/537.36 Chrome/131.0 Mobile Safari/537.36")).toBe("android");
    expect(device("Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) AppleWebKit/605.1.15 Version/18.1 Mobile/15E148 Safari/604.1")).toBe("ios");
  });
  it("tells an iPad asking for the desktop site from a Mac by touch", () => {
    const ua = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Version/18.1 Safari/605.1.15";
    expect(device(ua, 5)).toBe("ios");
    expect(device(ua, 0)).toBe("mac");
  });
  it("reads computers", () => {
    expect(device("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36")).toBe("windows");
    expect(device("Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/131.0 Safari/537.36")).toBe("linux");
    expect(device("curl/8.7.1")).toBe("other");
  });
});

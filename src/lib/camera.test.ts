import { describe, expect, it } from "vitest";
import { cameraProblem } from "./camera";

describe("cameraProblem", () => {
  it("reads the plugin's code from an object or a string", () => {
    expect(cameraProblem({ message: "camera_denied" })).toBe("camera_denied");
    expect(cameraProblem("no_camera")).toBe("no_camera");
    expect(cameraProblem({ message: "no_space" })).toBe("no_space");
  });
  it("anything else is other", () => {
    expect(cameraProblem(new Error("boom"))).toBe("other");
    expect(cameraProblem(undefined)).toBe("other");
  });
});

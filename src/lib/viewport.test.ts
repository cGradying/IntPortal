import { describe, expect, it } from "vitest";
import { focusOpens, keyboardUp } from "./viewport.svelte";

describe("the keyboard flag (#253)", () => {
  it("is up when the viewport lost more than a toolbar's worth of its tallest height", () => {
    expect(keyboardUp(874, 874)).toBe(false);
    expect(keyboardUp(820, 874)).toBe(false); // a browser bar or an input accessory, not a keyboard
    expect(keyboardUp(538, 874)).toBe(true);
  });
  it("measures against the tallest height seen, because Android shrinks the whole window", () => {
    // On Android innerHeight shrinks with the keyboard, so comparing the viewport with it never fires.
    expect(keyboardUp(520, 860)).toBe(true);
  });
  it("trusts a focus at once only when a finger just put it there", () => {
    expect(focusOpens(120)).toBe(true);
    expect(focusOpens(5000)).toBe(false); // focused from code: iOS raises no keyboard, so the bars stay
    expect(focusOpens(Infinity)).toBe(false);
  });
});

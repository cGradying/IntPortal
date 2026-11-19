import { expect, it } from "vitest";
import { talk } from "./talk";

it("starts with his hello, then the app's lines, none twice in a row of three (058 C12)", () => {
  expect(talk[0]).toBe("Tara, pasok!");
  expect(talk.length).toBeGreaterThan(6);
  expect(new Set(talk).size).toBe(talk.length);
  expect(talk.some((t) => /swipe|I-tap/.test(t))).toBe(false);
});

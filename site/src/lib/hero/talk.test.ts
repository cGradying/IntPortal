import { expect, it } from "vitest";
import { FORMS } from "./forms";
import { talk } from "./talk";

it("starts with his hello, then the app's lines, each once (058 C12)", () => {
  expect(talk[0].text).toBe("Tara, pasok!");
  expect(talk.length).toBeGreaterThan(6);
  expect(new Set(talk.map((t) => t.text)).size).toBe(talk.length);
  expect(talk.some((t) => /swipe|I-tap/.test(t.text))).toBe(false);
});

it("gives every line after the hello a sculpture that exists (059 C1)", () => {
  expect(talk[0].form).toBeNull();
  for (const t of talk.slice(1)) {
    expect(t.form, t.text).not.toBeNull();
    expect(FORMS[t.form!], t.text).toBeDefined();
  }
});

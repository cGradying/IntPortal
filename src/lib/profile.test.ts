// @ts-expect-error type error without @types/node package
import { readFileSync } from "node:fs";
import { beforeEach, describe, expect, it } from "vitest";
import { CAMPUSES, CAMPUS_KEY, NAME_KEY, cleanName, getCampus, getName, setCampus, setName } from "./profile";

const data = new Map<string, string>();
beforeEach(() => {
  data.clear();
  Object.assign(globalThis, { localStorage: { getItem: (k: string) => data.get(k) ?? null, setItem: (k: string, v: string) => data.set(k, v), removeItem: (k: string) => data.delete(k) } });
});

describe("the student's profile (spec 049 C4)", () => {
  it("c4_keeps_the_name_clean_and_short", () => {
    expect(cleanName("  Jan   Vincent  ")).toBe("Jan Vincent");
    expect(cleanName("a".repeat(30))).toHaveLength(20);
    expect(cleanName("Maria Clara de los Santos")).toBe("Maria Clara de los S");
    expect(cleanName("Maria Clara de los  Santos")).toBe("Maria Clara de los S");
    setName("  Jan ");
    expect(data.get(NAME_KEY)).toBe("Jan");
    expect(getName()).toBe("Jan");
    setName("   ");
    expect(data.has(NAME_KEY)).toBe(false);
    expect(getName()).toBe("");
  });

  it("c4_keeps_the_campus_under_its_contract_key", () => {
    expect(getCampus()).toBeNull();
    setCampus("Sta. Mesa");
    expect(data.get(CAMPUS_KEY)).toBe("Sta. Mesa");
    setCampus("school:mabini");
    expect(getCampus()).toBe("school:mabini");
    setCampus(null);
    expect(getCampus()).toBeNull();
    expect([NAME_KEY, CAMPUS_KEY]).toEqual(["intportal.name", "intportal.campus"]);
  });

  it("c4_survives_storage_that_throws", () => {
    Object.assign(globalThis, { localStorage: { getItem: () => { throw new Error("off"); }, setItem: () => { throw new Error("off"); }, removeItem: () => { throw new Error("off"); } } });
    expect(() => setName("Jan")).not.toThrow();
    expect(getName()).toBe("");
    expect(getCampus()).toBeNull();
  });

  it("c5_lists_every_campus_exactly_as_campus_rs_names_it", () => {
    const rs = readFileSync(new URL("../../crates/intportal-core/src/campus.rs", import.meta.url), "utf8");
    const names = [...rs.matchAll(/^\s*c\((?:Some\("\w+"\)|None), "([^"]+)", "[^"]+"\),$/gm)].map((m) => m[1]);
    expect(names).toHaveLength(25);
    expect([...CAMPUSES]).toEqual(names);
  });
});

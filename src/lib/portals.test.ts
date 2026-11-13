import { describe, expect, it } from "vitest";
import type { Portal } from "./api";
import { birthYears, daysIn, fieldValues, maskStudentNumber, portalCopy, triesLine, validate } from "./portals";

const sis = { id: "sis", fields: ["student_number", "birthdate", "password"], limits: { attempts: 3, window_secs: 900 } } as unknown as Portal;
const mabini = { id: "mabini", fields: ["student_number", "password"], limits: { attempts: 3, window_secs: 900 } } as unknown as Portal;

describe("validate", () => {
  it("asks only for the fields a portal has", () => {
    expect(validate(mabini, { student_number: "2026-00000-MN-0", birthdate: "", password: "x" })).toBe("");
    expect(validate(sis, { student_number: "2026-00000-MN-0", birthdate: "", password: "x" })).toBe("Add your birthdate.");
  });
  it("checks the student number shape and the password", () => {
    expect(validate(mabini, { student_number: "", birthdate: "", password: "x" })).toBe("Add your student number.");
    expect(validate(mabini, { student_number: "12345", birthdate: "", password: "x" })).toBe("Student number looks like 2026-00000-MN-0.");
    expect(validate(mabini, { student_number: "202600000mn0", birthdate: "", password: "" })).toBe("Add your password.");
  });
});

describe("fieldValues", () => {
  it("trims and upper-cases the student number", () => {
    expect(fieldValues({ student_number: " 2026-00000-mn-0 ", birthdate: "", password: "p" }).student_number).toBe("2026-00000-MN-0");
  });
});

describe("triesLine", () => {
  const now = 1_000_000;
  it("stays quiet until a try has been used", () => {
    expect(triesLine({ left: 3, retry_at: null, rejected: false }, sis, now)).toBe("");
  });
  it("counts what is left", () => {
    expect(triesLine({ left: 2, retry_at: null, rejected: false }, sis, now)).toBe("2 tries left");
    expect(triesLine({ left: 1, retry_at: null, rejected: false }, sis, now)).toBe("1 try left");
  });
  it("says when it unlocks once none are left", () => {
    expect(triesLine({ left: 0, retry_at: now + 600, rejected: false }, sis, now)).toMatch(/^Too many tries\. You can try again at /);
  });
});

describe("portalCopy", () => {
  it("speaks per portal, falling back to SIS wording", () => {
    expect(portalCopy("mabini").keychainNote).toMatch(/eMabini/);
    expect(portalCopy("sis").keychainNote).toMatch(/PUP SIS/);
    expect(portalCopy("unknown").keychainNote).toBe(portalCopy("sis").keychainNote);
  });
});

describe("011 form", () => {
  it("c4_student_number_is_masked_as_typed_and_pasted", () => {
    expect(maskStudentNumber("2026")).toBe("2026");
    expect(maskStudentNumber("20260012")).toBe("2026-0012");
    expect(maskStudentNumber("202600123mn0")).toBe("2026-00123-MN-0");
    expect(maskStudentNumber(" 2026 00123 mn 0 ")).toBe("2026-00123-MN-0");
    expect(maskStudentNumber("2026-00123-MN-0X9")).toBe("2026-00123-MN-0");
  });
  it("c2_years_run_14_to_70_years_back", () => {
    const y = birthYears(new Date(2026, 10, 11));
    expect(y[0]).toBe(2012);
    expect(y.at(-1)).toBe(1956);
  });
  it("c3_the_day_wheel_fits_the_month", () => {
    expect(daysIn(2, 2024)).toBe(29);
    expect(daysIn(2, 2026)).toBe(28);
    expect(daysIn(4, 2026)).toBe(30);
  });
});

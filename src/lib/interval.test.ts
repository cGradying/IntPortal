import { describe, expect, it } from "vitest";
import { dueIn, interval } from "./interval";

const DAY = 86_400;

describe("card intervals", () => {
  it("fits under a rating button", () => {
    expect([600, DAY, 3 * DAY, 16 * DAY, 60 * DAY, 540 * DAY].map(interval)).toEqual(["10m", "1d", "3d", "16d", "2mo", "1.5y"]);
    expect(interval(6 * 3600)).toBe("6h");
    expect(interval(5)).toBe("1m");
  });

  it("reads as words in the recap", () => {
    expect([600, DAY, 3 * DAY, 30 * DAY, 400 * DAY].map(dueIn)).toEqual(["in 10 minutes", "tomorrow", "in 3 days", "in 1 month", "in 1.1 years"]);
    expect(dueIn(60)).toBe("in 1 minute");
  });
});
